import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/stats.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/saisie/kpi.dart';

void main() {
  Future<void> pump(WidgetTester t, PeriodComparison week) async {
    t.view.physicalSize = const Size(360 * 3, 780 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: KpiRow(sets: 0, effort: 0, monthSessions: 11, week: week),
        ),
      ),
    ));
  }

  testWidgets('trois cases de même hauteur, évolution écrite en dessous',
      (t) async {
    await pump(t, const PeriodComparison(480, 1143, -58));
    final heights = {
      for (final e in t.widgetList<Kpi>(find.byType(Kpi)))
        t.getSize(find.byWidget(e)).height
    };
    expect(heights.length, 1); // toutes identiques
    expect(find.text('Reps semaine'), findsOneWidget);
    expect(
        find.text('Reps de la semaine : -58 % par rapport à la semaine '
            'dernière'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('sans semaine précédente : pas de ligne d\'évolution',
      (t) async {
    await pump(t, const PeriodComparison(120, 0, null));
    expect(find.byKey(const ValueKey('kpi-week-delta')), findsNothing);
  });
}
