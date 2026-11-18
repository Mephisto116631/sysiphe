import 'perf.dart';

/// Mots sans valeur pour reconnaître un exercice.
const _stopwords = {
  'de',
  'du',
  'des',
  'la',
  'le',
  'les',
  'un',
  'une',
  'et',
  'en',
  'au',
  'aux',
  'a',
  'to',
  'with',
  'avec',
  'sur',
  'sans',
  'pour',
  'the',
  'of',
  'on',
};

const _accents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'ô': 'o',
  'ö': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ÿ': 'y',
  'œ': 'oe',
  'æ': 'ae',
};

/// Mots d'un nom d'exercice, dans l'ordre : minuscules, sans accents, sans
/// mots vides, au singulier (« Pompes » → « pompe »). Deux mots accolés sont
/// aussi essayés collés (« hand stand » → « handstand »).
List<String> exerciseTokens(String name) {
  final lower =
      name.toLowerCase().split('').map((c) => _accents[c] ?? c).join();
  final words =
      lower.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  String norm(String w) => w.length > 3 && w.endsWith('s') && !w.endsWith('ss')
      ? w.substring(0, w.length - 1)
      : w;
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (w.length >= 2 && !_stopwords.contains(w)) out.add(norm(w));
    if (i + 1 < words.length &&
        !_stopwords.contains(w) &&
        !_stopwords.contains(words[i + 1])) {
      out.add(norm(w + words[i + 1]));
    }
  }
  return out;
}

/// Propose une catégorie pour un nom d'exercice en apprenant de la façon dont
/// l'utilisateur a déjà rangé ses exercices (pas de dictionnaire imposé).
///
/// Chaque mot connu vote pour les catégories où il apparaît, d'autant plus
/// fort qu'il est caractéristique : « handstand », vu dans une seule
/// catégorie, pèse plus que « pompe », vu dans plusieurs. À égalité, le mot
/// placé le plus tôt dans le nom l'emporte (« Planche to handstand » →
/// Planche). Aucun mot connu ou égalité parfaite sans ordre : null.
class CategoryLearner {
  /// mot → catégorie → nombre d'exercices
  final Map<String, Map<String, int>> _counts = {};
  final Map<String, String> _exact = {};

  CategoryLearner(Map<String, String> exerciseCategories) {
    exerciseCategories.forEach((ex, cat) {
      final c = cat.trim();
      if (c.isEmpty) return;
      _exact[exerciseTokens(ex).join(' ')] = c;
      for (final t in exerciseTokens(ex).toSet()) {
        final m = _counts[t] ??= {};
        m[c] = (m[c] ?? 0) + 1;
      }
    });
  }

  String? suggest(String name) {
    final tokens = exerciseTokens(name);
    if (tokens.isEmpty) return null;
    final exact = _exact[tokens.join(' ')];
    if (exact != null) return exact;
    final score = <String, double>{};
    final first = <String, int>{};
    for (var i = 0; i < tokens.length; i++) {
      final m = _counts[tokens[i]];
      if (m == null) continue;
      final total = m.values.fold<int>(0, (a, b) => a + b);
      for (final e in m.entries) {
        score[e.key] = (score[e.key] ?? 0) + e.value / total / m.length;
        first.putIfAbsent(e.key, () => i);
      }
    }
    if (score.isEmpty) return null;
    final ranked = score.keys.toList()
      ..sort((a, b) {
        final d = score[b]!.compareTo(score[a]!);
        if ((score[a]! - score[b]!).abs() > 1e-9) return d;
        return first[a]!.compareTo(first[b]!);
      });
    return ranked.first;
  }
}

/// Catégorie de chaque exercice : celle de la majorité de ses séries, plus le
/// détail quand elles diffèrent (ex. Abdos : Musculation 30 · Gainage 113).
class ExerciseCategory {
  final String exercice;
  final String main;
  final Map<String, int> counts;
  const ExerciseCategory(this.exercice, this.main, this.counts);
  bool get mixed => counts.length > 1;
  int get sets => counts.values.fold(0, (a, b) => a + b);
}

List<ExerciseCategory> exerciseCategories(Iterable<Perf> perfs) {
  final by = <String, Map<String, int>>{};
  for (final p in perfs) {
    if (p.exercice.isEmpty) continue;
    final m = by[p.exercice] ??= {};
    final c = p.categorie.trim().isEmpty ? 'Musculation' : p.categorie.trim();
    m[c] = (m[c] ?? 0) + 1;
  }
  final out = [
    for (final e in by.entries)
      ExerciseCategory(
          e.key,
          (e.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key,
          e.value),
  ]..sort(
      (a, b) => a.exercice.toLowerCase().compareTo(b.exercice.toLowerCase()));
  return out;
}
