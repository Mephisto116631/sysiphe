import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/stats.dart';
import '../../theme.dart';
import 'stat_cards.dart';

/// Une courbe de [MultiLineChart] : nom, points et couleur.
class ChartSeries {
  final String name;
  final List<DayPoint> points;
  final Color color;
  const ChartSeries(this.name, this.points, this.color);
}

/// Courbes par jour sur un axe de dates commun. Une seule courbe : remplie en
/// dessous (comme avant). Plusieurs : lignes de couleur, infobulle par série.
class MultiLineChart extends StatelessWidget {
  final List<ChartSeries> series;

  /// Unité ajoutée aux valeurs (« pts », « % »…) ; [unitOf] l'emporte par série.
  final String unit;
  final String Function(String series)? unitOf;

  const MultiLineChart(
      {super.key, required this.series, this.unit = '', this.unitOf});

  @override
  Widget build(BuildContext context) {
    final shown = series.where((s) => s.points.isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final origin = shown
        .map((s) => s.points.first.date)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    double x(DateTime d) => DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(origin.year, origin.month, origin.day))
        .inDays
        .toDouble();
    final all = [for (final s in shown) ...s.points];
    final minX = all.map((p) => x(p.date)).reduce((a, b) => a < b ? a : b);
    var maxX = all.map((p) => x(p.date)).reduce((a, b) => a > b ? a : b);
    if (maxX == minX) maxX = minX + 1;
    final ys = all.map((p) => p.value);
    final minY =
        (ys.reduce((a, b) => a < b ? a : b) * 0.9).clamp(0.0, double.infinity);
    var maxY = ys.reduce((a, b) => a > b ? a : b) * 1.1;
    if (maxY <= minY) maxY = minY + 1;
    final single = shown.length == 1;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          for (final s in shown)
            LineChartBarData(
              spots: [for (final p in s.points) FlSpot(x(p.date), p.value)],
              isCurved: true,
              preventCurveOverShooting: true,
              curveSmoothness: 0.25,
              color: s.color,
              barWidth: single ? 2.5 : 2,
              dotData: FlDotData(
                show: s.points.length <= 30,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: single ? 3 : 2.5, color: s.color, strokeWidth: 0),
              ),
              belowBarData: BarAreaData(
                show: single,
                color: s.color.withOpacity(0.08),
              ),
            ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppTheme.borderColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (val, meta) => Text(
                val.toInt().toString(),
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: ((maxX - minX) / 4).clamp(1, double.infinity),
              getTitlesWidget: (val, meta) => Text(
                DateFormat('d/MM/yy')
                    .format(origin.add(Duration(days: val.round()))),
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.textSecondary),
              ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touched) => touched.map((t) {
              final s = shown[t.barIndex];
              final p = s.points[t.spotIndex];
              final u = unitOf?.call(s.name) ?? unit;
              final head = single ? '' : '${s.name} : ';
              final date = t == touched.last
                  ? '\n${DateFormat('d MMM yyyy', 'fr_FR').format(p.date)}'
                  : '';
              return LineTooltipItem(
                '$head${fmtStat(p.value)}$u$date',
                TextStyle(
                    color: single ? Colors.white : s.color.withAlpha(255),
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: single ? null : FontWeight.w600),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
