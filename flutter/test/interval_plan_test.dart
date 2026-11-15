import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/interval_plan.dart';

void main() {
  const tabata = IntervalConfig(prep: 10, work: 20, rest: 10, cycles: 8);

  test('plan : préparation, puis exercice/repos, sans repos après le dernier', () {
    final p = IntervalPlan(tabata);
    expect(p.phases.length, 1 + 8 + 7);
    expect(p.phases.first.kind, IntervalKind.prep);
    expect(p.phases.last.kind, IntervalKind.work);
    expect(p.total, const Duration(seconds: 10 + 8 * 20 + 7 * 10));
  });

  test('sans préparation ni repos : que des exercices', () {
    final p = IntervalPlan(const IntervalConfig(prep: 0, work: 30, rest: 0, cycles: 3));
    expect(p.phases.map((e) => e.kind), everyElement(IntervalKind.work));
    expect(p.phases.length, 3);
  });

  test('position à un instant donné', () {
    final p = IntervalPlan(tabata);
    var pos = p.at(Duration.zero);
    expect(pos.phase!.kind, IntervalKind.prep);
    expect(pos.left, const Duration(seconds: 10));
    pos = p.at(const Duration(seconds: 10)); // début du 1er exercice
    expect(pos.phase!.kind, IntervalKind.work);
    expect(pos.phase!.cycle, 1);
    expect(pos.left, const Duration(seconds: 20));
    pos = p.at(const Duration(seconds: 35)); // 5 s dans le 1er repos
    expect(pos.phase!.kind, IntervalKind.rest);
    expect(pos.left, const Duration(seconds: 5));
    pos = p.at(const Duration(seconds: 40)); // 2e exercice
    expect(pos.phase!.cycle, 2);
  });

  test('terminé après la dernière phase', () {
    final p = IntervalPlan(tabata);
    expect(p.at(p.total).finished, isTrue);
    expect(p.at(p.total - const Duration(milliseconds: 1)).finished, isFalse);
  });

  test('startOf et next', () {
    final p = IntervalPlan(tabata);
    expect(p.startOf(0), Duration.zero);
    expect(p.startOf(1), const Duration(seconds: 10));
    expect(p.startOf(2), const Duration(seconds: 30));
    expect(p.next(0)!.kind, IntervalKind.work);
    expect(p.next(p.phases.length - 1), isNull);
  });

  test('titres et formats', () {
    final p = IntervalPlan(tabata);
    expect(p.phases[1].title(8), 'Exercice 1/8');
    expect(p.phases[2].title(8), 'Repos');
    expect(formatSeconds(30), '30 s');
    expect(formatSeconds(90), '1:30');
    expect(formatSeconds(605), '10:05');
    expect(clock(const Duration(milliseconds: 61500)), '1:02'); // arrondi au-dessus
  });
}
