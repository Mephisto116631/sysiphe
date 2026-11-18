import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/models/categorize.dart';
import 'package:sysiphe/models/perf.dart';

void main() {
  test('mots : accents, pluriel, mots vides, mots accolés', () {
    expect(exerciseTokens('Relevé Planche'), contains('releve'));
    expect(exerciseTokens('Pompes'), ['pompe']);
    expect(exerciseTokens('Pompe de hand stand'),
        containsAll(['pompe', 'hand', 'stand', 'handstand']));
    expect(exerciseTokens('Pompe de hand stand'), isNot(contains('de')));
    expect(exerciseTokens('Dips/triceps'), containsAll(['dip', 'tricep']));
  });

  // Rangement fait par l'utilisateur (sa nomenclature à lui).
  final rangement = {
    'Planche': 'Planche',
    'Lean Planche': 'Planche',
    'Relevé Planche': 'Planche',
    'HSPU Pompe hand stand': 'Handstand',
    'Handstand to diamond': 'Handstand',
    'Pompe': 'Pompe',
    'Pompes': 'Pompe',
    'Traction': 'Traction',
    'Australian': 'Traction',
  };
  final l = CategoryLearner(rangement);

  test('le mot le plus caractéristique l\'emporte', () {
    // « pompe » est vu en Pompe et en Handstand, « handstand » seulement en
    // Handstand : c'est lui qui décide.
    expect(l.suggest('Pompe de handstand'), 'Handstand');
    expect(l.suggest('Pompe de hand stand'), 'Handstand');
    expect(l.suggest('Pompes diamant'), 'Pompe');
    expect(l.suggest('Handstand PU'), 'Handstand');
  });

  test('à égalité, le premier mot du nom l\'emporte', () {
    expect(l.suggest('Planche to handstand'), 'Planche');
    expect(l.suggest('Handstand to planche'), 'Handstand');
  });

  test('exercice connu : sa catégorie ; mot inconnu : rien', () {
    expect(l.suggest('australian'), 'Traction');
    expect(l.suggest('Muscle up'), isNull);
    expect(l.suggest(''), isNull);
    expect(CategoryLearner({}).suggest('Planche'), isNull);
  });

  test('catégorie majoritaire par exercice, détail si mélangé', () {
    Perf p(String ex, String c) =>
        Perf(userId: 'u', date: DateTime(2026), exercice: ex, categorie: c);
    final r = exerciseCategories([
      p('Abdos', 'Gainage'),
      p('Abdos', 'Gainage'),
      p('Abdos', 'Musculation'),
      p('Traction', 'Musculation'),
    ]);
    expect(r.map((e) => e.exercice), ['Abdos', 'Traction']);
    expect(r.first.main, 'Gainage');
    expect(r.first.mixed, isTrue);
    expect(r.first.sets, 3);
    expect(r.last.mixed, isFalse);
  });
}
