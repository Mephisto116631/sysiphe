import 'package:flutter/material.dart';
import '../../models/categorize.dart';
import '../../models/session.dart';

/// « Nouvel exercice » : renvoie (nom, unité, catégorie).
/// La catégorie est proposée pendant la frappe du nom, d'après la façon dont
/// l'utilisateur a rangé ses exercices ([categories] : exercice → catégorie),
/// tant qu'il ne l'a pas choisie lui-même.
class NewExerciceDialog extends StatefulWidget {
  final List<String> existing;
  final Map<String, String> categories;

  const NewExerciceDialog(
      {super.key, required this.existing, this.categories = const {}});

  @override
  State<NewExerciceDialog> createState() => _NewExerciceDialogState();
}

class _NewExerciceDialogState extends State<NewExerciceDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cat = TextEditingController(text: 'Musculation');
  String _unite = 'Reps';
  late final _learner = CategoryLearner(widget.categories);
  bool _catChosen = false; // catégorie choisie à la main : plus de proposition
  bool _suggested = false;

  /// Catégories déjà utilisées, les plus fréquentes d'abord.
  late final List<String> _known = () {
    final n = <String, int>{};
    for (final c in widget.categories.values) {
      n[c] = (n[c] ?? 0) + 1;
    }
    return n.keys.toList()..sort((a, b) => n[b]!.compareTo(n[a]!));
  }();

  String get _defaultCat => _unite == 'Sec' ? 'Force Iso' : 'Musculation';

  void _onName(String name) {
    if (_catChosen) return;
    final s = _learner.suggest(name);
    _suggested = s != null;
    _cat.text = s ?? _defaultCat;
  }

  void _pickCat(String c) {
    _catChosen = true;
    _suggested = false;
    _cat.text = c;
  }

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
                onChanged: (v) => setState(() => _onName(v)),
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
                  // Catégorie par défaut cohérente avec l'unité (sauf si
                  // proposée d'après le nom ou choisie).
                  if (!_catChosen && !_suggested) _cat.text = _defaultCat;
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cat,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    labelText: 'Catégorie',
                    hintText: 'Musculation, Force Iso, Gainage…',
                    helperText:
                        _suggested ? 'Proposée d\'après tes exercices' : null,
                    prefixIcon: _suggested
                        ? const Icon(Icons.auto_awesome, size: 18)
                        : null),
                onChanged: (_) => setState(() {
                  _catChosen = true;
                  _suggested = false;
                }),
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_known.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final c in _known.take(8))
                      ChoiceChip(
                        label: Text(c),
                        selected: _cat.text.trim() == c,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _pickCat(c)),
                      ),
                  ],
                ),
              ],
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
