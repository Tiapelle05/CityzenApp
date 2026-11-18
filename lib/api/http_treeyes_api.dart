import '../citizen_api.dart';
import '../modelli/ambiente.dart';
import 'treeyes_api.dart';

/// [TreeyesApi] sul backend vero: usa il trasporto di [CitizenApi]
/// (token, nuova registrazione dopo il 401, errori come [ApiException]).
class HttpTreeyesApi implements TreeyesApi {
  final CitizenApi _api;
  HttpTreeyesApi(this._api);

  List<EnvMetric>? _metriche;

  @override
  Future<List<EnvMetric>> environmentMetrics() async {
    // Cambia di rado: resta in memoria per tutta la sessione.
    final giaPronte = _metriche;
    if (giaPronte != null) return giaPronte;
    final dati = await _api.richiesta('GET', '/citizen/environment/metrics');
    return _metriche = [
      for (final m in (dati as List).whereType<Map>()) EnvMetric.fromJson(Map<String, dynamic>.from(m)),
    ];
  }

  /// Da chiamare quando cambia il server.
  void dimenticaMetriche() => _metriche = null;

  @override
  Future<ParkEnvironment> parkEnvironment(int parkId) async {
    final dati = await _api.richiesta('GET', '/citizen/parks/$parkId/environment');
    return ParkEnvironment.fromJson(Map<String, dynamic>.from(dati as Map));
  }

  @override
  Future<EnvSeries> environmentSeries(
    int parkId, {
    required String metric,
    String range = '24h',
    int? stationId,
  }) async {
    final dati = await _api.richiesta(
      'GET',
      '/citizen/parks/$parkId/environment/series',
      query: {'metric': metric, 'range': range, 'station_id': ?stationId?.toString()},
    );
    return EnvSeries.fromJson(Map<String, dynamic>.from(dati as Map));
  }

  @override
  Future<AssistantReply> askAssistant(int parkId, String question, List<ChatTurn> history) async {
    final dati = await _api.richiesta(
      'POST',
      '/citizen/parks/$parkId/assistant',
      body: {
        'question': question.trim(),
        'history': [for (final t in LimitiAssistente.cronologia(history)) t.toJson()],
      },
      // L'assistente può metterci fino a 45 s: timeout più lungo del normale.
      timeout: const Duration(seconds: 50),
    );
    return AssistantReply.fromJson(Map<String, dynamic>.from(dati as Map));
  }
}
