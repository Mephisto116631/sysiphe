import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'models/profile.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/session_store.dart';
import 'theme.dart';

// Injectés à la compilation via --dart-define (GitHub Actions secrets)
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait uniquement (app mobile fitness)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await initializeDateFormatting('fr_FR', null);

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // Profil mémorisé : on entre directement, sans liste ni PIN
  // (lu localement, fonctionne même sans réseau).
  final saved = await SessionStore.load();

  runApp(SysipheApp(savedProfile: saved));
}

class SysipheApp extends StatelessWidget {
  final Profile? savedProfile;

  const SysipheApp({super.key, this.savedProfile});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sysiphe',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: savedProfile != null
          ? HomeScreen(profile: savedProfile!)
          : const ProfileScreen(),
    );
  }
}
