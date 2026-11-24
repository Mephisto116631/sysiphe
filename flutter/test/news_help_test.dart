import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sysiphe/app_flavor.dart';
import 'package:sysiphe/models/changelog.dart';
import 'package:sysiphe/screens/settings/help_page.dart';
import 'package:sysiphe/widgets/news_dialog.dart';

const _log = [
  ChangelogEntry('2.21.0', '', 'C', ['c']),
  ChangelogEntry('2.20.0', '', 'B', ['b']),
  ChangelogEntry('2.18.0', '', 'Course', ['r'], courseOnly: true),
  ChangelogEntry('2.17.0', '', 'A', ['a']),
];

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(360, 780);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  group('nouveautés : quoi montrer', () {
    test('comparaison de versions', () {
      expect(versionLess('2.9.0', '2.10.0'), isTrue);
      expect(versionLess('2.20.0', '2.20.0'), isFalse);
      expect(versionLess('3.0.0', '2.99.9'), isFalse);
      expect(versionLess('dev', '2.0.0'), isFalse);
    });

    List<String> titles(String? seen, String cur, {bool course = false}) => [
          for (final e in unseenChangelog(
              lastSeen: seen, current: cur, course: course, log: _log))
            e.title
        ];

    test('depuis la dernière version vue, jusqu\'à l\'installée', () {
      expect(titles('2.17.0', '2.21.0'), ['C', 'B']); // sans Course
      expect(titles('2.17.0', '2.21.0', course: true), ['C', 'B', 'Course']);
      expect(titles('2.20.0', '2.20.0'), isEmpty);
      expect(titles('2.17.0', '2.20.0'), ['B']); // pas de version future
      expect(titles(null, '2.21.0'), ['C']); // première fois : la dernière
    });

    test('journal de l\'app : du plus récent au plus ancien, versions valides',
        () {
      for (var i = 1; i < kChangelog.length; i++) {
        expect(versionLess(kChangelog[i].version, kChangelog[i - 1].version),
            isTrue,
            reason: kChangelog[i].version);
      }
      expect(kChangelog.every((e) => e.items.isNotEmpty), isTrue);
    });
  });

  group('écrans', () {
    testWidgets('fenêtre après mise à jour, une seule fois', (t) async {
      SharedPreferences.setMockInitialValues({kNewsSeenKey: '2.19.0'});
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(
          home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      showNewsIfUpdated(ctx, current: '2.21.0+50');
      await t.pumpAndSettle();
      expect(find.text('Quoi de neuf ? 🎉'), findsOneWidget);
      expect(find.text('Nouveautés et mode d\'emploi'), findsOneWidget);
      expect(find.text('Ta photo de profil'), findsOneWidget);
      expect(find.text('Tes réglages en un fichier'), findsNothing); // déjà vue
      await t.tap(find.text('Super !'));
      await t.pumpAndSettle();
      showNewsIfUpdated(ctx, current: '2.21.0+50');
      await t.pumpAndSettle();
      expect(find.text('Quoi de neuf ? 🎉'), findsNothing);
      // Build local : jamais.
      SharedPreferences.setMockInitialValues({});
      showNewsIfUpdated(ctx, current: 'dev');
      await t.pumpAndSettle();
      expect(find.text('Quoi de neuf ? 🎉'), findsNothing);
    });

    testWidgets('pages Nouveautés et Mode d\'emploi à 360 px', (t) async {
      phone(t);
      await t.pumpWidget(const MaterialApp(home: NewsPage()));
      expect(find.text('Ta photo de profil'), findsOneWidget);
      // Le module Course n'apparaît que dans la version course.
      if (kCourse) {
        await t.scrollUntilVisible(find.text('Le module Course'), 200);
      } else {
        await t.drag(find.byType(ListView), const Offset(0, -3000));
        await t.pumpAndSettle();
        expect(find.text('Le module Course'), findsNothing);
      }
      await t.scrollUntilVisible(find.text('Le chrono qui enchaîne'), 200);
      expect(find.text('Le chrono qui enchaîne'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.pumpWidget(const MaterialApp(home: HelpPage()));
      expect(find.text('La course'), kCourse ? findsOneWidget : findsNothing);
      await t.tap(find.text('Chrono et repos'));
      await t.pumpAndSettle();
      expect(find.textContaining('repos démarre'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
