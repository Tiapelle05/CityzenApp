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
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Inizio'), findsOneWidget);
    expect(find.text('Segnala'), findsNWidgets(2)); // barra e scorciatoia della Home
    expect(find.text('Mappa'), findsOneWidget);
    expect(find.text('Aria'), findsOneWidget);
    // Il nome dell'assistente compare nella barra e tra le scorciatoie della Home.
    expect(find.text(nomeAssistente), findsNWidgets(2));
    expect(find.text('Idee'), findsOneWidget);
    expect(find.text('Avvisi'), findsOneWidget);
    expect(find.byTooltip('Avvisi del parco'), findsOneWidget);
    expect(find.text('Ecco il parco in questo momento'), findsOneWidget);
    expect(find.text('Stato del parco'), findsNothing);
    expect(find.byType(AnteprimaMappa), findsOneWidget);

    await tester.tap(find.byTooltip('Cambia lingua'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is CheckedPopupMenuItem<bool> && widget.value == true,
    ));
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
  });
}
