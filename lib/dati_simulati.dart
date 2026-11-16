import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Dati simulati per la modalità demo: un parco reale (Parco Sempione, Milano)
/// con segnalazioni, idee e avvisi plausibili. Tutto resta in memoria: le
/// segnalazioni inviate in demo compaiono negli elenchi e avanzano di stato da sole,
/// come se una squadra le prendesse in carico.
///
/// Le risposte hanno la stessa forma di quelle del backend (/citizen/...).
class DatiSimulati {
  DatiSimulati._() {
    _semina();
  }
  static final DatiSimulati instance = DatiSimulati._();

  static const int idParco = 1;

  /// Asse del parco: dal Castello Sforzesco all'Arco della Pace.
  static const double _castelloLat = 45.47050, _castelloLon = 9.17930;
  static const double _arcoLat = 45.47560, _arcoLon = 9.17240;

  static final Map<String, dynamic> parco = {
    'id': idParco,
    'name': 'Parco Sempione',
    'city': 'Milano',
    'lat': 45.47300,
    'lon': 9.17590,
  };

  static const Map<String, String> etichetteStato = {
    'received': 'Ricevuta',
    'in_progress': 'In lavorazione',
    'resolved': 'Risolta',
    'closed': 'Chiusa',
  };

  static const List<Map<String, dynamic>> _categorie = [
    {'code': 'lighting', 'label': 'Illuminazione', 'icon': 'lightbulb', 'kinds': ['problem']},
    {'code': 'waste', 'label': 'Cestini e rifiuti', 'icon': 'delete', 'kinds': ['problem']},
    {'code': 'green', 'label': 'Verde e piante', 'icon': 'park', 'kinds': ['problem', 'suggestion']},
    {'code': 'fountains', 'label': 'Fontanelle', 'icon': 'water_drop', 'kinds': ['problem']},
    {'code': 'furniture', 'label': 'Arredi e panchine', 'icon': 'chair', 'kinds': ['problem', 'suggestion']},
    {'code': 'cleaning', 'label': 'Pulizia', 'icon': 'cleaning_services', 'kinds': ['problem']},
    {'code': 'play', 'label': 'Giochi e area sport', 'icon': 'sports_soccer', 'kinds': ['problem', 'suggestion']},
    {'code': 'other', 'label': 'Altro', 'icon': 'more_horiz', 'kinds': ['problem', 'suggestion']},
  ];

  final math.Random _caso = math.Random();
  final List<Map<String, dynamic>> _segnalazioni = [];
  final List<Map<String, dynamic>> _avvisi = [];
  final StreamController<Map<String, dynamic>> _eventi = StreamController.broadcast();
  int _prossimoId = 500;

  /// Eventi "live" con lo stesso formato del WebSocket /citizen/ws.
  Stream<Map<String, dynamic>> get eventi => _eventi.stream;

  /// Punto dentro il parco: [t] va da 0 (Castello) a 1 (Arco), [metri] è lo
  /// spostamento a destra (+) o a sinistra (−) dell'asse.
  static ({double lat, double lon}) punto(double t, double metri) {
    final lat = _castelloLat + (_arcoLat - _castelloLat) * t;
    final lon = _castelloLon + (_arcoLon - _castelloLon) * t;
    // Perpendicolare all'asse, in gradi (1° lat ≈ 111 km, 1° lon ≈ 78 km a Milano).
    return (lat: lat + metri * .69 / 111000, lon: lon + metri * .725 / 78000);
  }

  /// Posizione GPS simulata, sempre dentro il parco.
  ({double lat, double lon}) posizioneCasuale() =>
      punto(.3 + _caso.nextDouble() * .5, (_caso.nextDouble() - .5) * 240);

  String _iso(DateTime d) => d.toUtc().toIso8601String();

  String _etichettaCategoria(String code) =>
      (_categorie.firstWhere((c) => c['code'] == code, orElse: () => _categorie.last)['label']) as String;

