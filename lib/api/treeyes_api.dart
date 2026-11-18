import '../modelli/ambiente.dart';

/// API cittadino per dati ambientali e assistente.
///
/// Due implementazioni: [MockTreeyesApi] (JSON di `Assets/mock/`, usata in demo
/// e nei test) e [HttpTreeyesApi] (backend vero). `CitizenApi.instance.treeyes`
/// restituisce quella giusta per il collegamento in uso.
abstract class TreeyesApi {
  /// Catalogo delle metriche: etichetta, unità, decimali, soglie. Cambia di rado.
  Future<List<EnvMetric>> environmentMetrics();

  /// Stazioni del parco con ultima lettura, qualità dell'aria e mini-curve 24 h.
  Future<ParkEnvironment> parkEnvironment(int parkId);

  /// Andamento di una metrica. [range]: `24h`, `7d`, `30d`.
  /// Senza [stationId] il backend usa la prima stazione del parco.
  Future<EnvSeries> environmentSeries(int parkId, {required String metric, String range = '24h', int? stationId});

  /// Domanda all'assistente. [history]: ultimi turni (dal più vecchio), senza la domanda corrente.
  Future<AssistantReply> askAssistant(int parkId, String question, List<ChatTurn> history);
}

/// Limiti dell'assistente decisi dal backend.
abstract final class LimitiAssistente {
  static const lunghezzaDomanda = 500;
  static const turniCronologia = 10;
  static const lunghezzaTurno = 1000;

  /// Cronologia da inviare: ultimi 10 turni, testi tagliati a 1000 caratteri.
  static List<ChatTurn> cronologia(List<ChatTurn> conversazione) {
    final ultimi = conversazione.length > turniCronologia
        ? conversazione.sublist(conversazione.length - turniCronologia)
        : conversazione;
    return [
      for (final t in ultimi)
        ChatTurn(t.role, t.content.length > lunghezzaTurno ? t.content.substring(0, lunghezzaTurno) : t.content),
    ];
  }
}
