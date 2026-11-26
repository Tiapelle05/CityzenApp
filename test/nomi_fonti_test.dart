import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/assistente/nomi_fonti.dart';
import 'package:flutter_application_1/modelli/ambiente.dart';
import 'package:flutter_application_1/ui.dart';

void main() {
  final it = Copie(false);
  final nomi = NomiFonti();

  test('i link dei grafici dicono quale grandezza e quale stazione', () {
    final etichette = nomi.etichette(const [
      AssistantSource(type: TipiFonte.ambiente, metric: 'temperature', stationId: 1),
      AssistantSource(type: TipiFonte.ambiente, metric: 'temperature', stationId: 2),
      AssistantSource(type: TipiFonte.ambiente, stationId: 2),
      AssistantSource(type: TipiFonte.ambiente),
    ], it).map((e) => e.$2).toList();
    expect(etichette, hasLength(4));
    expect(etichette.toSet(), hasLength(4)); // nessun nome ripetuto
    expect(etichette[0], startsWith('Grafico '));
    expect(etichette[0], endsWith('Stazione 1'));
    expect(etichette[2], 'Stazione 2');
    expect(etichette[3], 'Qualità dell’aria');
  });

  test('avvisi e segnalazioni senza nome caricato hanno il numero; i doppioni spariscono', () {
    final etichette = nomi.etichette(const [
      AssistantSource(type: TipiFonte.avviso, id: 1),
      AssistantSource(type: TipiFonte.avviso, id: 2),
      AssistantSource(type: TipiFonte.avviso, id: 2),
      AssistantSource(type: TipiFonte.miaSegnalazione, id: 7),
      AssistantSource(type: TipiFonte.categorie),
      AssistantSource(type: 'sconosciuto'),
    ], it).map((e) => e.$2).toList();
    expect(etichette, ['Avviso n. 1', 'Avviso n. 2', 'Tua segnalazione n. 7', 'Segnala un problema']);
  });

  test('il nome mandato dal backend vince', () {
    final f = AssistantSource.fromJson(const {'type': TipiFonte.avviso, 'id': 3, 'label': 'Potatura viale Gadio'});
    expect(nomi.nome(f, it), 'Potatura viale Gadio');
  });
}
