import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/session_store.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'home_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Profile> _profiles = [];
  bool _loading = true;
  String? _error;

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
      final profiles = await SupabaseService.instance.getProfiles();
      setState(() {
        _profiles = profiles;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Connexion impossible : $e';
        _loading = false;
      });
    }
  }

  Future<void> _pick(Profile profile) async {
    if (profile.hasPin) {
      final ok = await _askPin(profile);
      if (!ok) return;
    }
    unawaited(SupabaseService.instance.touchLogin(profile.id));
    await SessionStore.save(profile); // plus de PIN aux prochaines ouvertures
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
    );
  }

  /// « Créer un compte » : prénom + PIN facultatif, puis entrée directe.
  Future<void> _createAccount() async {
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _CreateAccountDialog(),
    );
    if (res == null) return;
    final (name, pin) = res;
    try {
      final profile =
          await SupabaseService.instance.createProfile(name, pin: pin);
      await SessionStore.save(profile);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
      );
    } catch (e) {
      if (!mounted) return;
      final dup = '$e'.contains('duplicate') || '$e'.contains('23505');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dup ? 'Le profil « $name » existe déjà' : 'Erreur : $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<bool> _askPin(Profile profile) async {
    final ctrl = TextEditingController();
    bool ok = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool checking = false;
        return StatefulBuilder(builder: (ctx2, setLocal) {
          Future<void> submit() async {
            setLocal(() => checking = true);
            final valid =
                await SupabaseService.instance.verifyPin(profile.id, ctrl.text);
            setLocal(() => checking = false);
            if (valid) {
              ok = true;
              if (ctx2.mounted) Navigator.of(ctx2).pop();
            } else {
              ctrl.clear();
              if (ctx2.mounted) {
                ScaffoldMessenger.of(ctx2).showSnackBar(
                  const SnackBar(
                    content: Text('PIN incorrect'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }

          return AlertDialog(
            title: Text('PIN — ${profile.name}'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: 'Entrez votre PIN',
                counterText: '',
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx2).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: checking ? null : submit,
                child: checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('OK'),
              ),
            ],
          );
        });
      },
    );
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.fitness_center,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text('Sysiphe',
                      style: Theme.of(context).textTheme.headlineMedium),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Choisissez votre profil',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 40),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 160,
                          child: ElevatedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Réessayer'),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.15,
                    ),
                    itemCount: _profiles.length + 1,
                    itemBuilder: (ctx, i) => i == _profiles.length
                        ? _NewProfileCard(onTap: _createAccount)
                        : _ProfileCard(
                            profile: _profiles[i],
                            onTap: () => _pick(_profiles[i]),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;
  final VoidCallback onTap;

  const _ProfileCard({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.primaryBlue,
                child: Text(
                  profile.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                profile.name,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (profile.hasPin) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.lock, size: 12, color: AppTheme.textSecondary),
                    SizedBox(width: 3),
                    Text('PIN',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NewProfileCard extends StatelessWidget {
  final VoidCallback onTap;

  const _NewProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFE3F2FD),
                child: Icon(Icons.person_add_alt_1,
                    color: AppTheme.primaryBlue, size: 28),
              ),
              SizedBox(height: 10),
              Text('Créer un compte',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryBlue)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renvoie (prénom, PIN) — PIN vide = pas de PIN.
class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog();

  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, (_name.text.trim(), _pin.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer un compte'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Prénom / pseudo', hintText: 'ex. Sarah'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                  labelText: 'PIN (facultatif)', counterText: ''),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                return RegExp(r'^\d{4,6}$').hasMatch(t)
                    ? null
                    : '4 à 6 chiffres';
              },
            ),
            TextFormField(
              controller: _pin2,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                  labelText: 'Confirmer le PIN', counterText: ''),
              validator: (v) => (v?.trim() ?? '') == _pin.text.trim()
                  ? null
                  : 'Les PIN ne correspondent pas',
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
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

void unawaited(Future<void> f) {}
