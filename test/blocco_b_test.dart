import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/schermata_segnalazioni.dart';

void main() {
  const it = Copie(false);
  final oggi = DateTime(2026, 11, 24, 15);

  test('Le date degli avvisi si leggono a parole', () {
    expect(dataRelativa(DateTime(2026, 11, 24, 8), it, adesso: oggi), 'oggi');
    expect(dataRelativa(DateTime(2026, 11, 23, 23), it, adesso: oggi), 'ieri');
    expect(dataRelativa(DateTime(2026, 11, 21), it, adesso: oggi), '3 giorni fa');
    expect(dataRelativa(DateTime(2026, 11, 26), it, adesso: oggi), 'tra 2 giorni');
    expect(dataRelativa(DateTime(2026, 11, 2), it, adesso: oggi), '02/11');
  });

  testWidgets('Dopo l’invio compare la schermata di ringraziamento', (tester) async {
    bool? risultato;
    await tester.pumpWidget(MaterialApp(
      theme: temaTryees(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => risultato = await mostraSegnalazioneInviata(
            context,
            s: it,
            codice: 'SEG-2026-000123',
            stato: 'Ricevuta',
          ),
          child: const Text('invia'),
        ),
      ),
    ));
    await tester.tap(find.text('invia'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Segnalazione inviata'), findsOneWidget);
    expect(find.text('SEG-2026-000123'), findsOneWidget);
    await tester.tap(find.text('Vedi sulla mappa'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(risultato, isTrue);
    expect(find.text('Segnalazione inviata'), findsNothing);
  });

  testWidgets('La cronologia mostra lo stato attuale della segnalazione', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: temaTryees(),
      home: const Scaffold(body: SizedBox(width: 320, child: CronologiaStato(stato: 'in_progress', s: it))),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Ricevuta'), findsOneWidget);
    expect(find.text('In corso'), findsOneWidget);
    expect(find.text('Risolta'), findsOneWidget);
    expect(find.bySemanticsLabel('Stato: In corso'), findsOneWidget);
  });
}
