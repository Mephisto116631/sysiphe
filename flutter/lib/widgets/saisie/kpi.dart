import 'package:flutter/material.dart';
import '../../models/stats.dart';
import '../../theme.dart';

/// Panneau du jour : séries / effort, séances du mois, volume de la
/// semaine comparé à la précédente (panneau KPI du web).
class KpiRow extends StatelessWidget {
  final int sets;
  final int effort;
  final int monthSessions;
  final PeriodComparison week;

  const KpiRow({
    super.key,
    required this.sets,
    required this.effort,
    required this.monthSessions,
    required this.week,
  });

  @override
  Widget build(BuildContext context) {
    final d = week.deltaPct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trois cases de même hauteur : libellés courts, l'évolution de la
        // semaine est écrite en dessous.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: Kpi(
                      label: effort > 0 ? 'Effort du jour' : 'Séries du jour',
                      value: effort > 0 ? '$effort pts' : '$sets')),
              const SizedBox(width: 8),
              Expanded(
                  child: Kpi(label: 'Séances ce mois', value: '$monthSessions')),
              const SizedBox(width: 8),
              Expanded(
                child: Kpi(
                  label: 'Reps semaine',
                  value: week.current.round().toString(),
                ),
              ),
            ],
          ),
        ),
        if (d != null)
          Padding(
            key: const ValueKey('kpi-week-delta'),
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              'Reps de la semaine : ${d >= 0 ? '+' : ''}${d.round()} % '
              'par rapport à la semaine dernière',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: d >= 0 ? Colors.green.shade700 : Colors.orange.shade800),
            ),
          ),
      ],
    );
  }
}

/// « Record série : 15 · Moy. 5 séances : 42 · Aujourd'hui : 30 (−29 %) »
class InsightLine extends StatelessWidget {
  final ExerciseInsight? insight;
  final double todayVolume;
  final int todaySets;
  final int nbDaysAvg;
  final String unit; // ' pts' pour la planche

  const InsightLine(
      {super.key,
      required this.insight,
      required this.todayVolume,
      required this.todaySets,
      required this.nbDaysAvg,
      this.unit = ''});

  static String _n(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final ins = insight;
    if (ins == null) {
      return Row(children: [
        const Icon(Icons.fiber_new, size: 18, color: AppTheme.primaryBlue),
        const SizedBox(width: 6),
        Text('Nouvel exercice', style: style),
      ]);
    }
    // À série égale : « 3 séries aujourd'hui » vs « 3 premières séries » des
    // dernières séances (moyenne), pas vs une séance complète.
    final delta =
        todaySets > 0 ? ins.deltaPctAtSets(todayVolume, todaySets) : null;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Text('🏆 Record série : ${_n(ins.prSerie)}$unit', style: style),
        Text(
            'Moy. ${nbDaysAvg < ins.sessions ? nbDaysAvg : ins.sessions} '
            'séances : ${_n(ins.avgVolume)}$unit',
            style: style),
        if (todaySets > 0)
          Text(
            "Aujourd'hui : ${_n(todayVolume)}$unit"
            '${delta == null ? '' : ' (${delta >= 0 ? '+' : ''}${delta.round()} % vs moy.)'}',
            style: style?.copyWith(
                fontWeight: FontWeight.w600,
                color: (delta ?? 0) >= 0
                    ? Colors.green.shade700
                    : Colors.orange.shade800),
          ),
      ],
    );
  }
}

class Kpi extends StatelessWidget {
  final String label;
  final String value;

  const Kpi({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
