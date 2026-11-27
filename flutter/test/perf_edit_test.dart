import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/services/offline_store.dart';
import 'package:sysiphe/widgets/saisie/dialogs.dart';

void main() {
  final planche = Perf(
      id: 7,
      userId: 'u',
      date: DateTime(2026, 11, 27),
      exercice: 'Planche',
      serie: 2,
      performance: 12,
      variante: 'Adv_Tuck',
      forme: 'Normal');
  const choices = PlancheChoices(['Tuck', 'Adv_Tuck', 'Straddle'],
      ['High', 'Normal', 'Bas'], ['Aucun', 'Jaune'], ['N/A', 'Normal']);

  Future<PerfEdit?> open(WidgetTester t, Perf p, PlancheChoices? c,
      Future<void> Function() act) async {
    PerfEdit? got;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async =>
              got = await askPerfEdit(ctx, p, planche: c),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    await act();
    await t.tap(find.byKey(const ValueKey('edit-ok')));
    await t.pumpAndSettle();
    return got;
  }

  testWidgets('planche : changer la forme et le temps', (t) async {
    final e = await open(t, planche, choices, () async {
      await t.enterText(find.byKey(const ValueKey('edit-value')), '15');
      await t.tap(find.byKey(const ValueKey('edit-Forme')));
      await t.pumpAndSettle();
      await t.tap(find.text('Bas').last);
      await t.pumpAndSettle();
    });
    expect(e!.value, 15);
    expect(e.forme, 'Bas');
    expect(e.variante, 'Adv_Tuck');
    expect(e.changes(planche), isTrue);
  });

  testWidgets('autre exercice : seulement la valeur', (t) async {
    final traction = Perf(
        id: 3,
        userId: 'u',
        date: DateTime(2026, 11, 27),
        exercice: 'Traction',
        performance: 10,
        unite: 'Reps');
    final e = await open(t, traction, null, () async {
      expect(find.byKey(const ValueKey('edit-Forme')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('edit-value')), '12');
    });
    expect(e!.value, 12);
    expect(e.changes(traction), isTrue);
  });

  test('hors ligne : la correction de plusieurs champs est mise en file', () {
    final s = OfflineStore.memory()..clearForTest();
    s.setAllPerfs('u', [planche.toJson()..['id'] = 7]);
    s.updateFields(7, {'forme': 'Bas', 'performance': 15.0});
    final p = s.view('u').single;
    expect(p.forme, 'Bas');
    expect(p.performance, 15);
    expect(s.outbox.single.data, {'id': 7, 'forme': 'Bas', 'performance': 15.0});
  });
}