  void _semina() {
    final ora = DateTime.now();
    var id = 400;

    void problema(String categoria, String descrizione, String priorita, double t, double metri,
        List<(String, Duration, String?)> storico, {bool mia = false, int? voto}) {
      final p = punto(t, metri);
      final inizio = ora.subtract(storico.first.$2);
      final ultimo = storico.last;
      id++;
      _segnalazioni.add({
        'id': id,
        'code': 'SEG-${inizio.year}-${id.toString().padLeft(6, '0')}',
        'kind': 'problem',
        'category': categoria,
        'category_label': _etichettaCategoria(categoria),
        'description': descrizione,
        'priority': priorita,
        'lat': p.lat,
        'lon': p.lon,
        'rating': voto,
        'photo_url': null,
        'status': ultimo.$1,
        'status_label': etichetteStato[ultimo.$1],
        'created_at': _iso(inizio),
        'updated_at': _iso(ora.subtract(ultimo.$2)),
        'is_mine': mia,
        'history': [
          for (final (stato, fa, nota) in storico)
            {'status': stato, 'at': _iso(ora.subtract(fa)), 'note': nota},
        ],
      });
    }

    problema('lighting', 'Due lampioni spenti lungo il viale che porta all’Arco della Pace: la sera il tratto è completamente al buio.', 'high', .82, 60, [
      ('received', const Duration(hours: 3), null),
    ]);
    problema('waste', 'Cestino pieno e rifiuti a terra vicino alle panchine del laghetto.', 'medium', .45, -40, [
      ('received', const Duration(hours: 26), null),
      ('in_progress', const Duration(hours: 20), 'Presa in carico dalla squadra di pulizia.'),
    ], mia: true);
    problema('green', 'Ramo spezzato appeso sopra il sentiero dietro la Torre Branca, rischia di cadere.', 'high', .62, -150, [
      ('received', const Duration(days: 2, hours: 4), null),
      ('in_progress', const Duration(days: 1, hours: 22), 'Area transennata, intervento dei giardinieri in programma.'),
    ]);
    problema('fountains', 'La fontanella accanto al ponte delle Sirenette perde acqua di continuo.', 'medium', .38, 70, [
      ('received', const Duration(days: 4), null),
      ('in_progress', const Duration(days: 3, hours: 18), null),
      ('resolved', const Duration(days: 1, hours: 2), 'Sostituita la valvola, la fontanella funziona di nuovo.'),
    ], mia: true, voto: 5);
    problema('furniture', 'Panchina con due assi rotte sul prato centrale, si rischia di farsi male.', 'medium', .55, 110, [
      ('received', const Duration(days: 1, hours: 5), null),
    ]);
    problema('cleaning', 'Scritte sui muretti all’ingresso di piazza Sempione.', 'low', .9, -20, [
      ('received', const Duration(days: 6), null),
      ('in_progress', const Duration(days: 5), null),
      ('resolved', const Duration(days: 2), 'Muretti ripuliti.'),
    ], voto: 4);
    problema('play', 'Altalena dell’area giochi bloccata con il nastro, una catena è staccata.', 'high', .7, 140, [
      ('received', const Duration(hours: 9), null),
      ('in_progress', const Duration(hours: 5), 'Gioco messo in sicurezza in attesa del ricambio.'),
    ]);
    problema('waste', 'Sacchi abbandonati vicino all’uscita verso via Legnano.', 'medium', .33, 160, [
      ('received', const Duration(days: 9), null),
      ('closed', const Duration(days: 8), 'Segnalazione duplicata: già rimossi durante il giro di raccolta.'),
    ]);
    problema('lighting', 'Il faro che illumina l’Acquario Civico lampeggia dopo le 21.', 'low', .3, 120, [
      ('received', const Duration(days: 3, hours: 2), null),
    ], mia: true);
    problema('green', 'Aiuola calpestata e irrigatore rotto vicino alla Triennale.', 'low', .58, -190, [
      ('received', const Duration(days: 12), null),
      ('in_progress', const Duration(days: 10), null),
      ('resolved', const Duration(days: 7), 'Aiuola risistemata e irrigatore sostituito.'),
    ]);

    void idea(String categoria, String titolo, String dettagli, Duration fa, {String stato = 'received', bool mia = false}) {
      id++;
      final quando = ora.subtract(fa);
      _segnalazioni.add({
        'id': id,
        'code': 'SEG-${quando.year}-${id.toString().padLeft(6, '0')}',
        'kind': 'suggestion',
        'category': categoria,
        'category_label': _etichettaCategoria(categoria),
        'description': '$titolo\n$dettagli',
        'status': stato,
        'status_label': etichetteStato[stato],
        'created_at': _iso(quando),
        'updated_at': _iso(quando),
        'is_mine': mia,
        'history': [{'status': 'received', 'at': _iso(quando), 'note': null}],
      });
    }

    idea('furniture', 'Più panchine all’ombra vicino al laghetto',
        'D’estate le poche panchine all’ombra sono sempre occupate: ne servirebbero altre sotto gli alberi.', const Duration(days: 1, hours: 3));
    idea('play', 'Un’area per i cani recintata',
        'Uno spazio chiuso dove lasciare i cani liberi senza disturbare chi fa picnic.', const Duration(days: 3), stato: 'in_progress');
    idea('green', 'Cartelli con i nomi degli alberi',
        'Piccole targhe con nome e storia degli alberi più grandi, utili anche per le scuole.', const Duration(days: 5), mia: true);
    idea('other', 'Fontanelle per riempire le borracce',
        'Un paio di punti acqua con l’erogatore per le borracce lungo il percorso di corsa.', const Duration(days: 8));

    _avvisi.addAll([
      {
        'id': 1,
        'title': 'Potatura alberi lungo viale Gadio',
        'body': 'Fino a venerdì il sentiero tra il Castello e il laghetto è chiuso dalle 8 alle 13 per lavori di potatura.',
        'level': 'warning',
        'starts_at': _iso(ora.subtract(const Duration(days: 1))),
        'ends_at': _iso(ora.add(const Duration(days: 3))),
      },
      {
        'id': 2,
        'title': 'Concerto all’aperto sabato sera',
        'body': 'Sabato dalle 20:30 concerto gratuito sul prato davanti all’Arco della Pace. Ingresso libero.',
        'level': 'info',
        'starts_at': _iso(ora.subtract(const Duration(hours: 6))),
        'ends_at': null,
      },
      {
        'id': 3,
        'title': 'Nuova raccolta differenziata',
        'body': 'Sono stati installati i nuovi cestini per carta, plastica e vetro vicino agli ingressi principali.',
        'level': 'info',
        'starts_at': _iso(ora.subtract(const Duration(days: 4))),
        'ends_at': null,
      },
    ]);
    _prossimoId = id + 1;
  }

