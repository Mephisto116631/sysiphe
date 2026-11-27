import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/effort_model.dart';

void main() {
  final m = EffortModel.defaults(weight: 80);

  test('équivalences : les plus proches de la référence, référence exclue',
      () {
    final ref = m.effort('Adv_Tuck', 'Normal', 'Aucun', 'N/A', 10);
    final c = closestEfforts(m,
        variante: 'Adv_Tuck',
        forme: 'Normal',
        elastique: 'Aucun',
        tension: 'N/A',
        temps: 10);
    expect(c.length, 5);
    expect(c.any((e) => e.label == 'Adv_Tuck · Normal'), isFalse);
    // Triées par écart croissant à la référence.
    final gaps = [for (final e in c) (e.effort - ref).abs()];
    expect(gaps, [...gaps]..sort());
    // Personne d'autre n'est plus proche que le 5e.
    final all = closestEfforts(m,
        variante: 'Adv_Tuck',
        forme: 'Normal',
        elastique: 'Aucun',
        tension: 'N/A',
        temps: 10,
        n: 1000);
    expect(all.skip(5).every((e) => (e.effort - ref).abs() >= gaps.last),
        isTrue);
    // Avec élastique, la tension est indiquée ; sans, elle n'apparaît pas.
    expect(all.any((e) => e.label.contains('(')), isTrue);
    expect(all.where((e) => e.elastique == 'Aucun').every(
        (e) => !e.label.contains('(')), isTrue);
  });

  test('libellé lisible', () {
    expect(
        const EffortCombo('Straddle', 'Normal', 'Rouge/Violet', 'Normal', 39)
            .label,
        'Straddle · Normal · Rouge/Violet (Normal)');
    expect(const EffortCombo('Tuck', 'High', 'Aucun', 'N/A', 5).label,
        'Tuck · High');
  });
}
