import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/effort_model.dart';
import 'package:sysiphe/models/perf.dart';

void main() {
  final m = EffortModel.defaults(weight: 97);

  test('même résultat que calculerEffort (parité data.py)', () {
    // Référence data.py : Full / Jaune / Serré / High, 8 s, 97 kg → 59
    expect(m.effort('Full', 'High', 'Jaune', 'Serré', 8), 59);
  });

  test('détail du calcul cohérent avec le résultat', () {
    final b = m.breakdown('Full', 'High', 'Jaune', 'Serré', 8);
    expect(b.forceElastique, 25);
    expect(b.ratioTension, 0.60);
    expect(b.poidsEffectif, closeTo(97 - 25 * 0.6, 1e-9));
    expect(b.facteurPoids, closeTo((82 / 100) * (82 / 100), 1e-9));
    expect((8 * b.facteurPoids * b.facteurDifficulte / 100).round(), b.effort);
  });

  test('aller-retour user_settings', () {
    final m2 = EffortModel.fromSettings({
      'weight': 80,
      'variantes_config': {'Full': 12},
    });
    expect(m2.weight, 80);
    expect(m2.variantes['Full'], 12);
    expect(m2.variantes['Tuck'], 2); // défaut conservé
    expect(m2.toSettings()['weight'], 80);
  });

  test('impact sur l\'historique : meilleur effort avant / après', () {
    Perf p(String v, double t, int stored) => Perf(
        userId: 'u', date: DateTime(2026, 8, 1), exercice: 'Planche',
        variante: v, forme: 'Normal', elastique: 'Aucun', tension: 'N/A',
        performance: t, unite: 'Sec', effortPondere: stored);
    final h = [p('Tuck', 20, 40), p('Tuck', 25, 50), p('Full', 5, 100)];
    final full12 = m.copyWith(variantes: {...m.variantes, 'Full': 12});
    final i = impactOn(h, full12);
    expect(i.series, 3);
    final full = i.parVariante.firstWhere((e) => e.variante == 'Full');
    expect(full.bestBefore, 100);
    expect(full.bestAfter, full12.effort('Full', 'Normal', 'Aucun', 'N/A', 5));
    expect(full.delta, full.bestAfter - 100);
    expect(i.parVariante.firstWhere((e) => e.variante == 'Tuck').series, 2);
  });

  group('générateur des formes', () {
    test('les formes par défaut sont une progression 34 × 1,4', () {
      final (base, ratio) = inferGeometric(kFormes)!;
      expect(base, 34);
      expect(ratio, closeTo(1.4, 1e-9));
      expect(ascendingKeys(kFormes), ['High', 'Normal', 'Bas', 'Dead']);
    });
    test('régénère exactement les valeurs par défaut', () {
      final g = geometricSeries(ascendingKeys(kFormes), 34, 1.4);
      for (final e in kFormes.entries) {
        expect(g[e.key], closeTo(e.value, 1e-9), reason: e.key);
      }
    });
    test('nouveau multiplicateur appliqué dans l\'ordre', () {
      final g = geometricSeries(['High', 'Normal', 'Bas'], 30, 1.5);
      expect(g, {'High': 30, 'Normal': 45, 'Bas': 67.5});
    });
    test('cas impossibles', () {
      expect(inferGeometric({'A': 1}), isNull);
      expect(inferGeometric({'A': 0, 'B': 2}), isNull);
    });
  });
}
