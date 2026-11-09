import 'dart:math' as math;
import 'package:intl/intl.dart';

class Perf {
  final String? id;
  final String userId;
  final DateTime date;
  final String exercice;
  final String variante;
  final String forme;
  final int serie;
  final double charge; // Secondes pour planche, kg/reps sinon
  final String unite;  // "Sec" | "Reps" | "Kg" …
  final String elastique;
  final String tension;
  final int? effortPondere;
  final DateTime? createdAt;

  const Perf({
    this.id,
    required this.userId,
    required this.date,
    required this.exercice,
    this.variante = 'Full',
    this.forme = 'Normal',
    this.serie = 1,
    this.charge = 0.0,
    this.unite = 'Sec',
    this.elastique = 'Aucun',
    this.tension = 'N/A',
    this.effortPondere,
    this.createdAt,
  });

  factory Perf.fromJson(Map<String, dynamic> json) => Perf(
        id: json['id'] as String?,
        userId: json['user_id'] as String,
        date: DateTime.parse(json['date'] as String),
        exercice: (json['exercice'] as String?)?.trim() ?? '',
        variante: (json['variante'] as String?)?.trim() ?? 'Full',
        forme: (json['forme'] as String?)?.trim() ?? 'Normal',
        serie: (json['serie'] as num?)?.toInt() ?? 1,
        charge: (json['charge'] as num?)?.toDouble() ?? 0.0,
        unite: (json['unite'] as String?)?.trim() ?? 'Sec',
        elastique: (json['elastique'] as String?)?.trim() ?? 'Aucun',
        tension: (json['tension'] as String?)?.trim() ?? 'N/A',
        effortPondere: (json['effort_pondere'] as num?)?.toInt(),
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'date': DateFormat('yyyy-MM-dd').format(date),
        'exercice': exercice,
        'variante': variante,
        'forme': forme,
        'serie': serie,
        'charge': charge,
        'unite': unite,
        'elastique': elastique,
        'tension': tension,
        if (effortPondere != null) 'effort_pondere': effortPondere,
      };

  String get displayValue {
    if (unite == 'Sec') return '${charge.toStringAsFixed(0)}s';
    return charge % 1 == 0
        ? '${charge.toInt()} $unite'
        : '${charge.toStringAsFixed(1)} $unite';
  }

  bool get isPlanche => unite == 'Sec';
}

// ─── Calcul d'effort planche (port fidèle de data.py) ────────────────────────

const kVariantes = {
  'Full': 10.0, 'Straddle': 9.0, 'Half_Lay': 9.0,
  'Diamond': 5.0, 'Maltese': 11.0, 'Tuck': 2.0, 'Adv_Tuck': 3.0,
};
const kFormes = {
  'Normal': 47.6, 'High': 34.0, 'Bas': 66.64, 'Dead': 93.296,
};
const kElastiques = {
  'Aucun': 0.0, 'Rouge/Violet': 35.0, 'Jaune+Bleu': 40.0,
  'Jaune': 25.0, 'Bleu': 15.0, 'Vert': 45.0,
};
const kTensions = {
  'N/A': 0.70, 'Ecarté': 0.85, 'Normal': 0.70, 'Serré': 0.60,
};

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
