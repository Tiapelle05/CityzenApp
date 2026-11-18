// Modelli dei dati ambientali e dell'assistente (API /citizen, vedi
// GUIDA_AMBIENTE_ASSISTENTE.md del backend). I JSON sono in snake_case,
// le date ISO 8601 UTC: qui diventano DateTime in UTC.

/// Livello di una metrica o della qualità dell'aria. Insieme chiuso:
/// un valore sconosciuto è [unknown], mai un errore.
enum EnvLevel { good, moderate, poor, bad, unknown }

EnvLevel parseLevel(Object? s) => EnvLevel.values.firstWhere((l) => l.name == s, orElse: () => EnvLevel.unknown);

/// Vero per i livelli che meritano un'allerta (banner in Home).
bool livelloDiAllerta(EnvLevel? l) => l == EnvLevel.poor || l == EnvLevel.bad;

/// Metriche conosciute dall'app (l'ordine di visualizzazione arriva dal catalogo).
abstract final class Metriche {
  static const temperatura = 'temperature';
  static const umidita = 'humidity';
  static const luce = 'light';
  static const polveri = 'dust';
  static const gas = 'gas';
}

double? _num(Object? v) => (v as num?)?.toDouble();
int? _int(Object? v) => (v as num?)?.toInt();
DateTime? _data(Object? v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;
DateTime _dataObbligatoria(Object? v) => _data(v) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
List<Map<String, dynamic>> _lista(Object? v) =>
    v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];

// ── Catalogo delle metriche (GET /citizen/environment/metrics) ──────────────

class MetricLevel {
  /// Soglia massima del livello; null per l'ultimo (senza limite).
  final double? max;
  final EnvLevel level;
  final String text;
  const MetricLevel({required this.max, required this.level, required this.text});

  factory MetricLevel.fromJson(Map<String, dynamic> j) =>
      MetricLevel(max: _num(j['max']), level: parseLevel(j['level']), text: j['text'] as String? ?? '');
}

class EnvMetric {
  final String metric, label, unit;
  final int decimals;

  /// Solo per polveri e gas.
  final List<MetricLevel>? levels;
  const EnvMetric({required this.metric, required this.label, required this.unit, required this.decimals, this.levels});

  factory EnvMetric.fromJson(Map<String, dynamic> j) => EnvMetric(
    metric: j['metric'] as String,
    label: j['label'] as String? ?? j['metric'] as String,
    unit: j['unit'] as String? ?? '',
    decimals: _int(j['decimals']) ?? 0,
    levels: j['levels'] is List ? _lista(j['levels']).map(MetricLevel.fromJson).toList() : null,
  );

  /// Il gas è un indice adimensionale (≈1 in aria pulita): niente unità.
  bool get senzaUnita => unit.isEmpty;
}

// ── Stato ambientale del parco (GET /citizen/parks/{id}/environment) ────────

class AirQuality {
  final EnvLevel level;

  /// Già in italiano: "Aria buona", "Dati non disponibili"…
  final String text;
  const AirQuality({required this.level, required this.text});

  factory AirQuality.fromJson(Map<String, dynamic>? j) =>
      AirQuality(level: parseLevel(j?['level']), text: j?['text'] as String? ?? '');
}

class StationReading {
  final String metric;

  /// null: dato non disponibile (si mostra "—").
  final double? value;
  final double? delta1h, min24h, max24h;

  /// null per temperatura, umidità, luce.
  final EnvLevel? level;
  final String? text;
  const StationReading({
    required this.metric,
    this.value,
    this.delta1h,
    this.min24h,
    this.max24h,
    this.level,
    this.text,
  });

  factory StationReading.fromJson(Map<String, dynamic> j) => StationReading(
    metric: j['metric'] as String,
    value: _num(j['value']),
    delta1h: _num(j['delta_1h']),
    min24h: _num(j['min_24h']),
    max24h: _num(j['max_24h']),
    level: j['level'] == null ? null : parseLevel(j['level']),
    text: j['text'] as String?,
  );

  /// Copia con il nuovo valore arrivato dal WebSocket; min e max si allargano.
  StationReading aggiornata(double? nuovo, EnvLevel? nuovoLivello, String? nuovoTesto) => StationReading(
    metric: metric,
    value: nuovo,
    delta1h: delta1h,
    min24h: nuovo == null || min24h == null ? min24h : (nuovo < min24h! ? nuovo : min24h),
    max24h: nuovo == null || max24h == null ? max24h : (nuovo > max24h! ? nuovo : max24h),
    level: nuovoLivello ?? level,
    text: nuovoTesto ?? (nuovoLivello == null || nuovoLivello == level ? text : null),
  );
}

class EnvStation {
  final int id;
  final String name;
  final String? zone;

