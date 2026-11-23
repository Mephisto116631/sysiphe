import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/perf.dart';
import '../../services/profile_prefs.dart';
import '../../theme.dart';

String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Une série du jour : valeur, options planche, effort (en couleur
/// d'intensité pour la planche) et repos pris avant (en orange s'il a été
/// passé ou raccourci).
class PerfTile extends StatelessWidget {
  final Perf perf;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  /// Meilleur effort de planche connu (couleurs en mode automatique).
  final int bestEffort;

  const PerfTile(
      {super.key,
      required this.perf,
      required this.onDelete,
      required this.onEdit,
      this.bestEffort = 0});

  @override
  Widget build(BuildContext context) {
    // Un appui permet de corriger la série.
    return Card(
      child: ListTile(
        onTap: perf.id != null ? onEdit : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
          child: Text('S${perf.serie}',
              style: const TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
        title: Text(perf.exercice,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text.rich(
          TextSpan(style: const TextStyle(fontSize: 12), children: [
            TextSpan(text: perf.displayValue),
            if (perf.isPlanche)
              TextSpan(text: ' · ${perf.variante} · ${perf.forme}'),
            if ((perf.effortPondere ?? 0) > 0) ...[
              const TextSpan(text: ' · '),
              TextSpan(
                text: '${perf.effortPondere} pts',
                style: perf.isPlanche
                    ? TextStyle(
                        fontWeight: FontWeight.w700,
                        color: intensityNotifier.value.colorFor(
                            perf.effortPondere!,
                            best: bestEffort > 0
                                ? bestEffort
                                : perf.effortPondere!))
                    : null,
              ),
            ],
            if (perf.reposS != null)
              TextSpan(
                text: perf.reposPasse
                    ? ' · repos passé (${_clock(perf.reposS!)} / '
                        '${_clock(perf.reposPrevuS!)})'
                    : ' · repos ${_clock(perf.reposS!)}',
                style: perf.reposPasse
                    ? TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600)
                    : null,
              ),
          ]),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
          onPressed: perf.id != null ? onDelete : null,
        ),
      ),
    );
  }
}

/// Séries du jour affiché (titre de date, chargement, liste vide ou tuiles).
class DayPerfList extends StatelessWidget {
  final int bestEffort;
  final DateTime date;
  final bool loading;
  final List<Perf> perfs;
  final ValueChanged<Perf> onEdit;
  final ValueChanged<Perf> onDelete;

  const DayPerfList({
    super.key,
    this.bestEffort = 0,
    required this.date,
    required this.loading,
    required this.perfs,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('d MMMM', 'fr_FR').format(date),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (perfs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Aucune saisie pour ce jour',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: perfs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => PerfTile(
                bestEffort: bestEffort,
                perf: perfs[i],
                onDelete: () => onDelete(perfs[i]),
                onEdit: () => onEdit(perfs[i])),
          ),
      ],
    );
  }
}
