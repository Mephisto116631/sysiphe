import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/theme.dart';
import 'package:sysiphe/widgets/saisie/new_exercice_dialog.dart';

void main() {
  final rangement = {
    'Planche': 'Planche',
    'HSPU Pompe hand stand': 'Handstand',
    'Handstand to diamond': 'Handstand',
    'Pompe': 'Pompe',
    'Pompes': 'Pompe',
  };

  testWidgets('nouvel exercice : catégorie proposée pendant la frappe',
      (t) async {
    t.view.physicalSize = const Size(360 * 3, 780 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    (String, String, String)? res;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => res = await showDialog(
                context: ctx,
                builder: (_) => NewExerciceDialog(
                    existing: rangement.keys.toList(), categories: rangement)),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    final nom = find.widgetWithText(TextFormField, 'Nom');
    final cat = find.widgetWithText(TextFormField, 'Catégorie');
    String catText() => t.widget<TextFormField>(cat).controller!.text;

    await t.enterText(nom, 'Pompe de handstand');
    await t.pump();
    expect(catText(), 'Handstand');
    expect(find.text('Proposée d\'après tes exercices'), findsOneWidget);

    await t.enterText(nom, 'Muscle up');
    await t.pump();
    expect(catText(), 'Musculation'); // rien de connu : défaut selon l'unité

    // Choix manuel : plus de proposition ensuite.
    await t.tap(find.widgetWithText(ChoiceChip, 'Pompe'));
    await t.pump();
    await t.enterText(nom, 'Handstand PU');
    await t.pump();
    expect(catText(), 'Pompe');
    await t.tap(find.text('Créer'));
    await t.pumpAndSettle();
    expect(res, ('Handstand PU', 'Reps', 'Pompe'));
    expect(t.takeException(), isNull);
  });
}
