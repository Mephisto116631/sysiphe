import 'package:flutter/material.dart';
import '../../models/session.dart';

/// « Nouvel exercice » : renvoie (nom, unité, catégorie).
class NewExerciceDialog extends StatefulWidget {
  final List<String> existing;

  const NewExerciceDialog({super.key, required this.existing});

  @override
  State<NewExerciceDialog> createState() => _NewExerciceDialogState();
}

class _NewExerciceDialogState extends State<NewExerciceDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cat = TextEditingController(text: 'Musculation');
  String _unite = 'Reps';

  @override
  void dispose() {
    _name.dispose();
    _cat.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final cat = _cat.text.trim();
    // Exercice déjà connu : on renvoie son nom d'origine (même casse).
    final name =
        findExistingExercise(widget.existing, _name.text) ?? _name.text.trim();
    Navigator.pop(context, (
      name,
      _unite,
      cat.isEmpty ? (_unite == 'Sec' ? 'Force Iso' : 'Musculation') : cat,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvel exercice'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    labelText: 'Nom',
                    hintText: 'ex. Tractions lestées',
                    // Pas de blocage : un nom connu ouvre l'exercice existant.
                    helperText:
                        findExistingExercise(widget.existing, _name.text) !=
                                null
                            ? 'Existe déjà : il sera ouvert tel quel'
                            : null),
                onChanged: (_) => setState(() {}),
                validator: (v) => (v?.trim() ?? '').isEmpty ? 'Requis' : null,
              ),
              const SizedBox(height: 16),
              const Text('Unité'),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Reps', label: Text('Reps')),
                  ButtonSegment(value: 'Sec', label: Text('Secondes')),
                  ButtonSegment(value: 'Kg', label: Text('Kg')),
                ],
                selected: {_unite},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() {
                  _unite = v.first;
                  // Catégorie par défaut cohérente avec l'unité.
                  if (_cat.text == 'Musculation' || _cat.text == 'Force Iso') {
                    _cat.text = _unite == 'Sec' ? 'Force Iso' : 'Musculation';
                  }
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cat,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    hintText: 'Musculation, Force Iso, Gainage…'),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _submit, child: const Text('Créer')),
      ],
    );
  }
}