  /// null: la stazione compare in elenco ma non sulla mappa.
  final double? lat, lon;
  final bool online;

  /// false: dati vecchi o stazione spenta.
  final bool fresh;
  final DateTime lastSeen;
  final List<StationReading> readings;

  /// 48 medie da 30 minuti per metrica (dalla più vecchia).
  final Map<String, List<double>> spark24h;

  const EnvStation({
    required this.id,
    required this.name,
    this.zone,
    this.lat,
    this.lon,
    required this.online,
    required this.fresh,
    required this.lastSeen,
    required this.readings,
    required this.spark24h,
  });

  factory EnvStation.fromJson(Map<String, dynamic> j) {
    final spark = <String, List<double>>{};
    final grezzo = j['spark_24h'];
    if (grezzo is Map) {
      grezzo.forEach((k, v) {
        if (v is List) {
          spark['$k'] = [
            for (final x in v)
              if (x is num) x.toDouble(),
          ];
        }
      });
    }
    return EnvStation(
      id: _int(j['id']) ?? 0,
      name: j['name'] as String? ?? '',
      zone: j['zone'] as String?,
      lat: _num(j['lat']),
      lon: _num(j['lon']),
      online: j['online'] as bool? ?? false,
      fresh: j['fresh'] as bool? ?? false,
      lastSeen: _dataObbligatoria(j['last_seen']),
      readings: _lista(j['readings']).map(StationReading.fromJson).toList(),
      spark24h: spark,
    );
  }

  StationReading? lettura(String metric) => readings.where((r) => r.metric == metric).firstOrNull;

  EnvStation copyWith({bool? online, bool? fresh, DateTime? lastSeen, List<StationReading>? readings}) => EnvStation(
    id: id,
    name: name,
    zone: zone,
    lat: lat,
    lon: lon,
    online: online ?? this.online,
    fresh: fresh ?? this.fresh,
    lastSeen: lastSeen ?? this.lastSeen,
    readings: readings ?? this.readings,
    spark24h: spark24h,
  );
}

class ParkEnvironment {
  final int parkId;
  final DateTime updatedAt;
  final AirQuality airQuality;

  /// Può essere vuota: in Home niente card.
  final List<EnvStation> stations;

  const ParkEnvironment({
    required this.parkId,
    required this.updatedAt,
    required this.airQuality,
    required this.stations,
  });

  factory ParkEnvironment.fromJson(Map<String, dynamic> j) => ParkEnvironment(
    parkId: _int(j['park_id']) ?? 0,
    updatedAt: _dataObbligatoria(j['updated_at']),
    airQuality: AirQuality.fromJson(j['air_quality'] as Map<String, dynamic>?),
    stations: _lista(j['stations']).map(EnvStation.fromJson).toList(),
  );

  EnvStation? stazione(int? id) =>
      id == null ? stations.firstOrNull : stations.where((s) => s.id == id).firstOrNull ?? stations.firstOrNull;

  /// Applica un messaggio `environment_reading` del WebSocket.
  ParkEnvironment conLettura(EnvReadingEvent e) {
    if (e.parkId != parkId) return this;
    return ParkEnvironment(
      parkId: parkId,
      updatedAt: e.at.isAfter(updatedAt) ? e.at : updatedAt,
      airQuality: airQuality,
      stations: [
        for (final s in stations)
          if (s.id != e.stationId)
            s
          else
            s.copyWith(
              online: true,
              fresh: true,
              lastSeen: e.at,
              readings: [
                for (final r in s.readings)
                  if (e.readings.where((n) => n.metric == r.metric).firstOrNull case final n?)
                    r.aggiornata(n.value, n.level, n.text)
                  else
                    r,
              ],
            ),
      ],
    );
  }
}

// ── Serie storiche (GET …/environment/series) ───────────────────────────────

class SeriesPoint {
  final DateTime t;
  final double? avg, min, max;
  const SeriesPoint({required this.t, this.avg, this.min, this.max});

  factory SeriesPoint.fromJson(Map<String, dynamic> j) =>
      SeriesPoint(t: _dataObbligatoria(j['t']), avg: _num(j['avg']), min: _num(j['min']), max: _num(j['max']));
}

/// Intervalli del grafico: `24h` (punti da 5 min), `7d` (30 min), `30d` (2 h).
abstract final class Intervalli {
  static const giorno = '24h';
  static const settimana = '7d';
  static const mese = '30d';
  static const tutti = [giorno, settimana, mese];
}

class EnvSeries {
  final int stationId, bucketMinutes;
  final String metric, unit, range;
  final List<SeriesPoint> points;

  const EnvSeries({
    required this.stationId,
    required this.bucketMinutes,
    required this.metric,
    required this.unit,
    required this.range,
    required this.points,
  });

