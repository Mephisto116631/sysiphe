import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/chrono.dart';

void main() {
  testWidgets('démarrer puis arrêter renvoie les secondes arrondies', (t) async {
    var now = DateTime(2026, 11, 14, 10);
    final got = <int>[];
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Chrono(now: () => now, onStop: got.add)),
    ));
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
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Chrono(now: () => now, onStop: got.add)),
    ));
    await t.tap(find.text('Démarrer'));
    await t.pump();
    await t.tap(find.text('Arrêter'));
    await t.pump();
    expect(got, isEmpty);
  });
}
