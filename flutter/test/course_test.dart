import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/app_flavor.dart';
import 'package:sysiphe/models/course.dart';
import 'package:sysiphe/screens/course_screen.dart';
import 'package:sysiphe/services/chrono_fx.dart';
import 'package:sysiphe/services/course_tracker.dart';
import 'package:sysiphe/services/offline_store.dart';
import 'package:sysiphe/services/update_service.dart';
import 'package:sysiphe/widgets/course_map.dart';

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

/// Faux GPS : les positions sont poussées par le test.
class FakeSource implements PositionSource {
  final ctrl = StreamController<GpsPoint>.broadcast();
  String? error;
  @override
  Future<String?> prepare() async => error;
  @override
  Stream<GpsPoint> positions() => ctrl.stream;
}

const _mPerDegLat = 111195.0;
final _t0 = DateTime(2026, 11, 24, 8);

/// Point à [meters] au nord du départ, [s] secondes après le départ.
GpsPoint at(double meters, double s, {double? alt, double accuracy = 5}) =>
    GpsPoint(48.85 + meters / _mPerDegLat, 2.35,
        _t0.add(Duration(milliseconds: (s * 1000).round())),
        alt: alt, accuracy: accuracy);

/// Course régulière : [speed] m/s pendant [seconds], un point par seconde.
List<GpsPoint> run(double speed, int seconds,
        {double from = 0, double startS = 0}) =>
    [for (var i = 0; i <= seconds; i++) at(from + speed * i, startS + i)];

