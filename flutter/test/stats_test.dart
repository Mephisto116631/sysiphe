import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/models/stats.dart';

List<DayPoint> pts(List<DateTime> d, List<double> v) =>
    [for (var i = 0; i < d.length; i++) DayPoint(d[i], v[i])];

final juillet = [
  DateTime(2026, 7, 1),
  DateTime(2026, 7, 5),
  DateTime(2026, 7, 10),
  DateTime(2026, 7, 15),
];

void main() {
  group('detectPlateau — parité avec data.detect_plateau', () {
    // Références calculées avec data.py.
    void check(List<DayPoint> p, Trend t, double slope, double rel, int n) {
      final r = detectPlateau(p);
      expect(r.status, t);
      expect(r.slope, closeTo(slope, 1e-6));
      expect(r.relativeSlope, closeTo(rel, 1e-6));
      expect(r.nPoints, n);
    }

    test('progression', () => check(pts(juillet, [10, 12, 14, 16]),
        Trend.progress, 0.424379, 0.685536, 4));
    test('régression', () => check(pts(juillet, [16, 14, 12, 10]),
        Trend.regression, -0.424379, -0.685536, 4));
    test('plateau', () => check(pts(juillet, [10, 10.2, 9.9, 10.1]),
        Trend.plateau, -0.000451, -0.000943, 4));
    test('seuls les 21 derniers jours comptent', () => check(
        pts([DateTime(2026, 5, 1), DateTime(2026, 7, 1), DateTime(2026, 7, 10),
            DateTime(2026, 7, 20)], [100, 10, 11, 12]),
        Trend.progress, 0.105166, 0.200772, 3));
    test('moins de 3 points', () => check(
        pts(juillet.sublist(0, 2), [1, 2]), Trend.insufficientData, 0, 0, 2));
  });

  group('dailySeries / metricFor', () {
    Perf p(String ex, DateTime d, double perf,
            {String unite = 'Reps', double charge = 0, int? effort}) =>
        Perf(userId: 'u', date: d, exercice: ex, performance: perf,
            unite: unite, charge: charge, effortPondere: effort);
    final j1 = DateTime(2026, 7, 1), j2 = DateTime(2026, 7, 2);

    test('planche : effort max du jour', () {
      final perfs = [
        p('Planche', j1, 10, unite: 'Sec', effort: 50),
        p('Planche', j1, 12, unite: 'Sec', effort: 70),
        p('Planche', j2, 8, unite: 'Sec', effort: 60),
      ];
      expect(metricFor(perfs), StatMetric.effort);
      final s = dailySeries(perfs, StatMetric.effort);
      expect(s.map((e) => e.value), [70, 60]);
    });

    test('reps sans lest : volume = somme du jour', () {
      final perfs = [p('Pompe', j1, 10), p('Pompe', j1, 8), p('Pompe', j2, 12)];
      expect(metricFor(perfs), StatMetric.volume);
      expect(dailySeries(perfs, StatMetric.volume).map((e) => e.value),
          [18, 12]);
    });

    test('reps lestées : tonnage = Σ reps × kg', () {
      final perfs = [
        p('Traction', j1, 5, charge: 10),
        p('Traction', j1, 6),
      ];
      expect(metricFor(perfs), StatMetric.tonnage);
      expect(dailySeries(perfs, StatMetric.tonnage).single.value, 56);
    });

    test('secondes hors planche : meilleure valeur du jour', () {
      final perfs = [
        p('Lean Planche', j1, 20, unite: 'Sec'),
        p('Lean Planche', j1, 30, unite: 'Sec'),
      ];
      expect(metricFor(perfs), StatMetric.best);
      expect(dailySeries(perfs, StatMetric.best).single.value, 30);
    });
  });

  group('computeRest — parité avec suggest_next_session', () {
    test('égalité de fréquence : le plus petit repos l\'emporte', () {
      final r = computeRest([
        DateTime(2026, 7, 1), DateTime(2026, 7, 3), DateTime(2026, 7, 6),
        DateTime(2026, 7, 8), DateTime(2026, 7, 11),
      ])!;
      expect(r.mode, 1); // data.py : mode_repos = 1
      expect(r.nextSession, DateTime(2026, 7, 13)); // data.py : 2026-07-13
      expect(r.longest, 2);
      expect(r.mean, 1.5);
      expect(r.distribution, {1: 2, 2: 2});
    });
    test('rythme régulier de 2 jours de repos', () {
      final r = computeRest([
        DateTime(2026, 7, 1), DateTime(2026, 7, 4),
        DateTime(2026, 7, 7), DateTime(2026, 7, 10),
      ])!;
      expect(r.mode, 2);
      expect(r.nextSession, DateTime(2026, 7, 13));
    });
    test('plusieurs séries le même jour = une séance', () {
      final r = computeRest([
        DateTime(2026, 7, 1, 9), DateTime(2026, 7, 1, 18), DateTime(2026, 7, 2),
      ])!;
      expect(r.gaps.single.restDays, 0);
    });
    test('moins de deux jours de séance', () {
      expect(computeRest([DateTime(2026, 7, 1)]), isNull);
    });
  });

  group('comparePeriods — parité avec compute_period_comparison', () {
    Perf v(DateTime d, double x) =>
        Perf(userId: 'u', date: d, exercice: 'Pompe', performance: x, unite: 'Reps');
    final perfs = [
      v(DateTime(2026, 6, 1), 100),
      v(DateTime(2026, 6, 8), 0),
      v(DateTime(2026, 6, 15), 150),
    ];
    test('période précédente à 0 : pas de pourcentage', () {
      final r = comparePeriods(perfs, (p) => p.performance,
          currentStart: DateTime(2026, 6, 15), currentEnd: DateTime(2026, 6, 21),
          previousStart: DateTime(2026, 6, 8), previousEnd: DateTime(2026, 6, 14));
      expect(r.current, 150);
      expect(r.previous, 0);
      expect(r.deltaPct, isNull);
    });
    test('delta positif arrondi à 0,1', () {
      final r = comparePeriods(perfs, (p) => p.performance,
          currentStart: DateTime(2026, 6, 15), currentEnd: DateTime(2026, 6, 21),
          previousStart: DateTime(2026, 6, 1), previousEnd: DateTime(2026, 6, 7));
      expect(r.deltaPct, 50.0);
    });
    test('semaine lundi → dimanche', () {
      // mercredi 17 juin 2026 : semaine du 15 au 21
      final r = weekVolume(perfs, DateTime(2026, 6, 17));
      expect(r.current, 150);
      expect(r.previous, 0);
    });
  });

  group('insightFor / sessionsInMonth', () {
    Perf v(DateTime d, double x) =>
        Perf(userId: 'u', date: d, exercice: 'Pompe', performance: x, unite: 'Reps');
    final h = [
      v(DateTime(2026, 7, 1), 10), v(DateTime(2026, 7, 1), 8), // 18
      v(DateTime(2026, 7, 3), 12), v(DateTime(2026, 7, 3), 10), // 22
      v(DateTime(2026, 7, 5), 30), // aujourd'hui : exclu
    ];
    test('PR et moyenne hors séance du jour', () {
      final i = insightFor(h, DateTime(2026, 7, 5))!;
      expect(i.prSerie, 12);
      expect(i.avgVolume, 20);
      expect(i.sessions, 2);
      expect(i.deltaPct(30), closeTo(50, 1e-9));
    });
    test('fenêtre des N dernières séances', () {
      expect(insightFor(h, DateTime(2026, 7, 5), nbDaysAvg: 1)!.avgVolume, 22);
    });
    test('% à série égale (cumul des N premières séries)', () {
      final i = insightFor(h, DateTime(2026, 7, 5))!;
      // Après 1 série : moyenne (10 + 12) / 2 = 11 ; après 2 : (18 + 22) / 2 = 20.
      expect(i.avgVolumeAt(1), 11);
      expect(i.avgVolumeAt(2), 20);
      expect(i.avgVolumeAt(5), 20); // séances plus courtes : total
      expect(i.deltaPctAtSets(22, 1), closeTo(100, 1e-9));
      expect(i.deltaPctAtSets(11, 1), closeTo(0, 1e-9));
    });
    test('pas d\'historique', () => expect(insightFor(h, DateTime(2026, 7, 1)), isNull));
    test('séances du mois', () => expect(sessionsInMonth(h, DateTime(2026, 7, 20)), 3));
  });

  group('records', () {
    Perf pl(String v, String e, double t, int eff) => Perf(
        userId: 'u', date: DateTime(2026, 7, 1), exercice: 'Planche',
        variante: v, elastique: e, tension: 'N/A', performance: t,
        unite: 'Sec', effortPondere: eff);
    test('planche : meilleure série par combinaison, triées par effort', () {
      final r = plancheRecords([
        pl('Tuck', 'Aucun', 20, 40), pl('Tuck', 'Aucun', 25, 50),
        pl('Full', 'Jaune', 8, 90),
      ]);
      expect(r.map((e) => e.variante), ['Full', 'Tuck']);
      expect(r[1].best.performance, 25);
    });
    test('volume : meilleure séance et meilleure série', () {
      Perf t(DateTime d, double x, double kg) => Perf(userId: 'u', date: d,
          exercice: 'Traction', performance: x, unite: 'Reps', charge: kg);
      final r = volumeRecords([
        t(DateTime(2026, 7, 1), 8, 10), t(DateTime(2026, 7, 1), 6, 10), // 140 kg
        t(DateTime(2026, 7, 3), 10, 0), // 10
      ]).single;
      expect(r.tonnage, isTrue);
      expect(r.volume, 140);
      expect(r.date, DateTime(2026, 7, 1));
      expect(r.bestSerie, 10);
    });
  });

  test('sessionDatesSince : filtre de période pour la récupération', () {
    final d = [DateTime(2026, 6, 1), DateTime(2026, 8, 1), DateTime(2026, 8, 20)];
    final now = DateTime(2026, 8, 31);
    expect(sessionDatesSince(d, 30, now: now), [DateTime(2026, 8, 1), DateTime(2026, 8, 20)]);
    expect(sessionDatesSince(d, 7, now: now), isEmpty);
    expect(sessionDatesSince(d, null, now: now).length, 3);
    // Récupération sur la période : un seul écart (1er → 20 août)
    expect(computeRest(sessionDatesSince(d, 30, now: now))!.gaps.single.restDays, 18);
  });
}
