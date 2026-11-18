import 'package:flutter/material.dart';
import '../models/categorize.dart';
import '../models/perf.dart';
import '../services/data_events.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/load_error.dart';

/// Réglages → Catégories des exercices : ranger chaque exercice dans une
/// catégorie (sa nomenclature à soi), appliqué à tout son historique. Ces
/// choix servent ensuite à proposer la catégorie des nouveaux exercices.
class CategoriesScreen extends StatefulWidget {
  final String userId;

  /// Historique et enregistrement fournis directement (tests).
  final List<Perf>? initialPerfs;
  final Future<void> Function(String exercice, String categorie)? onSave;

  const CategoriesScreen(
      {super.key, required this.userId, this.initialPerfs, this.onSave});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<ExerciseCategory> _items = [];
  bool _loading = true;
  Object? _error;
  List<Perf>? _perfs;

  @override
  void initState() {
    super.initState();
    _perfs = widget.initialPerfs;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final perfs =
          _perfs ?? await SupabaseService.instance.getAllPerfs(widget.userId);
      if (!mounted) return;
      setState(() {
        _items = exerciseCategories(perfs);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<String> get _categories {
    final c = <String, int>{};
    for (final i in _items) {
      i.counts.forEach((k, v) => c[k] = (c[k] ?? 0) + v);
    }
    return c.keys.toList()..sort((a, b) => c[b]!.compareTo(c[a]!));
  }

  Future<void> _edit(ExerciseCategory item) async {
    // Proposition apprise des AUTRES exercices (pas de celui-ci).
    final learner = CategoryLearner({
      for (final i in _items)
        if (i.exercice != item.exercice) i.exercice: i.main
    });
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryDialog(
        exercice: item.exercice,
        current: item.main,
        categories: _categories,
        suggestion: learner.suggest(item.exercice),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == item.main && !item.mixed) return;
    try {
      await (widget.onSave ??
          (ex, c) => SupabaseService.instance.setExerciseCategory(
              widget.userId, ex, c))(item.exercice, picked);
      if (_perfs != null) {
        _perfs = [
          for (final p in _perfs!)
            p.exercice == item.exercice ? p.copyWithCategorie(picked) : p
        ];
      }
      notifyDataChanged(); // Stats et Saisie relisent les catégories
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('« ${item.exercice} » → $picked '
            '(${item.sets} série${item.sets > 1 ? 's' : ''})'),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Catégories des exercices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                        'Range chaque exercice avec tes propres catégories : '
                        'tout son historique suit. Ces choix servent ensuite '
                        'à proposer la catégorie des nouveaux exercices.',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          for (final i in _items)
                            ListTile(
                              title: Text(i.exercice),
                              subtitle: Text(i.mixed
                                  ? 'Mélangé : ${(i.counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key} ${e.value}').join(' · ')}'
                                  : '${i.main} · ${i.sets} série${i.sets > 1 ? 's' : ''}'),
                              trailing: const Icon(Icons.edit_outlined,
                                  size: 20, color: AppTheme.textSecondary),
                              onTap: () => _edit(i),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Choix d'une catégorie : existantes en puces, proposition, ou nouvelle.
class _CategoryDialog extends StatefulWidget {
  final String exercice;
  final String current;
  final List<String> categories;
  final String? suggestion;

  const _CategoryDialog({
    required this.exercice,
    required this.current,
    required this.categories,
    required this.suggestion,
  });

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
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
