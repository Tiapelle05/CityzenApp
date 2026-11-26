import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/mappa_parco.dart';

void main() {
  testWidgets('cambiando la scelta ogni segnaposto tiene la sua animazione', (tester) async {
    Widget mappa(String scelto) => MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: FlutterMap(
                options: const MapOptions(initialCenter: LatLng(45.47, 9.17), initialZoom: 17),
                children: [
                  LivelloGruppi<String>(
                    punti: const [
                      ('A', LatLng(45.4700, 9.1700)),
                      ('B', LatLng(45.4705, 9.1710)),
                      ('C', LatLng(45.4695, 9.1690)),
                    ],
                    chiave: (k) => k,
                    scelto: (k) => k == scelto,
                    segnaposto: (k) => Segnaposto(icona: Icons.place, colore: Colors.green, selezionato: k == scelto),
                  ),
                ],
              ),
            ),
          ),
        );

    Element segnaposto(String k) => tester.element(find.byKey(ValueKey<(String, Object?)>(('uno', k))));

    await tester.pumpWidget(mappa('A'));
    await tester.pump(); // la mappa conosce le sue dimensioni dal secondo frame
    final a = segnaposto('A'), b = segnaposto('B'), c = segnaposto('C');

    // La scelta passa a B: B va disegnato in cima, ma nessun segnaposto
    // prende lo stato (e l'animazione) di un altro.
    await tester.pumpWidget(mappa('B'));
    expect(segnaposto('A'), same(a));
    expect(segnaposto('B'), same(b));
    expect(segnaposto('C'), same(c));
    await tester.pump(const Duration(seconds: 1)); // il segnaposto scelto pulsa di continuo
  });
}
