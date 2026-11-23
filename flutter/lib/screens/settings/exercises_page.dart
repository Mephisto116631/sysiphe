import 'package:flutter/material.dart';
import '../../models/categorize.dart';
import '../../models/perf.dart';
import '../../services/data_events.dart';
import '../../services/profile_prefs.dart';
import '../../services/supabase_service.dart';
import '../../theme.dart';
import '../../widgets/category_picker.dart';
import '../../widgets/intensity_dialog.dart';
import '../model_screen.dart';
import '../../widgets/load_error.dart';
import 'common.dart';

/// Opérations sur les exercices (injectables pour les tests).
class ExerciseOps {
  final Future<List<Perf>> Function() loadPerfs;
  final Future<Set<String>> Function() loadAssistables;
  final Future<void> Function(String from, String to) rename;
  final Future<void> Function(String exercice, String categorie) setCategory;
  final Future<void> Function(Set<String> assistables) saveAssistables;

  /// Réglages du profil : planche activée, couleurs d'intensité.
  final Future<void> Function(Map<String, dynamic> settings) saveSettings;

  /// Profil, pour ouvrir son Modèle de la planche (null : pas de lien).
  final String? userId;

  const ExerciseOps({
    required this.loadPerfs,
    required this.loadAssistables,
    required this.rename,
    required this.setCategory,
    required this.saveAssistables,
    required this.saveSettings,
    this.userId,
  });

  factory ExerciseOps.supabase(String userId) {
    final s = SupabaseService.instance;
    return ExerciseOps(
      loadPerfs: () => s.getAllPerfs(userId),
      loadAssistables: () async {
        final a = (await s.getSettings(userId))['assistable_exercises'];
        return a is List ? a.map((e) => '$e'.trim()).toSet() : <String>{};
      },
      rename: (from, to) => s.renameExercice(userId, from, to),
      setCategory: (ex, c) => s.setExerciseCategory(userId, ex, c),
      saveAssistables: (a) =>
          s.saveSettings(userId, {'assistable_exercises': a.toList()..sort()}),
      saveSettings: (m) => s.saveSettings(userId, m),
      userId: userId,
    );
  }
}

enum _Action { rename, category, assistable, planche, model, intensity }

/// Réglages → Exercices : une ligne par exercice ; un appui ouvre sa fiche
/// (renommer, catégorie, assistable). Remplace les anciens écrans « Profils et
/// exercices » (partie exercices), « Catégories » et « Assistables ».
class ExercisesPage extends StatefulWidget {
  final ExerciseOps ops;
  const ExercisesPage({super.key, required this.ops});

  @override
  State<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends State<ExercisesPage> {
  List<ExerciseCategory> _items = [];
  Set<String> _assistables = {};
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait(
          [widget.ops.loadPerfs(), widget.ops.loadAssistables()]);
      if (!mounted) return;
      setState(() {
        _items = exerciseCategories(r[0] as List<Perf>);
        // La fiche Planche est toujours là, pour pouvoir l'activer.
        if (!_items.any((i) => Perf.isPlancheRawName(i.exercice))) {
          _items = [
            const ExerciseCategory('Planche', 'Planche', {}),
            ..._items
          ];
        }
        _assistables = r[1] as Set<String>;
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

  String _subtitle(ExerciseCategory i) {
    if (Perf.isPlancheRawName(i.exercice)) {
      final on = plancheEnabledNotifier.value;
      return [
        on ? 'Planche activée' : 'Planche désactivée',
        if (i.sets > 0) '${i.sets} série${i.sets > 1 ? 's' : ''}',
      ].join(' · ');
    }
    final cat = i.mixed
        ? 'Mélangé : ${(i.counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key} ${e.value}').join(' · ')}'
        : i.main;
    final n = '${i.sets} série${i.sets > 1 ? 's' : ''}';
    return [cat, n, if (_assistables.contains(i.exercice)) 'assistable']
        .join(' · ');
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      notifyDataChanged(); // Saisie et Stats relisent
      if (mounted) showSnack(context, ok);
    } catch (e) {
      if (!mounted) return;
      final dup = '$e'.contains('duplicate') || '$e'.contains('23505');
      showSnack(context, dup ? 'Ce nom existe déjà' : errorText(e),
          error: true);
    }
    await _load();
  }

