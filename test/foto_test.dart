import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/ui.dart';

/// PNG 1×1 trasparente, come URL `data:` (lo stesso formato delle foto in demo).
const _png = 'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  testWidgets('La foto a schermo intero occupa tutto lo schermo e si chiude', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: const [FotoApribile(url: _png)])),
    ));

    await tester.tap(find.byType(FotoApribile));
    await tester.pumpAndSettle();

    // Il visualizzatore deve riempire lo schermo, non il solo riquadro del pulsante.
    expect(tester.getSize(find.byType(InteractiveViewer)), const Size(400, 800));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
