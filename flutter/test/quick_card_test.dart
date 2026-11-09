import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/quick_card.dart';

void main() {
  Future<List<List<double>>> pump(WidgetTester t,
      {int done = 0, bool ok = true}) async {
    final saved = <List<double>>[];
    t.view.physicalSize = const Size(360 * 3, 400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: QuickCard(
          exercice: 'Abdos ( dragon press bicyclette ou hold)',
          unite: 'Reps',
          hint: '30/40',
          helper: 'Dernière fois le 1 août · record série 60',
          done: done,
          onSave: (v) async {
            saved.add(v);
            return ok;
          },
        ),
      ),
    ));
    return saved;
  }

  testWidgets('champ vide, dernière fois en gris dans le champ', (t) async {
    await pump(t);
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty); // pas pré-rempli
    expect(find.text('30/40'), findsOneWidget); // indice gris
    expect(find.text('Dernière fois le 1 août · record série 60'), findsOneWidget);
    expect(t.takeException(), isNull); // nom long : pas de débordement
  });

  testWidgets('« 12/10 » enregistre deux séries puis vide le champ', (t) async {
    final saved = await pump(t);
    await t.enterText(find.byType(TextField), '12/10');
    await t.tap(find.byIcon(Icons.save_outlined));
    await t.pumpAndSettle();
    expect(saved, [
      [12.0, 10.0]
    ]);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('saisie vide refusée, échec conserve la saisie', (t) async {
    final saved = await pump(t, ok: false);
    await t.tap(find.byIcon(Icons.save_outlined));
    await t.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.text('Saisis au moins une valeur'), findsOneWidget);
    await t.enterText(find.byType(TextField), '15');
    await t.tap(find.byIcon(Icons.save_outlined));
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '15');
  });

  testWidgets('badge des séries du jour', (t) async {
    await pump(t, done: 2);
    expect(find.text('2 séries'), findsOneWidget);
  });
}
