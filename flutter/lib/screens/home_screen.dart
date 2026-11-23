import 'package:flutter/material.dart';
import '../app_flavor.dart';
import '../models/profile.dart';
import '../services/profile_prefs.dart';
import '../services/role.dart';
import '../services/session_store.dart';
import '../services/settings_transfer.dart';
import '../services/supabase_service.dart';
import '../widgets/pin_dialog.dart';
import '../widgets/update_flow.dart';
import 'profile_screen.dart';
import 'saisie_screen.dart';
import 'stats_screen.dart';
import 'calendar_screen.dart';
import 'course_screen.dart';
import 'model_screen.dart';
import 'records_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Profile profile;

  const HomeScreen({super.key, required this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _idx = 0;

  /// La recherche de mise à jour se fait une fois par lancement de l'app, pas
  /// à chaque changement de profil (la version est celle de l'app, pas du profil).
  static bool _updateChecked = false;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // Après le premier affichage : jamais de latence à l'ouverture.
    isAdminNotifier.value = false;
    _modelShown = _modelWanted;
    plancheEnabledNotifier.addListener(_onModelChanged);
    isAdminNotifier.addListener(_onModelChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAccess();
      _loadRole();
      _loadProfilePrefs();
      // Nouvelle version ? Signalée discrètement (rien si à jour ou hors ligne).
      if (mounted && !_updateChecked) {
        _updateChecked = true;
        checkAndOfferUpdate(context, silent: true);
      }
    });
    final uid = widget.profile.id;
    _screens = [
      SaisieScreen(userId: uid),
      StatsScreen(userId: uid),
      CalendarScreen(userId: uid),
      RecordsScreen(userId: uid),
      ModelScreen(userId: uid),
      SettingsScreen(userId: uid, profile: widget.profile),
      if (kCourse) CourseScreen(userId: uid),
    ];
  }

  /// Rôle du profil (admin / user) lu côté serveur : options
  /// d'administration (export, suppression de profils).
  Future<void> _loadRole() async {
    final admin = await SupabaseService.instance.isAdmin(widget.profile.id);
    if (!mounted || admin == isAdminNotifier.value) return;
    isAdminNotifier.value = admin; // _onModelChanged met l'écran à jour
    setState(() {});
  }

  /// Planche activée et couleurs d'intensité du profil (user_settings).
  Future<void> _loadProfilePrefs() async {
    final uid = widget.profile.id;
    Map<String, dynamic> s;
    try {
      s = await SupabaseService.instance.getSettings(uid);
      applyProfilePrefs(s);
    } catch (_) {
      return; // hors ligne : réglages par défaut
    }
    // Réglages envoyés par l'admin (appareil, recalcul des efforts).
    try {
      await applyAdminPush(uid, s);
    } catch (_) {/* réessayé à la prochaine ouverture */}
    // Message de présentation de l'admin, affiché une fois.
    final msg = await pendingPresentation(uid, s);
    if (msg == null || !mounted) return;
    final (id, title, text) = msg;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK')),
        ],
      ),
    );
    await markPresentationSeen(uid, id);
  }

  /// L'onglet Modèle (modèle mathématique de la planche) est réservé à
  /// l'admin, planche activée ; les autres profils règlent seulement leur
  /// poids. Il s'insère avant Réglages : on garde l'onglet affiché.
  static bool get _modelWanted =>
      plancheEnabledNotifier.value && isAdminNotifier.value;
  bool _modelShown = _modelWanted;
  void _onModelChanged() {
    final on = _modelWanted;
    if (!mounted || on == _modelShown) return;
    setState(() {
      if (_idx >= (kCourse ? 5 : 4)) _idx += on ? 1 : -1;
      _modelShown = on;
    });
  }

  @override
  void dispose() {
    plancheEnabledNotifier.removeListener(_onModelChanged);
    isAdminNotifier.removeListener(_onModelChanged);
    super.dispose();
  }

  /// Vérifie, en arrière-plan, que cet appareil est rattaché au profil
  /// mémorisé (cas d'une installation antérieure à la v2.2). Si non, le PIN
  /// est demandé une seule fois. Hors ligne : on ne bloque rien.
  Future<void> _checkAccess() async {
    final svc = SupabaseService.instance;
    final p = widget.profile;
    try {
      if (await svc.isMember(p.id)) return;
      if (!p.hasPin) {
        await svc.claimProfile(p.id);
        return;
      }
    } catch (_) {
      return; // réseau indisponible : on réessaiera à la prochaine ouverture
    }
    if (!mounted) return;
    final ok = await askPinAndClaim(context, p,
        message: 'Mise à jour de sécurité : confirmez votre PIN une '
            'dernière fois sur ce téléphone.');
    if (ok || !mounted) return;
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = _modelShown;
    // Version course : onglet Course après Saisie.
    final screens = [
      _screens[0],
      if (kCourse) _screens[6],
      ..._screens.sublist(1, 4),
      if (model) _screens[4],
      _screens[5],
    ];
    final idx = _idx.clamp(0, screens.length - 1).toInt();
    return Scaffold(
      body: IndexedStack(index: idx, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        // Jusqu'à 6 onglets : libellés toujours visibles, police réduite
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        currentIndex: idx,
        onTap: (i) => setState(() => _idx = i),
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.fitness_center), label: 'Saisie'),
          if (kCourse)
            const BottomNavigationBarItem(
                icon: Icon(Icons.directions_run), label: 'Course'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Stats'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month), label: 'Calendrier'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events), label: 'Records'),
          if (model)
            const BottomNavigationBarItem(
                icon: Icon(Icons.functions), label: 'Modèle'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Réglages'),
        ],
      ),
    );
  }
}
