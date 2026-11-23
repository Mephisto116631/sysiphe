import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../models/interval_plan.dart' show clock;
import '../theme.dart';

/// Repos entre les séries. Au repos : une ligne bleue compacte (décompte,
/// −15 s / +15 s, Passer). Sinon : le choix discret de la durée du repos
/// automatique (« Sans » désactive), mémorisé sur l'appareil.
class RestBar extends StatelessWidget {
  static const choices = [0, 60, 90, 120, 180];

  final int seconds; // réglage (0 = sans repos automatique)
  final ValueChanged<int> onConfig;
  final ValueListenable<Duration?> left; // null = pas de repos en cours
  final VoidCallback onSkip;
  final ValueChanged<int> onAdjust; // ± secondes

  const RestBar({
    super.key,
    required this.seconds,
    required this.onConfig,
    required this.left,
    required this.onSkip,
    required this.onAdjust,
  });

  static String label(int s) => s == 0
      ? 'Sans'
      : s % 60 == 0
          ? '${s ~/ 60} min'
          : '$s s';

  Widget _small(String text, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(40, 36),
            padding: const EdgeInsets.symmetric(horizontal: 6)),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: left,
      builder: (context, d, _) {
        if (d != null) {
          // Pendant le repos : une seule ligne bleue, compacte.
          return Card(
            color: Colors.blue.shade700,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_bottom,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(clock(d),
                          key: const ValueKey('rest-time'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  _small('−15', () => onAdjust(-15)),
                  _small('+15', () => onAdjust(15)),
                  const SizedBox(width: 4),
                  FilledButton.tonal(
                    onPressed: onSkip,
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: const Text('Passer'),
                  ),
                ],
              ),
            ),
          );
        }
        // Hors repos : choix discret de la durée.
        return Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty,
                size: 16, color: AppTheme.textSecondary),
            const Text('Repos',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            for (final c in choices)
              ChoiceChip(
                label: Text(label(c)),
                selected: seconds == c,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onConfig(c),
              ),
          ],
        );
      },
    );
  }
}
