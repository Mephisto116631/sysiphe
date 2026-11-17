import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/models/effort_settings.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/services/rest_timer.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/saisie/dialogs.dart';
import 'package:sysiphe/widgets/saisie/form_bits.dart';
import 'package:sysiphe/widgets/saisie/options_fields.dart';

Widget _app(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('RestTimer', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('décompte, ajustement, fin', () async {
      var now = DateTime(2026, 11, 17, 10);
      final r = RestTimer(now: () => now);
      r.start();
      expect(r.running, isTrue);
      expect(r.left.value, const Duration(seconds: 90));
      r.adjust(15);
      expect(r.left.value, const Duration(seconds: 105));
      now = now.add(const Duration(seconds: 106));
      r.tick();
      expect(r.running, isFalse);
      expect(r.left.value, isNull);
      r.dispose();
    });

    test('0 s = pas de repos ; la durée est mémorisée', () async {
      final r = RestTimer();
      r.setSeconds(0);
      r.start();
      expect(r.running, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      r.setSeconds(60);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final r2 = RestTimer();
      await r2.load();
      expect(r2.seconds, 60);
      r.dispose();
      r2.dispose();
    });
  });

  group('EffortSettings', () {
    test('mêmes résultats que les fonctions de calcul', () {
      final c = EffortSettings.fromSettings({'weight': 80});
      expect(
          c.planche(
              variante: 'Full',
              forme: 'Normal',
              elastique: 'Aucun',
              tension: 'N/A',
              temps: 30),
          calculerEffort(
              variante: 'Full',
              elastique: 'Aucun',
              tension: 'N/A',
              forme: 'Normal',
              temps: 30,
              weight: 80));
      expect(
          c.assiste(
              reps: 10,
              lest: 5,
              elastique: 'Aucun',
              tension: 'N/A',
              ecartement: 'Large'),
          calculerEffortAssiste(
              reps: 10,
              lest: 5,
              elastique: 'Aucun',
              tension: 'N/A',
              ecartement: 'Large',
              weight: 80));
    });

    test('poids par défaut 97 kg', () {
      expect(const EffortSettings().weight, 97);
      expect(EffortSettings.fromSettings({}).weight, 97);
    });
  });

  testWidgets('SeriesStepper : jamais sous 1', (t) async {
    var v = 1;
    await t.pumpWidget(_app(StatefulBuilder(
        builder: (_, set) =>
            SeriesStepper(serie: v, onChanged: (x) => set(() => v = x)))));
    await t.tap(find.byIcon(Icons.remove));
    expect(v, 1);
    await t.tap(find.byIcon(Icons.add));
    await t.pump();
    expect(v, 2);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('PlancheOptions : dépliage et tension désactivée sans élastique',
      (t) async {
    var toggled = false;
    Widget build(bool expanded) => _app(PlancheOptions(
          expanded: expanded,
          onToggle: () => toggled = true,
          variante: 'Full',
          forme: 'Normal',
          elastique: 'Aucun',
          tension: 'N/A',
          variantes: kVariantes.keys.toList(),
          formes: kFormes.keys.toList(),
          elastiques: kElastiques.keys.toList(),
          tensions: kTensions.keys.toList(),
          onVariante: (_) {},
          onForme: (_) {},
          onElastique: (_) {},
          onTension: (_) {},
        ));
    await t.pumpWidget(build(false));
    expect(find.text('Variante'), findsNothing);
    await t.tap(find.text('Options planche'));
    expect(toggled, isTrue);
    await t.pumpWidget(build(true));
    expect(find.text('Variante'), findsOneWidget);
    final tension = t.widget<DropdownButtonFormField<String>>(
        find.widgetWithText(DropdownButtonFormField<String>, 'Tension'));
    expect(tension.onChanged, isNull);
  });

  testWidgets('confirmDelete renvoie le choix', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final f = confirmDelete(ctx, title: 'Supprimer ?', content: 'x');
    await t.pumpAndSettle();
    await t.tap(find.text('Supprimer'));
    await t.pumpAndSettle();
    expect(await f, isTrue);
  });
}
