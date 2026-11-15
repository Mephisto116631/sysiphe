import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../models/interval_plan.dart' show clock;
import '../theme.dart';

/// Repos entre les séries. Au repos : gros décompte avec −15 s / +15 s /
/// Passer. Sinon : le choix de la durée du repos automatique (« Sans »
/// désactive), mémorisé sur l'appareil.
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: left,
      builder: (context, d, _) {
        if (d != null) {
          return Card(
            color: Colors.blue.shade700,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_bottom, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text('Repos',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(clock(d),
                          key: const ValueKey('rest-time'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                      onPressed: () => onAdjust(-15),
                      child: const Text('−15',
                          style: TextStyle(color: Colors.white))),
                  TextButton(
                      onPressed: () => onAdjust(15),
                      child: const Text('+15',
                          style: TextStyle(color: Colors.white))),
                  FilledButton.tonal(
                      onPressed: onSkip, child: const Text('Passer')),
                ],
              ),
            ),
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Repos après chaque série',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                for (final c in choices)
                  ChoiceChip(
                    label: Text(label(c)),
                    selected: seconds == c,
                    onSelected: (_) => onConfig(c),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
