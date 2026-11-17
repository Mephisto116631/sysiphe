import 'package:flutter/material.dart';
import '../../theme.dart';

class SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const SmallBtn({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.bgGrey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Icon(icon, size: 16, color: AppTheme.textPrimary),
      ),
    );
  }
}

class DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?>? onChanged;

  const DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
      items: items
          .map((item) => DropdownMenuItem<T>(
                value: item,
                child:
                    Text(item.toString(), style: const TextStyle(fontSize: 14)),
              ))
          .toList(),
    );
  }
}

/// « Série » avec − / + (jamais sous 1).
class SeriesStepper extends StatelessWidget {
  final int serie;
  final ValueChanged<int> onChanged;

  const SeriesStepper(
      {super.key, required this.serie, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Série',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Row(
          children: [
            SmallBtn(
                icon: Icons.remove,
                onTap: () {
                  if (serie > 1) onChanged(serie - 1);
                }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('$serie',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            SmallBtn(icon: Icons.add, onTap: () => onChanged(serie + 1)),
          ],
        ),
      ],
    );
  }
}
