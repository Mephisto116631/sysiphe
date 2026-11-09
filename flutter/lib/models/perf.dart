import 'dart:math' as math;
import 'package:intl/intl.dart';

class Perf {
  final int? id; // perfs.id est un bigint (identity), croissant à l'insertion
  final String userId;
  final DateTime date;
  final String exercice;
  final String variante;
  final String forme;
  final int serie;
  // Schéma partagé avec l'app Streamlit (supabase_io.py / ui_saisie.py) :
  //   performance = valeur de la série (secondes, reps ou kg selon `unite`)
  //   charge      = lest externe en kg (tractions lestées…), 0 sinon
  final double performance;
  final double charge;
  final String unite; // "Sec" | "Reps" | "Kg"
  final String categorie; // "Force Iso" | "Musculation"
  final String elastique;
  final String tension;
  final int? effortPondere;

  const Perf({
    this.id,
    required this.userId,
    required this.date,
    required this.exercice,
    this.variante = 'Full',
    this.forme = 'Normal',
    this.serie = 1,
    this.performance = 0.0,
    this.charge = 0.0,
    this.unite = 'Sec',
    this.categorie = 'Musculation',
    this.elastique = 'Aucun',
    this.tension = 'N/A',
    this.effortPondere,
  });

  factory Perf.fromJson(Map<String, dynamic> json) => Perf(
        id: (json['id'] as num?)?.toInt(),
        userId: json['user_id'] as String,
        date: DateTime.parse(json['date'] as String),
        exercice: (json['exercice'] as String?)?.trim() ?? '',
        variante: (json['variante'] as String?)?.trim() ?? 'Tuck', // comme load_data()
        forme: (json['forme'] as String?)?.trim() ?? 'Normal',
        serie: (json['serie'] as num?)?.toInt() ?? 1,
        performance: (json['performance'] as num?)?.toDouble() ?? 0.0,
        charge: (json['charge'] as num?)?.toDouble() ?? 0.0,
        unite: (json['unite'] as String?)?.trim() ?? 'Sec',
        categorie: (json['categorie'] as String?)?.trim() ?? 'Musculation',
        elastique: (json['elastique'] as String?)?.trim() ?? 'Aucun',
        tension: (json['tension'] as String?)?.trim() ?? 'N/A',
        effortPondere: (json['effort_pondere'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'date': DateFormat('yyyy-MM-dd').format(date),
        'exercice': exercice,
        'variante': variante,
        'forme': forme,
        'serie': serie,
        'performance': performance,
        'charge': charge,
        'unite': unite,
        'categorie': categorie,
        'elastique': elastique,
        'tension': tension,
        'effort_pondere': effortPondere ?? 0,
      };

  String get displayValue {
    if (unite == 'Sec') return '${performance.toStringAsFixed(0)}s';
    final v = performance % 1 == 0
        ? '${performance.toInt()} $unite'
        : '${performance.toStringAsFixed(1)} $unite';
    return charge > 0 ? '$v · +${_fmt(charge)} kg' : v;
  }

  static String _fmt(double x) =>
      x % 1 == 0 ? x.toInt().toString() : x.toStringAsFixed(1);

  /// Même règle que l'app Streamlit : la planche est identifiée par son nom.
  bool get isPlanche => isPlancheName(exercice);

  static bool isPlancheName(String exercice) =>
      exercice.trim().toLowerCase() == 'planche';
}

// ─── Calcul d'effort planche (port fidèle de data.py) ────────────────────────

const kVariantes = {
  'Full': 10.0,
  'Straddle': 9.0,
  'Half_Lay': 9.0,
  'Diamond': 5.0,
  'Maltese': 11.0,
  'Tuck': 2.0,
  'Adv_Tuck': 3.0,
};
const kFormes = {
  'Normal': 47.6,
  'High': 34.0,
  'Bas': 66.64,
  'Dead': 93.296,
};
const kElastiques = {
  'Aucun': 0.0,
  'Rouge/Violet': 35.0,
  'Jaune+Bleu': 40.0,
  'Jaune': 25.0,
  'Bleu': 15.0,
  'Vert': 45.0,
};
const kTensions = {
  'N/A': 0.70,
  'Ecarté': 0.85,
  'Normal': 0.70,
  'Serré': 0.60,
};

/// Fusionne une config JSONB stockée (user_settings) avec les valeurs par
/// défaut, comme load_user_settings() côté Python : les clés absentes ou non
/// numériques gardent leur valeur par défaut.
Map<String, double> mergeConfig(dynamic raw, Map<String, double> defaults) {
  final merged = Map<String, double>.of(defaults);
  if (raw is Map) {
    raw.forEach((k, v) {
      if (v is num) merged[k.toString()] = v.toDouble();
    });
  }
  return merged;
}

int calculerEffort({
  required String variante,
  required String elastique,
  required String tension,
  required String forme,
  required double temps,
  required double weight,
  Map<String, double>? variantes,
  Map<String, double>? formes,
  Map<String, double>? elastiquesMap,
  Map<String, double>? tensions,
}) {
  final v = variantes ?? kVariantes;
  final f = formes ?? kFormes;
  final e = elastiquesMap ?? kElastiques;
  final t = tensions ?? kTensions;

  try {
    final forceE = e[elastique] ?? 0.0;
    final ratioT = t[tension] ?? 0.70;
    final scoreV = v[variante] ?? 0.0;
    final scoreF = f[forme] ?? 0.0;

    if (scoreV == 0 || scoreF == 0 || temps <= 0) return 0;

    final poidsEff = weight - forceE * ratioT;
    final facteurE = math.pow(poidsEff / 100, 2).toDouble();
    final facteurM = math.pow(scoreV * scoreF, 1.2).toDouble();

    return ((temps * facteurE * facteurM) / 100).round();
  } catch (_) {
    return 0;
  }
}

// ─── Records ────────────────────────────────────────────────────────────────

/// Planche : le record est l'effort pondéré le plus élevé (comme l'onglet
/// Records du web), puis le temps. Autres exercices : la valeur la plus
/// haute, puis le lest le plus lourd.
bool isBetterRecord(Perf a, Perf b) {
  if (a.isPlanche) {
    final ea = a.effortPondere ?? 0, eb = b.effortPondere ?? 0;
    if (ea != eb) return ea > eb;
    return a.performance > b.performance;
  }
  if (a.performance != b.performance) return a.performance > b.performance;
  return a.charge > b.charge;
}
