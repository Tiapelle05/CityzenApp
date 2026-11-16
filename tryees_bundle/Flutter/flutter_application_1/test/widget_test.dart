import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/citizen_api.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('Tryees carica le cinque sezioni principali', (tester) async {
    CitizenApi.instance.testMode = true;
    addTearDown(() => CitizenApi.instance.testMode = false);

    await tester.pumpWidget(const ParkApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Inizio'), findsOneWidget);
    expect(find.text('Segnala'), findsOneWidget);
    expect(find.text('Elenco'), findsOneWidget);
    expect(find.text('Idee'), findsOneWidget);
    expect(find.text('Avvisi'), findsOneWidget);
    expect(find.text('Esplora il parco'), findsOneWidget);
    expect(find.text('Buono'), findsOneWidget);
    expect(find.text('Nessuna criticità aperta segnalata.'), findsOneWidget);

    await tester.tap(find.byTooltip('Cambia lingua'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is CheckedPopupMenuItem<bool> && widget.value == true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Good'), findsOneWidget);
    expect(find.text('No open issues are currently reported.'), findsOneWidget);
  });
}
