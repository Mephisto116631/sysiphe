import 'dart:convert';

/// Fichier de paramètres Sysiphe (texte JSON) : réglages du profil (serveur)
/// et réglages de l'appareil. Sert à l'export / import par chacun et à
/// l'envoi de réglages par l'admin.
const kBundleFormat = 'sysiphe-parametres';
const kBundleVersion = 1;

/// Réglages du profil (table user_settings) qu'on exporte / importe.
const kProfileKeys = <String, Type>{
  'weight': num,
  'enable_charges': bool,
  'include_planche': bool,
  'inactivity_days': int,
  'nb_days_avg': int,
  'intensity_config': Map,
  'ecartements_config': Map,
  'assistable_exercises': List,
};
// Les coefficients du modèle de la planche (variantes, formes, élastiques,
// tensions) sont communs à tous les profils : réglés par l'admin dans
// Réglages → Modèle de la planche, jamais par un fichier.

/// Clés qui changent l'effort de la planche (recalcul après import).
const kEffortKeys = {'weight', 'include_planche'};

/// Réglages de l'appareil (préférences locales) : clés exactes…
const kDeviceKeys = <String, Type>{
  'rest_seconds': int,
  'reminders_on': bool,
  'reminders_hour': int,
  'chrono_sound_mode': int,
  'chrono_pre_seconds': int,
  'chrono_fullscreen': bool,
  'chrono_target_seconds': int,
  'chrono_sets': int,
  'minuteur_config': String,
  'course_goal_type': String,
  'course_goal_distance': int,
  'course_goal_duree': int,
  'course_auto_pause': bool,
};

/// … et clés par exercice (« chrono_sets:planche »).
const kDevicePrefixes = <String, Type>{
  'chrono_sets:': int,
  'chrono_target_seconds:': int,
};

Type? deviceKeyType(String k) {
  final t = kDeviceKeys[k];
  if (t != null) return t;
  for (final e in kDevicePrefixes.entries) {
    if (k.startsWith(e.key) && k.length > e.key.length) return e.value;
  }
  return null;
}

bool _typeOk(Object? v, Type t) => switch (t) {
      const (num) => v is num,
      const (int) => v is int || (v is num && v == v.roundToDouble()),
      const (bool) => v is bool,
      const (String) => v is String,
      const (Map) => v is Map,
      const (List) => v is List,
      _ => false,
    };

class SettingsBundle {
  final Map<String, dynamic> profile;
  final Map<String, Object> device;
  final String? profileName;
  final DateTime? exportedAt;

  /// Clés inconnues ou de mauvais type, ignorées à la lecture.
  final List<String> ignored;

  const SettingsBundle({
    this.profile = const {},
    this.device = const {},
    this.profileName,
    this.exportedAt,
    this.ignored = const [],
  });

  bool get isEmpty => profile.isEmpty && device.isEmpty;

  /// Garde seulement les réglages connus (user_settings et appareil).
  factory SettingsBundle.from({
    required Map<String, dynamic> settings,
    required Map<String, Object?> device,
    String? profileName,
    DateTime? now,
  }) =>
      SettingsBundle(
        profile: {
          for (final k in kProfileKeys.keys)
            if (settings[k] != null && _typeOk(settings[k], kProfileKeys[k]!))
              k: settings[k],
        },
        device: {
          for (final e in device.entries)
            if (e.value != null &&
                deviceKeyType(e.key) != null &&
                _typeOk(e.value, deviceKeyType(e.key)!))
              e.key: e.value!,
        },
        profileName: profileName,
        exportedAt: now,
      );

  Map<String, dynamic> toJson() => {
        'format': kBundleFormat,
        'version': kBundleVersion,
        if (profileName != null) 'profil': profileName,
        if (exportedAt != null) 'exporte_le': exportedAt!.toIso8601String(),
        'profil_reglages': Map.fromEntries(
            profile.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
        'appareil': Map.fromEntries(
            device.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      };

  /// Texte JSON lisible (indenté).
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Lit un fichier de paramètres. [FormatException] avec un message en
  /// français si le texte n'en est pas un.
  static SettingsBundle parse(String text) {
    Object? j;
    try {
      j = jsonDecode(text.trim());
    } catch (_) {
      throw const FormatException('Ce texte n\'est pas du JSON valide.');
    }
    if (j is! Map || j['format'] != kBundleFormat) {
      throw const FormatException(
          'Ce n\'est pas un fichier de paramètres Sysiphe.');
    }
    final v = (j['version'] as num?)?.toInt() ?? 0;
    if (v > kBundleVersion) {
      throw const FormatException(
          'Fichier d\'une version plus récente de l\'app : mets-la à jour.');
    }
    final ignored = <String>[];
    final profile = <String, dynamic>{};
    final p = j['profil_reglages'];
    if (p is Map) {
      p.forEach((k, val) {
        final t = kProfileKeys['$k'];
        if (t != null && val != null && _typeOk(val, t)) {
          profile['$k'] = t == int ? (val as num).toInt() : val;
        } else {
          ignored.add('$k');
        }
      });
    }
    final device = <String, Object>{};
    final d = j['appareil'];
    if (d is Map) {
      d.forEach((k, val) {
        final t = deviceKeyType('$k');
        if (t != null && val != null && _typeOk(val, t)) {
          device['$k'] = t == int ? (val as num).toInt() : val as Object;
        } else {
          ignored.add('$k');
        }
      });
    }
    final w = profile['weight'];
    if (w is num && (w <= 0 || w > 400)) {
      profile.remove('weight');
      ignored.add('weight');
    }
    return SettingsBundle(
      profile: profile,
      device: device,
      profileName: j['profil'] as String?,
      exportedAt: DateTime.tryParse('${j['exporte_le']}'),
      ignored: ignored,
    );
  }

  /// Résumé lisible de ce qui sera appliqué (confirmation d'import).
  List<String> describe() => [
        if (profile['weight'] != null) 'Poids : ${profile['weight']} kg',
        if (profile['include_planche'] != null)
          'Planche : ${profile['include_planche'] == true ? 'activée' : 'désactivée'}',
        if (profile['enable_charges'] != null)
          'Champ lest : ${profile['enable_charges'] == true ? 'affiché' : 'masqué'}',
        if (profile['intensity_config'] != null) 'Couleurs d\'intensité',
        if (profile['assistable_exercises'] != null) 'Exercices assistables',
        if (profile['inactivity_days'] != null)
          'Rappel après ${profile['inactivity_days']} jours sans séance',
        if (device['rest_seconds'] != null) 'Repos : ${device['rest_seconds']} s',
        if (device.keys.any((k) => k.startsWith('chrono')))
          'Chrono (son, départ, objectifs…)',
        if (device['reminders_on'] != null || device['reminders_hour'] != null)
          'Rappels de séance',
        if (device['minuteur_config'] != null) 'Minuteur',
        if (device.keys.any((k) => k.startsWith('course_')))
          'Course (objectif, pause automatique)',
      ];
}
