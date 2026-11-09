import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sysiphe/models/perf.dart';
import 'package:sysiphe/screens/model_screen.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final history = [
    Perf(userId: 'u', date: DateTime(2026, 8, 1), exercice: 'Planche',
        variante: 'Straddle', forme: 'Normal', elastique: 'Jaune',
        tension: 'Serré', performance: 12, unite: 'Sec', effortPondere: 80),
    Perf(userId: 'u', date: DateTime(2026, 8, 1), exercice: 'Planche',
        variante: 'Tuck', forme: 'Normal', elastique: 'Aucun',
        tension: 'N/A', performance: 25, unite: 'Sec', effortPondere: 30),
  ];

  // La page défile verticalement ; la grille, horizontalement.
  final page = find.byType(Scrollable).first;

  Future<void> pump(WidgetTester t) async {
    // Écran de téléphone (360 × 780 dp) : détecte les débordements.
    t.view.physicalSize = const Size(360 * 3, 780 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: ModelScreen(
        userId: 'u',
        loader: () async => (<String, dynamic>{'weight': 97}, history),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('affiche grille, impact, sans débordement', (t) async {
    await pump(t);
    expect(find.text('Grille des efforts'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.text('Impact sur ton historique'), 300,
        scrollable: page);
    expect(find.textContaining('2 séries de planche'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('modifier le poids recalcule et propose « Appliquer »', (t) async {
    await pump(t);
    expect(find.textContaining('séries changent'), findsNothing);
    await t.enterText(find.widgetWithText(TextField, 'kg'), '80');
    await t.pumpAndSettle();
    expect(find.textContaining('séries changent'), findsOneWidget); // bouton
    expect(find.textContaining('Brouillon'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('toucher une case affiche le détail du calcul', (t) async {
    await pump(t);
    // Case Full × Normal, 10 s, sans élastique, 97 kg (valeur calculée)
    final e = calculerEffort(variante: 'Full', forme: 'Normal', elastique: 'Aucun',
        tension: 'N/A', temps: 10, weight: 97);
    // La case dans la grille (premier tableau), ramenée à l'écran.
    final cell = find
        .descendant(of: find.byType(Table).first, matching: find.text('$e'))
        .first;
    await t.ensureVisible(cell);
    await t.pumpAndSettle();
    await t.tap(cell);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Détail : Full · Normal'), 300,
        scrollable: page);
    expect(find.text('Facteur de difficulté'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('générateur des formes : 34 × 1,4 retrouvé, régénération',
      (t) async {
    await pump(t);
    await t.tap(find.text('Formes'));
    await t.pumpAndSettle();
    // Paramètres déduits des valeurs par défaut
    expect(find.widgetWithText(TextField, '34'), findsWidgets);
    expect(find.widgetWithText(TextField, '1.4'), findsOneWidget);
    // Multiplicateur 1,5 → Normal = 51
    await t.enterText(find.widgetWithText(TextField, '1.4'), '1.5');
    await t.pumpAndSettle();
    final gen = find.text('Générer les formes');
    await t.ensureVisible(gen);
    await t.pumpAndSettle();
    await t.tap(gen);
    await t.pumpAndSettle();
    // Le bouton « Appliquer » (barre du bas, toujours construite) apparaît.
    expect(find.textContaining('séries changent'), findsOneWidget);
    expect(find.widgetWithText(TextField, '51'), findsOneWidget); // Normal
    expect(t.takeException(), isNull);
  });

  testWidgets('modifier un coefficient garde la section ouverte (régression)',
      (t) async {
    await pump(t);
    await t.tap(find.text('Variantes'));
    await t.pumpAndSettle();
    // Premier chiffre tapé : le brouillon apparaît…
    await t.enterText(find.widgetWithText(TextField, 'Full'), '12');
    await t.pumpAndSettle();
    expect(find.textContaining('séries changent'), findsOneWidget);
    // …et la section reste ouverte avec la saisie intacte.
    expect(find.widgetWithText(TextField, 'Tuck'), findsOneWidget);
    expect(find.widgetWithText(TextField, '12'), findsOneWidget);
  });

  testWidgets('les champs montrent la valeur exacte (66.64, pas 66.6)', (t) async {
    await pump(t);
    await t.tap(find.text('Formes'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, '66.64'), findsOneWidget);
    expect(find.widgetWithText(TextField, '93.296'), findsOneWidget);
  });
}
