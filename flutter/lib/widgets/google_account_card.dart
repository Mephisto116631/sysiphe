import 'package:flutter/material.dart';
import '../screens/profile_screen.dart' show ProfileScreen;
import '../services/google_account.dart';
import '../services/session_store.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

/// Réglages → Compte Google : associer les profils de ce téléphone à un
/// compte Google (pour les retrouver sans PIN sur un autre téléphone ou sur
/// le site), ou se déconnecter de Google.
class GoogleAccountCard extends StatefulWidget {
  const GoogleAccountCard({super.key});

  @override
  State<GoogleAccountCard> createState() => _GoogleAccountCardState();
}

class _GoogleAccountCardState extends State<GoogleAccountCard> {
  String? _email;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    try {
      _email = GoogleAccount.currentEmail;
    } catch (_) {}
  }

  Future<void> _link() async {
    setState(() => _busy = true);
    final out = await GoogleAccount.supabase().connect(link: true);
    if (!mounted) return;
    String? email;
    try {
      email = GoogleAccount.currentEmail;
    } catch (_) {}
    setState(() {
      _busy = false;
      _email = email;
    });
    final (msg, error) = switch (out.result) {
      GoogleResult.linked => (
          'Compte Google associé ✓ — ${out.profiles} profil'
              '${out.profiles > 1 ? 's' : ''} accessible'
              '${out.profiles > 1 ? 's' : ''} sans PIN',
          false
        ),
      GoogleResult.cancelled => ('Connexion Google annulée', true),
      GoogleResult.noProfile => (
          'Aucun profil sur ce téléphone à associer',
          true
        ),
      GoogleResult.tokenError => (
          'Connecté à Google, mais l\'association a échoué '
              '(${out.message}). Réessaie.',
          true
        ),
      _ => ('Erreur : ${out.message}', true),
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green));
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter de Google ?'),
        content: const Text(
            'Ce téléphone revient à l\'écran des profils ; le PIN sera '
            'redemandé, ou « Se connecter avec Google ».'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Déconnecter')),
        ],
      ),
    );
    if (ok != true) return;
    await SessionStore.clear();
    await SupabaseService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle_outlined,
                color: AppTheme.primaryBlue),
            title: Text(email == null
                ? 'Associer mon compte Google'
                : 'Associé à $email'),
            subtitle: Text(email == null
                ? 'Retrouve tes profils sans PIN sur un autre téléphone ou '
                    'sur le site'
                : 'Sur un autre téléphone ou sur le site : « Se connecter '
                    'avec Google »'),
            trailing: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : email == null
                    ? const Icon(Icons.chevron_right,
                        color: AppTheme.textSecondary)
                    : null,
            onTap: _busy || email != null ? null : _link,
          ),
          if (email != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _signOut,
                child: const Text('Se déconnecter de Google'),
              ),
            ),
        ],
      ),
    );
  }
}
