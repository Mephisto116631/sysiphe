import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/models/intensity.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/screens/settings/exercises_page.dart';
import 'package:sysiphe/services/chrono_fx.dart';
import 'package:sysiphe/services/profile_prefs.dart';
import 'package:sysiphe/services/rest_timer.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/rest_bar.dart';
import 'package:sysiphe/widgets/saisie/perf_tile.dart';

class FakeFx implements ChronoFx {
  final bips = <Bip>[];
  final said = <String>[];
  @override
  void bip(Bip b) => bips.add(b);
  @override
  void keepAwake(bool on) {}
  @override
  void say(String text) => said.add(text);
}

void main() {
  group('repos : son et durée réelle', () {
    late DateTime now;
    late FakeFx fx;
    late RestTimer r;

    Future<void> startWith(int mode) async {
      SharedPreferences.setMockInitialValues({kChronoSoundModeKey: mode});
      now = DateTime(2026, 11, 23, 18);
      fx = FakeFx();
      r = RestTimer(now: () => now, fx: fx);
      r.setSeconds(60);
      r.start();
      await Future<void>.delayed(const Duration(milliseconds: 20)); // son lu
    }

    void wait(int s) {
      now = now.add(Duration(seconds: s));
      r.tick();
    }

    tearDown(() => r.dispose());

    test('bips sur les 3 dernières secondes, bip long et voix à la fin',
        () async {
      await startWith(2);
      wait(57);
      wait(1);
      wait(1);
      wait(1); // fin
      expect(fx.bips, [Bip.court, Bip.court, Bip.court, Bip.depart]);
      expect(fx.said, ['Repos terminé']);
      expect(r.takeLastRest(), const RestTaken(60, 60));
      expect(r.takeLastRest(), isNull); // ne sert qu'une fois
    });

    test('bips seuls, puis muet', () async {
      await startWith(1);
      wait(60);
      expect(fx.bips, [Bip.depart]);
      expect(fx.said, isEmpty);
      await startWith(0);
      wait(60);
      expect(fx.bips, isEmpty);
    });

    test('« Passer » : durée réellement prise gardée, repos passé', () async {
      await startWith(0);
      wait(20);
      r.stop();
      final t = r.takeLastRest()!;
      expect(t, const RestTaken(20, 60));
      expect(t.skipped, isTrue);
    });

    test('+15 s compte dans la durée prévue', () async {
      await startWith(0);
      r.adjust(15);
      wait(75);
      expect(r.takeLastRest(), const RestTaken(75, 75));
    });

    test('série enregistrée pendant le repos : durée écoulée jusqu\'ici',
        () async {
      await startWith(0);
      wait(45);
      expect(r.takeLastRest(), const RestTaken(45, 60));
    });
  });

  test('Perf : repos lu et écrit, absent du JSON s\'il est inconnu', () {
    final p = Perf.fromJson({
      'user_id': 'u',
      'date': '2026-11-23',
      'exercice': 'Traction',
      'repos_s': 20,
      'repos_prevu_s': 90,
    });
    expect(p.reposS, 20);
    expect(p.reposPasse, isTrue);
    expect(p.toJson()['repos_s'], 20);
    final sans = Perf(userId: 'u', date: DateTime(2026), exercice: 'x');
    expect(sans.toJson().containsKey('repos_s'), isFalse);
    expect(sans.toJson().containsKey('repos_prevu_s'), isFalse);
  });

  group('couleurs d\'intensité', () {
    test('automatique : relatif au meilleur effort (comme avant)', () {
      const c = IntensityConfig();
      expect(c.auto, isTrue);
      expect(c.ratio(50, best: 100), 0.5);
      expect(c.ratio(150, best: 100), 1);
    });

    test('seuils du profil : orange et rouge aux bons points', () {
      const c = IntensityConfig(orange: 40, rouge: 80);
      expect(c.ratio(20, best: 999), 0.25);
      expect(c.ratio(40, best: 999), 0.5); // orange
      expect(c.ratio(60, best: 999), 0.75);
      expect(c.ratio(80, best: 999), 1); // rouge
      expect(c.colorFor(80, best: 1), intensityColor(1));
      expect(c.toSettings(), {'orange': 40, 'rouge': 80});
      expect(IntensityConfig.fromSettings({'orange': 40, 'rouge': 80}).auto,
          isFalse);
      expect(const IntensityConfig(orange: 80, rouge: 40).auto, isTrue);
    });
  });

  group('écrans', () {
    void phone(WidgetTester t) {
      t.view.physicalSize = const Size(360 * 3, 780 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
    }

    testWidgets('bandeau de repos compact : une ligne, Passer', (t) async {
      phone(t);
      var skipped = 0;
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: RestBar(
            seconds: 90,
            onConfig: (_) {},
            left: ValueNotifier(const Duration(seconds: 84)),
            onSkip: () => skipped++,
            onAdjust: (_) {},
          ),
        ),
      ));
      expect(t.getSize(find.byType(RestBar)).height, lessThan(60));
      await t.tap(find.text('Passer'));
      expect(skipped, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('série : « repos passé » en orange', (t) async {
      phone(t);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PerfTile(
            perf: Perf(
                id: 1,
                userId: 'u',
                date: DateTime(2026, 11, 23),
                exercice: 'Traction',
                serie: 2,
                performance: 12,
                unite: 'Reps',
                reposS: 20,
                reposPrevuS: 90),
            onDelete: () {},
            onEdit: () {},
          ),
        ),
      ));
      expect(
          find.textContaining('repos passé (0:20 / 1:30)', findRichText: true),
          findsOneWidget);
    });

    testWidgets('fiche Planche : activer / désactiver, Modèle, intensité',
        (t) async {
      phone(t);
      addTearDown(() {
        Perf.plancheEnabled = true;
        plancheEnabledNotifier.value = true;
      });
      final saved = <Map<String, dynamic>>[];
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: ExercisesPage(
          ops: ExerciseOps(
            loadPerfs: () async => [
              Perf(
                  userId: 'u',
                  date: DateTime(2026, 11, 1),
                  exercice: 'Traction',
                  unite: 'Reps')
            ],
            loadAssistables: () async => {},
            rename: (_, __) async {},
            setCategory: (_, __) async {},
            saveAssistables: (_) async {},
            saveSettings: (m) async => saved.add(m),
            userId: 'u',
          ),
        ),
      ));
      await t.pumpAndSettle();
      // Pas encore de planche : la fiche est là pour pouvoir l'activer.
      expect(find.text('Planche'), findsOneWidget);
      await t.tap(find.text('Planche'));
      await t.pumpAndSettle();
      expect(find.text('Modèle de la planche'), findsOneWidget);
      expect(find.text('Couleurs d\'intensité'), findsOneWidget);
      expect(find.text('Renommer'), findsNothing);
      await t.tap(find.text('Activer la planche'));
      await t.pumpAndSettle();
      expect(saved.single, {'include_planche': false});
      expect(Perf.plancheEnabled, isFalse);
      expect(Perf.isPlancheName('Planche'), isFalse); // exercice ordinaire
      expect(find.text('Planche désactivée'), findsWidgets); // liste + message
    });
  });
}
