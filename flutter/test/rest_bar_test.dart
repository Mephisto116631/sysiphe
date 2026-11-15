import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/rest_bar.dart';

void main() {
  Future<void> pump(WidgetTester t, ValueNotifier<Duration?> left,
      {int seconds = 90,
      void Function(int)? onConfig,
      VoidCallback? onSkip,
      void Function(int)? onAdjust}) async {
    t.view.physicalSize = const Size(360 * 3, 800 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: RestBar(
          seconds: seconds,
          onConfig: onConfig ?? (_) {},
          left: left,
          onSkip: onSkip ?? () {},
          onAdjust: onAdjust ?? (_) {},
        ),
      ),
    ));
  }

  testWidgets('au repos : choix de la durée, valeur courante sélectionnée',
      (t) async {
    final chosen = <int>[];
    await pump(t, ValueNotifier(null), onConfig: chosen.add);
    expect(find.text('Repos après chaque série'), findsOneWidget);
    for (final l in ['Sans', '1 min', '90 s', '2 min', '3 min']) {
      expect(find.text(l), findsOneWidget);
    }
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '90 s')).selected,
        isTrue);
    await t.tap(find.text('2 min'));
    expect(chosen, [120]);
  });

  testWidgets('repos en cours : décompte, −15 / +15 / Passer', (t) async {
    final left = ValueNotifier<Duration?>(const Duration(seconds: 83));
    final adj = <int>[];
    var skipped = 0;
    await pump(t, left, onAdjust: adj.add, onSkip: () => skipped++);
    expect(find.text('1:23'), findsOneWidget);
    await t.tap(find.text('+15'));
    await t.tap(find.text('−15'));
    await t.tap(find.text('Passer'));
    expect(adj, [15, -15]);
    expect(skipped, 1);
    left.value = const Duration(milliseconds: 2400); // arrondi au-dessus
    await t.pump();
    expect(find.text('0:03'), findsOneWidget);
    left.value = null; // fin du repos : retour au choix de durée
    await t.pump();
    expect(find.text('Repos après chaque série'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('libellés des durées', () {
    expect(RestBar.label(0), 'Sans');
    expect(RestBar.label(60), '1 min');
    expect(RestBar.label(90), '90 s');
    expect(RestBar.label(180), '3 min');
  });
}
