import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/citizen_api.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/mappa_parco.dart';

void main() {
  testWidgets('In modalità demo l’elenco mostra i dati simulati e la mappa', (tester) async {
    CitizenApi.instance.demoMode = true;
    addTearDown(() => CitizenApi.instance.demoMode = false);
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ParkApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('DEMO'), findsOneWidget);

    // La scheda «Mappa» apre subito la mappa delle segnalazioni.
    await tester.tap(find.text('Mappa'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MappaParco), findsOneWidget);
    // I segnaposto vicini si uniscono in gruppi: ce n'è almeno uno dei due tipi.
    expect(
      find.byType(Segnaposto).evaluate().length + find.byType(SegnapostoGruppo).evaluate().length,
      greaterThan(0),
    );

    // Il pannello sotto la mappa elenca le segnalazioni simulate.
    expect(find.text('Segnalazioni'), findsOneWidget);
    expect(find.text('Illuminazione'), findsWidgets);
  });
}
