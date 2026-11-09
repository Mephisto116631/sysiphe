import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/profile_screen.dart';
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

  runApp(const SysipheApp());
}

class SysipheApp extends StatelessWidget {
  const SysipheApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sysiphe',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const ProfileScreen(),
    );
  }
}
