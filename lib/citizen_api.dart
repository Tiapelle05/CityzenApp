import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'dati_simulati.dart';

/// Client REST per le API cittadino di Tryees.
/// L'URL può essere sovrascritto con --dart-define=API_BASE_URL=... .
///
/// Modalità demo: risponde con [DatiSimulati] senza contattare il server.
/// Si attiva dall'app, con --dart-define=DEMO=true oppure, sul web, con ?demo=1.
class CitizenApi {
  CitizenApi._() {
    DatiSimulati.instance.eventi.listen((e) {
      if (demoMode) _events.add(e);
    });
  }
  static final CitizenApi instance = CitizenApi._();

  static const String _configuredUrl = String.fromEnvironment('API_BASE_URL');
  static const String _installIdKey = 'tryees_install_id';
  static const String _tokenKey = 'tryees_access_token';
  static const String _parkIdKey = 'tryees_park_id';
  static const String _demoKey = 'tryees_demo';
  static const bool _demoDaBuild = bool.fromEnvironment('DEMO');
  static final Uuid _uuid = Uuid();

  late final String baseUrl = _configuredUrl.isNotEmpty
      ? _configuredUrl.replaceAll(RegExp(r'/$'), '')
      : kIsWeb
          ? 'http://localhost:8000'
          : defaultTargetPlatform == TargetPlatform.android
              ? 'http://10.0.2.2:8000'
              : 'http://127.0.0.1:8000';

  String? _token;
  int? _parkId;
  Map<String, dynamic>? _cachedParkStatus;
  Map<String, dynamic>? get cachedParkStatus => _cachedParkStatus;
  String? initializationError;
  bool testMode = false;

  /// Dati simulati al posto del backend.
  bool demoMode = false;
  /// Scelta fatta dall'utente in questa sessione: vince su build e URL.
  bool? _demoScelto;

  /// Parco in uso (id, name, city, lat, lon), se noto.
  Map<String, dynamic>? _park;
  Map<String, dynamic>? get park => _park;
  Future<void>? _initialization;
  bool get isReady => _token != null && _parkId != null;
  int? get parkId => _parkId;

  Future<void> initialize() {
    final active = _initialization;
    if (active != null) return active;
    final future = _initializeInternal();
    _initialization = future;
    return future.whenComplete(() { _initialization = null; });
  }

  Future<void> _initializeInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final daUrl = kIsWeb && const {'1', 'true', 'si', 'sì'}.contains(Uri.base.queryParameters['demo']);
    demoMode = _demoScelto ?? (_demoDaBuild || daUrl || (prefs.getBool(_demoKey) ?? false));
    if (demoMode) {
      _park = DatiSimulati.parco;
      _cachedParkStatus = DatiSimulati.instance.statoParco();
      initializationError = null;
      return;
    }
    var installId = prefs.getString(_installIdKey);
    if (installId == null || installId.isEmpty) {
      installId = _uuid.v4();
      await prefs.setString(_installIdKey, installId);
    }
    _token = prefs.getString(_tokenKey);
    _parkId = prefs.getInt(_parkIdKey);

