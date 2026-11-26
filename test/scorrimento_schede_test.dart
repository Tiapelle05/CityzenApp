import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/schermata_segnalazioni.dart';

/// Millisecondi tra il rilascio del dito e il carosello fermo.
Future<int> tempoPerFermarsi(WidgetTester tester, ScrollPhysics? fisica) async {
  final controller = PageController(viewportFraction: .9);
  addTearDown(controller.dispose);
  await tester.pumpWidget(const SizedBox()); // si riparte da zero
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: SizedBox(
        width: 400,
        height: 120,
        child: PageView.builder(
          controller: controller,
          physics: fisica,
          itemCount: 10,
          itemBuilder: (_, i) => ColoredBox(color: Colors.green, child: Text('$i')),
        ),
      ),
    ),
  ));
  await tester.fling(find.byType(PageView), const Offset(-120, 0), 600);
  var ms = 0;
  while (tester.binding.hasScheduledFrame) {
    await tester.pump(const Duration(milliseconds: 16));
    ms += 16;
  }
  expect(controller.page, closeTo(1, .01));
  return ms;
}

void main() {
  testWidgets('il carosello si ferma presto dopo uno scorrimento', (tester) async {
    final predefinito = await tempoPerFermarsi(tester, null);
    final rapido = await tempoPerFermarsi(tester, const SchedeRapide().applyTo(const ClampingScrollPhysics()));
    expect(rapido, lessThan(400));
    expect(rapido, lessThan(predefinito * .6));
  });
}
