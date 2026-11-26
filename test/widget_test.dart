import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/assistente/schermata_assistente.dart';
import 'package:flutter_application_1/citizen_api.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/mappa_parco.dart';
import 'package:flutter_application_1/schermata_segnalazioni.dart';

void main() {
  testWidgets('Tryees carica le cinque sezioni principali', (tester) async {
    CitizenApi.instance.testMode = true;
    addTearDown(() => CitizenApi.instance.testMode = false);

    await tester.pumpWidget(const ParkApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(BarraSchede), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Segnala'), findsOneWidget); // solo nella barra: niente doppioni in Home
    expect(find.text('Segnalate'), findsOneWidget); // riquadro «numero e parola» delle mie segnalazioni
    expect(find.text('Mappa'), findsOneWidget);
    expect(find.text('Aria'), findsOneWidget);
    // Il nome dell'assistente compare solo nella barra.
    expect(find.text(nomeAssistente), findsOneWidget);
    expect(find.text('Idee'), findsOneWidget);
    expect(find.text('Avvisi'), findsOneWidget);
    expect(find.byTooltip('Avvisi del parco'), findsOneWidget);
    expect(find.text('Ecco il parco in questo momento'), findsOneWidget);
    expect(find.text('Stato del parco'), findsNothing);
    expect(find.byType(AnteprimaMappa), findsOneWidget);
    // Le schede mai aperte non si costruiscono: all'avvio c'è solo la Home.
    expect(find.byType(SchermataSegnalazioni, skipOffstage: false), findsNothing);
    expect(find.byType(SchermataAssistente, skipOffstage: false), findsNothing);

    // La lingua si cambia dal menu laterale.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('EN'));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    expect(find.text('SETTINGS'), findsOneWidget);
    Navigator.of(tester.element(find.text('SETTINGS'))).pop();
    await tester.pump(); await tester.pump(const Duration(seconds: 1));

    expect(find.text('Open the map'), findsOneWidget);
    expect(find.text('Air'), findsOneWidget);

    // Scheda Aria e chat raggiungibili dalla barra in basso.
    await tester.tap(find.text('Air'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Air quality'), findsOneWidget);
    await tester.tap(find.text(nomeAssistente).first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hi, I’m $nomeAssistente'), findsOneWidget);
    // Tornando alla Home la chat resta costruita (la conversazione non si perde).
    await tester.tap(find.text('Home'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SchermataAssistente, skipOffstage: false), findsOneWidget);
  });

  testWidgets('Il tema scuro si sceglie dal menu e non chiude la scheda aperta', (tester) async {
    CitizenApi.instance.testMode = true;
    addTearDown(() {
      CitizenApi.instance.testMode = false;
      impostaTemaScuro(false);
    });

    await tester.pumpWidget(const ParkApp());
    await tester.pump();
    expect(temaScuro, isFalse);

    // Si apre la scheda Segnala, poi si cambia tema dal menu.
    await tester.tap(find.text('Segnala'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Scuro'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Scuro'));
    await tester.pump(const Duration(seconds: 1));
    Navigator.of(tester.element(find.text('Scuro'))).pop();
    await tester.pump(const Duration(seconds: 1));

    expect(temaScuro, isTrue);
    expect(Theme.of(tester.element(find.byType(BarraSchede))).brightness, Brightness.dark);
    // La scheda aperta resta la stessa e i testi prendono i colori scuri.
    expect(find.text('Segnala un problema'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Segnala un problema')).style?.color, testo);
  });
}
