import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/models/profile.dart';
import 'package:sysiphe/screens/settings/account_page.dart';
import 'package:sysiphe/screens/settings/exercises_page.dart';
import 'package:sysiphe/screens/settings_screen.dart';
import 'package:sysiphe/services/role.dart';
import 'package:sysiphe/theme.dart';

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(360 * 3, 780 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  group('écran principal', () {
    Future<void> pump(WidgetTester t, {bool admin = false}) async {
      phone(t);
      isAdminNotifier.value = admin;
      addTearDown(() => isAdminNotifier.value = false);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: SettingsScreen(
          userId: 'u',
          profile: const Profile(id: 'u', name: 'Médhi', hasPin: true),
          loadSummary: () async => const SettingsSummary(
              weight: 82.5,
              enableCharges: false,
              reminderHour: 7,
              inactivityDays: 3,
              googleEmail: 'a@b.fr'),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('5 entrées avec leur résumé, sans Admin', (t) async {
      await pump(t);
      for (final e in [
        'Entraînement',
        'Exercices',
        'Rappels',
        'Compte et sécurité',
        'Application',
        'Changer de profil',
      ]) {
        expect(find.text(e), findsOneWidget, reason: e);
      }
      expect(find.text('Admin'), findsNothing);
      expect(find.text('Profil actif · 82.5 kg'), findsOneWidget);
      expect(find.text('Poids 82.5 kg · lest masqué'), findsOneWidget);
      expect(find.text('07:00 · après 3 jours sans séance'), findsOneWidget);
      expect(find.text('Google : a@b.fr · PIN · profils'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('entrée Admin pour un admin', (t) async {
      await pump(t, admin: true);
      expect(find.text('Admin'), findsOneWidget);
    });
  });

  group('page Exercices', () {
    Perf p(String ex, String c) => Perf(
        userId: 'u', date: DateTime(2026, 11, 1), exercice: ex, categorie: c);
    late List<Perf> perfs;
    late Set<String> assist;
    late List<String> calls;

    setUp(() {
      perfs = [
        p('Planche', 'Planche'),
        p('Handstand to diamond', 'Handstand'),
        p('HSPU Pompe hand stand', 'Musculation'),
        p('HSPU Pompe hand stand', 'Musculation'),
        p('Traction', 'Traction'),
        p('Abdos', 'Gainage'),
        p('Abdos', 'Musculation'),
      ];
      assist = {'Traction'};
      calls = [];
    });

    ExerciseOps ops() => ExerciseOps(
          loadPerfs: () async => perfs,
          loadAssistables: () async => assist,
          rename: (a, b) async {
            calls.add('rename $a→$b');
            perfs = [
              for (final x in perfs)
                x.exercice == a
                    ? Perf(
                        userId: 'u',
                        date: x.date,
                        exercice: b,
                        categorie: x.categorie)
                    : x
            ];
          },
          setCategory: (ex, c) async {
            calls.add('cat $ex→$c');
            perfs = [
              for (final x in perfs)
                x.exercice == ex ? x.copyWithCategorie(c) : x
            ];
          },
          saveAssistables: (a) async {
            calls.add('assist ${(a.toList()..sort()).join(',')}');
            assist = a;
          },
        );

    Future<void> pump(WidgetTester t) async {
      phone(t);
      await t.pumpWidget(
          MaterialApp(theme: AppTheme.light, home: ExercisesPage(ops: ops())));
      await t.pumpAndSettle();
    }

    testWidgets('liste : catégorie, séries, assistable, mélangé', (t) async {
      await pump(t);
      expect(find.text('Traction · 1 série · assistable'), findsOneWidget);
      expect(find.textContaining('Mélangé : '), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('fiche : catégorie proposée d\'après les autres', (t) async {
      await pump(t);
      await t.tap(find.text('HSPU Pompe hand stand'));
      await t.pumpAndSettle();
      await t.tap(find.text('Catégorie'));
      await t.pumpAndSettle();
      await t.tap(find.text('Proposée : Handstand'));
      await t.pump();
      await t.tap(find.text('Appliquer'));
      await t.pumpAndSettle();
      expect(calls, ['cat HSPU Pompe hand stand→Handstand']);
      expect(find.text('Handstand · 2 séries'), findsOneWidget);
    });

    testWidgets('fiche : renommer garde le réglage assistable', (t) async {
      await pump(t);
      await t.tap(find.text('Traction'));
      await t.pumpAndSettle();
      await t.tap(find.text('Renommer'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Tractions');
      await t.tap(find.text('Valider'));
      await t.pumpAndSettle();
      expect(calls, ['rename Traction→Tractions', 'assist Tractions']);
      expect(find.text('Tractions'), findsOneWidget);
      expect(find.text('Traction · 1 série · assistable'), findsOneWidget);
    });

    testWidgets('fiche : basculer assistable ; pas pour la planche', (t) async {
      await pump(t);
      await t.tap(find.text('Abdos'));
      await t.pumpAndSettle();
      await t.tap(find.text('Assistable'));
      await t.pumpAndSettle();
      expect(calls, ['assist Abdos,Traction']);
      await t.tap(find.text('Planche'));
      await t.pumpAndSettle();
      expect(find.text('Assistable'), findsNothing);
    });
  });

  group('Compte et sécurité', () {
    const moi = Profile(id: 'a', name: 'Médhi', hasPin: true);
    const autre = Profile(id: 'b', name: 'Dilbert', hasPin: false);

    Future<void> pump(WidgetTester t, {required bool admin}) async {
      phone(t);
      isAdminNotifier.value = admin;
      addTearDown(() => isAdminNotifier.value = false);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: AccountPage(
            current: moi, loadProfiles: () async => const [moi, autre]),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('suppression de profil cachée hors admin', (t) async {
      await pump(t, admin: false);
      expect(find.text('Dilbert'), findsOneWidget);
      expect(find.byTooltip('Supprimer'), findsNothing);
      expect(find.byTooltip('Renommer'), findsNWidgets(2));
    });

    testWidgets('admin : suppression proposée, sauf pour le profil actif',
        (t) async {
      await pump(t, admin: true);
      expect(find.byTooltip('Supprimer'), findsOneWidget);
    });
  });
}
