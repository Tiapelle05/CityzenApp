import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/barra_schede.dart';
import 'package:flutter_application_1/ui.dart';

final _voci = [
  VoceBarra(icona: Icons.home_outlined, iconaScelta: Icons.home_rounded, etichetta: 'A', accento: Accento.verde),
  VoceBarra(icona: Icons.add_outlined, iconaScelta: Icons.add, etichetta: 'B', accento: Accento.arancio),
  VoceBarra(icona: Icons.map_outlined, iconaScelta: Icons.map_rounded, etichetta: 'C', accento: Accento.blu),
  VoceBarra(icona: Icons.air_rounded, iconaScelta: Icons.air_rounded, etichetta: 'D', accento: Accento.acqua),
  VoceBarra(icona: Icons.forum_outlined, iconaScelta: Icons.forum_rounded, etichetta: 'E', accento: Accento.viola),
];

/// Quanto [c] è andato da [da] verso [a] (0 = fermo, 1 = arrivato), sul canale
/// che cambia di più.
double _avanzamento(Color da, Color a, Color c) {
  final canali = [(da.r, a.r, c.r), (da.g, a.g, c.g), (da.b, a.b, c.b)];
  final (x, y, z) = canali.reduce((p, q) => (p.$2 - p.$1).abs() >= (q.$2 - q.$1).abs() ? p : q);
  return (z - x) / (y - x);
}

void main() {
  late int indice;

  Future<void> monta(WidgetTester tester) async {
    indice = 0;
    await tester.binding.setSurfaceSize(const Size(500, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          bottomNavigationBar: BarraSchede(
            voci: _voci,
            indice: indice,
            onScelta: (i) => setState(() => indice = i),
          ),
        ),
      ),
    ));
  }

  double centroIndicatore(WidgetTester tester) => tester.getCenter(find.byKey(BarraSchede.chiaveIndicatore)).dx;
  double centroVoce(WidgetTester tester, String etichetta) => tester.getCenter(find.text(etichetta)).dx;
  Color coloreEtichetta(WidgetTester tester, String etichetta) => tester.widget<Text>(find.text(etichetta)).style!.color!;

  testWidgets('una voce si colora solo quando l’indicatore le arriva sopra', (tester) async {
    await monta(tester);
    final da = centroVoce(tester, 'A'), a = centroVoce(tester, 'C');
    final passo = (a - da) / 2; // larghezza di una voce
    expect(centroIndicatore(tester), moreOrLessEquals(da, epsilon: .5));
    expect(coloreEtichetta(tester, 'A'), Accento.verde.forte);

    await tester.tap(find.text('C'));
    await tester.pump();
    // Al primo fotogramma non è cambiato ancora nulla: niente colore in anticipo.
    expect(coloreEtichetta(tester, 'C'), testoSecondario);
    expect(centroIndicatore(tester), moreOrLessEquals(da, epsilon: .5));

    // Più fotogrammi lungo la corsa: in ognuno il colore delle etichette
    // corrisponde a quanto l'indicatore è vicino; B, solo attraversata, resta grigia.
    var visteMeta = 0;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      final posizione = (centroIndicatore(tester) - da) / passo; // 0 = su A, 2 = su C
      if (posizione > .05 && posizione < 1.95) visteMeta++;
      final attesaC = (1 - (posizione - 2).abs()).clamp(0.0, 1.0);
      final attesaA = (1 - posizione).clamp(0.0, 1.0);
      expect(_avanzamento(testoSecondario, Accento.blu.forte, coloreEtichetta(tester, 'C')),
          moreOrLessEquals(attesaC, epsilon: .03), reason: 'C con indicatore a $posizione');
      expect(_avanzamento(testoSecondario, Accento.verde.forte, coloreEtichetta(tester, 'A')),
          moreOrLessEquals(attesaA, epsilon: .03), reason: 'A con indicatore a $posizione');
      expect(coloreEtichetta(tester, 'B'), testoSecondario);
    }
    expect(visteMeta, greaterThan(2), reason: 'la corsa deve essere visibile in più fotogrammi');

    await tester.pumpAndSettle();
    expect(centroIndicatore(tester), moreOrLessEquals(a, epsilon: .5));
    expect(coloreEtichetta(tester, 'C'), Accento.blu.forte);
    expect(coloreEtichetta(tester, 'A'), testoSecondario);
  });

  testWidgets('un nuovo tocco a metà corsa riparte da dove si trova, senza salti', (tester) async {
    await monta(tester);
    await tester.tap(find.text('C'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final prima = centroIndicatore(tester);

    await tester.tap(find.text('E'));
    await tester.pump();
    expect(centroIndicatore(tester), moreOrLessEquals(prima, epsilon: .5));

    await tester.pumpAndSettle();
    expect(centroIndicatore(tester), moreOrLessEquals(centroVoce(tester, 'E'), epsilon: .5));
    expect(coloreEtichetta(tester, 'E'), Accento.viola.forte);
    for (final altra in ['A', 'B', 'C', 'D']) {
      expect(coloreEtichetta(tester, altra), testoSecondario);
    }
  });
}
