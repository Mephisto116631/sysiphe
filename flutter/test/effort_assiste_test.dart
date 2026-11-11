import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/perf.dart';

void main() {
  group('effort des exercices assistables', () {
    test('sans élastique : (poids/100)² × reps', () {
      final e = effortAssisteExact(
          reps: 10,
          elastique: 'Aucun',
          tension: 'N/A',
          ecartement: 'Standard',
          weight: 95);
      expect(e, closeTo(9.025, 1e-9));
    });

    test('élastique + écartement large', () {
      final e = effortAssisteExact(
          reps: 10,
          elastique: 'Jaune',
          tension: 'Normal',
          ecartement: 'Large',
          weight: 95);
      expect(e, closeTo(7.103, 1e-3)); // 77,5 kg effectifs, 1,15^1,2
    });

    test('lest augmente l\'effort, 0 rep = 0', () {
      double f(double reps, double lest) => effortAssisteExact(
          reps: reps,
          elastique: 'Aucun',
          tension: 'N/A',
          ecartement: 'Standard',
          weight: 95,
          lest: lest);
      expect(f(10, 10), greaterThan(f(10, 0)));
      expect(f(0, 0), 0);
    });
  });
}
