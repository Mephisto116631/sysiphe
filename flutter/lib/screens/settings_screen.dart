import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/profile.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'profile_screen.dart' show unawaited, ProfileScreen;

class SettingsScreen extends StatefulWidget {
  final String userId;
  final Profile profile;

  const SettingsScreen(
      {super.key, required this.userId, required this.profile});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _weightCtrl = TextEditingController();
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await SupabaseService.instance.getSettings(widget.userId);
    if (!mounted) return;
    setState(() {
      _weightCtrl.text = ((s['weight'] as num?)?.toString() ?? '97');
      _loading = false;
    });
  }

  Future<void> _saveWeight() async {
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    if (weight == null || weight <= 0) {
      _snack('Poids invalide', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService.instance
          .saveSettings(widget.userId, {'weight': weight});
      setState(() => _saving = false);
      _snack('Poids enregistré');
    } catch (e) {
      setState(() => _saving = false);
      _snack('Erreur : $e', error: true);
    }
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
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              if (ctrl1.text.isEmpty || ctrl1.text != ctrl2.text) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('PINs ne correspondent pas')),
                  );
                }
                return;
              }
              try {
                await SupabaseService.instance
                    .setPin(widget.userId, ctrl1.text);
                if (ctx.mounted) Navigator.pop(ctx);
                _snack('PIN mis à jour');
              } catch (e) {
                _snack('Erreur : $e', error: true);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
      (_) => false,
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionLabel('Profil'),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryBlue,
                      child: Text(widget.profile.initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text(widget.profile.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    subtitle: const Text('Profil actif'),
                  ),
                ),
                const SizedBox(height: 20),

                _SectionLabel('Entraînement'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Poids corporel (kg)',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text('Utilisé pour le calcul d\'effort planche.',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _weightCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d.,]')),
                                ],
                                decoration: const InputDecoration(
                                    labelText: 'Poids', suffixText: 'kg'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _saving ? null : _saveWeight,
                              style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(80, 50)),
                              child: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Text('OK'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                _SectionLabel('Sécurité'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline,
                        color: AppTheme.primaryBlue),
                    title: const Text('Changer le PIN'),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppTheme.textSecondary),
                    onTap: _changePin,
                  ),
                ),
                const SizedBox(height: 20),

                _SectionLabel('Session'),
                Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text('Changer de profil',
                        style: TextStyle(color: Colors.redAccent)),
                    onTap: _logout,
                  ),
                ),
                const SizedBox(height: 40),
                Center(
                  child: Text('Sysiphe v2.0 · Flutter',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
