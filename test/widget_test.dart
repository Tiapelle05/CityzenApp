import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/assistente/schermata_assistente.dart';
import 'package:flutter_application_1/citizen_api.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/mappa_parco.dart';

void main() {
  testWidgets('Tryees carica le cinque sezioni principali', (tester) async {
    CitizenApi.instance.testMode = true;
    addTearDown(() => CitizenApi.instance.testMode = false);

    await tester.pumpWidget(const ParkApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(BarraSchede), findsOneWidget);
    expect(find.text('Inizio'), findsOneWidget);
    expect(find.text('Segnala'), findsOneWidget); // pulsante centrale della barra
    expect(find.text('Mappa'), findsOneWidget);
    expect(find.text('Aria'), findsOneWidget);
    expect(find.text(nomeAssistente), findsOneWidget);
    expect(find.text('Le mie segnalazioni'), findsOneWidget);
    expect(find.text('Idee'), findsOneWidget);
    expect(find.text('Avvisi'), findsOneWidget);
    expect(find.byTooltip('Avvisi del parco'), findsOneWidget);
    expect(find.text('Ecco il parco in questo momento'), findsOneWidget);
    expect(find.text('Stato del parco'), findsNothing);
    expect(find.byType(AnteprimaMappa), findsOneWidget);

    // Lingua dal pannello Impostazioni.
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('🇬🇧  English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Settings'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Open the map'), findsOneWidget);
    expect(find.text('Air'), findsOneWidget);

    // Scheda Aria e chat raggiungibili dalla barra in basso.
    await tester.tap(find.text('Air'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Air quality'), findsOneWidget);
    await tester.tap(find.text(nomeAssistente).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hi, I’m $nomeAssistente'), findsOneWidget);
  });

  testWidgets('Il tema scuro si attiva e si disattiva con un tocco', (tester) async {
    CitizenApi.instance.testMode = true;
    addTearDown(() {
      CitizenApi.instance.testMode = false;
      impostaTemaScuro(false);
    });

    await tester.pumpWidget(const ParkApp());
    await tester.pump();
    expect(temaScuro, isFalse);

    await tester.tap(find.byTooltip('Passa al tema scuro'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(temaScuro, isTrue);
    expect(Theme.of(tester.element(find.byType(BarraSchede))).brightness, Brightness.dark);

    await tester.tap(find.byTooltip('Passa al tema chiaro'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(temaScuro, isFalse);
  });
}
