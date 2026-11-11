import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/models/session.dart';

Perf s(int id, String ex, int serie, double v,
        {String unite = 'Reps', double charge = 0, String variante = 'Tuck'}) =>
    Perf(
        id: id,
        userId: 'u',
        date: DateTime(2026, 8, 1),
        exercice: ex,
        serie: serie,
        performance: v,
        unite: unite,
        charge: charge,
        variante: variante);

void main() {
  final seance = [
    s(10, 'Planche', 1, 15, unite: 'Sec', variante: 'Straddle'),
    s(11, 'Planche', 2, 12, unite: 'Sec', variante: 'Straddle'),
    s(12, 'Traction', 1, 8, charge: 10),
    s(13, 'Traction', 2, 8, charge: 10),
    s(14, 'Traction', 3, 8, charge: 10),
    s(15, 'Pompe', 1, 20),
  ];

  test('exercices dans l\'ordre de la séance, séries regroupées', () {
    final t = templatesFrom(seance.reversed.toList());
    expect(t.map((e) => e.exercice), ['Planche', 'Traction', 'Pompe']);
    expect(t[1].series.length, 3);
    expect(t[0].unite, 'Sec');
  });

  test('série n : même série que la dernière fois, sinon la dernière', () {
    final planche = templatesFrom(seance).first;
    expect(planche.seriesFor(1).performance, 15);
    expect(planche.seriesFor(2).performance, 12);
    expect(planche.seriesFor(5).performance, 12); // au-delà : dernière
    expect(planche.seriesFor(1).variante, 'Straddle');
  });

  test('résumé lisible', () {
    final t = templatesFrom(seance);
    expect(t[0].summary, '15s · 12s');
    expect(t[1].summary, '3 × 8 Reps · +10 kg');
    expect(t[2].summary, '20 Reps');
  });

  test('séance vide', () => expect(templatesFrom([]), isEmpty));

  group('parseSeries — parité avec data.parse_reps', () {
    test('simple', () => expect(parseSeries('12 10 8'), [12, 10, 8]));
    test('vide', () => expect(parseSeries(''), isEmpty));
    test('décimal (point et virgule)',
        () => expect(parseSeries('12.5 10,5'), [12.5, 10.5]));
    test(
        'espaces multiples', () => expect(parseSeries('  12   10 '), [12, 10]));
    test('séparateurs du pavé numérique',
        () => expect(parseSeries('12/10+8;6'), [12, 10, 8, 6]));
    test('négatif refusé',
        () => expect(() => parseSeries('12 -5 8'), throwsFormatException));
    test('non numérique refusé',
        () => expect(() => parseSeries('12 abc 8'), throwsFormatException));
  });

  group('reprise des exercices', () {
    Perf at(int id, String ex, DateTime d, double v) => Perf(
        id: id, userId: 'u', date: d, exercice: ex, performance: v, unite: 'Reps');
    final h = [
      at(1, 'Pompe', DateTime(2026, 7, 1), 20),
      at(2, 'Dips', DateTime(2026, 7, 1), 10),
      at(3, 'Traction', DateTime(2026, 7, 20), 8),
      at(4, 'Traction', DateTime(2026, 7, 20), 7),
      at(5, 'Pompe', DateTime(2026, 7, 25), 25),
      at(6, 'Planche', DateTime(2026, 7, 25), 15),
    ];
    test('exercices par récence (jour, puis ordre de saisie)', () {
      expect(exercisesByRecency(h), ['Planche', 'Pompe', 'Traction', 'Dips']);
    });
    test('dernière fois pour un exercice quelconque', () {
      final t = lastTemplateFor(h, 'Traction', DateTime(2026, 8, 1))!;
      expect(t.series.map((p) => p.performance), [8, 7]);
      expect(lastTemplateFor(h, 'Traction', DateTime(2026, 7, 20)), isNull);
      expect(lastTemplateFor(h, 'Inconnu', DateTime(2026, 8, 1)), isNull);
    });
    test('exercice suivant à faire', () {
      final t = templatesFrom([
        at(10, 'Planche', DateTime(2026, 8, 1), 23),
        at(11, 'Planche', DateTime(2026, 8, 1), 21),
        at(12, 'Pompe', DateTime(2026, 8, 1), 30),
      ]);
      expect(nextPending(t, (_) => 0)!.exercice, 'Planche');
      expect(nextPending(t, (e) => e == 'Planche' ? 2 : 0)!.exercice, 'Pompe');
      expect(nextPending(t, (_) => 5), isNull);
    });
  });

  group('petites cartes', () {
    Perf at(int id, String ex, double v) => Perf(
        id: id, userId: 'u', date: DateTime(2026, 8, 1), exercice: ex,
        performance: v, unite: 'Reps');
    final t = templatesFrom([
      at(1, 'Pompe', 30),
      at(2, 'Planche', 23),
      at(3, 'Abdos', 30),
      at(4, 'Abdos', 40),
    ]);
    test('séance reprise, puis faits aujourd\'hui, puis ajoutés ; sans planche ni doublon', () {
      final today = [at(10, 'Dips', 12), at(11, 'Pompe', 25)];
      expect(cardExercises(t, today, ['Traction', 'Dips', ' planche ']),
          ['Pompe', 'Abdos', 'Dips', 'Traction']);
    });
    test('avec includePlanche : une seule carte planche, à sa place', () {
      final today = [at(10, 'Dips', 12), at(11, 'Pompe', 25)];
      expect(
          cardExercises(t, today, ['Traction', 'Dips', ' planche '],
              includePlanche: true),
          ['Pompe', 'Planche', 'Abdos', 'Dips', 'Traction']);
    });
    test('indice gris au format de saisie rapide', () {
      expect(seriesHint(t.firstWhere((e) => e.exercice == 'Abdos')), '30/40');
    });
  });
}
