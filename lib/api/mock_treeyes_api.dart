import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../dati_simulati.dart';
import '../modelli/ambiente.dart';
import 'treeyes_api.dart';

/// Scenari dei dati ambientali simulati (file `Assets/mock/park_environment_*.json`).
abstract final class ScenariAmbiente {
  static const normale = 'normal';
  static const polveriAlte = 'dust_high';
  static const spenta = 'offline';
  static const preriscaldamento = 'warming_up';
  static const tutti = [normale, polveriAlte, spenta, preriscaldamento];
}

/// [TreeyesApi] simulata: legge i JSON generati dal backend in `Assets/mock/`.
///
/// Le date dei file vengono spostate a oggi, così le letture sembrano appena
/// arrivate. Lo scenario si sceglie con `--dart-define=ENV_SCENARIO=dust_high`
/// oppure dal menu della schermata Ambiente in demo.
class MockTreeyesApi implements TreeyesApi {
  MockTreeyesApi({AssetBundle? bundle, DateTime Function()? orologio, this.ritardi = true})
    : _bundle = bundle ?? rootBundle,
      _ora = orologio ?? DateTime.now;

  /// Scenario in uso (vale per tutta l'app).
  static String scenario = const String.fromEnvironment('ENV_SCENARIO', defaultValue: ScenariAmbiente.normale);

  final AssetBundle _bundle;
  final DateTime Function() _ora;

  /// Falso nei test: nessuna attesa simulata.
  final bool ritardi;

  static const _cartella = 'Assets/mock';

  Future<dynamic> _json(String nome) async => jsonDecode(await _bundle.loadString('$_cartella/$nome'));

  Future<void> _attesa(int ms) async {
    if (ritardi) await Future<void>.delayed(Duration(milliseconds: ms));
  }

  @override
  Future<List<EnvMetric>> environmentMetrics() async {
    final dati = await _json('environment_metrics.json') as List;
    return [for (final m in dati.cast<Map<String, dynamic>>()) EnvMetric.fromJson(m)];
  }

  @override
  Future<ParkEnvironment> parkEnvironment(int parkId) async {
    await _attesa(300);
    final file = scenario == ScenariAmbiente.normale ? 'park_environment.json' : 'park_environment_$scenario.json';
    final dati = Map<String, dynamic>.from(await _json(file) as Map);
    final spostamento = _arrotondaAlMinuto(_ora().toUtc()).difference(await _momentoGenerazione());
    _spostaDate(dati, spostamento);
    dati['park_id'] = parkId;
    if (scenario != ScenariAmbiente.spenta) _variaLetture(dati);
    return ParkEnvironment.fromJson(dati);
  }

  @override
  Future<EnvSeries> environmentSeries(
    int parkId, {
    required String metric,
    String range = '24h',
    int? stationId,
  }) async {
    await _attesa(350);
    final Map<String, dynamic> dati;
    try {
      dati = Map<String, dynamic>.from(await _json('environment_series_${metric}_$range.json') as Map);
    } catch (_) {
      // Per gli intervalli senza file si ricostruisce la serie dal giorno tipo delle 24 ore.
      return _serieDaGiornoTipo(metric, range, stationId);
    }
    final punti = (dati['points'] as List).cast<Map<String, dynamic>>();
    if (punti.isNotEmpty) {
      final bucket = (dati['bucket_minutes'] as num).toInt();
      final ultimo = DateTime.parse(punti.last['t'] as String).add(Duration(minutes: bucket));
      _spostaDate(dati, _arrotondaAlMinuto(_ora().toUtc()).difference(ultimo));
    }
    if (stationId != null) dati['station_id'] = stationId;
    return EnvSeries.fromJson(dati);
  }

