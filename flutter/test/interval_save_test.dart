import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/interval_plan.dart';
import 'package:sysiphe/screens/minuteur_screen.dart';

void main() {
  const tabata = IntervalConfig(prep: 10, work: 20, rest: 10, cycles: 3);

  IntervalLog run(IntervalConfig c, List<int> seconds) {
    final plan = IntervalPlan(c);
    final log = IntervalLog(c);
    for (var i = 0; i < seconds.length; i++) {
      log.phaseEnded(plan.phases[i], seconds[i]);
    }
    return log;
  }

  group('journal du minuteur', () {
    test('séance complète : un cycle par série, repos pris avant', () {
      // prép 10, effort 20, repos 10, effort 20, repos 12, effort 20
      final log = run(tabata, [10, 20, 10, 20, 12, 20]);
      expect(log.rounds, const [
        IntervalRound(20, null, 10),
        IntervalRound(20, 10, 10),
        IntervalRound(20, 12, 10),
      ]);
      expect(log.totalWorkS, 60);
    });

    test('repos passé et séance arrêtée en plein effort', () {
      // prép, effort 20, repos passé après 3 s, effort arrêté à 8 s
      final log = run(tabata, [10, 20, 3, 8]);
      expect(log.rounds, const [
        IntervalRound(20, null, 10),
        IntervalRound(8, 3, 10),
      ]);
    });

    test('arrêt pendant la préparation : rien à enregistrer', () {
      expect(run(tabata, [4]).rounds, isEmpty);
    });

    test('nom proposé', () {
      expect(intervalExerciseName(tabata), 'Tabata');
      expect(
          intervalExerciseName(
              const IntervalConfig(work: 40, rest: 20, cycles: 10)),
          'HIIT');
      expect(
          intervalExerciseName(
              const IntervalConfig(work: 60, rest: 0, cycles: 5)),
          'Intervalles');
    });
  });

  testWidgets('fenêtre « Enregistrer la séance ? »', (t) async {
    final log = run(tabata, [10, 20, 10, 20, 10, 20]);
    String? got = 'pas fermé';
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => got = await showDialog<String>(
              context: ctx,
              builder: (_) =>
                  IntervalSaveDialog(log: log, initialName: 'Tabata')),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    expect(find.text('3 cycles · 1:00 d\'effort · repos 10 s'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('interval-name')), '');
    await t.pump();
    expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('interval-save')))
            .onPressed,
        isNull);
    await t.enterText(
        find.byKey(const ValueKey('interval-name')), 'Corde à sauter');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('interval-save')));
    await t.pumpAndSettle();
    expect(got, 'Corde à sauter');

    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ignorer'));
    await t.pumpAndSettle();
    expect(got, isNull);
  });
}
