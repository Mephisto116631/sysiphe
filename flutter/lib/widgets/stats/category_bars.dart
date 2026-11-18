import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/stats.dart';
import '../../theme.dart';

/// Barres empilées : nombre de séries par catégorie, par semaine ou par mois.
class CategoryBars extends StatelessWidget {
  final List<(DateTime, Map<String, int>)> buckets;
  final List<String> categories; // ordre et couleurs
  final Bucket bucket;

  const CategoryBars({
    super.key,
    required this.buckets,
    required this.categories,
    required this.bucket,
  });

  Color _color(String c) => AppTheme.seriesColor(categories.indexOf(c));

  String _label(DateTime d) => bucket == Bucket.month
      ? DateFormat('MMM yy', 'fr_FR').format(d)
      : DateFormat('d/MM', 'fr_FR').format(d);

  @override
  Widget build(BuildContext context) {
    final totals = [
      for (final (_, m) in buckets) m.values.fold<int>(0, (a, b) => a + b)
    ];
    final maxY =
        totals.isEmpty ? 1.0 : totals.reduce((a, b) => a > b ? a : b) * 1.15;
    final every = (buckets.length / 6).ceil().clamp(1, 1 << 30);
    final width = (220 / buckets.length.clamp(1, 1 << 30)).clamp(3.0, 22.0);

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY,
        alignment: BarChartAlignment.spaceAround,
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: totals[i].toDouble(),
                width: width,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                rodStackItems: () {
                  var y = 0.0;
                  return [
                    for (final c in categories)
                      if ((buckets[i].$2[c] ?? 0) > 0)
                        BarChartRodStackItem(
                            y, y += buckets[i].$2[c]!.toDouble(), _color(c)),
                  ];
                }(),
              ),
            ]),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppTheme.borderColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, meta) => Text(v.toInt().toString(),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= buckets.length || i % every != 0) {
                  return const SizedBox.shrink();
                }
                return Text(_label(buckets[i].$1),
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textSecondary));
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, _, rod, __) {
              final (start, m) = buckets[group.x];
              final head = bucket == Bucket.month
                  ? DateFormat('MMMM yyyy', 'fr_FR').format(start)
                  : 'Semaine du ${DateFormat('d MMM', 'fr_FR').format(start)}';
              final lines = [
                for (final c in categories)
                  if ((m[c] ?? 0) > 0) '$c : ${m[c]}'
              ];
              return BarTooltipItem(
                [head, ...lines].join('\n'),
                const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
              );
            },
          ),
        ),
      ),
    );
  }
}
