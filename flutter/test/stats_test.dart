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
}
