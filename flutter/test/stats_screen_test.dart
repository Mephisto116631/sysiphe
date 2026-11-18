import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/screens/stats_screen.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/stats/category_bars.dart';
import 'package:sysiphe/widgets/stats/multi_line_chart.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  // Trois semaines récentes : planche (deux variantes), tractions, pompes.
  final now = DateTime.now();
  DateTime day(int ago) => DateTime(now.year, now.month, now.day - ago);
  final perfs = [
    for (final ago in [20, 15, 10, 5, 1]) ...[
      Perf(
          userId: 'u',
          date: day(ago),
          exercice: 'Planche',
          variante: 'Tuck',
          performance: 30.0 + ago,
          unite: 'Sec',
          categorie: 'Force isométrique',
          effortPondere: 40 + ago),
      Perf(
          userId: 'u',
          date: day(ago),
          exercice: 'Planche',
          variante: 'Straddle',
          performance: 10,
          unite: 'Sec',
          categorie: 'Force Iso',
          effortPondere: 80 - ago),
      Perf(
          userId: 'u',
          date: day(ago),
          exercice: 'Tractions lestées',
          performance: 8,
          charge: 10.0 + ago,
          unite: 'Reps'),
      Perf(
          userId: 'u',
          date: day(ago),
          exercice: 'Pompes',
          performance: 20.0 + ago,
          unite: 'Reps'),
    ],
  ];

  Future<void> pump(WidgetTester t,
      {Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    t.view.physicalSize = const Size(360 * 3, 780 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: StatsScreen(userId: 'u', initialPerfs: perfs),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('Exercice : planche par défaut, courbe par variante', (t) async {
    await pump(t);
    expect(find.text('Effort pondéré'), findsOneWidget);
    expect(find.byType(MultiLineChart), findsOneWidget);
    await t.tap(find.text('Par variante'));
    await t.pumpAndSettle();
    expect(find.text('Effort pondéré par variante'), findsOneWidget);
    // Légende : la variante la plus dure d'abord, chacune masquable.
    expect(find.text('Straddle'), findsOneWidget);
    expect(find.text('Tuck'), findsOneWidget);
    await t.tap(find.text('Tuck'));
    await t.pumpAndSettle();
    final chart = t.widget<MultiLineChart>(find.byType(MultiLineChart));
    expect(chart.series.map((s) => s.name), ['Straddle']);
    expect(
        (await SharedPreferences.getInstance()).getBool('stats_par_variante'),
        true);
    expect(t.takeException(), isNull);
  });

  testWidgets('Comparer : 3 exercices récents, en % du record', (t) async {
    await pump(t);
    await t.tap(find.text('Comparer'));
    await t.pumpAndSettle();
    final chart = t.widget<MultiLineChart>(find.byType(MultiLineChart));
    expect(chart.series.length, 3);
    for (final s in chart.series) {
      final best = s.points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
      expect(best, closeTo(100, 1e-9));
    }
    expect(find.text('100 % = meilleure séance de la période'), findsOneWidget);
    // Retirer un exercice : choix mémorisé par profil.
    await t.tap(find.widgetWithText(FilterChip, 'Pompes'));
    await t.pumpAndSettle();
    expect(
        t.widget<MultiLineChart>(find.byType(MultiLineChart)).series.length, 2);
    final saved = (await SharedPreferences.getInstance())
        .getString('stats_compare_u')!
        .split('\n');
    expect(saved, isNot(contains('Pompes')));
    expect(t.takeException(), isNull);
  });

  testWidgets('Catégories : barres, catégories regroupées', (t) async {
    await pump(t, prefs: {'stats_period': 'd30'});
    await t.tap(find.text('Catégories'));
    await t.pumpAndSettle();
    expect(find.text('Séries par catégorie, par semaine'), findsOneWidget);
    final bars = t.widget<CategoryBars>(find.byType(CategoryBars));
    // « Force isométrique » et « Force Iso » regroupés.
    expect(bars.categories.toSet(), {'Force Iso', 'Musculation'});
    expect(find.text('Force Iso · 10'), findsOneWidget);
    expect(find.text('Musculation · 10'), findsOneWidget);
    expect(find.text('20 séries sur la période'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
