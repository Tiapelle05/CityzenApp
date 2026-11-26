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
    await tester.pumpAndSettle();
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);
    Navigator.of(tester.element(find.text('SETTINGS'))).pop();
    await tester.pumpAndSettle();

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
}