  Future<void> _open(ExerciseCategory i) async {
    final planche = Perf.isPlancheRawName(i.exercice);
    final plancheOn = plancheEnabledNotifier.value;
    final intensity = intensityNotifier.value;
    final assist = _assistables.contains(i.exercice);
    final action = await showModalBottomSheet<_Action>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true, // fiche Planche plus longue : défilante
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(i.exercice,
                  style: Theme.of(ctx).textTheme.titleMedium,
                  textAlign: TextAlign.center),
            ),
            if (planche) ...[
              // La planche est reconnue par son nom : pas de renommage.
              SwitchListTile(
                secondary: const Icon(Icons.accessibility_new,
                    color: AppTheme.primaryBlue),
                title: const Text('Activer la planche'),
                subtitle: const Text(
                    'Options, effort pondéré, stats et Modèle de la planche'),
                value: plancheOn,
                onChanged: (_) => Navigator.pop(ctx, _Action.planche),
              ),
              if (plancheOn && widget.ops.userId != null)
                ListTile(
                  leading:
                      const Icon(Icons.functions, color: AppTheme.primaryBlue),
                  title: const Text('Modèle de la planche'),
                  subtitle:
                      const Text('Tes coefficients, propres à ton profil'),
                  onTap: () => Navigator.pop(ctx, _Action.model),
                ),
              if (plancheOn)
                ListTile(
                  leading: const Icon(Icons.palette_outlined,
                      color: AppTheme.primaryBlue),
                  title: const Text('Couleurs d\'intensité'),
                  subtitle: Text(intensity.auto
                      ? 'Automatique (relatif à ton meilleur effort)'
                      : 'Orange dès ${intensity.orange} pts · '
                          'rouge dès ${intensity.rouge} pts'),
                  onTap: () => Navigator.pop(ctx, _Action.intensity),
                ),
            ] else
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: AppTheme.primaryBlue),
                title: const Text('Renommer'),
                subtitle: const Text('Dans tout l\'historique'),
                onTap: () => Navigator.pop(ctx, _Action.rename),
              ),
            if (i.sets > 0)
              ListTile(
                leading: const Icon(Icons.category_outlined,
                    color: AppTheme.primaryBlue),
                title: const Text('Catégorie'),
                subtitle: Text(i.mixed ? 'Mélangée' : i.main),
                onTap: () => Navigator.pop(ctx, _Action.category),
              ),
            if (!planche)
              SwitchListTile(
                secondary: const Icon(Icons.fitness_center_outlined,
                    color: AppTheme.primaryBlue),
                title: const Text('Assistable'),
                subtitle: const Text(
                    'Élastique, tension et écartement dans la saisie'),
                value: assist,
                onChanged: (_) => Navigator.pop(ctx, _Action.assistable),
              ),
            const SizedBox(height: 8),
          ],
        )),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _Action.rename:
        await _rename(i.exercice);
      case _Action.category:
        await _category(i);
      case _Action.planche:
        await _run(() async {
          await widget.ops.saveSettings({'include_planche': !plancheOn});
          applyProfilePrefs({
            'include_planche': !plancheOn,
            'intensity_config': intensity.toSettings(),
          });
        }, plancheOn ? 'Planche désactivée' : 'Planche activée');
      case _Action.model:
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ModelScreen(userId: widget.ops.userId!)));
      case _Action.intensity:
        final cfg = await askIntensity(context, intensity);
        if (cfg == null || !mounted) return;
        await _run(() async {
          await widget.ops.saveSettings({'intensity_config': cfg.toSettings()});
          intensityNotifier.value = cfg;
        }, 'Couleurs d\'intensité enregistrées');
      case _Action.assistable:
        final next = assist
            ? _assistables.where((e) => e != i.exercice).toSet()
            : {..._assistables, i.exercice};
        await _run(
            () => widget.ops.saveAssistables(next),
            assist
                ? '« ${i.exercice} » n\'est plus assistable'
                : '« ${i.exercice} » est assistable');
    }
  }

  Future<void> _rename(String ex) async {
    final name = await askName(context, 'Renommer « $ex »', initial: ex);
    if (name == null || !mounted) return;
    final exists = _items.any((i) => i.exercice == name);
    if (exists &&
        !await confirmAction(context, '« $name » existe déjà',
            'Les séries de « $ex » seront fusionnées dans « $name ».')) {
      return;
    }
    await _run(() async {
      await widget.ops.rename(ex, name);
      if (_assistables.contains(ex)) {
        await widget.ops
            .saveAssistables({..._assistables.where((e) => e != ex), name});
      }
    }, '« $ex » → « $name » dans tout l\'historique');
  }

  Future<void> _category(ExerciseCategory item) async {
    // Proposition apprise des AUTRES exercices.
    final learner = CategoryLearner({
      for (final i in _items)
        if (i.exercice != item.exercice) i.exercice: i.main
    });
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => CategoryPickerDialog(
        exercice: item.exercice,
        current: item.main,
        categories: _categories,
        suggestion: learner.suggest(item.exercice),
      ),
    );
    if (picked == null || (picked == item.main && !item.mixed)) return;
    await _run(() => widget.ops.setCategory(item.exercice, picked),
        '« ${item.exercice} » → $picked');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                        'Touche un exercice pour le renommer, changer sa '
                        'catégorie (tes propres catégories : elles servent à '
                        'proposer celle des nouveaux exercices) ou le rendre '
                        'assistable.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Card(
                      child: _items.isEmpty
                          ? const ListTile(
                              title: Text('Aucun exercice pour le moment'),
                              subtitle: Text('Enregistre une première série : '
                                  'l\'exercice apparaîtra ici.'))
                          : Column(
                              children: [
                                for (final i in _items)
                                  ListTile(
                                    title: Text(i.exercice),
                                    subtitle: Text(_subtitle(i)),
                                    trailing: const Icon(Icons.chevron_right,
                                        color: AppTheme.textSecondary),
                                    onTap: () => _open(i),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
    );
  }
}
