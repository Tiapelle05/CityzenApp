import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/schermata_segnalazioni.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('il carosello segue i segnaposto: vicini sulla mappa, vicini nelle schede', () {
    // Parco largo est-ovest; in elenco (per data) sono mescolati.
    const punti = {
      'C': LatLng(45.0000, 7.0040),
      'A': LatLng(45.0000, 7.0000),
      'E': LatLng(45.0002, 7.0080),
      'B': LatLng(45.0003, 7.0020),
      'D': LatLng(45.0001, 7.0060),
    };
    final ordine = ordinaPerVicinanza(['C', 'senza', 'A', 'E', 'B', 'D'], (k) => punti[k]);
    expect(ordine, ['A', 'B', 'C', 'D', 'E', 'senza']);
  });

  test('parco lungo nord-sud: si parte da nord', () {
    const punti = {
      'sud': LatLng(45.000, 7.0),
      'nord': LatLng(45.010, 7.0001),
      'centro': LatLng(45.005, 7.0),
    };
    expect(ordinaPerVicinanza(['sud', 'centro', 'nord'], (k) => punti[k]), ['nord', 'centro', 'sud']);
  });

  test('pochi elementi o nessuna posizione', () {
    expect(ordinaPerVicinanza(<String>[], (_) => null), isEmpty);
    expect(ordinaPerVicinanza(['x', 'y'], (_) => null), ['x', 'y']);
  });
}
