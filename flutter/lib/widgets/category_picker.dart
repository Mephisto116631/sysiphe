import 'package:flutter/material.dart';

/// Choix d'une catégorie : existantes en puces, proposition, ou nouvelle.
class CategoryPickerDialog extends StatefulWidget {
  final String exercice;
  final String current;
  final List<String> categories;
  final String? suggestion;

  const CategoryPickerDialog({
    super.key,
    required this.exercice,
    required this.current,
    required this.categories,
    required this.suggestion,
  });

  @override
  State<CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<CategoryPickerDialog> {
  late final _ctrl = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _ok() {
    final v = _ctrl.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    return AlertDialog(
      title: Text(widget.exercice),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: false,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _ok(),
            ),
            if (s != null && s != _ctrl.text.trim()) ...[
              const SizedBox(height: 8),
              ActionChip(
                avatar: const Icon(Icons.auto_awesome, size: 16),
                label: Text('Proposée : $s'),
                onPressed: () => setState(() => _ctrl.text = s),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in widget.categories)
                  ChoiceChip(
                    label: Text(c),
                    selected: _ctrl.text.trim() == c,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _ctrl.text = c),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _ok, child: const Text('Appliquer')),
      ],
    );
  }
}
