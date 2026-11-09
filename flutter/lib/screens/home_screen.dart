import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/session_store.dart';
import '../services/supabase_service.dart';
import '../widgets/pin_dialog.dart';
import 'profile_screen.dart';
import 'saisie_screen.dart';
import 'stats_screen.dart';
import 'calendar_screen.dart';
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

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    // Après le premier affichage : jamais de latence à l'ouverture.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAccess());
    final uid = widget.profile.id;
    _screens = [
      SaisieScreen(userId: uid),
      StatsScreen(userId: uid),
      CalendarScreen(userId: uid),
      RecordsScreen(userId: uid),
      SettingsScreen(userId: uid, profile: widget.profile),
    ];
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
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        onTap: (i) => setState(() => _idx = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.fitness_center), label: 'Saisie'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Stats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month), label: 'Calendrier'),
          BottomNavigationBarItem(
              icon: Icon(Icons.emoji_events), label: 'Records'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Paramètres'),
        ],
      ),
    );
  }
}
