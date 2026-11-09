import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/models/profile.dart';

void main() {
  group('Perf.fromJson — lignes réelles de la table perfs', () {
    // Forme exacte renvoyée par Supabase (id bigint, pas de created_at).
    test('série de planche', () {
      final p = Perf.fromJson({
        'id': 4889,
        'user_id': '7c1a2ca2-9b9d-43d9-af21-3f84578fe53e',
        'date': '2026-08-01',
        'exercice': 'Planche',
        'serie': 2,
        'performance': 14,
        'variante': 'Diamond',
        'elastique': 'Aucun',
        'tension': 'N/A',
        'forme': 'Normal',
        'effort_pondere': 94,
        'categorie': 'Force Iso',
        'unite': 'Sec',
        'charge': 0,
      });
      expect(p.id, 4889);
      expect(p.performance, 14.0);
      expect(p.charge, 0.0);
      expect(p.effortPondere, 94);
      expect(p.isPlanche, isTrue);
      expect(p.displayValue, '14s');
    });

    test('série en reps avec champs planche à null', () {
      final p = Perf.fromJson({
        'id': 4886,
        'user_id': '9250e548-1d5a-48d1-98c0-5c97089a77d8',
        'date': '2026-08-01',
        'exercice': 'Abdos ( dragon press bicyclette ou hold)',
        'serie': 2,
        'performance': 40,
        'variante': null,
        'elastique': null,
        'tension': null,
        'forme': null,
        'effort_pondere': 0,
        'categorie': 'Musculation',
        'unite': 'Reps',
        'charge': 0,
      });
      expect(p.id, 4886);
      expect(p.performance, 40.0);
      expect(p.isPlanche, isFalse);
      expect(p.displayValue, '40 Reps');
    });

    test('série lestée : le lest est affiché', () {
      final p = Perf.fromJson({
        'id': 1,
        'user_id': 'u',
        'date': '2026-08-01',
        'exercice': 'Traction',
        'performance': 8,
        'unite': 'Reps',
        'charge': 12.5,
      });
      expect(p.displayValue, '8 Reps · +12.5 kg');
    });

    test('toJson écrit performance et non created_at', () {
      final json = Perf(
        userId: 'u',
        date: DateTime(2026, 11, 9),
        exercice: 'Planche',
        performance: 10,
        unite: 'Sec',
        categorie: 'Force Iso',
      ).toJson();
      expect(json['performance'], 10.0);
      expect(json['charge'], 0.0);
      expect(json['date'], '2026-11-09');
      expect(json.containsKey('created_at'), isFalse);
      expect(json.containsKey('id'), isFalse);
    });
  });

  group('calculerEffort — parité avec data.py', () {
    // Valeurs de référence calculées avec data.calculer_effort (Python).
    final cases = <(String, String, String, String, double, double, int)>[
      ('Diamond', 'Aucun', 'N/A', 'Normal', 14, 70, 49),
      ('Full', 'Jaune', 'Serré', 'High', 8, 97, 59),
      ('Straddle', 'Rouge/Violet', 'Ecarté', 'Bas', 12.5, 85, 82),
      ('Adv_Tuck', 'Vert', 'Normal', 'Dead', 20, 97, 74),
      ('Tuck', 'Aucun', 'N/A', 'Normal', 0, 97, 0),
      ('Inconnue', 'Aucun', 'N/A', 'Normal', 10, 97, 0),
    ];
    for (final (v, e, t, f, temps, w, attendu) in cases) {
      test('$v / $e / $t / $f, ${temps}s, ${w}kg → $attendu', () {
        expect(
          calculerEffort(
              variante: v,
              elastique: e,
              tension: t,
              forme: f,
              temps: temps,
              weight: w),
          attendu,
        );
      });
    }

    test('la calibration utilisateur est prise en compte', () {
      final base = calculerEffort(
          variante: 'Full', elastique: 'Aucun', tension: 'N/A',
          forme: 'Normal', temps: 10, weight: 80);
      final calibre = calculerEffort(
          variante: 'Full', elastique: 'Aucun', tension: 'N/A',
          forme: 'Normal', temps: 10, weight: 80,
          variantes: {...kVariantes, 'Full': 12});
      expect(calibre, greaterThan(base));
    });
  });

  group('isBetterRecord', () {
    Perf p(String ex, double perf, {int? effort, double charge = 0}) => Perf(
        userId: 'u', date: DateTime(2026), exercice: ex,
        performance: perf, effortPondere: effort, charge: charge);

    test('planche : l\'effort prime sur le temps', () {
      expect(isBetterRecord(p('Planche', 8, effort: 120),
          p('Planche', 15, effort: 90)), isTrue);
    });
    test('planche : à effort égal, le temps départage', () {
      expect(isBetterRecord(p('Planche', 12, effort: 90),
          p('Planche', 10, effort: 90)), isTrue);
    });
    test('reps : la valeur prime, puis le lest', () {
      expect(isBetterRecord(p('Traction', 10), p('Traction', 8, charge: 20)),
          isTrue);
      expect(isBetterRecord(p('Traction', 8, charge: 20), p('Traction', 8)),
          isTrue);
      expect(isBetterRecord(p('Traction', 8), p('Traction', 8)), isFalse);
    });
  });

  test('mergeConfig : clés stockées prioritaires, défauts sinon', () {
    final m = mergeConfig({'Full': 12, 'Bidon': 'x', 'Nouvelle': 4}, kVariantes);
    expect(m['Full'], 12.0); // surchargé
    expect(m['Tuck'], 2.0); // défaut conservé
    expect(m['Nouvelle'], 4.0); // clé ajoutée par l'utilisateur
    expect(m.containsKey('Bidon'), isFalse); // non numérique ignoré
    expect(mergeConfig(null, kFormes), kFormes);
  });

  test('Profile.initials : emoji entier, espaces multiples, nom vide', () {
    Profile p(String n) => Profile(id: 'x', name: n, hasPin: false);
    expect(p('Dilbert 🐶').initials, 'D🐶'); // emoji non coupé
    expect(p('Medhi').initials, 'M');
    expect(p('jean  paul').initials, 'JP'); // double espace : plus de crash
    expect(p('   ').initials, '?');
  });

  test('isPlancheName est insensible à la casse et aux espaces', () {
    expect(Perf.isPlancheName(' planche '), isTrue);
    expect(Perf.isPlancheName('PLANCHE'), isTrue);
    expect(Perf.isPlancheName('Lean Planche'), isFalse);
  });
}
