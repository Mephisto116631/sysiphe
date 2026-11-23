import 'package:flutter/foundation.dart';
import '../models/intensity.dart';
import '../models/perf.dart';
import 'data_events.dart';

/// Réglages du profil actif utiles à plusieurs écrans, lus dans
/// user_settings à l'ouverture et à chaque changement :
/// - planche activée (include_planche, défaut oui) ;
/// - seuils des couleurs d'intensité (intensity_config).
final ValueNotifier<bool> plancheEnabledNotifier = ValueNotifier<bool>(true);

final intensityNotifier =
    ValueNotifier<IntensityConfig>(const IntensityConfig());

/// Applique les réglages lus dans user_settings.
/// Planche activée ou non : les écrans se rechargent (options, stats,
/// records, onglet Modèle).
void applyProfilePrefs(Map<String, dynamic> settings) {
  final on = settings['include_planche'] as bool? ?? true;
  Perf.plancheEnabled = on;
  if (plancheEnabledNotifier.value != on) {
    plancheEnabledNotifier.value = on;
    notifyDataChanged();
  }
  intensityNotifier.value =
      IntensityConfig.fromSettings(settings['intensity_config']);
}
