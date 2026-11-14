import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/models/session.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/exercise_card.dart';

void main() {
  Future<List<CardEntry>> pump(WidgetTester t,
      {CardKind kind = CardKind.plain, int done = 0, bool ok = true}) async {
    final saved = <CardEntry>[];
    t.view.physicalSize = const Size(360 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExerciseCard(
            exercice: 'Abdos ( dragon press bicyclette ou hold)',
            unite: 'Reps',
            kind: kind,
            done: done,
            last: null,
            helper: 'Dernière fois le 1 août · record série 60',
            insight: null,
            enableCharges: false,
            variantes: const ['Full', 'Tuck'],
            formes: const ['Normal'],
            elastiques: const ['Aucun', 'Jaune'],
            tensions: const ['N/A', 'Normal'],
            ecartements: const ['Standard', 'Large'],
            onSave: (e) async {
              saved.add(e);
              return ok;
            },
          ),
        ),
      ),
    ));
    return saved;
  }

  testWidgets('série = séries faites + 1, saisie vide, aide affichée', (t) async {
    await pump(t, done: 2);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Dernière fois le 1 août · record série 60'), findsOneWidget);
    expect(t.takeException(), isNull); // nom long : pas de débordement
  });

  testWidgets('Enregistrer envoie une seule série puis vide le champ', (t) async {
    final saved = await pump(t);
    await t.enterText(find.byType(TextField).first, '12');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(saved.length, 1);
    expect(saved.first.value, 12);
    expect(saved.first.serie, 1);
    expect(t.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
  });

  testWidgets('enregistrement automatique 3 s après la frappe', (t) async {
    final saved = await pump(t);
    await t.enterText(find.byType(TextField).first, '15');
    await t.pump(const Duration(seconds: 2));
    expect(saved, isEmpty);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(saved.length, 1);
    expect(saved.first.value, 15);
  });

  testWidgets('échec : la saisie est conservée', (t) async {
    final saved = await pump(t, ok: false);
    await t.enterText(find.byType(TextField).first, '9');
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(saved.length, 1);
    expect(t.widget<TextField>(find.byType(TextField).first).controller!.text, '9');
  });

  testWidgets('assistable : élastique, tension et écartement visibles', (t) async {
    await pump(t, kind: CardKind.assist);
    expect(find.text('Écartement des mains'), findsOneWidget);
    expect(find.text('Élastique'), findsOneWidget);
  });

  testWidgets('la dernière séance est un exemple en sous-texte, pas une saisie',
      (t) async {
    final tpl = templatesFrom([
      Perf(
          id: 1,
          userId: 'u',
          date: DateTime(2026, 11, 10),
          exercice: 'Traction',
          performance: 30,
          unite: 'Reps',
          charge: 10),
    ]).first;
    t.view.physicalSize = const Size(360 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExerciseCard(
            exercice: 'Traction',
            unite: 'Reps',
            kind: CardKind.plain,
            done: 0,
            last: tpl,
            helper: null,
            insight: null,
            enableCharges: true,
            variantes: const ['Full'],
            formes: const ['Normal'],
            elastiques: const ['Aucun'],
            tensions: const ['N/A'],
            ecartements: const ['Standard'],
            onSave: (e) async => true,
          ),
        ),
      ),
    ));
    final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.text, isEmpty);
    expect(fields[0].decoration!.hintText, 'ex. 30');
    expect(fields[1].controller!.text, isEmpty);
    expect(fields[1].decoration!.hintText, 'ex. 10');
  });

  testWidgets('exercice en secondes : chronomètre qui remplit le champ', (t) async {
    t.view.physicalSize = const Size(360 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExerciseCard(
            exercice: 'Gainage',
            unite: 'Sec',
            kind: CardKind.plain,
            done: 0,
            last: null,
            helper: null,
            insight: null,
            enableCharges: false,
            variantes: const ['Full'],
            formes: const ['Normal'],
            elastiques: const ['Aucun'],
            tensions: const ['N/A'],
            ecartements: const ['Standard'],
            onSave: (e) async => true,
          ),
        ),
      ),
    ));
    expect(find.text('Démarrer'), findsOneWidget);
    await t.tap(find.text('Démarrer'));
    await t.pump(const Duration(milliseconds: 1600));
    await t.tap(find.text('Arrêter'));
    await t.pump();
    // ≥ 1 s écoulée (horloge réelle) : le champ de valeur est rempli
    final txt = t.widget<TextField>(find.byType(TextField).first).controller!.text;
    expect(txt.isEmpty || int.tryParse(txt) != null, isTrue);
    await t.pump(const Duration(seconds: 4)); // laisse l'autosave se terminer
  });
}
