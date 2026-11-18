import 'package:flutter/material.dart';
import '../app_version.dart';
import '../models/profile.dart';
import '../services/google_account.dart';
import '../services/reminders.dart';
import '../services/role.dart';
import '../services/session_store.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'profile_screen.dart' show ProfileScreen;
import 'settings/account_page.dart';
import 'settings/admin_page.dart';
import 'settings/app_page.dart';
import 'settings/common.dart';
import 'settings/exercises_page.dart';
import 'settings/reminders_page.dart';
import 'settings/training_page.dart';

/// État résumé affiché sous chaque entrée de l'écran principal.
class SettingsSummary {
  final double weight;
  final bool enableCharges;
  final bool remindersOn;
  final int reminderHour;
  final int inactivityDays;
  final String? googleEmail;

  const SettingsSummary({
    this.weight = 97,
    this.enableCharges = true,
    this.remindersOn = true,
    this.reminderHour = Reminders.defaultHour,
    this.inactivityDays = 2,
    this.googleEmail,
  });

  static Future<SettingsSummary> load(String userId) async {
    final s = await SupabaseService.instance.getSettings(userId);
    String? email;
    try {
      email = GoogleAccount.currentEmail;
    } catch (_) {}
    return SettingsSummary(
      weight: (s['weight'] as num?)?.toDouble() ?? 97,
      enableCharges: s['enable_charges'] as bool? ?? true,
      remindersOn: await Reminders.enabled(),
      reminderHour: await Reminders.hour(),
      inactivityDays: (s['inactivity_days'] as num?)?.toInt() ?? 2,
      googleEmail: email,
    );
  }
}

String _num(double v) => v % 1 == 0 ? v.toInt().toString() : '$v';

/// Réglages : en-tête du profil, puis une entrée par thème (sous-pages).
class SettingsScreen extends StatefulWidget {
  final String userId;
  final Profile profile;

  /// Résumé fourni directement (tests) : pas d'accès réseau.
  final Future<SettingsSummary> Function()? loadSummary;

  const SettingsScreen(
      {super.key,
      required this.userId,
      required this.profile,
      this.loadSummary});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsSummary? _s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await (widget.loadSummary ??
          () => SettingsSummary.load(widget.userId))();
      if (mounted) setState(() => _s = s);
    } catch (_) {
      if (mounted) setState(() => _s ??= const SettingsSummary());
    }
  }

  /// Ouvre une sous-page puis rafraîchit les résumés au retour.
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    // Session anonyme : on la ferme, ce téléphone perd son rattachement aux
    // profils et le PIN sera redemandé (une nouvelle session sera créée).
    // Session Google : gardée (ses profils restent accessibles sans PIN) ;
    // « Se déconnecter de Google » est dans Compte et sécurité.
    if (GoogleAccount.currentEmail == null) {
      await SupabaseService.instance.signOut();
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryBlue,
                    child: Text(widget.profile.initials,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(widget.profile.name,
                      style: theme.textTheme.titleMedium),
                  subtitle: Text(s == null
                      ? 'Profil actif'
                      : 'Profil actif · ${_num(s.weight)} kg'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.swap_horiz, color: Colors.redAccent),
                  title: const Text('Changer de profil',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: _logout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                NavTile(
                  icon: Icons.fitness_center,
                  title: 'Entraînement',
                  subtitle: s == null
                      ? 'Poids, champ lest'
                      : 'Poids ${_num(s.weight)} kg · lest '
                          '${s.enableCharges ? 'affiché' : 'masqué'}',
                  onTap: () => _open(TrainingPage(userId: widget.userId)),
                ),
                NavTile(
                  icon: Icons.list_alt,
                  title: 'Exercices',
                  subtitle: 'Nom, catégorie, assistable',
                  onTap: () => _open(
                      ExercisesPage(ops: ExerciseOps.supabase(widget.userId))),
                ),
                NavTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Rappels',
                  subtitle: s == null
                      ? 'Séance conseillée, inactivité'
                      : s.remindersOn
                          ? '${s.reminderHour.toString().padLeft(2, '0')}:00 · '
                              'après ${s.inactivityDays} jour'
                              '${s.inactivityDays > 1 ? 's' : ''} sans séance'
                          : 'Désactivés',
                  onTap: () => _open(RemindersPage(userId: widget.userId)),
                ),
                NavTile(
                  icon: Icons.lock_outline,
                  title: 'Compte et sécurité',
                  subtitle: s?.googleEmail != null
                      ? 'Google : ${s!.googleEmail} · PIN · profils'
                      : 'Google, PIN, profils',
                  onTap: () => _open(AccountPage(current: widget.profile)),
                ),
                NavTile(
                  icon: Icons.phone_android,
                  title: 'Application',
                  subtitle: 'Mises à jour, espace',
                  trailingText: 'v${kAppVersion.split('+').first}',
                  onTap: () => _open(const AppPage()),
                ),
                // Visible seulement pour un profil admin.
                ValueListenableBuilder<bool>(
                  valueListenable: isAdminNotifier,
                  builder: (_, admin, __) => !admin
                      ? const SizedBox.shrink()
                      : NavTile(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Admin',
                          subtitle: 'Calibration planche, export',
                          onTap: () => _open(AdminPage(userId: widget.userId)),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
