import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/session.dart';
import '../../theme.dart';

/// Exercices de la séance précédente : un appui pré-remplit le formulaire
/// avec la série suivante, telle qu'elle a été faite la dernière fois.
class PreviousSessionCard extends StatelessWidget {
  final DateTime date;
  final List<ExerciseTemplate> templates;
  final int Function(String exercice) doneToday;
  final void Function(ExerciseTemplate) onPick;

  const PreviousSessionCard({
    super.key,
    required this.date,
    required this.templates,
    required this.doneToday,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history,
                    size: 20, color: AppTheme.primaryBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Séance précédente · '
                    '${DateFormat('EEEE d MMMM', 'fr_FR').format(date)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Touchez un exercice pour le refaire.',
                style: theme.textTheme.bodySmall),
            for (final t in templates)
              _templateTile(context, t, doneToday(t.exercice)),
          ],
        ),
      ),
    );
  }

  Widget _templateTile(BuildContext context, ExerciseTemplate t, int done) {
    final total = t.series.length;
    final finished = done >= total;
    return ListTile(
      contentPadding: const EdgeInsets.only(right: 8),
      dense: true,
      title: Text(t.exercice,
          style: TextStyle(
              decoration: finished ? TextDecoration.lineThrough : null)),
      subtitle: Text(t.summary),
      trailing: finished
          ? const Icon(Icons.check_circle, color: Colors.green)
          : done > 0
              ? Text('$done/$total',
                  style: const TextStyle(
                      color: AppTheme.primaryBlue, fontWeight: FontWeight.w600))
              : const Icon(Icons.play_circle_outline,
                  color: AppTheme.primaryBlue),
      onTap: () => onPick(t),
    );
  }
}
