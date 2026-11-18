import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/stats.dart';
import '../../theme.dart';

/// 12 → « 12 », 12,5 → « 12.5 ».
String fmtStat(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

class StatRow extends StatelessWidget {
  final List<DayPoint> points;
  final String unit;

  const StatRow({super.key, required this.points, required this.unit});

  @override
  Widget build(BuildContext context) {
    final best = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final last = points.last;
    return Row(
      children: [
        Expanded(
            child: StatCard(label: 'Record', value: '${fmtStat(best)}$unit')),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label:
                'Dernière séance\n${DateFormat('d MMM', 'fr_FR').format(last.date)}',
            value: '${fmtStat(last.value)}$unit',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: StatCard(label: 'Séances', value: '${points.length}')),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;

  const StatCard({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlue)),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Tendance des 21 derniers jours de séance (port de detect_plateau).
class TrendBadge extends StatelessWidget {
  final PlateauResult result;

  const TrendBadge({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = switch (result.status) {
      Trend.progress => (
          Icons.trending_up,
          Colors.green.shade700,
          'En progression (+${(result.relativeSlope * 100).round()} % sur 21 j)'
        ),
      Trend.regression => (
          Icons.trending_down,
          Colors.red.shade700,
          'En baisse (${(result.relativeSlope * 100).round()} % sur 21 j)'
        ),
      Trend.plateau => (
          Icons.trending_flat,
          Colors.orange.shade800,
          'Plateau sur les 21 derniers jours'
        ),
      Trend.insufficientData => (
          Icons.info_outline,
          AppTheme.textSecondary,
          'Pas assez de séances récentes pour une tendance'
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}
