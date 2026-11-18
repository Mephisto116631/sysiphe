import 'package:flutter/material.dart';

/// Légende en puces colorées ; un appui masque ou affiche la série.
class SeriesLegend extends StatelessWidget {
  final List<(String name, Color color)> items;
  final Set<String> hidden;
  final ValueChanged<String> onToggle;

  const SeriesLegend({
    super.key,
    required this.items,
    required this.hidden,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final (name, color) in items)
          FilterChip(
            avatar: CircleAvatar(
                backgroundColor:
                    hidden.contains(name) ? Colors.grey.shade400 : color,
                radius: 6),
            label: Text(name, overflow: TextOverflow.ellipsis),
            selected: !hidden.contains(name),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onToggle(name),
          ),
      ],
    );
  }
}
