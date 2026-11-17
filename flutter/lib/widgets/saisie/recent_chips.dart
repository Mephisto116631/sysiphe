import 'package:flutter/material.dart';
import '../../theme.dart';

/// Anciens exercices, du plus récent au plus ancien : un appui reprend la
/// dernière fois. En bleu : déjà fait pendant la séance.
class RecentChips extends StatelessWidget {
  final List<String> names;
  final String selected;
  final bool Function(String exercice) doneToday;
  final ValueChanged<String> onPick;

  const RecentChips({
    super.key,
    required this.names,
    required this.selected,
    required this.doneToday,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: names.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => ChoiceChip(
          // Noms longs coupés proprement
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(names[i],
                overflow: TextOverflow.ellipsis,
                style: doneToday(names[i])
                    ? const TextStyle(
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w700)
                    : null),
          ),
          showCheckmark: false,
          tooltip: names[i],
          selected: names[i] == selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onPick(names[i]),
        ),
      ),
    );
  }
}
