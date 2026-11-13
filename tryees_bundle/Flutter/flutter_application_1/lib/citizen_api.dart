import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Client REST per le API cittadino di Tryees.
/// L'URL può essere sovrascritto con --dart-define=API_BASE_URL=... .
class CitizenApi {
  CitizenApi._();
  static final CitizenApi instance = CitizenApi._();

  static const String _configuredUrl = String.fromEnvironment('API_BASE_URL');
  static const String _installIdKey = 'tryees_install_id';
  static const String _tokenKey = 'tryees_access_token';
  static const String _parkIdKey = 'tryees_park_id';
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
    } catch (e) {
      initializationError = _cleanError(e);
      rethrow;
    }
  }

  Future<void> _ensureReady() async {
    if (!isReady) await initialize();
  }

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
    await prefs.setInt(_parkIdKey, _parkId!);
    return parks;
  }

  Future<Map<String, dynamic>> getParkStatus() async {
    if (testMode) { _cachedParkStatus = {'level': 'ok', 'message': 'Test'}; return _cachedParkStatus!; }
    await _ensureReady();
    final id = _requirePark();
    _cachedParkStatus = (await _get('/citizen/parks/$id/status')) as Map<String, dynamic>;
    return _cachedParkStatus!;
  }

  Future<List<Map<String, dynamic>>> getNotices() async {
    if (testMode) return [];
    await _ensureReady();
    final id = _requirePark();
    return ((await _get('/citizen/parks/$id/notices')) as List)
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getCategories() async =>
      ((await _get('/citizen/categories')) as List).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> getIdeas({String sort = 'recent'}) async {
    if (testMode) return {'items': <Map<String, dynamic>>[], 'total': 0};
    await _ensureReady();
    final id = _requirePark();
    return (await _get('/citizen/ideas?park_id=$id&sort=$sort&skip=0&limit=50'))
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createIdea({
    required String title,
    required String description,
    required bool isPrivate,
  }) async {
    await _ensureReady();
    final id = _requirePark();
    return (await _postJson('/citizen/ideas', {
      'park_id': id,
      'title': title,
      'description': description,
      'visibility': isPrivate ? 'private' : 'public',
      'client_ref': _uuid.v4(),
    })) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> voteIdea(int ideaId) async {
    await _ensureReady();
    return (await _postJson('/citizen/ideas/$ideaId/vote', const {}))
          as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> removeIdeaVote(int ideaId) async {
    await _ensureReady();
    return (await _delete('/citizen/ideas/$ideaId/vote')) as Map<String, dynamic>;
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
    await _ensureReady();
    final id = _requirePark();
    final request = http.MultipartRequest('POST', _uri('/citizen/reports'));
    request.headers['Authorization'] = 'Bearer ${_requireToken()}';
    request.fields.addAll({
      'kind': 'problem',
      'park_id': '$id',
      'description': description,
      'client_ref': _uuid.v4(),
      'category': category,
      'priority': priority,
      'lat': '$latitude',
      'lon': '$longitude',
    });
    if (photoBytes != null && photoBytes.isNotEmpty) {
      request.files.add(http.MultipartFile.fromBytes(
        'photo',
        photoBytes,
        filename: photoName ?? 'segnalazione.jpg',
      ));
    }
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);
    return _decode(response) as Map<String, dynamic>;
  }

  Future<dynamic> _get(String path) => _request('GET', path);
  Future<dynamic> _delete(String path) => _request('DELETE', path);

  Future<dynamic> _postJson(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: body);

  Future<dynamic> _request(String method, String path,
      {Map<String, dynamic>? body}) async {
    if (_token == null) await initialize();
    final headers = <String, String>{'Authorization': 'Bearer ${_requireToken()}'};
    if (body != null) headers['Content-Type'] = 'application/json';
    late http.Response response;
    final uri = _uri(path);
    if (method == 'GET') {
      response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    } else if (method == 'POST') {
      response = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 20));
    } else {
      response = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 20));
    }
    return _decode(response);
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
        message = detail is String ? detail : detail.toString();
      }
      throw ApiException(message);
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
  const ApiException(this.message);
  @override
  String toString() => message;
}
