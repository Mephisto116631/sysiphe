import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

/// Profil mémorisé sur le téléphone, comme le cookie d'un an du web :
/// le PIN n'est demandé qu'à la première connexion ou après
/// « Changer de profil ».
class SessionStore {
  static const _kId = 'session.profile_id';
  static const _kName = 'session.profile_name';
  static const _kPin = 'session.profile_has_pin';

  static Future<Profile?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kId);
      if (id == null) return null;
      return Profile(
        id: id,
        name: prefs.getString(_kName) ?? 'Profil',
        hasPin: prefs.getBool(_kPin) ?? false,
      );
    } catch (_) {
      return null; // stockage illisible : on repasse par l'écran de profils
    }
  }

  static Future<void> save(Profile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kId, p.id);
    await prefs.setString(_kName, p.name);
    await prefs.setBool(_kPin, p.hasPin);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kId);
    await prefs.remove(_kName);
    await prefs.remove(_kPin);
  }
}
