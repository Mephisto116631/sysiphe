import 'package:shared_preferences/shared_preferences.dart';

/// Préférences d'interface de l'appareil (filtres, réglages de repos…).
/// Jamais bloquant : en cas d'erreur, on retombe sur la valeur par défaut.
class UiPrefs {
  static Future<SharedPreferences?> _p() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getString(String k) async => (await _p())?.getString(k);
  static Future<void> setString(String k, String v) async =>
      (await _p())?.setString(k, v);
  static Future<int?> getInt(String k) async => (await _p())?.getInt(k);
  static Future<void> setInt(String k, int v) async => (await _p())?.setInt(k, v);
  static Future<bool?> getBool(String k) async => (await _p())?.getBool(k);
  static Future<void> setBool(String k, bool v) async =>
      (await _p())?.setBool(k, v);
}