  // ── Risposte come quelle del backend ────────────────────────────────────────

  Future<T> _ritardo<T>(T valore) async {
    // Una piccola attesa rende visibili caricamenti e transizioni, come con un server vero.
    await Future<void>.delayed(Duration(milliseconds: 250 + _caso.nextInt(250)));
    return valore;
  }

  Map<String, dynamic> _copia(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  Map<String, dynamic> statoParco() {
    final aperte = _segnalazioni
        .where((r) => r['kind'] == 'problem' && (r['status'] == 'received' || r['status'] == 'in_progress'))
        .length;
    final allerta = _avvisi.any((a) => a['level'] == 'alert');
    return {
      'park_id': idParco,
      'level': allerta ? 'alert' : aperte > 0 ? 'warning' : 'ok',
      'message': '',
      'open_issues': aperte,
      'updated_at': _iso(DateTime.now()),
      'highlights': const [],
    };
  }

  Future<List<Map<String, dynamic>>> parchi() => _ritardo([Map<String, dynamic>.of(parco)]);

  Future<Map<String, dynamic>> stato() => _ritardo(statoParco());

  Future<List<Map<String, dynamic>>> avvisi() => _ritardo(_avvisi.map(_copia).toList());

  Future<List<Map<String, dynamic>>> categorie() => _ritardo(_categorie.map(_copia).toList());

  List<Map<String, dynamic>> _ordinate(Iterable<Map<String, dynamic>> righe) =>
      (righe.map(_copia).toList()..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String)));

  Future<Map<String, dynamic>> feed({String? kind, int limit = 20}) {
    final righe = _ordinate(_segnalazioni.where((r) => kind == null || r['kind'] == kind)).take(limit).toList();
    return _ritardo({'items': righe, 'total': righe.length});
  }

  Future<Map<String, dynamic>> mie({int limit = 20}) {
    final righe = _ordinate(_segnalazioni.where((r) => r['is_mine'] == true)).take(limit).toList();
    return _ritardo({'items': righe, 'total': righe.length});
  }

  Future<Map<String, dynamic>> dettaglio(int id) async {
    final r = _segnalazioni.where((r) => r['id'] == id).firstOrNull;
    if (r == null) throw StateError('Segnalazione non trovata');
    return _ritardo(_copia(r));
  }

  Future<Map<String, dynamic>> crea({
    required String kind,
    required String category,
    required String description,
    String? priority,
    double? lat,
    double? lon,
    Uint8List? foto,
  }) async {
    final ora = DateTime.now();
    final id = _prossimoId++;
    final r = <String, dynamic>{
      'id': id,
      'code': 'SEG-${ora.year}-${id.toString().padLeft(6, '0')}',
      'kind': kind,
      'category': category,
      'category_label': _etichettaCategoria(category),
      'description': description,
      'priority': priority,
      'lat': lat,
      'lon': lon,
      'rating': null,
      // In demo la foto resta nel dispositivo: un data URL basta per mostrarla.
      'photo_url': foto == null || foto.isEmpty ? null : 'data:image/jpeg;base64,${base64Encode(foto)}',
      'status': 'received',
      'status_label': etichetteStato['received'],
      'created_at': _iso(ora),
      'updated_at': _iso(ora),
      'is_mine': true,
      'history': [{'status': 'received', 'at': _iso(ora), 'note': null}],
    };
    _segnalazioni.add(r);
    await _ritardo(null);
    _emetti('report_created', r);
    if (kind == 'problem') {
      // La "squadra" prende in carico il problema dopo qualche secondo.
      Timer(const Duration(seconds: 8), () => _avanza(r, 'in_progress', 'Presa in carico dalla squadra del parco.'));
    }
    return {
      'id': id,
      'code': r['code'],
      'kind': kind,
      'status': 'received',
      'status_label': r['status_label'],
      'created_at': r['created_at'],
      'photo_url': r['photo_url'],
    };
  }

  void _avanza(Map<String, dynamic> r, String stato, String? nota) {
    final ora = _iso(DateTime.now());
    r['status'] = stato;
    r['status_label'] = etichetteStato[stato];
    r['updated_at'] = ora;
    (r['history'] as List).add({'status': stato, 'at': ora, 'note': nota});
    _emetti('report_status_changed', r);
  }

  void _emetti(String tipo, Map<String, dynamic> r) {
    _eventi.add({
      'type': tipo,
      'data': {
        'report_id': r['id'],
        'park_id': idParco,
        'kind': r['kind'],
        'status': r['status'],
        'status_label': r['status_label'],
        'at': r['updated_at'],
      },
    });
    _eventi.add({'type': 'park_status_changed', 'data': {'park_id': idParco, ...statoParco()}});
  }
}
