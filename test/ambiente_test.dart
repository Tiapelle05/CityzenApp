import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/ambiente/formato_ambiente.dart';
import 'package:flutter_application_1/ambiente/grafici_ambiente.dart';
import 'package:flutter_application_1/ambiente/scheda_aria.dart';
import 'package:flutter_application_1/ambiente/stato_ambiente.dart';
import 'package:flutter_application_1/api/mock_treeyes_api.dart';
import 'package:flutter_application_1/api/treeyes_api.dart';
import 'package:flutter_application_1/assistente/schermata_assistente.dart';
import 'package:flutter_application_1/citizen_api.dart';
import 'package:flutter_application_1/modelli/ambiente.dart';
import 'package:flutter_application_1/ui.dart';

Map<String, dynamic> _file(String nome) =>
    jsonDecode(File('Assets/mock/$nome').readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const it = Copie(false);

  group('Modelli', () {
    test('livello sconosciuto diventa unknown', () {
      expect(parseLevel('good'), EnvLevel.good);
      expect(parseLevel('tremendo'), EnvLevel.unknown);
      expect(parseLevel(null), EnvLevel.unknown);
    });

    test('park_environment.json', () {
      final a = ParkEnvironment.fromJson(_file('park_environment.json'));
      expect(a.airQuality.level, EnvLevel.good);
      expect(a.stations, hasLength(1));
      final st = a.stations.first;
      expect(st.fresh, isTrue);
      expect(st.lettura('temperature')!.value, 14.0);
      expect(st.lettura('temperature')!.level, isNull);
      expect(st.lettura('dust')!.level, EnvLevel.good);
      expect(st.spark24h['temperature'], isNotEmpty);
    });

    test('scenari limite', () {
      final spenta = ParkEnvironment.fromJson(_file('park_environment_offline.json'));
      expect(spenta.stations.first.online, isFalse);
      expect(spenta.stations.first.fresh, isFalse);
      expect(spenta.airQuality.level, EnvLevel.unknown);

      final gas = ParkEnvironment.fromJson(_file('park_environment_warming_up.json')).stations.first.lettura('gas')!;
      expect(gas.value, isNull);
      expect(gas.level, EnvLevel.unknown);

      final polveri = ParkEnvironment.fromJson(_file('park_environment_dust_high.json'));
      expect(polveri.airQuality.level, EnvLevel.poor);
    });

    test('serie e risposta dell’assistente', () {
      final serie = EnvSeries.fromJson(_file('environment_series_dust_7d.json'));
      expect(serie.range, '7d');
      expect(serie.bucketMinutes, 30);
      expect(serie.points, isNotEmpty);

      final r = AssistantReply.fromJson(_file('assistant_reply.json'));
      expect(r.mode, 'rules');
      expect(r.sources.single.type, TipiFonte.ambiente);
      expect(r.sources.single.stationId, 1);
      expect(r.disclaimer, isNotEmpty);
    });

    test('environment_reading aggiorna valore, min e max', () {
      final a = ParkEnvironment.fromJson(_file('park_environment.json'));
      final dopo = a.conLettura(EnvReadingEvent.fromJson({
        'park_id': 1,
        'station_id': 1,
        'at': '2026-11-18T15:13:00Z',
        'readings': [
          {'metric': 'temperature', 'value': 15.2, 'level': null},
          {'metric': 'dust', 'value': 80, 'level': 'poor'},
        ],
      }));
      final st = dopo.stations.first;
      expect(st.lettura('temperature')!.value, 15.2);
      expect(st.lettura('temperature')!.max24h, 15.2);
      expect(st.lettura('dust')!.level, EnvLevel.poor);
      expect(st.lastSeen, DateTime.utc(2026, 11, 18, 15, 13));
    });
  });

  group('Formattazione', () {
    test('numeri all’italiana con i decimali del catalogo', () {
      final temp = EnvMetric.fromJson({'metric': 'temperature', 'label': 'Temperatura', 'unit': '°C', 'decimals': 1});
      final gas = EnvMetric.fromJson({'metric': 'gas', 'label': 'Gas', 'unit': '', 'decimals': 2});
      expect(formattaValore(13.94, temp, it), '13,9 °C');
      expect(formattaValore(0.98, gas, it), '0,98');
      expect(formattaValore(null, gas, it), '—');
      expect(unitaMostrata(gas, it), 'indice');
    });
  });

  group('Assistente', () {
    test('cronologia: ultimi 10 turni, al massimo 1000 caratteri', () {
      final turni = [for (var i = 0; i < 14; i++) ChatTurn(i.isEven ? 'user' : 'assistant', 'x' * (i == 13 ? 1500 : 5))];
      final c = LimitiAssistente.cronologia(turni);
      expect(c, hasLength(10));
      expect(c.first.content, turni[4].content);
      expect(c.last.content.length, 1000);
    });
  });

  group('Grafico', () {
    test('i buchi oltre due bucket interrompono la linea', () {
      final serie = EnvSeries(
        stationId: 1,
        bucketMinutes: 5,
        metric: 'dust',
        unit: 'µg/m³',
        range: '24h',
        points: [
          SeriesPoint(t: DateTime.utc(2026, 1, 1, 10, 0), avg: 1),
          SeriesPoint(t: DateTime.utc(2026, 1, 1, 10, 5), avg: 2),
          SeriesPoint(t: DateTime.utc(2026, 1, 1, 10, 10), avg: 3),
          // 20 minuti di vuoto: più di due bucket
          SeriesPoint(t: DateTime.utc(2026, 1, 1, 10, 30), avg: 4),
        ],
      );
      final spots = GraficoSerie.spotConBuchi(serie, (p) => p.avg);
      expect(spots.where((s) => s.isNull()), hasLength(1));
      expect(spots[3].isNull(), isTrue);
    });
  });

  group('Mock', () {
    final ora = DateTime.utc(2026, 12, 1, 9, 30);
    final api = MockTreeyesApi(ritardi: false, orologio: () => ora);
    tearDown(() => MockTreeyesApi.scenario = ScenariAmbiente.normale);

    test('le date vengono portate a oggi', () async {
      final a = await api.parkEnvironment(7);
      expect(a.parkId, 7);
      expect(a.updatedAt, ora);
      expect(a.stations.first.lastSeen, ora);
    });

    test('scenario offline e serie ricostruite', () async {
      MockTreeyesApi.scenario = ScenariAmbiente.spenta;
      final a = await api.parkEnvironment(1);
      expect(a.stations.first.fresh, isFalse);
      expect(a.stations.first.lastSeen.isBefore(ora), isTrue);

      final mese = await api.environmentSeries(1, metric: 'temperature', range: '30d');
      expect(mese.bucketMinutes, 120);
      expect(mese.points.length, greaterThan(300));
      expect(mese.points.last.t.isBefore(ora), isTrue);
    });
  });

  group('Widget', () {
    setUp(() => CitizenApi.instance.testMode = true);
    tearDown(() {
      CitizenApi.instance.testMode = false;
      MockTreeyesApi.scenario = ScenariAmbiente.normale;
    });

    Future<StatoAmbiente> stato(WidgetTester tester) async {
      final st = StatoAmbiente();
      addTearDown(st.dispose);
      await tester.runAsync(st.ricarica);
      return st;
    }

    testWidgets('card "Aria nel parco" e banner con polveri alte', (tester) async {
      MockTreeyesApi.scenario = ScenariAmbiente.polveriAlte;
      final st = await stato(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            BannerAllerteAmbiente(stato: st, s: it, onApri: () {}),
            SchedaAriaParco(stato: st, s: it, onApri: () {}),
          ]),
        ),
      ));
      await tester.pump();
      expect(find.text('ARIA NEL PARCO'), findsOneWidget);
      expect(find.textContaining('Polveri sottili: scarsa'), findsOneWidget);
    });

    testWidgets('allerta dal WebSocket e chiusura', (tester) async {
      final st = await stato(tester);
      expect(st.allerte, isEmpty);
      CitizenApi.instance.testMode = true;
      // Gli eventi del socket passano dallo stesso stream di CitizenApi.
      final evento = {
        'type': 'environment_alert',
        'data': {
          'park_id': 1,
          'station_id': 1,
          'metric': 'gas',
          'value': 3.4,
          'level': 'bad',
          'text': 'Molto elevato',
          'at': '2026-11-18T15:12:00Z',
        },
      };
      CitizenApi.instance.emettiEvento(evento);
      await tester.pump();
      expect(st.allerte.single.level, EnvLevel.bad);
      CitizenApi.instance.emettiEvento({'type': 'tipo_futuro', 'data': {'park_id': 1}});
      CitizenApi.instance.emettiEvento({
        'type': 'environment_alert_ended',
        'data': {'park_id': 1, 'station_id': 1, 'at': '2026-11-18T15:30:00Z'},
      });
      await tester.pump();
      expect(st.allerte, isEmpty);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    });

    testWidgets('chat: domanda suggerita, risposta e fonti', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: temaTryees(), home: const SchermataAssistente(s: it)));
      expect(find.textContaining('Non scrivere dati personali.'), findsOneWidget);
      await tester.tap(find.text('Com’è l’aria adesso?'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.textContaining('Aria buona'), findsOneWidget);
      expect(find.text('Dati ambientali'), findsOneWidget);
    });
  });
}
