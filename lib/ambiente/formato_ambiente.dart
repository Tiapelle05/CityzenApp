import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../modelli/ambiente.dart';
import '../ui.dart';

// Colori, icone e formattazione dei dati ambientali.

const Color aranciaLivello = Color(0xFFEA7A1A);
const Color aranciaScuro = Color(0xFF9A4A05);
const Color aranciaChiaro = Color(0xFFFFEEDC);
const Color rossoLivello = Color(0xFFD92D20);
const Color rossoChiaro = Color(0xFFFDE4E1);
Color get grigioChiaro => temaScuro ? const Color(0xFF222C26) : const Color(0xFFEEF1EC);

/// Colore di un livello (stessi colori dello stato del parco):
/// verde, giallo, arancione, rosso; grigio se sconosciuto.
Accento accentoLivello(EnvLevel? l) => switch (l) {
  EnvLevel.good => Accento.verde,
  EnvLevel.moderate => Accento.giallo,
  EnvLevel.poor => const Accento(aranciaLivello, aranciaScuro, aranciaChiaro),
  EnvLevel.bad => Accento(rossoLivello, coralloScuro, rossoChiaro),
  _ => Accento(testoTenue, testoSecondario, grigioChiaro),
};

/// Accento grigio per dati non aggiornati.
Accento get accentoSpento => Accento(testoTenue, testoSecondario, grigioChiaro);

IconData iconaMetrica(String metric) => switch (metric) {
  Metriche.temperatura => Icons.thermostat_rounded,
  Metriche.umidita => Icons.water_drop_rounded,
  Metriche.luce => Icons.wb_sunny_rounded,
  Metriche.polveri => Icons.grain_rounded,
  Metriche.gas => Icons.local_fire_department_rounded,
  _ => Icons.sensors_rounded,
};

const Map<String, String> _etichetteInglesi = {
  Metriche.temperatura: 'Temperature',
  Metriche.umidita: 'Humidity',
  Metriche.luce: 'Light',
  Metriche.polveri: 'Fine dust',
  Metriche.gas: 'Combustible gas and smoke',
};

/// Etichetta della metrica: quella del catalogo in italiano, tradotta in inglese.
String etichettaMetrica(String metric, Copie s, [EnvMetric? m]) =>
    s.inglese ? (_etichetteInglesi[metric] ?? m?.label ?? metric) : (m?.label ?? metric);

const Map<EnvLevel, String> _testiInglesi = {
  EnvLevel.good: 'Good',
  EnvLevel.moderate: 'Moderate',
  EnvLevel.poor: 'Poor',
  EnvLevel.bad: 'Very poor',
  EnvLevel.unknown: 'Not available',
};

/// Testo del livello: quello del backend in italiano, una traduzione in inglese.
String testoLivello(EnvLevel? l, String? testoBackend, Copie s) {
  if (!s.inglese && testoBackend != null && testoBackend.isNotEmpty) return testoBackend;
  if (l == null) return testoBackend ?? '';
  return s.inglese ? _testiInglesi[l]! : (testoBackend ?? '');
}

/// Testo della qualità dell'aria ("Aria buona"…).
String testoAria(AirQuality a, Copie s) {
  if (!s.inglese) return a.text;
  return switch (a.level) {
    EnvLevel.good => 'Good air',
    EnvLevel.moderate => 'Moderate air',
    EnvLevel.poor => 'Poor air',
    EnvLevel.bad => 'Very poor air',
    EnvLevel.unknown => 'Data not available',
  };
}

final Map<String, NumberFormat> _formati = {};

/// Numero all'italiana (virgola decimale) con [decimali] cifre: 13,9 · 24 · 0,98.
String formattaNumero(double v, int decimali, Copie s) {
  final locale = s.inglese ? 'en_US' : 'it_IT';
  final f = _formati.putIfAbsent(
    '$locale/$decimali',
    () => NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: decimali),
  );
  return f.format(v);
}

/// Valore con unità ("13,9 °C"); "—" se manca. Il gas è un indice senza unità.
String formattaValore(double? v, EnvMetric? m, Copie s, {bool conUnita = true}) {
  if (v == null) return '—';
  final n = formattaNumero(v, m?.decimals ?? 1, s);
  final unita = m?.unit ?? '';
  if (!conUnita || unita.isEmpty) return n;
  return unita == '%' ? '$n%' : '$n $unita';
}

/// Unità da mostrare accanto al valore ("indice" per il gas).
String unitaMostrata(EnvMetric? m, Copie s) => m == null
    ? ''
    : m.senzaUnita
    ? s.t('indice', 'index')
    : m.unit;

/// Ora locale "HH:MM".
String formattaOra(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// "alle 16:12" oggi, altrimenti "il 17/11 alle 16:12".
String quandoLettura(DateTime d, Copie s) {
  final l = d.toLocal();
  final ora = DateTime.now();
  final oggi = l.year == ora.year && l.month == ora.month && l.day == ora.day;
  if (oggi) return s.t('alle ${formattaOra(d)}', 'at ${formattaOra(d)}');
  return s.t('il ${formattaData(l)} alle ${formattaOra(d)}', 'on ${formattaData(l)} at ${formattaOra(d)}');
}

/// Avvertenza sempre visibile sotto i dati ambientali.
String avvertenzaSensori(Copie s) => s.t(
  'Valori stimati da sensori a basso costo, non certificati. Le etichette «Buona», «Scarsa»… non sono giudizi sanitari.',
  'Values estimated by low-cost, non-certified sensors. Labels such as “Good” or “Poor” are not health assessments.',
);

/// Pillola colorata con il testo del livello (il colore non basta da solo).
class BadgeLivello extends StatelessWidget {
  final EnvLevel? livello;
  final String testo;
  const BadgeLivello({super.key, required this.livello, required this.testo});

  @override
  Widget build(BuildContext context) {
    final a = accentoLivello(livello);
    return Etichetta(testo, colore: a.forte, sfondo: a.tinta, puntino: true);
  }
}
