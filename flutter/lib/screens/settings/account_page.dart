import 'package:flutter/material.dart';
import '../../models/profile.dart';
import '../../services/session_store.dart';
import '../../services/supabase_service.dart';
import '../../theme.dart';
import '../../widgets/google_account_card.dart';
import '../../widgets/load_error.dart';
import 'common.dart';

/// Réglages → Compte et sécurité : compte Google, PIN, profils (créer,
/// renommer, supprimer).
class AccountPage extends StatefulWidget {
  final Profile current;
  const AccountPage({super.key, required this.current});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _svc = SupabaseService.instance;
  List<Profile> _profiles = [];
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
      final p = await _svc.getProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = p;
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

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) showSnack(context, ok);
    } catch (e) {
      if (!mounted) return;
      final dup = '$e'.contains('duplicate') || '$e'.contains('23505');
      showSnack(context, dup ? 'Ce nom existe déjà' : 'Erreur : $e',
          error: true);
    }
    await _load();
  }

  Future<void> _addProfile() async {
    final name = await askName(context, 'Nouveau profil');
    if (name == null) return;
    await _run(() => _svc.createProfile(name), 'Profil « $name » créé');
  }

  Future<void> _renameProfile(Profile p) async {
    final name =
        await askName(context, 'Renommer « ${p.name} »', initial: p.name);
    if (name == null) return;
    await _run(() async {
      await _svc.renameProfile(p.id, name);
      if (p.id == widget.current.id) {
        // Garder le profil mémorisé à jour pour les prochaines ouvertures.
        await SessionStore.save(
            Profile(id: p.id, name: name, hasPin: p.hasPin));
      }
    }, '« ${p.name} » → « $name »');
  }

  Future<void> _deleteProfile(Profile p) async {
    if (!await confirmAction(context, 'Supprimer « ${p.name} » ?',
        'Le profil disparaît de la liste. Ses séries restent en base.',
        ok: 'Supprimer')) {
      return;
    }
    await _run(() => _svc.deleteProfile(p.id), 'Profil « ${p.name} » supprimé');
  }

  Future<void> _changePin() async {
    final ctrl1 = TextEditingController();
    final ctrl2 = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer le PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl1,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                  labelText: 'Nouveau PIN', counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl2,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                  labelText: 'Confirmer le PIN', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (ctrl1.text.isEmpty || ctrl1.text != ctrl2.text) {
                showSnack(ctx, 'PINs ne correspondent pas', error: true);
                return;
              }
              try {
                await _svc.setPin(widget.current.id, ctrl1.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) showSnack(context, 'PIN mis à jour');
              } catch (e) {
                if (mounted) showSnack(context, 'Erreur : $e', error: true);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compte et sécurité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('Compte Google'),
          const GoogleAccountCard(),
          const SizedBox(height: 16),
          const SectionLabel('PIN'),
          Card(
            child: ListTile(
              leading:
                  const Icon(Icons.lock_outline, color: AppTheme.primaryBlue),
              title: const Text('Changer le PIN'),
              subtitle: Text('Profil ${widget.current.name}'),
              trailing: const Icon(Icons.chevron_right,
                  color: AppTheme.textSecondary),
              onTap: _changePin,
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Profils'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            LoadError(error: _error!, onRetry: _load)
          else
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
        ],
      ),
    );
  }
}
