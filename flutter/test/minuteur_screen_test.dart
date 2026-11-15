import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/screens/minuteur_screen.dart';
import 'package:sysiphe/theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(360 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const MinuteurScreen()));
    await t.pumpAndSettle();
  }

  testWidgets('configuration : durée totale par défaut et bouton Démarrer',
      (t) async {
    await pump(t);
    expect(find.text('Démarrer'), findsOneWidget);
    // 5 s de préparation + 4 × 30 s d'exercice + 3 × 30 s de repos = 3:35
    expect(find.text('Durée totale : 3:35'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('un préréglage change la durée totale', (t) async {
    await pump(t);
    await t.tap(find.text('Tabata 20/10 ×8'));
    await t.pumpAndSettle();
    // 10 + 8 × 20 + 7 × 10 = 240 s
    expect(find.text('Durée totale : 4:00'), findsOneWidget);
  });

  testWidgets('les + et − des cycles ajustent la durée', (t) async {
    await pump(t);
    final plus = find.descendant(
        of: find.ancestor(of: find.text('Cycles'), matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.add));
    await t.tap(plus.first);
    await t.pumpAndSettle();
    // 5 cycles : 5 + 5 × 30 + 4 × 30 = 275 s = 4:35
    expect(find.text('Durée totale : 4:35'), findsOneWidget);
  });
}