  @override
  Future<AssistantReply> askAssistant(int parkId, String question, List<ChatTurn> history) async {
    // Attesa visibile: si vede l'indicatore "sta scrivendo…".
    await _attesa(1400);
    final base = AssistantReply.fromJson(Map<String, dynamic>.from(await _json('assistant_reply.json') as Map));
    final q = question.toLowerCase();
    // Presentazione, come la regola del backend (nome uguale a `nomeAssistente`)
    if (['chi sei', 'come ti chiami', 'il tuo nome', 'cosa sai fare', 'cosa puoi fare', 'presentati'].any(q.contains)) {
      return _risposta(
        base,
        _elenco('Sono Parky, l’assistente del parco. Posso dirti:', [
          'com’è l’aria adesso',
          'se ci sono avvisi',
          'a che punto sono le tue segnalazioni',
          'quali idee sono state proposte',
          'cosa puoi segnalare',
        ]),
        const [],
      );
    }
    if (q.contains('avvis')) {
      final avvisi = await DatiSimulati.instance.avvisi();
      return _risposta(
        base,
        avvisi.isEmpty
            ? 'Non ci sono avvisi in corso nel parco.'
            : _elenco(
                avvisi.length == 1 ? 'C’è un avviso in corso:' : 'Ci sono ${avvisi.length} avvisi in corso:',
                [for (final a in avvisi) '${a['title']}: ${a['body']}'],
              ),
        [
          for (final a in avvisi)
            AssistantSource(type: TipiFonte.avviso, id: (a['id'] as num).toInt(), title: a['title'] as String?),
        ],
      );
    }
    // Le idee prima delle segnalazioni: "segnalare un'idea" parla di idee.
    if (RegExp(r'\bide[ae]\b|\bideas?\b|propost|propor|suggeriment').hasMatch(q)) {
      final idee = ((await DatiSimulati.instance.feed(kind: 'suggestion', limit: 5))['items'] as List)
          .cast<Map<String, dynamic>>();
      if (idee.isEmpty) {
        return _risposta(base, 'Non ci sono ancora idee per il parco: puoi proporne una tu.', const []);
      }
      return _risposta(
        base,
        _elenco(
          idee.length == 1 ? 'C’è un’idea proposta per il parco:' : 'Ci sono ${idee.length} idee proposte per il parco:',
          [
            for (final i in idee)
              '${titoloSegnalazione(i)} – ${(i['status_label'] as String).toLowerCase()}'
                  '${i['is_mine'] == true ? ' (tua)' : ''}',
          ],
        ),
        [
          for (final i in idee) AssistantSource(type: TipiFonte.idea, id: (i['id'] as num).toInt(), title: titoloSegnalazione(i)),
        ],
      );
    }
    if (q.contains('segnalazion')) {
      final mie = ((await DatiSimulati.instance.mie(limit: 20))['items'] as List)
          .cast<Map<String, dynamic>>()
          .where((r) => r['kind'] != 'suggestion')
          .take(3)
          .toList();
      if (mie.isEmpty) return _risposta(base, 'Non hai ancora inviato segnalazioni.', const []);
      return _risposta(
        base,
        _elenco(
          mie.length == 1 ? 'Hai una segnalazione:' : 'Ecco le tue segnalazioni più recenti:',
          [for (final r in mie) '${titoloSegnalazione(r)} – ${(r['status_label'] as String).toLowerCase()}'],
        ),
        [
          for (final r in mie)
            AssistantSource(type: TipiFonte.miaSegnalazione, id: (r['id'] as num).toInt(), title: titoloSegnalazione(r)),
        ],
      );
    }
    if (q.contains('segnal') || q.contains('categori')) {
      final cat = await DatiSimulati.instance.categorie();
      return _risposta(
        base,
        '${_elenco('Puoi segnalare problemi su:', [for (final c in cat) c['label'] as String])}\n\n'
        'Per segnalare usa la scheda Segnala dell’app.',
        const [AssistantSource(type: TipiFonte.categorie)],
      );
    }
    if (q.contains('temperatura') || q.contains('ieri') || q.contains('caldo') || q.contains('freddo')) {
      final ieri = _ora().toUtc().subtract(const Duration(days: 1));
      return _risposta(base, _elenco('Temperatura nelle ultime 24 ore:', ['adesso: circa 14 °C', 'minima: 4,6 °C', 'massima: 14,1 °C']), [
        AssistantSource(
          type: TipiFonte.ambiente,
          stationId: 1,
          metric: Metriche.temperatura,
          from: ieri,
          to: _ora().toUtc(),
        ),
      ]);
    }
    return base;
  }

  /// Come le risposte del backend: una frase breve e poi un punto per riga.
  static String _elenco(String intro, List<String> voci) =>
      [intro, for (final v in voci) '• ${v[0].toUpperCase()}${v.substring(1)}'].join('\n');

  AssistantReply _risposta(AssistantReply base, String testo, List<AssistantSource> fonti) =>
      AssistantReply(answer: testo, sources: fonti, mode: base.mode, model: base.model, disclaimer: base.disclaimer);

  // ── Supporto ───────────────────────────────────────────────────────────────

  DateTime? _generazione;

