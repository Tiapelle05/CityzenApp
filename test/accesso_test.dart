import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/citizen_api.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  test('L’indirizzo del server si completa da solo', () {
    expect(CitizenApi.normalizzaServer('192.168.1.20'), 'http://192.168.1.20:8000');
    expect(CitizenApi.normalizzaServer(' 192.168.1.20:9000/ '), 'http://192.168.1.20:9000');
    expect(CitizenApi.normalizzaServer('http://10.0.0.5'), 'http://10.0.0.5:8000');
    expect(CitizenApi.normalizzaServer('https://api.treeyes.it'), 'https://api.treeyes.it');
    expect(CitizenApi.normalizzaServer(''), isNull);
    expect(CitizenApi.normalizzaServer('ftp://x'), isNull);
  });

  testWidgets('Senza server né demo si apre la pagina di accesso', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ParkApp());
    await tester.pump();

    expect(find.text('Collegati al server'), findsOneWidget);
    expect(find.text('Prova senza server (demo)'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // Indirizzo vuoto: messaggio chiaro, nessun tentativo di collegamento.
    await tester.tap(find.text('Collegati'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Scrivi l’indirizzo IP'), findsOneWidget);
  });
}
