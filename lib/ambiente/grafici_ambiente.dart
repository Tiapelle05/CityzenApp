import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../modelli/ambiente.dart';
import '../ui.dart';
import 'formato_ambiente.dart';

/// Mini-curva delle ultime 24 ore (`spark_24h`, 48 medie da 30 minuti).
class MiniCurva extends StatelessWidget {
  final List<double> valori;
  final Color colore;
  final double altezza;

  const MiniCurva({super.key, required this.valori, required this.colore, this.altezza = 46});

  @override
  Widget build(BuildContext context) {
    if (valori.length < 2) return SizedBox(height: altezza);
    var minY = valori.reduce(math.min);
    var maxY = valori.reduce(math.max);
    if (maxY - minY < 1e-9) {
      minY -= 1;
      maxY += 1;
    }
    final margine = (maxY - minY) * .12;
    return ExcludeSemantics(
      child: SizedBox(
        height: altezza,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (valori.length - 1).toDouble(),
            minY: minY - margine,
            maxY: maxY + margine,
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              LineChartBarData(
                spots: [for (var i = 0; i < valori.length; i++) FlSpot(i.toDouble(), valori[i])],
                isCurved: true,
                preventCurveOverShooting: true,
                color: colore,
                barWidth: 2.2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colore.withValues(alpha: .22), colore.withValues(alpha: 0)],
                  ),
                ),
              ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}

/// Grafico di una serie: linea delle medie e banda minimo–massimo.
/// I buchi restano buchi: se tra due punti passano più di due `bucket_minutes`
/// la linea si interrompe.
class GraficoSerie extends StatelessWidget {
  final EnvSeries serie;
  final EnvMetric? metrica;
  final Copie s;
  final Color? _colore;
  Color get colore => _colore ?? foresta;
  final double altezza;

  const GraficoSerie({
    super.key,
    required this.serie,
    required this.metrica,
    required this.s,
    Color? colore,
    this.altezza = 260,
  }) : _colore = colore;

  /// Minuti "da orologio locale": le etichette cadono su ore tonde del telefono.
  static double _x(DateTime t) => (t.millisecondsSinceEpoch + t.toLocal().timeZoneOffset.inMilliseconds) / 60000;

  static DateTime _daX(double x) => DateTime.fromMillisecondsSinceEpoch((x * 60000).round(), isUtc: true);

  /// Punti con [FlSpot.nullSpot] dove la serie ha un buco.
  static List<FlSpot> spotConBuchi(EnvSeries serie, double? Function(SeriesPoint) valore) {
    final spots = <FlSpot>[];
    final soglia = Duration(minutes: serie.bucketMinutes * 2);
    SeriesPoint? precedente;
    for (final p in serie.points) {
      final v = valore(p);
      if (precedente != null && p.t.difference(precedente.t) > soglia && spots.isNotEmpty && !spots.last.isNull()) {
        spots.add(FlSpot.nullSpot);
      }
      if (v == null) {
        if (spots.isNotEmpty && !spots.last.isNull()) spots.add(FlSpot.nullSpot);
      } else {
        spots.add(FlSpot(_x(p.t), v));
      }
      precedente = p;
    }
    return spots;
  }

  static String _due(int n) => n.toString().padLeft(2, '0');

  /// Ora di un valore x (già in ora locale: niente toLocal()).
  static String _oraDi(double x) {
    final d = _daX(x);
    return '${_due(d.hour)}:${_due(d.minute)}';
  }

  static String _giornoDi(double x) {
    final d = _daX(x);
    return '${_due(d.day)}/${_due(d.month)}';
  }

  String _etichettaX(double x) => serie.range == Intervalli.giorno ? _oraDi(x) : _giornoDi(x);

  @override
  Widget build(BuildContext context) {
    final medie = spotConBuchi(serie, (p) => p.avg);
    final minimi = spotConBuchi(serie, (p) => p.min ?? p.avg);
    final massimi = spotConBuchi(serie, (p) => p.max ?? p.avg);
    final tutti = [...medie, ...minimi, ...massimi].where((p) => !p.isNull()).toList();
    if (tutti.isEmpty) {
      return SizedBox(
        height: altezza,
        child: Center(
          child: Text(
            s.t('Nessun dato in questo periodo.', 'No data in this period.'),
            style: TextStyle(color: testoSecondario),
          ),
        ),
      );
    }
    var minY = tutti.map((p) => p.y).reduce(math.min);
    var maxY = tutti.map((p) => p.y).reduce(math.max);
    if (maxY - minY < 1e-9) {
      minY -= 1;
      maxY += 1;
    }
    final margine = (maxY - minY) * .1;
    minY -= margine;
    maxY += margine;
    if (minY < 0 && tutti.every((p) => p.y >= 0)) minY = 0;

    final minX = serie.points.isEmpty ? 0.0 : _x(serie.points.first.t);
    final maxX = serie.points.isEmpty ? 1.0 : _x(serie.points.last.t);
    final intervalloX = switch (serie.range) {
      Intervalli.settimana => 1440.0,
      Intervalli.mese => 1440.0 * 7,
      _ => 360.0,
    };
    final decimali = metrica?.decimals ?? 1;

    final banda = colore.withValues(alpha: .14);
    final stileAsse = TextStyle(fontSize: 11, color: testoSecondario, fontWeight: FontWeight.w600);

    return SizedBox(
      height: altezza,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: bordo, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, meta) {
                  if (v == meta.min || v == meta.max) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      formattaNumero(v, decimali > 0 && (maxY - minY) < 5 ? decimali : 0, s),
                      style: stileAsse,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: intervalloX,
                getTitlesWidget: (v, meta) {
                  if ((v % intervalloX).abs() > 1e-6) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(_etichettaX(v), style: stileAsse),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => forestaScura,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (punti) => [
                for (final p in punti)
                  p.barIndex != 2
                      ? null
                      : LineTooltipItem(
                          '${formattaValore(p.y, metrica, s)}\n',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                          children: [
                            TextSpan(
                              text: serie.range == Intervalli.giorno ? _oraDi(p.x) : '${_giornoDi(p.x)} ${_oraDi(p.x)}',
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 12),
                            ),
                          ],
                        ),
              ],
            ),
          ),
          betweenBarsData: [BetweenBarsData(fromIndex: 0, toIndex: 1, color: banda)],
          lineBarsData: [
            LineChartBarData(
              spots: minimi,
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: massimi,
              color: Colors.transparent,
              barWidth: 0,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: medie,
              color: colore,
              barWidth: 2.4,
              isCurved: serie.range != Intervalli.giorno,
              preventCurveOverShooting: true,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}