void main() {
  group('calculs', () {
    test('haversine : 1° de latitude ≈ 111 km', () {
      expect(haversine(48, 2, 49, 2), closeTo(_mPerDegLat, 50));
      expect(haversine(48, 2, 48, 2), 0);
    });

    test('distance, temps et km : 2,1 km à 4 m/s', () {
      final acc = TrackAccumulator(autoPause: false);
      final events = <TrackEvent>[];
      for (final p in run(4, 525)) {
        events.addAll(acc.add(p));
      }
      expect(acc.distance, closeTo(2100, 2));
      expect(acc.movingS, 525);
      expect(events, [const KmReached(1, 250), const KmReached(2, 250)]);
      expect(acc.splits, [250, 250]);
      expect(acc.trace.length, greaterThan(150)); // un point tous les ~10 m
    });

    test('points imprécis et sauts GPS ignorés', () {
      final acc = TrackAccumulator(autoPause: false);
      acc.add(at(0, 0));
      acc.add(at(4, 1));
      acc.add(at(500, 2, accuracy: 60)); // imprécis
      acc.add(at(300, 3)); // saut de 296 m en 2 s
      acc.add(at(12, 3));
      expect(acc.distance, closeTo(12, 0.5));
    });

    test('pause automatique au feu rouge, puis reprise', () {
      final acc = TrackAccumulator();
      final events = <TrackEvent>[];
      for (final p in [
        ...run(3, 60), // 180 m
        for (var i = 1; i <= 30; i++) at(180, 60.0 + i), // arrêt 30 s
        ...run(3, 60, from: 180, startS: 90).skip(1),
      ]) {
        events.addAll(acc.add(p));
      }
      expect(events.whereType<AutoPaused>().length, 1);
      expect(events.whereType<AutoResumed>().length, 1);
      // Le temps arrêté ne compte presque pas (5 s avant la pause).
      expect(acc.movingS, inInclusiveRange(120, 127));
      expect(acc.distance, closeTo(357, 4));
    });

    test('sans pause automatique, l\'arrêt compte dans le temps', () {
      final acc = TrackAccumulator(autoPause: false);
      for (final p in [
        ...run(3, 10),
        for (var i = 1; i <= 20; i++) at(30, 10.0 + i),
      ]) {
        acc.add(p);
      }
      expect(acc.movingS, 30);
    });

    test('pause manuelle : la distance pendant la pause n\'est pas comptée', () {
      final acc = TrackAccumulator(autoPause: false);
      for (final p in run(3, 10)) {
        acc.add(p);
      }
      acc.breakSegment();
      for (final p in run(3, 10, from: 500, startS: 100)) {
        acc.add(p);
      }
      expect(acc.distance, closeTo(60, 1));
      expect(acc.movingS, 20);
    });

    test('dénivelé positif lissé (bruit de ±1 m ignoré)', () {
      final acc = TrackAccumulator(autoPause: false);
      final alts = <double>[100, 101, 100, 101, 104, 103, 108, 107, 110];
      for (var i = 0; i < alts.length; i++) {
        acc.add(at(i * 3.0, i.toDouble(), alt: alts[i]));
      }
      // Montées comptées par paliers de 3 m : 100 → 104 → 108 ; les 2 m
      // suivants (110) attendent le palier suivant.
      expect(acc.elevationGain, closeTo(8, 0.01));
    });

    test('meilleur temps sur une distance (fenêtre glissante)', () {
      // 1 km à 5 m/s puis 1 km à 4 m/s : meilleur km = 200 s.
      final acc = TrackAccumulator(autoPause: false);
      for (final p in [...run(5, 200), ...run(4, 250, from: 1000, startS: 200).skip(1)]) {
        acc.add(p);
      }
      final t = acc.finalTrace();
      expect(bestEffort(t, 1000), closeTo(200, 2));
      expect(bestEffort(t, 5000), isNull);
    });

    test('records : 1 km, 5 km, 10 km, plus longue', () {
      Course c(double speed, int s) {
        final acc = TrackAccumulator(autoPause: false);
        for (final p in run(speed, s)) {
          acc.add(p);
        }
        return Course(
            userId: 'u',
            debut: _t0,
            distanceM: acc.distance.round(),
            dureeS: acc.movingS.round(),
            dureeTotaleS: acc.movingS.round(),
            trace: acc.finalTrace());
      }

      final r = courseRecords([c(3, 400), c(4, 1300)]);
      expect(r.map((e) => e.label), ['1 km', '5 km', '10 km', 'Plus longue']);
      expect(r[0].timeS, closeTo(250, 2)); // à 4 m/s
      expect(r[1].timeS, closeTo(1250, 3));
      expect(r[2].timeS, isNull);
      expect(r[3].meters, closeTo(5200, 3));
    });

    test('objectif distance / durée', () {
      const d = CourseGoal(GoalType.distance, 5000);
      expect(d.reached(4999, 0), isFalse);
      expect(d.reached(5000, 0), isTrue);
      expect(d.progress(2500, 0), 0.5);
      const t = CourseGoal(GoalType.duree, 1800);
      expect(t.reached(0, 1800), isTrue);
      expect(CourseGoal.none.progress(1, 1), isNull);
      expect(CourseGoal.fromJson(d.toJson()).value, 5000);
      expect(CourseGoal.fromJson(null).type, GoalType.aucun);
    });

    test('formats et annonce vocale', () {
      expect(formatDuration(65), '1:05');
      expect(formatDuration(3725), '1:02:05');
      expect(formatKm(5230), '5,23 km');
      expect(formatPace(332), '5\'32"');
      expect(formatPace(null), '–\'––"');
      expect(kmAnnouncement(1, 332), '1 kilomètre, 5 minutes 32');
      expect(kmAnnouncement(3, 300), '3 kilomètres, 5 minutes');
    });

    test('Course : aller-retour JSON', () {
      final c = Course(
        id: 4,
        userId: 'u',
        clientId: 'abc',
        debut: _t0,
        distanceM: 5230,
        dureeS: 1700,
        dureeTotaleS: 1800,
        deniveleM: 12,
        splitsS: const [330, 325],
        trace: const [TracePoint(48.85, 2.35, 0, 0), TracePoint(48.86, 2.35, 1112, 330)],
        objectif: const CourseGoal(GoalType.distance, 5000),
      );
      final j = c.toJson();
      expect(j['date'], '2026-11-24');
      final back = Course.fromJson(j);
      expect(back.distanceM, 5230);
      expect(back.splitsS, [330, 325]);
      expect(back.trace.last.m, 1112);
      expect(back.objectif.type, GoalType.distance);
      expect(back.paceS, closeTo(325, 1));
      expect(back.debut, _t0);
    });

    test('distance par semaine', () {
      Course c(DateTime d, int m) =>
          Course(userId: 'u', debut: d, distanceM: m, dureeS: 1, dureeTotaleS: 1);
      final w = weeklyDistance([
        c(DateTime(2026, 11, 24), 5000), // mardi
        c(DateTime(2026, 11, 29), 3000), // dimanche, même semaine
        c(DateTime(2026, 11, 30), 2000), // lundi suivant
      ]);
      expect(w[DateTime(2026, 11, 23)], 8000);
      expect(w[DateTime(2026, 11, 30)], 2000);
    });
  });

  group('suivi', () {
    late FakeSource src;
    late FakeFx fx;
    late DateTime now;
    late CourseTracker t;

    setUp(() {
      src = FakeSource();
      fx = FakeFx();
      now = _t0;
      t = CourseTracker(
          source: src, fx: fx, now: () => now, soundMode: () async => 2);
    });

    Future<void> push(List<GpsPoint> pts) async {
      for (final p in pts) {
        now = p.t;
        src.ctrl.add(p);
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('annonces : départ, km, objectif, fin', () async {
      expect(await t.start(goal: const CourseGoal(GoalType.distance, 1000)),
          isNull);
      await push(run(4, 300));
      expect(fx.said, [
        'Course démarrée',
        '1 kilomètre, 4 minutes 10',
        'Objectif atteint',
      ]);
      expect(fx.bips, [Bip.objectif]);
      final c = t.finish('u');
      expect(c.distanceM, 1200);
      expect(c.splitsS, [250]);
      expect(c.clientId, isNotNull);
      expect(fx.said.last, 'Course terminée, 1,20 km');
      t.dispose();
    });

    test('muet : aucune annonce', () async {
      t = CourseTracker(source: src, fx: fx, now: () => now, soundMode: () async => 0);
      await t.start();
      await push(run(4, 300));
      expect(fx.said, isEmpty);
      t.dispose();
    });

    test('permission refusée : pas de départ', () async {
      src.error = 'Autorise la localisation';
      expect(await t.start(), 'Autorise la localisation');
      expect(t.state, TrackState.pret);
    });

    test('pause manuelle puis reprise', () async {
      await t.start(autoPause: false);
      await push(run(3, 10));
      t.pause();
      await push(run(3, 10, from: 30, startS: 10).skip(1).toList());
      t.resume();
      await push(run(3, 10, from: 60, startS: 20));
      final c = t.finish('u');
      expect(c.distanceM, 60);
      expect(c.dureeS, 20);
      expect(fx.said, containsAllInOrder(['Pause', 'Reprise']));
      t.dispose();
    });
  });

  group('hors ligne', () {
    test('course en attente, puis envoyée', () {
      final s = OfflineStore.memory()..clearForTest();
      final c = Course(
          userId: 'u', clientId: 'x', debut: _t0, distanceM: 3000, dureeS: 900, dureeTotaleS: 950);
      final id = s.enqueueCourse('u', c.toJson());
      expect(id, lessThan(0));
      expect(s.courses('u').single.pending, isTrue);
      expect(s.pendingCount('u'), 1);
      final op = s.outbox.single;
      expect(op.kind, 'course_insert');
      s.done(op);
      s.addCourse('u', {...c.toJson(), 'id': 7});
      expect(s.courses('u').single.id, 7);
      s.deleteCourse('u', 7);
      expect(s.courses('u'), isEmpty);
      expect(s.outbox.single.kind, 'course_delete');
    });

    test('course en attente supprimée : retirée de la file', () {
      final s = OfflineStore.memory()..clearForTest();
      final id = s.enqueueCourse('u',
          Course(userId: 'u', debut: _t0, distanceM: 1, dureeS: 1, dureeTotaleS: 1).toJson());
      s.deleteCourse('u', id);
      expect(s.outbox, isEmpty);
      expect(s.courses('u'), isEmpty);
    });
  });

  group('deux APK', () {
    final release = {
      'body': 'Build 2.18.0+60 — commit abc',
      'assets': [
        {'name': 'sysiphe.apk', 'size': 1, 'browser_download_url': 'u/sysiphe.apk'},
        {'name': 'sysiphe-course.apk', 'size': 2, 'browser_download_url': 'u/sysiphe-course.apk'},
      ],
    };

    test('chaque version prend son APK', () {
      final std = parseRelease(release, apkName: 'sysiphe.apk')!;
      final crs = parseRelease(release, apkName: 'sysiphe-course.apk')!;
      expect(std.apkUrl, 'u/sysiphe.apk');
      expect(crs.apkUrl, 'u/sysiphe-course.apk');
      expect(std.fileName, 'sysiphe-2.18.0+60.apk');
      expect(crs.fileName, 'sysiphe-course-2.18.0+60.apk');
      // Par défaut : l'APK de la version compilée.
      expect(parseRelease(release)!.apkUrl, 'u/$kApkName');
    });

    test('ancienne Release sans APK course : pas de bascule', () {
      final old = {
        ...release,
        'assets': [release['assets']! as List].expand((l) => l).take(1).toList(),
      };
      expect(parseRelease(old, apkName: 'sysiphe-course.apk'), isNull);
      expect(parseRelease(old, apkName: 'sysiphe.apk'), isNotNull);
    });
  });

  group('écran', () {
    setUpAll(() async {
      await initializeDateFormatting('fr_FR');
      CourseMap.tilesEnabled = false;
    });
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('départ, 1,2 km, fin et enregistrement', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final src = FakeSource();
      final fx = FakeFx();
      var now = _t0;
      final tracker = CourseTracker(
          source: src, fx: fx, now: () => now, soundMode: () async => 2);
      final saved = <Course>[];
      final ops = CourseOps(
        () async => saved,
        (c) async {
          saved.add(c);
          return false; // hors ligne
        },
        (c) async => saved.remove(c),
      );
      await tester.pumpWidget(MaterialApp(
          home: CourseScreen(userId: 'u', tracker: tracker, ops: ops)));
      await tester.pumpAndSettle();
      expect(find.text('Aucune course pour l\'instant.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('course-start')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Recherche du signal GPS…'), findsOneWidget);

      for (final p in run(4, 300)) {
        now = p.t;
        src.ctrl.add(p);
        await tester.pump();
      }
      expect(find.text('1,20 km'), findsOneWidget);
      expect(fx.said, contains('1 kilomètre, 4 minutes 10'));
      expect(tester.takeException(), isNull); // pas de débordement à 360 px

      // Un appui court ne termine pas.
      await tester.tap(find.byKey(const ValueKey('course-stop')));
      await tester.pump();
      expect(tracker.active, isTrue);
      await tester.longPress(find.byKey(const ValueKey('course-stop')));
      await tester.pumpAndSettle();
      expect(find.text('Temps par km'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('course-save')));
      await tester.pumpAndSettle();
      expect(saved.single.distanceM, 1200);
      expect(find.text('Enregistrée hors ligne ✓ (envoi automatique)'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('course-start')), findsOneWidget);
      tracker.dispose();
    });
  });
}
