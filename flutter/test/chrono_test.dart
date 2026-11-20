import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/services/chrono_fx.dart';
import 'package:sysiphe/services/rest_timer.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/chrono.dart';

class FakeFx implements ChronoFx {
  final bips = <Bip>[];
  final awake = <bool>[];
  @override
  void bip(Bip b) => bips.add(b);
  @override
  void keepAwake(bool on) => awake.add(on);
  final said = <String>[];
  @override
  void say(String text) => said.add(text);
}

void main() {
  late FakeFx fx;
  setUp(() => fx = FakeFx());

  Future<void> pump(WidgetTester t, DateTime Function() now, List<int> got,
      {int pre = 0, Map<String, Object> extra = const {}, String? exo}) async {
    SharedPreferences.setMockInitialValues({kChronoPreKey: pre, ...extra});
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
          body: SingleChildScrollView(
              child: Chrono(now: now, onStop: got.add, exercice: exo, fx: fx))),
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

  testWidgets('bips : 3 derniers tics de la préparation, départ, objectif',
      (t) async {
    var now = DateTime(2026, 11, 17, 10);
    await pump(t, () => now, <int>[], pre: 5, extra: {kChronoTargetKey: 10});
    await t.tap(find.text('Démarrer'));
    await t.pump();
    expect(fx.awake, [true]); // écran maintenu allumé
    for (var i = 0; i < 16; i++) {
      now = now.add(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 100));
    }
    // préparation : 3, 2, 1 → départ ; objectif : 3, 2, 1 → atteint
    expect(fx.bips, [
      Bip.court, Bip.court, Bip.court, Bip.depart, //
      Bip.court, Bip.court, Bip.court, Bip.objectif,
    ]);
    await t.tap(find.text('Arrêter'));
    await t.pump(const Duration(seconds: 1));
    expect(fx.awake, [true, false]);
  });

  testWidgets('son : voix → bips → muet, choix mémorisé', (t) async {
    var now = DateTime(2026, 11, 17, 10);
    await pump(t, () => now, <int>[], pre: 3);
    await t.tap(find.byIcon(Icons.record_voice_over)); // voix (défaut) → bips
    await t.pump();
    await t.tap(find.byIcon(Icons.volume_up)); // bips → muet
    await t.pump();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance()).getInt(kChronoSoundModeKey), 0);
    await t.tap(find.text('Démarrer'));
    await t.pump();
    now = now.add(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 100));
    expect(fx.bips, isEmpty);
    expect(fx.said, isEmpty);
  });

  testWidgets('ancien réglage « bips coupés » repris en muet', (t) async {
    final now = DateTime(2026, 11, 17, 10);
    await pump(t, () => now, <int>[], extra: {kChronoSoundKey: false});
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
  });

  testWidgets('annonces vocales : 10 secondes, objectif, minutes', (t) async {
    var now = DateTime(2026, 11, 17, 10);
    await pump(t, () => now, <int>[], extra: {kChronoTargetKey: 30});
    await t.tap(find.text('Démarrer'));
    await t.pump();
    for (var i = 0; i < 95; i++) {
      now = now.add(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(fx.said, ['10 secondes', 'Objectif atteint', '1 minute']);
    await t.tap(find.text('Arrêter'));
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('plein écran : gros chiffres, Arrêter ferme et renvoie le temps',
      (t) async {
    var now = DateTime(2026, 11, 17, 10);
    final got = <int>[];
    await pump(t, () => now, got);
    await t.tap(find.text('Démarrer'));
    await t.pump();
    await t.tap(find.byIcon(Icons.fullscreen));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chrono-full-time')), findsOneWidget);
    now = now.add(const Duration(seconds: 42));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('0:42.0'), findsWidgets);
    await t.tap(find.text('Arrêter').last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chrono-full-time')), findsNothing);
    expect(got, [42]);
    // dernier choix repris : la série suivante s'ouvre en plein écran
    expect(
        (await SharedPreferences.getInstance()).getBool(kChronoFullKey), true);
    await t.tap(find.text('Démarrer'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chrono-full-time')), findsOneWidget);
    await t.tap(find.byTooltip('Réduire'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('chrono-full-time')), findsNothing);
    expect(find.text('Arrêter'), findsOneWidget); // la série continue
    expect(
        (await SharedPreferences.getInstance()).getBool(kChronoFullKey), false);
    await t.tap(find.text('Arrêter'));
    await t.pump();
  });

  group('enchaînement', () {
    testWidgets('3 séries : enregistrement, repos, relance automatique',
        (t) async {
      var now = DateTime(2026, 11, 19, 10);
      SharedPreferences.setMockInitialValues(
          {kChronoPreKey: 0, chronoSetsKey('Planche'): 3});
      final rest = RestTimer(now: () => now);
      rest.setSeconds(60);
      final saved = <int>[];
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Chrono(
              now: () => now,
              exercice: 'Planche',
              fx: fx,
              rest: rest,
              onStop: (_) => fail('pas d\'onStop en enchaînement'),
              onChainStop: (sec) async {
                saved.add(sec);
                rest.start(); // la Saisie lance le repos après l'enregistrement
                return true;
              },
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('3'), findsOneWidget); // puce « Séries : 3 » choisie

      Future<void> wait(int sec) async {
        now = now.add(Duration(seconds: sec));
        rest.tick();
        await t.pump(const Duration(milliseconds: 100));
      }

      await t.tap(find.text('Démarrer'));
      await t.pump();
      expect(fx.said, ['Série 1 sur 3']);
      await wait(20);
      await t.tap(find.text('Arrêter'));
      await t.pump();
      await t.pump();
      expect(saved, [20]);
      expect(find.text('Passer'), findsOneWidget); // en repos
      expect(find.textContaining('série 2/3 ensuite'), findsOneWidget);
      await wait(61); // fin du repos → série 2 relancée seule
      await t.pump();
      expect(find.text('Arrêter'), findsOneWidget);
      expect(fx.said.last, 'Série 2 sur 3');
      await wait(25);
      await t.tap(find.text('Arrêter'));
      await t.pump();
      await t.pump();
      // « Passer » saute le repos.
      await t.tap(find.text('Passer'));
      await t.pump();
      await t.pump();
      expect(fx.said.last, 'Série 3 sur 3');
      await wait(30);
      await t.tap(find.text('Arrêter'));
      await t.pump();
      await t.pump();
      expect(saved, [20, 25, 30]);
      expect(fx.said.last, 'Terminé, bravo');
      expect(find.text('Démarrer'), findsOneWidget);
      expect(fx.awake.last, false);
      rest.dispose();
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('plein écran : toucher l\'écran arrête la série', (t) async {
      var now = DateTime(2026, 11, 19, 10);
      final got = <int>[];
      await pump(t, () => now, got, extra: {kChronoFullKey: true});
      await t.tap(find.text('Démarrer'));
      await t.pumpAndSettle();
      expect(find.text('Touche l\'écran pour arrêter'), findsOneWidget);
      now = now.add(const Duration(seconds: 12));
      await t.pump(const Duration(milliseconds: 100));
      await t.tapAt(const Offset(200, 300)); // au milieu, pas sur un bouton
      await t.pumpAndSettle();
      expect(got, [12]);
      expect(find.byKey(const ValueKey('chrono-full-time')), findsNothing);
    });
  });
}
