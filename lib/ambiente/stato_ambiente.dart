import 'dart:async';

import 'package:flutter/foundation.dart';

import '../citizen_api.dart';
import '../modelli/ambiente.dart';

/// Dati ambientali del parco condivisi da Home e schermata Ambiente.
///
/// Si aggiorna all'apertura, con [ricarica] (pull-to-refresh), con i messaggi
/// `environment_*` del WebSocket e, mentre la Home è visibile, con un GET ogni
/// 60 secondi (necessario in demo e quando il WebSocket non è collegato).
class StatoAmbiente extends ChangeNotifier {
  StatoAmbiente({CitizenApi? api}) : _api = api ?? CitizenApi.instance {
    _live = _api.events.listen(_evento);
  }

  final CitizenApi _api;
  StreamSubscription<Map<String, dynamic>>? _live;
  Timer? _periodico;
  bool _chiuso = false;

  List<EnvMetric> metriche = const [];
  ParkEnvironment? ambiente;
  String? errore;
  bool caricamento = false;

  /// Allerte arrivate dal WebSocket, per stazione e metrica.
  final Map<int, Map<String, EnvAlert>> _allerteLive = {};

  EnvMetric? metrica(String nome) => metriche.where((m) => m.metric == nome).firstOrNull;

  /// Allerte da mostrare nel banner: quelle del WebSocket più quelle che
  /// risultano dalle letture (polveri o gas a livello scarso o peggiore).
  List<EnvAlert> get allerte {
    final a = ambiente;
    final perChiave = <String, EnvAlert>{};
    if (a != null) {
      for (final st in a.stations) {
        if (!st.fresh) continue;
        for (final r in st.readings) {
          if (!livelloDiAllerta(r.level)) continue;
          perChiave['${st.id}/${r.metric}'] = EnvAlert(
            parkId: a.parkId,
            stationId: st.id,
            metric: r.metric,
            value: r.value,
            level: r.level!,
            text: r.text ?? '',
            at: st.lastSeen,
          );
        }
      }
    }
    _allerteLive.forEach((stazione, perMetrica) {
      perMetrica.forEach((metrica, al) => perChiave['$stazione/$metrica'] = al);
    });
    final elenco = perChiave.values.toList()..sort((x, y) => y.level.index.compareTo(x.level.index));
    return elenco;
  }

  /// Carica catalogo e stato del parco. Senza [silenzioso] mostra il caricamento.
  Future<void> ricarica({bool silenzioso = false}) async {
    if (_chiuso) return;
    if (!silenzioso) {
      caricamento = true;
      notifyListeners();
    }
    try {
      final api = _api.treeyes;
      final parco = await _api.parcoInUso();
      final risultati = await Future.wait([if (metriche.isEmpty) api.environmentMetrics(), api.parkEnvironment(parco)]);
      if (_chiuso) return;
      if (risultati.length == 2) metriche = risultati.first as List<EnvMetric>;
      ambiente = risultati.last as ParkEnvironment;
      errore = null;
    } catch (e) {
      if (_chiuso) return;
      // Un aggiornamento silenzioso fallito non cancella i dati già mostrati.
      if (!silenzioso || ambiente == null) errore = _api.descriviErrore(e);
    }
    caricamento = false;
    notifyListeners();
  }

  /// Aggiornamento periodico, da accendere mentre la Home è visibile.
  void aggiornamentoPeriodico(bool attivo) {
    if (attivo == (_periodico != null)) return;
    _periodico?.cancel();
    _periodico = attivo ? Timer.periodic(const Duration(seconds: 60), (_) => ricarica(silenzioso: true)) : null;
  }

  void _evento(Map<String, dynamic> e) {
    final dati = e['data'];
    if (dati is! Map) return;
    final d = Map<String, dynamic>.from(dati);
    final parco = ambiente?.parkId;
    if (parco != null && d['park_id'] is num && (d['park_id'] as num).toInt() != parco) return;
    switch (e['type']) {
      case EventiAmbiente.lettura:
        final a = ambiente;
        if (a == null) return;
        ambiente = a.conLettura(EnvReadingEvent.fromJson(d));
        notifyListeners();
      case EventiAmbiente.allerta:
        final al = EnvAlert.fromJson(d);
        (_allerteLive[al.stationId] ??= {})[al.metric] = al;
        notifyListeners();
      case EventiAmbiente.allertaFinita:
        final stazione = (d['station_id'] as num?)?.toInt();
        if (stazione == null) return;
        _allerteLive.remove(stazione);
        notifyListeners();
        // Lo stato vero (livelli delle letture) arriva dal server.
        unawaited(ricarica(silenzioso: true));
      default:
        // Gli altri type non riguardano l'ambiente (e quelli sconosciuti si ignorano).
        break;
    }
  }

  @override
  void dispose() {
    _chiuso = true;
    _live?.cancel();
    _periodico?.cancel();
    super.dispose();
  }
}
