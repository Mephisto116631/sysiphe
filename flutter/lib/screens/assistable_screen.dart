import 'package:flutter/material.dart';
import '../models/perf.dart';
import '../services/data_events.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

/// Réglage « exercice assistable » : active, pour un exercice (tractions avec
/// élastique…), l'élastique, sa tension et l'écartement des mains dans la
/// saisie, et pondère l'effort. Réglage propre à chaque profil.
class AssistableScreen extends StatefulWidget {
  final String userId;
  const AssistableScreen({super.key, required this.userId});

  @override
  State<AssistableScreen> createState() => _AssistableScreenState();
}

class _AssistableScreenState extends State<AssistableScreen> {
  final _svc = SupabaseService.instance;
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
      final res = await Future.wait([
        _svc.getExerciceNames(widget.userId),
        _svc.getSettings(widget.userId),
      ]);
      if (!mounted) return;
      final a = (res[1] as Map<String, dynamic>)['assistable_exercises'];
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
      await _svc.saveSettings(
          widget.userId, {'assistable_exercises': next.toList()..sort()});
      notifyDataChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _assistables = on
          ? _assistables.where((x) => x != ex).toSet()
          : {..._assistables, ex});
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Chargement impossible : $_error',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Active-le pour un exercice qui peut se faire avec un '
                      'élastique (tractions, dips…). La saisie affiche alors '
                      'l\'élastique, sa tension et l\'écartement des mains, '
                      'et l\'effort est pondéré par l\'assistance.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: _exercices.isEmpty
                          ? const ListTile(
                              title: Text('Aucun exercice pour le moment'),
                              subtitle: Text(
                                  'Enregistre une première série : l\'exercice apparaîtra ici.'),
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
