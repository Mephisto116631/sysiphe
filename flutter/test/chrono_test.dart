import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/chrono.dart';

void main() {
  Future<void> pump(WidgetTester t, DateTime Function() now, List<int> got,
      {int pre = 0, Map<String, Object> extra = const {}, String? exo}) async {
    SharedPreferences.setMockInitialValues({kChronoPreKey: pre, ...extra});
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
          body: SingleChildScrollView(
              child: Chrono(now: now, onStop: got.add, exercice: exo))),
    ));
    await t.pumpAndSettle(); // laisse charger le réglage
  }

  testWidgets('sans préparation : démarrer puis arrêter renvoie les secondes',
      (t) async {
    var now = DateTime(2026, 11, 14, 10);
    final got = <int>[];
    await pump(t, () => now, got);
    expect(find.text('0:00.0'), findsOneWidget);
    await t.tap(find.text('Démarrer'));
    await t.pump();
    now = now.add(const Duration(seconds: 72, milliseconds: 600));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Arrêter'));
    await t.pump();
    expect(got, [73]); // 72,6 s → 73
    expect(find.text('1:12.6'), findsOneWidget);
    expect(find.text('Démarrer'), findsOneWidget);
  });

  testWidgets('arrêt immédiat (< 0,5 s) ne remplit rien', (t) async {
    final now = DateTime(2026, 11, 14, 10);
    final got = <int>[];
    await pump(t, () => now, got);
    await t.tap(find.text('Démarrer'));
    await t.pump();
    await t.tap(find.text('Arrêter'));
    await t.pump();
    expect(got, isEmpty);
  });

  testWidgets('préparation 5 s : compte à rebours puis le chrono démarre seul',
      (t) async {
    var now = DateTime(2026, 11, 14, 10);
    final got = <int>[];
    await pump(t, () => now, got, pre: 5);
    await t.tap(find.text('Démarrer'));
    await t.pump();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    now = now.add(const Duration(milliseconds: 2200));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('3'), findsOneWidget); // il reste 2,8 s
    now = now.add(const Duration(milliseconds: 2800)); // fin de la préparation
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Arrêter'), findsOneWidget); // chrono lancé
    now = now.add(const Duration(seconds: 30));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('Arrêter'));
    await t.pump();
    // départ réel = fin du compte à rebours (pas le tick suivant) : 30 s
    expect(got, [30]);
  });

  testWidgets('annuler pendant la préparation ne lance rien', (t) async {
    var now = DateTime(2026, 11, 14, 10);
    final got = <int>[];
    await pump(t, () => now, got, pre: 10);
    await t.tap(find.text('Démarrer'));
    await t.pump();
    await t.tap(find.text('Annuler'));
    await t.pump();
    now = now.add(const Duration(seconds: 20));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Démarrer'), findsOneWidget);
    expect(got, isEmpty);
  });

  testWidgets('le réglage de préparation se choisit et se mémorise', (t) async {
    final now = DateTime(2026, 11, 14, 10);
    await pump(t, () => now, <int>[], pre: 5);
    await t.tap(find.text('15 s'));
    await t.pump();
    expect((await SharedPreferences.getInstance()).getInt(kChronoPreKey), 15);
  });

  test('parseDuree accepte secondes et min:s', () {
    expect(parseDuree('90'), 90);
    expect(parseDuree('1:30'), 90);
    expect(parseDuree('1m30'), 90);
    expect(parseDuree('1 min 30'), 90);
    expect(parseDuree('2m'), 120);
    expect(parseDuree('45s'), 45);
    expect(parseDuree('1:75'), isNull);
    expect(parseDuree('abc'), isNull);
    expect(parseDuree(''), isNull);
    expect(formatDuree(45), '45 s');
    expect(formatDuree(75), '1:15');
  });

  testWidgets('objectif 1:00 : décompte, puis dépassement, temps total renvoyé',
      (t) async {
    var now = DateTime(2026, 11, 17, 10);
    final got = <int>[];
    await pump(t, () => now, got,
        extra: {chronoTargetKey('Planche'): 60}, exo: 'Planche');
    expect(find.text('Objectif'), findsOneWidget);
    await t.tap(find.text('Démarrer'));
    await t.pump();
    expect(find.text('1:00'), findsWidgets);
    now = now.add(const Duration(seconds: 15, milliseconds: 300));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('0:45'), findsOneWidget); // 44,7 s restantes → 0:45
    now = now.add(const Duration(seconds: 50));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('+0:05'), findsOneWidget);
    expect(find.textContaining('Objectif atteint'), findsOneWidget);
    await t.tap(find.text('Arrêter'));
    await t.pump();
    expect(got, [65]);
    await t.pump(const Duration(seconds: 1)); // fin des vibrations différées
  });

  testWidgets('objectif mémorisé par exercice, temps personnalisé', (t) async {
    final now = DateTime(2026, 11, 17, 10);
    await pump(t, () => now, <int>[], exo: 'Gainage');
    await t.tap(find.text('Autre').last); // chip « Autre » de l'objectif
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '1:15');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    final p = await SharedPreferences.getInstance();
    expect(p.getInt(chronoTargetKey('Gainage')), 75);
    expect(find.text('1:15'), findsOneWidget); // chip personnalisé sélectionné
  });

  testWidgets(
      'préparation personnalisée invalide → erreur, pas d\'enregistrement',
      (t) async {
    final now = DateTime(2026, 11, 17, 10);
    await pump(t, () => now, <int>[], pre: 5);
    await t.tap(find.text('Autre').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '1:99');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.textContaining('Ex. 90'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getInt(kChronoPreKey), 5);
  });
}