  /// Momento in cui il backend ha generato i file: `updated_at` dello scenario normale.
  /// Tutti gli scenari si spostano della stessa quantità, così la stazione spenta
  /// resta indietro di qualche ora come nel file.
  Future<DateTime> _momentoGenerazione() async => _generazione ??=
      DateTime.parse((await _json('park_environment.json') as Map)['updated_at'] as String);

  static DateTime _arrotondaAlMinuto(DateTime d) => DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);

  static const _campiData = {'updated_at', 'last_seen', 't', 'at', 'from', 'to'};

  /// Sposta in avanti tutte le date del JSON della stessa quantità (le distanze restano uguali).
  static void _spostaDate(Object? nodo, Duration spostamento) {
    if (nodo is Map) {
      for (final k in nodo.keys.toList()) {
        final v = nodo[k];
        if (_campiData.contains(k) && v is String) {
          final d = DateTime.tryParse(v);
          if (d != null) nodo[k] = d.toUtc().add(spostamento).toIso8601String();
        } else {
          _spostaDate(v, spostamento);
        }
      }
    } else if (nodo is List) {
      for (final v in nodo) {
        _spostaDate(v, spostamento);
      }
    }
  }

  /// Piccole variazioni minuto per minuto: in demo i valori si muovono come quelli veri.
  void _variaLetture(Map<String, dynamic> dati) {
    final minuto = _ora().millisecondsSinceEpoch ~/ 60000;
    for (final st in (dati['stations'] as List).cast<Map<String, dynamic>>()) {
      for (final r in (st['readings'] as List).cast<Map<String, dynamic>>()) {
        final v = (r['value'] as num?)?.toDouble();
        if (v == null) continue;
        final onda = math.sin(minuto / 7 + r['metric'].hashCode % 10);
        r['value'] = switch (r['metric']) {
          Metriche.temperatura => ((v + .2 * onda) * 10).roundToDouble() / 10,
          Metriche.gas => ((v + .02 * onda) * 100).roundToDouble() / 100,
          _ => (v * (1 + .02 * onda)).roundToDouble(),
        };
        final nuovo = r['value'] as double;
        final min = (r['min_24h'] as num?)?.toDouble();
        final max = (r['max_24h'] as num?)?.toDouble();
        if (min != null && nuovo < min) r['min_24h'] = nuovo;
        if (max != null && nuovo > max) r['max_24h'] = nuovo;
      }
    }
  }

  /// Serie `7d` o `30d` costruita ripetendo il giorno tipo del file 24 h, con
  /// un andamento lento da un giorno all'altro. Solo per la demo.
  Future<EnvSeries> _serieDaGiornoTipo(String metric, String range, int? stationId) async {
    final base = await environmentSeries(0, metric: metric, range: Intervalli.giorno);
    final bucket = range == Intervalli.mese ? 120 : 30;
    final giorni = range == Intervalli.mese ? 30 : 7;
    final profilo = <int, List<SeriesPoint>>{};
    for (final p in base.points) {
      final minutoDelGiorno = p.t.hour * 60 + p.t.minute;
      profilo.putIfAbsent(minutoDelGiorno ~/ bucket, () => []).add(p);
    }
    final fine = _arrotondaAlMinuto(_ora().toUtc());
    final inizio = fine.subtract(Duration(days: giorni));
    final punti = <SeriesPoint>[];
    for (var t = inizio; t.isBefore(fine); t = t.add(Duration(minutes: bucket))) {
      final fascia = profilo[(t.hour * 60 + t.minute) ~/ bucket];
      if (fascia == null || fascia.isEmpty) continue;
      final giorno = t.difference(inizio).inHours / 24;
      final fattore = 1 + .08 * math.sin(giorno / 2.3) + .04 * math.sin(giorno * 1.7);
      double? media(Iterable<double?> xs) {
        final v = xs.whereType<double>().toList();
        return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
      }

      double? scala(double? v) => v == null ? null : v * fattore;
      punti.add(
        SeriesPoint(
          t: t,
          avg: scala(media(fascia.map((p) => p.avg))),
          min: scala(
            fascia.map((p) => p.min).whereType<double>().fold<double?>(null, (a, b) => a == null || b < a ? b : a),
          ),
          max: scala(
            fascia.map((p) => p.max).whereType<double>().fold<double?>(null, (a, b) => a == null || b > a ? b : a),
          ),
        ),
      );
    }
    return EnvSeries(
      stationId: stationId ?? base.stationId,
      bucketMinutes: bucket,
      metric: metric,
      unit: base.unit,
      range: range,
      points: punti,
    );
  }
}
