import 'dart:math' as math;
import 'perf.dart';

/// Le modèle d'effort planche complet (poids + 4 tables de coefficients),
/// manipulé en brouillon dans l'onglet « Modèle » avant d'être appliqué.
class EffortModel {
  final double weight;
  final Map<String, double> variantes, formes, elastiques, tensions;

  const EffortModel({
    required this.weight,
    required this.variantes,
    required this.formes,
    required this.elastiques,
    required this.tensions,
  });

  factory EffortModel.defaults({double weight = 97}) => EffortModel(
        weight: weight,
        variantes: Map.of(kVariantes),
        formes: Map.of(kFormes),
        elastiques: Map.of(kElastiques),
        tensions: Map.of(kTensions),
      );

  /// Depuis une ligne user_settings (clés absentes → valeurs par défaut).
  factory EffortModel.fromSettings(Map<String, dynamic> s) => EffortModel(
        weight: (s['weight'] as num?)?.toDouble() ?? 97,
        variantes: mergeConfig(s['variantes_config'], kVariantes),
        formes: mergeConfig(s['formes_config'], kFormes),
        elastiques: mergeConfig(s['elastiques_config'], kElastiques),
        tensions: mergeConfig(s['tensions_config'], kTensions),
      );

  /// Colonnes de user_settings, prêtes pour l'upsert.
  Map<String, dynamic> toSettings() => {
        'weight': weight,
        'variantes_config': variantes,
        'formes_config': formes,
        'elastiques_config': elastiques,
        'tensions_config': tensions,
      };

  EffortModel copyWith({
    double? weight,
    Map<String, double>? variantes,
    Map<String, double>? formes,
    Map<String, double>? elastiques,
    Map<String, double>? tensions,
  }) =>
      EffortModel(
        weight: weight ?? this.weight,
        variantes: variantes ?? this.variantes,
        formes: formes ?? this.formes,
        elastiques: elastiques ?? this.elastiques,
        tensions: tensions ?? this.tensions,
      );

  /// Effort pondéré — même formule que calculerEffort / data.py.
  int effort(String variante, String forme, String elastique, String tension,
          double temps) =>
      calculerEffort(
        variante: variante,
        forme: forme,
        elastique: elastique,
        tension: tension,
        temps: temps,
        weight: weight,
        variantes: variantes,
        formes: formes,
        elastiquesMap: elastiques,
        tensions: tensions,
      );

  /// Étapes du calcul, pour l'afficher comme dans un tableur.
  EffortBreakdown breakdown(String variante, String forme, String elastique,
      String tension, double temps) {
    final forceE = elastiques[elastique] ?? 0;
    final ratioT = tensions[tension] ?? 0.70;
    final scoreV = variantes[variante] ?? 0;
    final scoreF = formes[forme] ?? 0;
    final poidsEff = weight - forceE * ratioT;
    return EffortBreakdown(
      forceElastique: forceE,
      ratioTension: ratioT,
      poidsEffectif: poidsEff,
      facteurPoids: math.pow(poidsEff / 100, 2).toDouble(),
      scoreVariante: scoreV,
      scoreForme: scoreF,
      facteurDifficulte: math.pow(scoreV * scoreF, 1.2).toDouble(),
      effort: effort(variante, forme, elastique, tension, temps),
    );
  }
}

class EffortBreakdown {
  final double forceElastique, ratioTension, poidsEffectif, facteurPoids;
  final double scoreVariante, scoreForme, facteurDifficulte;
  final int effort;
  const EffortBreakdown({
    required this.forceElastique,
    required this.ratioTension,
    required this.poidsEffectif,
    required this.facteurPoids,
    required this.scoreVariante,
    required this.scoreForme,
    required this.facteurDifficulte,
    required this.effort,
  });
}

/// Impact d'un modèle sur l'historique, par variante : meilleur effort
/// actuel (enregistré en base) et avec le modèle en cours d'édition.
class VarianteImpact {
  final String variante;
  final int bestBefore, bestAfter, series;
  const VarianteImpact(this.variante, this.bestBefore, this.bestAfter, this.series);
  int get delta => bestAfter - bestBefore;
}

class HistoryImpact {
  final List<VarianteImpact> parVariante; // trié par meilleur effort (après)
  final int series; // séries de planche
  final int changed; // séries dont l'effort changerait
  const HistoryImpact(this.parVariante, this.series, this.changed);
}

HistoryImpact impactOn(Iterable<Perf> history, EffortModel model) {
  final best = <String, (int, int, int)>{}; // variante → (avant, après, n)
  var series = 0, changed = 0;
  for (final p in history) {
    if (!p.isPlanche) continue;
    series++;
    final before = p.effortPondere ?? 0;
    final after =
        model.effort(p.variante, p.forme, p.elastique, p.tension, p.performance);
    if (after != before) changed++;
    final cur = best[p.variante] ?? (0, 0, 0);
    best[p.variante] = (
      before > cur.$1 ? before : cur.$1,
      after > cur.$2 ? after : cur.$2,
      cur.$3 + 1,
    );
  }
  final list = [
    for (final e in best.entries) VarianteImpact(e.key, e.value.$1, e.value.$2, e.value.$3),
  ]..sort((a, b) => b.bestAfter.compareTo(a.bestAfter));
  return HistoryImpact(list, series, changed);
}