    try {
      await _register(installId);
      await refreshParks();
      try { await getParkStatus(); } catch (_) {}
      initializationError = null;
      // Se una schermata aveva chiesto gli aggiornamenti live prima che ci fosse il token
      if (_wsWanted) connectLive();
    } catch (e) {
      initializationError = _cleanError(e);
      rethrow;
    }
  }

  /// Nuova registrazione con lo stesso install_id (stesso cittadino, nuovo token).
  /// Usata quando il backend risponde 401 (token scaduto o chiave cambiata).
  Future<void> _reRegister() async {
    final prefs = await SharedPreferences.getInstance();
    final installId = prefs.getString(_installIdKey) ?? _uuid.v4();
    await prefs.setString(_installIdKey, installId);
    await _register(installId);
  }

  Future<void> _ensureReady() async {
    if (!isReady) await initialize();
  }

  /// Attiva o disattiva i dati simulati. Le schermate vanno ricostruite dopo la chiamata.
  Future<void> setDemoMode(bool attiva) async {
    _demoScelto = attiva;
    demoMode = attiva;
    _cachedParkStatus = null;
    _park = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_demoKey, attiva);
    if (attiva) {
      disconnectLive();
      _park = DatiSimulati.parco;
      _cachedParkStatus = DatiSimulati.instance.statoParco();
    } else {
      try {
        await initialize().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Le schermate mostrano l'errore del backend come al solito.
      }
    }
  }

  /// Posizione GPS simulata dentro il parco demo.
  ({double lat, double lon}) posizioneSimulata() => DatiSimulati.instance.posizioneCasuale();

  Future<void> retryInitialization() async {
    initializationError = null;
    await initialize();
  }

  Future<void> _register(String installId) async {
    final platform = kIsWeb
        ? 'web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android';
    final response = await http.post(
      _uri('/citizen/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'install_id': installId,
        'platform': platform,
        'app_version': '1.0.0',
      }),
    ).timeout(const Duration(seconds: 15));
    final data = _decode(response);
    _token = data['access_token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
  }

  Future<List<Map<String, dynamic>>> refreshParks() async {
    if (demoMode) return DatiSimulati.instance.parchi();
    final data = await _get('/citizen/parks');
    final parks = (data as List).cast<Map<String, dynamic>>();
    if (parks.isEmpty) {
      _parkId = null;
      throw const ApiException('Nessun parco attivo configurato nel database.');
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_parkIdKey);
    final exists = parks.any((p) => p['id'] == saved);
    _parkId = exists ? saved : parks.first['id'] as int;
    _park = parks.firstWhere((p) => p['id'] == _parkId);
    await prefs.setInt(_parkIdKey, _parkId!);
    return parks;
  }

  Future<Map<String, dynamic>> getParkStatus() async {
    if (testMode) { _cachedParkStatus = {'level': 'ok', 'message': 'Test'}; return _cachedParkStatus!; }
    if (demoMode) { _cachedParkStatus = await DatiSimulati.instance.stato(); return _cachedParkStatus!; }
    await _ensureReady();
    final id = _requirePark();
    _cachedParkStatus = (await _get('/citizen/parks/$id/status')) as Map<String, dynamic>;
    return _cachedParkStatus!;
  }

  Future<List<Map<String, dynamic>>> getNotices() async {
    if (testMode) return [];
    if (demoMode) return DatiSimulati.instance.avvisi();
    await _ensureReady();
    final id = _requirePark();
    return ((await _get('/citizen/parks/$id/notices')) as List)
        .cast<Map<String, dynamic>>();
  }

  /// Categorie attive; con [kind] solo quelle usabili per quel tipo (problem, suggestion).
  Future<List<Map<String, dynamic>>> getCategories({String? kind}) async {
    if (testMode) return [];
    final List<Map<String, dynamic>> rows;
    if (demoMode) {
      rows = await DatiSimulati.instance.categorie();
    } else {
      await _ensureReady();
      rows = ((await _get('/citizen/categories')) as List).cast<Map<String, dynamic>>();
    }
    if (kind == null) return rows;
    return rows.where((c) => (c['kinds'] as List? ?? const []).contains(kind)).toList();
  }

  /// Idea per il parco: nel backend è una segnalazione `suggestion`, pubblica nel feed.
  /// Non serve la posizione.
  Future<Map<String, dynamic>> createSuggestion({
    required String category,
    required String description,
  }) async {
    if (demoMode) {
      return DatiSimulati.instance.crea(kind: 'suggestion', category: category, description: description);
    }
    await _ensureReady();
    final id = _requirePark();
    return _sendReport({
      'kind': 'suggestion',
      'park_id': '$id',
      'description': description,
      'category': category,
    });
  }

  Future<Map<String, dynamic>> createProblemReport({
    required String category,
    required String description,
    required String priority,
    required double latitude,
    required double longitude,
    Uint8List? photoBytes,
    String? photoName,
  }) async {
    if (demoMode) {
      return DatiSimulati.instance.crea(
        kind: 'problem', category: category, description: description, priority: priority,
        lat: latitude, lon: longitude, foto: photoBytes,
      );
    }
    await _ensureReady();
    final id = _requirePark();
    return _sendReport({
      'kind': 'problem',
      'park_id': '$id',
      'description': description,
      'category': category,
      'priority': priority,
      'lat': '$latitude',
      'lon': '$longitude',
    }, photoBytes: photoBytes, photoName: photoName);
  }

  /// POST /citizen/reports (sempre multipart, anche senza foto).
  Future<Map<String, dynamic>> _sendReport(Map<String, String> fields,
      {Uint8List? photoBytes, String? photoName}) async {
    // client_ref creato una volta sola: un reinvio (anche dopo il 401) non crea doppioni.
    final clientRef = _uuid.v4();
    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', _uri('/citizen/reports'));
      request.headers['Authorization'] = 'Bearer ${_requireToken()}';
      request.fields.addAll({...fields, 'client_ref': clientRef});
      if (photoBytes != null && photoBytes.isNotEmpty) {
        request.files.add(http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: photoName ?? 'segnalazione.jpg',
        ));
      }
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      return http.Response.fromStream(streamed);
    }

    var response = await send();
    if (response.statusCode == 401) {
      await _reRegister();
      response = await send();
    }
    return _decode(response) as Map<String, dynamic>;
  }

  /// Segnalazioni dell'utente (dalla più recente).
  Future<Map<String, dynamic>> getMyReports({int skip = 0, int limit = 20}) async {
    if (testMode) return {'items': <Map<String, dynamic>>[], 'total': 0};
    if (demoMode) return DatiSimulati.instance.mie(limit: limit);
    await _ensureReady();
    return (await _get('/citizen/reports?skip=$skip&limit=$limit')) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getReport(int id) async {
    if (demoMode) return DatiSimulati.instance.dettaglio(id);
    await _ensureReady();
    return (await _get('/citizen/reports/$id')) as Map<String, dynamic>;
  }

  /// Segnalazioni di tutti i cittadini del parco (GET /citizen/feed).
  Future<Map<String, dynamic>> getFeed({String? kind, int skip = 0, int limit = 20}) async {
    if (testMode) return {'items': <Map<String, dynamic>>[], 'total': 0};
    if (demoMode) return DatiSimulati.instance.feed(kind: kind, limit: limit);
    await _ensureReady();
    final id = _requirePark();
    final q = 'park_id=$id&skip=$skip&limit=$limit${kind == null ? '' : '&kind=$kind'}';
    return (await _get('/citizen/feed?$q')) as Map<String, dynamic>;
  }

  /// URL assoluto di una foto restituita dal backend (`photo_url` è relativo).
  String? absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http') || path.startsWith('data:')) return path;
    return '$baseUrl${path.startsWith('/') ? '' : '/'}$path';
  }

  // --- Aggiornamenti live (WS /citizen/ws) ---------------------------------
  final StreamController<Map<String, dynamic>> _events = StreamController.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  WebSocketChannel? _ws;
  Timer? _wsPing;
  Timer? _wsRetry;
  int _wsBackoff = 2;
  bool _wsWanted = false;

  /// Apre il WebSocket (idempotente). Messaggi: {type, data} con type
  /// report_created | report_status_changed | report_updated | notice_created |
  /// park_status_changed. Si inoltrano solo quelli del parco in uso (o senza park_id).
  /// Se il token non c'è ancora, si connette appena initialize() riesce.
  void connectLive() {
    if (testMode || demoMode) return; // in demo gli eventi arrivano da DatiSimulati
    _wsWanted = true;
    if (_ws != null || _token == null) return;
    final wsBase = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final channel = WebSocketChannel.connect(
        Uri.parse('$wsBase/citizen/ws?token=${Uri.encodeQueryComponent(_token!)}'));
    _ws = channel;
    _wsPing = Timer.periodic(const Duration(seconds: 25), (_) {
      try { channel.sink.add('ping'); } catch (_) {}
    });
    channel.stream.listen(
      (message) {
        _wsBackoff = 2;
        try {
          final data = jsonDecode(message as String);
          if (data is! Map<String, dynamic>) return;
          final payload = data['data'];
          final park = payload is Map ? payload['park_id'] : null;
          if (park == null || park == _parkId) _events.add(data);
        } catch (_) {}
      },
      onError: (_) => _wsClosed(channel, null),
      onDone: () => _wsClosed(channel, channel.closeCode),
    );
  }

  void _wsClosed(WebSocketChannel channel, int? code) {
    if (!identical(_ws, channel)) return;
    _wsPing?.cancel();
    _ws = null;
    if (!_wsWanted) return;
    _wsRetry?.cancel();
    _wsRetry = Timer(Duration(seconds: _wsBackoff), () async {
      if (code == 1008) {
        // token non valido: nuova registrazione prima di riconnettersi
        try { await _reRegister(); } catch (_) {}
      }
      connectLive();
    });
    _wsBackoff = (_wsBackoff * 2).clamp(2, 60);
  }

  void disconnectLive() {
    _wsWanted = false;
    _wsPing?.cancel();
    _wsRetry?.cancel();
    final ws = _ws;
    _ws = null;
    ws?.sink.close();
  }

  Future<dynamic> _get(String path) => _request('GET', path);

  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? body}) async {
    if (_token == null) await initialize();
    var response = await _send(method, path, body);
    if (response.statusCode == 401) {
      // token scaduto o non valido: nuova registrazione e un solo nuovo tentativo
      await _reRegister();
      response = await _send(method, path, body);
    }
    return _decode(response);
  }

  Future<http.Response> _send(String method, String path, Map<String, dynamic>? body) {
    final headers = <String, String>{'Authorization': 'Bearer ${_requireToken()}'};
    if (body != null) headers['Content-Type'] = 'application/json';
    final uri = _uri(path);
    const t = Duration(seconds: 20);
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers).timeout(t);
      case 'POST':
        return http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(t);
      default:
        return http.delete(uri, headers: headers).timeout(t);
    }
  }

  dynamic _decode(http.Response response) {
    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      data = response.body;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Errore server (${response.statusCode})';
      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail is List && detail.isNotEmpty && detail.first is Map) {
          message = (detail.first['msg'] ?? detail.first).toString();
        } else {
          message = detail.toString();
        }
      } else if (response.statusCode == 403) {
        message = 'Questa installazione è stata bloccata.';
      }
      if (response.statusCode == 429) {
        final wait = int.tryParse(response.headers['retry-after'] ?? '');
        if (wait != null) {
          message = '$message (riprova tra ${(wait / 60).ceil()} min)';
        }
      }
      throw ApiException(message, statusCode: response.statusCode);
    }
    return data;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');
  int _requirePark() => _parkId ?? (throw const ApiException('Parco non disponibile.'));
  String _requireToken() => _token ?? (throw const ApiException('Installazione non registrata.'));

  String _cleanError(Object error) {
    if (error is ApiException) return error.message;
    if (error.toString().contains('SocketException') || error.toString().contains('Failed host lookup')) {
      return 'Backend non raggiungibile. Avvia Docker e verifica l’indirizzo API.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}
