import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/models/stats.dart';
import 'package:sysiphe/services/reminders.dart';
import 'package:sysiphe/widgets/reminders_card.dart';

Perf p(DateTime d, String ex, double v) => Perf(
    userId: 'u', date: d, exercice: ex, performance: v, unite: 'Reps');

/// Séances : après 1 jour de repos on fait 60 pompes, après 3 jours 40.
List<Perf> history() {
  final out = <Perf>[];
  var d = DateTime(2026, 9, 1);
  out.add(p(d, 'Pompes', 50));
  out.add(p(d, 'Traction', 10));
  for (var i = 0; i < 8; i++) {
    final rest = i.isEven ? 1 : 3;
    d = DateTime(d.year, d.month, d.day + rest + 1);
    out.add(p(d, 'Pompes', rest == 1 ? 60 : 40));
    out.add(p(d, 'Traction', rest == 1 ? 12 : 8));
  }
  return out;
}

void main() {
  group('repos le plus efficace', () {
    test('les meilleures séances suivent 1 jour de repos', () {
      final o = optimalRest(history())!;
      expect(o.bestDays, 1);
      expect(o.bestScore, greaterThan(1.1));
      expect(o.buckets.map((b) => b.days), [1, 3]);
      expect(o.buckets.map((b) => b.sessions), [4, 4]);
      final three = o.buckets.firstWhere((b) => b.days == 3);
      expect(three.score, lessThan(0.9));
    });

    test('pas assez de séances : rien', () {
      expect(optimalRest(history().take(6)), isNull);
      expect(optimalRest(const []), isNull);
    });

    test('libellés', () {
      expect(restDaysLabel(2), '2 j');
      expect(restDaysLabel(6), '4 j et +');
    });
  });

  group('rappel de séance conseillée', () {
    final rest = computeRest(history().map((e) => e.date));

    test('habituel, optimal (repli sur l\'habituel), choisi', () {
      expect(chooseRest(RestTarget.habituel, rest: rest)!.reason,
          'Ton repos habituel');
      final o = optimalRest(history());
      final c = chooseRest(RestTarget.optimal, rest: rest, optimal: o)!;
      expect((c.days, c.reason), (1, 'Ton repos optimal'));
      expect(chooseRest(RestTarget.optimal, rest: rest)!.reason,
          'Ton repos habituel');
      expect(chooseRest(RestTarget.choisi, rest: rest, chosenDays: 2)!.days, 2);
    });

    test('date et message du rappel', () {
      final last = DateTime(2026, 11, 20);
      final plan = planReminders(
        sessionDates: [DateTime(2026, 11, 17), last],
        inactivityDays: 5,
        hour: 18,
        now: DateTime(2026, 11, 20, 20),
        restChoice: const RestChoice(1, 'Ton repos optimal'),
      );
      final next = plan.firstWhere((r) => r.id == kReminderNextId);
      expect(next.at, DateTime(2026, 11, 22, 18));
      expect(next.body, 'Ton repos optimal (1 jour) est terminé.');
    });
  });

  testWidgets('Réglages → Rappels : choisir le repos visé', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(360 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: RemindersCard(userId: 'u')))));
    await t.pumpAndSettle();
    await t.tap(find.text('Optimal'));
    await t.pumpAndSettle();
    expect(await Reminders.target(), RestTarget.optimal);
    expect(find.byKey(const ValueKey('rest-chosen')), findsNothing);
    await t.tap(find.text('Choisi'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Plus de repos'));
    await t.pumpAndSettle();
    expect(await Reminders.chosenDays(), 2);
    expect(find.text('2 jours de repos'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
