import 'perf.dart';

/// Réglages d'effort de l'utilisateur (poids + calibrations planche et
/// assistables), lus dans user_settings. Une table absente (null) = valeurs
/// par défaut. Regroupe les calculs d'effort de la Saisie.
class EffortSettings {
  final double weight;
  final Map<String, double>? variantes,
      formes,
      elastiques,
      tensions,
      ecartements;

  const EffortSettings({
    this.weight = 97.0,
    this.variantes,
    this.formes,
    this.elastiques,
    this.tensions,
    this.ecartements,
  });

  factory EffortSettings.fromSettings(Map<String, dynamic> s) => EffortSettings(
        weight: (s['weight'] as num?)?.toDouble() ?? 97.0,
        variantes: mergeConfig(s['variantes_config'], kVariantes),
        formes: mergeConfig(s['formes_config'], kFormes),
        elastiques: mergeConfig(s['elastiques_config'], kElastiques),
        tensions: mergeConfig(s['tensions_config'], kTensions),
        ecartements: mergeConfig(s['ecartements_config'], kEcartements),
      );

  /// Effort pondéré d'une série de planche.
  int planche({
    required String variante,
    required String forme,
    required String elastique,
    required String tension,
    required double temps,
  }) =>
      calculerEffort(
        variante: variante,
        elastique: elastique,
        tension: tension,
        forme: forme,
        temps: temps,
        weight: weight,
        variantes: variantes,
        formes: formes,
        elastiquesMap: elastiques,
        tensions: tensions,
      );

  /// Effort arrondi d'une série d'exercice assistable.
  int assiste({
    required double reps,
    required double lest,
    required String elastique,
    required String tension,
    required String ecartement,
  }) =>
      calculerEffortAssiste(
        reps: reps,
        lest: lest,
        elastique: elastique,
        tension: tension,
        ecartement: ecartement,
        weight: weight,
        elastiquesMap: elastiques,
        tensions: tensions,
        ecartements: ecartements,
      );

  /// Effort non arrondi d'une série assistable déjà enregistrée (recalculé
  /// depuis ses paramètres : l'historique reste cohérent).
  double assisteExact(Perf p) => effortAssisteExact(
        reps: p.performance,
        lest: p.charge,
        elastique: p.elastique,
        tension: p.tension,
        ecartement: p.ecartement,
        weight: weight,
        elastiquesMap: elastiques,
        tensions: tensions,
        ecartements: ecartements,
      );
}