  factory EnvSeries.fromJson(Map<String, dynamic> j) => EnvSeries(
    stationId: _int(j['station_id']) ?? 0,
    bucketMinutes: _int(j['bucket_minutes']) ?? 5,
    metric: j['metric'] as String? ?? '',
    unit: j['unit'] as String? ?? '',
    range: j['range'] as String? ?? Intervalli.giorno,
    points: _lista(j['points']).map(SeriesPoint.fromJson).toList()..sort((a, b) => a.t.compareTo(b.t)),
  );
}

// ── Assistente (POST /citizen/parks/{id}/assistant) ──────────────────────────

class ChatTurn {
  static const utente = 'user';
  static const assistente = 'assistant';

  /// "user" | "assistant".
  final String role;
  final String content;
  const ChatTurn(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Tipi di fonte che l'assistente può citare.
abstract final class TipiFonte {
  static const statoParco = 'park_status';
  static const avviso = 'notice';
  static const segnalazione = 'report';
  static const miaSegnalazione = 'my_report';
  static const categorie = 'categories';
  static const ambiente = 'environment';
}

class AssistantSource {
  final String type;
  final int? id, parkId, stationId;
  final String? metric;

  /// Chiavi JSON "from" e "to".
  final DateTime? from, to;

  const AssistantSource({required this.type, this.id, this.parkId, this.stationId, this.metric, this.from, this.to});

  factory AssistantSource.fromJson(Map<String, dynamic> j) => AssistantSource(
    type: j['type'] as String? ?? '',
    id: _int(j['id']),
    parkId: _int(j['park_id']),
    stationId: _int(j['station_id']),
    metric: j['metric'] as String?,
    from: _data(j['from']),
    to: _data(j['to']),
  );
}

class AssistantReply {
  final String answer;
  final List<AssistantSource> sources;

  /// "rules" | "llm".
  final String mode;
  final String? model;
  final String disclaimer;

  const AssistantReply({
    required this.answer,
    required this.sources,
    required this.mode,
    this.model,
    required this.disclaimer,
  });

  factory AssistantReply.fromJson(Map<String, dynamic> j) => AssistantReply(
    answer: j['answer'] as String? ?? '',
    sources: _lista(j['sources']).map(AssistantSource.fromJson).toList(),
    mode: j['mode'] as String? ?? 'rules',
    model: j['model'] as String?,
    disclaimer: j['disclaimer'] as String? ?? '',
  );
}

// ── Messaggi WebSocket /citizen/ws ──────────────────────────────────────────

abstract final class EventiAmbiente {
  static const lettura = 'environment_reading';
  static const allerta = 'environment_alert';
  static const allertaFinita = 'environment_alert_ended';
}

class ReadingUpdate {
  final String metric;
  final double? value;
  final EnvLevel? level;
  final String? text;
  const ReadingUpdate({required this.metric, this.value, this.level, this.text});

  factory ReadingUpdate.fromJson(Map<String, dynamic> j) => ReadingUpdate(
    metric: j['metric'] as String? ?? '',
    value: _num(j['value']),
    level: j['level'] == null ? null : parseLevel(j['level']),
    text: j['text'] as String?,
  );
}

/// `environment_reading`: park_id, station_id, at, readings.
class EnvReadingEvent {
  final int parkId, stationId;
  final DateTime at;
  final List<ReadingUpdate> readings;
  const EnvReadingEvent({required this.parkId, required this.stationId, required this.at, required this.readings});

  factory EnvReadingEvent.fromJson(Map<String, dynamic> j) => EnvReadingEvent(
    parkId: _int(j['park_id']) ?? 0,
    stationId: _int(j['station_id']) ?? 0,
    at: _data(j['at']) ?? DateTime.now().toUtc(),
    readings: _lista(j['readings']).map(ReadingUpdate.fromJson).toList(),
  );
}

/// `environment_alert`: banner arancione o rosso in Home (non è un danger_alert).
class EnvAlert {
  final int parkId, stationId;
  final String metric;
  final double? value;
  final EnvLevel level;
  final String text;
  final DateTime at;

  const EnvAlert({
    required this.parkId,
    required this.stationId,
    required this.metric,
    this.value,
    required this.level,
    required this.text,
    required this.at,
  });

  factory EnvAlert.fromJson(Map<String, dynamic> j) => EnvAlert(
    parkId: _int(j['park_id']) ?? 0,
    stationId: _int(j['station_id']) ?? 0,
    metric: j['metric'] as String? ?? '',
    value: _num(j['value']),
    level: parseLevel(j['level']),
    text: j['text'] as String? ?? '',
    at: _data(j['at']) ?? DateTime.now().toUtc(),
  );
}
