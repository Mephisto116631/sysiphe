import 'package:flutter/material.dart';
import '../models/perf.dart';
import '../models/profile.dart';
import '../services/data_events.dart';
import '../services/supabase_service.dart';
import '../widgets/load_error.dart';

/// Réglage des exercices « assistables » (tractions avec élastique…) :
/// la saisie ajoute alors l'élastique, sa tension et l'écartement des mains,
/// et l'effort est pondéré. Réglage propre à chaque profil.
class AssistablesScreen extends StatefulWidget {
  final Profile profile;

  const AssistablesScreen({super.key, required this.profile});

  @override
  State<AssistablesScreen> createState() => _AssistablesScreenState();
}

class _AssistablesScreenState extends State<AssistablesScreen> {
  List<String> _exercices = [];
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
      final svc = SupabaseService.instance;
      final res = await Future.wait([
        svc.getExerciceNames(widget.profile.id),
        svc.getSettings(widget.profile.id),
      ]);
      final a = (res[1] as Map<String, dynamic>)['assistable_exercises'];
      if (!mounted) return;
      setState(() {
        _exercices = (res[0] as List<String>)
            .where((e) => !Perf.isPlancheName(e))
            .toList();
        _assistables = a is List ? a.map((e) => '$e'.trim()).toSet() : {};
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

  Future<void> _toggle(String ex, bool on) async {
    final next = on
        ? {..._assistables, ex}
        : _assistables.where((e) => e != ex).toSet();
    setState(() => _assistables = next); // retour immédiat
    try {
      await SupabaseService.instance.saveSettings(
          widget.profile.id, {'assistable_exercises': next.toList()..sort()});
      notifyDataChanged(); // la saisie recharge ses réglages
    } catch (e) {
      if (!mounted) return;
      setState(() => _assistables =
          on ? _assistables.where((x) => x != ex).toSet() : {..._assistables, ex});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Exercices assistables')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Active-le pour un exercice qui peut se faire avec un '
                      'élastique (tractions, dips…). La saisie ajoute alors '
                      'l\'élastique, sa tension et l\'écartement des mains, '
                      'et l\'effort est pondéré par l\'assistance.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: _exercices.isEmpty
                          ? const ListTile(
                              title: Text('Aucun exercice pour l\'instant'),
                              subtitle: Text(
                                  'Enregistre une première série pour le voir ici.'),
                            )
                          : Column(
                              children: [
                                for (final ex in _exercices)
                                  SwitchListTile(
                                    title: Text(ex),
                                    value: _assistables.contains(ex),
                                    onChanged: (v) => _toggle(ex, v),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
    );
  }
}
