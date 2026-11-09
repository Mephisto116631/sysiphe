import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/load_error.dart';

/// Gestion des profils (créer, renommer, supprimer) et renommage d'un
/// exercice dans l'historique — équivalent des Paramètres du web.
class ManageScreen extends StatefulWidget {
  final Profile current;

  const ManageScreen({super.key, required this.current});

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  final _svc = SupabaseService.instance;
  List<Profile> _profiles = [];
  List<String> _exercices = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Future.wait([
        _svc.getProfiles(),
        _svc.getExerciceNames(widget.current.id),
      ]);
      if (!mounted) return;
      setState(() {
        _profiles = res[0] as List<Profile>;
        _exercices = res[1] as List<String>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Exécute [action], affiche [ok] ou l'erreur, puis recharge.
  Future<void> _run(Future<void> Function() action, String ok) async {
    try {
      await action();
      _snack(ok);
    } catch (e) {
      final msg = '$e'.contains('duplicate') || '$e'.contains('23505')
          ? 'Ce nom existe déjà'
          : 'Erreur : $e';
      _snack(msg, error: true);
    }
    await _load();
  }

  /// Boîte de saisie d'un nom ; null si annulée ou inchangée.
  Future<String?> _askName(String title, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nom'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Valider')),
        ],
      ),
    );
    ctrl.dispose();
    final name = res?.trim() ?? '';
    if (name.isEmpty || name == initial.trim()) return null;
    return name;
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _addProfile() async {
    final name = await _askName('Nouveau profil');
    if (name == null) return;
    await _run(() => _svc.createProfile(name), 'Profil « $name » créé');
  }

  Future<void> _renameProfile(Profile p) async {
    final name = await _askName('Renommer « ${p.name} »', initial: p.name);
    if (name == null) return;
    await _run(() => _svc.renameProfile(p.id, name), '« ${p.name} » → « $name »');
  }

  Future<void> _deleteProfile(Profile p) async {
    if (!await _confirm('Supprimer « ${p.name} » ?',
        'Le profil disparaît de la liste. Ses séries restent en base.')) {
      return;
    }
    await _run(() => _svc.deleteProfile(p.id), 'Profil « ${p.name} » supprimé');
  }

  Future<void> _renameExercice(String ex) async {
    final name = await _askName('Renommer « $ex »', initial: ex);
    if (name == null) return;
    if (_exercices.contains(name) &&
        !await _confirm('« $name » existe déjà',
            'Les séries de « $ex » seront fusionnées dans « $name ».')) {
      return;
    }
    await _run(() => _svc.renameExercice(widget.current.id, ex, name),
        '« $ex » → « $name » dans tout l\'historique');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Profils et exercices')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Profils', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          for (final p in _profiles)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryBlue,
                                child: Text(p.initials,
                                    style: const TextStyle(color: Colors.white)),
                              ),
                              title: Text(p.name),
                              subtitle: p.id == widget.current.id
                                  ? const Text('Profil actif')
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Renommer',
                                    onPressed: () => _renameProfile(p),
                                  ),
                                  // On ne supprime pas le profil en cours.
                                  if (p.id != widget.current.id)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.redAccent),
                                      tooltip: 'Supprimer',
                                      onPressed: () => _deleteProfile(p),
                                    ),
                                ],
                              ),
                            ),
                          ListTile(
                            leading: const Icon(Icons.person_add_alt,
                                color: AppTheme.primaryBlue),
                            title: const Text('Nouveau profil'),
                            onTap: _addProfile,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Renommer un exercice', style: theme.textTheme.titleMedium),
                    Text('Corrige une faute de frappe ou uniformise un nom dans '
                        'tout ton historique.',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Card(
                      child: _exercices.isEmpty
                          ? const ListTile(title: Text('Aucun exercice'))
                          : Column(
                              children: [
                                for (final ex in _exercices)
                                  ListTile(
                                    title: Text(ex),
                                    trailing: const Icon(Icons.edit_outlined,
                                        size: 20),
                                    onTap: () => _renameExercice(ex),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
    );
  }
}
