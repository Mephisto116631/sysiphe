import 'package:shared_preferences/shared_preferences.dart';
import '../models/effort_model.dart';
import '../models/perf.dart';
import '../models/settings_bundle.dart';
import 'data_events.dart';
import 'profile_prefs.dart';
import 'supabase_service.dart';
import 'ui_prefs.dart';

/// Réglages de l'appareil connus (repos, chrono, rappels, minuteur, course).
Future<Map<String, Object>> readDevicePrefs() async {
  try {
    final p = await SharedPreferences.getInstance();
    return {
      for (final k in p.getKeys())
        if (deviceKeyType(k) != null && p.get(k) != null) k: p.get(k)!,
    };
  } catch (_) {
    return {};
  }
}

/// Écrit les réglages de l'appareil (clés connues seulement).
Future<void> applyDevicePrefs(Map<String, Object> device) async {
  final p = await SharedPreferences.getInstance();
  for (final e in device.entries) {
    final v = e.value;
    switch (deviceKeyType(e.key)) {
      case const (int):
        if (v is num) await p.setInt(e.key, v.toInt());
      case const (bool):
        if (v is bool) await p.setBool(e.key, v);
      case const (String):
        if (v is String) await p.setString(e.key, v);
      default:
        break;
    }
  }
}

/// Recalcule l'effort de toutes les séries de planche du profil avec ses
/// réglages actuels (poids, coefficients). Rien si la planche est désactivée.
Future<int> recalcPlancheEfforts(String userId) async {
  if (!Perf.plancheEnabled) return 0;
  final svc = SupabaseService.instance;
  final m = EffortModel.fromSettings(await svc.getSettings(userId));
  return svc.recalculateEfforts(userId,
      weight: m.weight,
      variantes: m.variantes,
      formes: m.formes,
      elastiques: m.elastiques,
      tensions: m.tensions);
}

/// Fichier de paramètres du profil : réglages du profil et de l'appareil.
Future<SettingsBundle> exportBundle(String userId, {String? profileName}) async =>
    SettingsBundle.from(
      settings: await SupabaseService.instance.getSettings(userId),
      device: await readDevicePrefs(),
      profileName: profileName,
      now: DateTime.now(),
    );

/// Applique un fichier de paramètres au profil actif (et à l'appareil).
Future<void> importBundle(String userId, SettingsBundle b) async {
  final svc = SupabaseService.instance;
  if (b.profile.isNotEmpty) {
    await svc.saveSettings(userId, b.profile);
    applyProfilePrefs(await svc.getSettings(userId));
    if (b.profile.keys.any(kEffortKeys.contains)) {
      await recalcPlancheEfforts(userId);
    }
  }
  if (b.device.isNotEmpty) await applyDevicePrefs(b.device);
  notifyDataChanged();
}

// ── Envoi par l'admin (appliqué à l'ouverture par le profil) ─────────────

String _pushKey(String userId) => 'admin_push_applied_$userId';
String _presentationKey(String userId) => 'presentation_seen_$userId';

/// Réglages envoyés par l'admin, pas encore appliqués sur ce téléphone :
/// réglages de l'appareil, puis recalcul des efforts. true si appliqués.
Future<bool> applyAdminPush(String userId, Map<String, dynamic> settings) async {
  final push = settings['admin_push'];
  if (push is! Map || push['id'] == null) return false;
  final id = '${push['id']}';
  if (await UiPrefs.getString(_pushKey(userId)) == id) return false;
  final device = push['device'];
  if (device is Map) {
    // Clés connues et de bon type seulement.
    await applyDevicePrefs(SettingsBundle.from(
        settings: const {},
        device: {for (final e in device.entries) '${e.key}': e.value}).device);
  }
  if (push['recalc'] == true) {
    try {
      await recalcPlancheEfforts(userId);
    } catch (_) {
      return false; // hors ligne : on réessaiera à la prochaine ouverture
    }
  }
  await UiPrefs.setString(_pushKey(userId), id);
  notifyDataChanged();
  return true;
}

/// Message de présentation envoyé par l'admin, pas encore lu sur ce
/// téléphone : (id, titre, texte), sinon null.
Future<(String, String, String)?> pendingPresentation(
    String userId, Map<String, dynamic> settings) async {
  final p = settings['presentation'];
  if (p is! Map || p['id'] == null) return null;
  final text = '${p['texte'] ?? ''}'.trim();
  if (text.isEmpty) return null;
  final id = '${p['id']}';
  if (await UiPrefs.getString(_presentationKey(userId)) == id) return null;
  final title = '${p['titre'] ?? ''}'.trim();
  return (id, title.isEmpty ? 'Message' : title, text);
}

Future<void> markPresentationSeen(String userId, String id) =>
    UiPrefs.setString(_presentationKey(userId), id);

// ── Modèle commun de la planche ─────────────────────────────────────────

String _modelKey(String userId) => 'effort_model_applied_$userId';

/// Le modèle commun a changé (ou n'a jamais été appliqué à ce profil sur ce
/// téléphone) : recalcule les efforts de planche du profil. true si fait.
Future<bool> applySharedModelIfChanged(String userId) async {
  if (!Perf.plancheEnabled) return false;
  final m = await SupabaseService.instance.getSharedModel();
  if (m == null || m.version.isEmpty) return false;
  if (await UiPrefs.getString(_modelKey(userId)) == m.version) return false;
  try {
    await recalcPlancheEfforts(userId);
  } catch (_) {
    return false; // hors ligne : à la prochaine ouverture
  }
  await UiPrefs.setString(_modelKey(userId), m.version);
  notifyDataChanged();
  return true;
}
