import 'perf.dart';

/// Un exercice de la séance précédente, prêt à être refait : sert à
/// pré-remplir le formulaire de Saisie.
class ExerciseTemplate {
  final String exercice;
  final String unite;
  final List<Perf> series; // dans l'ordre des séries

  const ExerciseTemplate(this.exercice, this.unite, this.series);

  /// Modèle de la série [n] (1-based) : la même série de la dernière fois,
  /// ou la dernière série si on en fait plus qu'avant.
  Perf seriesFor(int n) => series[(n - 1).clamp(0, series.length - 1)];

  /// Résumé lisible, ex. « 3 × 12 Reps » ou « 15s · 12s · 10s ».
  String get summary {
    final values = series.map((p) => p.displayValue).toList();
    final same = values.toSet().length == 1;
    return same && values.length > 1
        ? '${values.length} × ${values.first}'
        : values.join(' · ');
  }
}

/// Regroupe les séries d'une séance par exercice, dans l'ordre où ils ont
/// été faits (ordre d'insertion = id croissant).
List<ExerciseTemplate> templatesFrom(List<Perf> session) {
  final sorted = [...session]..sort((a, b) {
      final c = (a.id ?? 0).compareTo(b.id ?? 0);
      return c != 0 ? c : a.serie.compareTo(b.serie);
    });
  final byEx = <String, List<Perf>>{};
  for (final p in sorted) {
    (byEx[p.exercice] ??= []).add(p);
  }
  return [
    for (final e in byEx.entries)
      ExerciseTemplate(
        e.key,
        e.value.first.unite,
        e.value..sort((a, b) => a.serie.compareTo(b.serie)),
      ),
  ];
}

/// Port de `parse_reps` (data.py) : « 12 10 8 » → [12, 10, 8].
/// Accepte aussi « / », « + » et « ; » comme séparateurs (le pavé numérique
/// Android n'a pas toujours d'espace) et la virgule décimale (« 12,5 »). Lève FormatException si
/// une valeur n'est pas un nombre positif.
List<double> parseSeries(String raw) {
  final out = <double>[];
  for (final token in raw.trim().split(RegExp(r'[\s/+;]+'))) {
    if (token.isEmpty) continue;
    final v = double.tryParse(token.replaceAll(',', '.'));
    if (v == null) throw FormatException('Valeur non numérique : $token');
    if (v < 0) throw FormatException('Valeur négative : $token');
    out.add(v);
  }
  return out;
}

/// Exercices du plus récent au plus ancien (dernier jour pratiqué, puis
/// dernière saisie). Sert à la liste « Récents » et à l'autocomplétion.
List<String> exercisesByRecency(Iterable<Perf> history) {
  final last = <String, (DateTime, int)>{};
  for (final p in history) {
    if (p.exercice.isEmpty) continue;
    final key = (DateTime(p.date.year, p.date.month, p.date.day), p.id ?? 0);
    final cur = last[p.exercice];
    if (cur == null ||
        key.$1.isAfter(cur.$1) ||
        (key.$1 == cur.$1 && key.$2 > cur.$2)) {
      last[p.exercice] = key;
    }
  }
  final names = last.keys.toList()
    ..sort((a, b) {
      final c = last[b]!.$1.compareTo(last[a]!.$1);
      return c != 0 ? c : last[b]!.$2.compareTo(last[a]!.$2);
    });
  return names;
}

/// Modèle de la dernière fois où [exercice] a été fait avant [before]
/// (toutes ses séries de ce jour-là), pour reprendre n'importe quel
/// exercice, pas seulement ceux de la séance précédente.
ExerciseTemplate? lastTemplateFor(
    Iterable<Perf> history, String exercice, DateTime before) {
  final day = DateTime(before.year, before.month, before.day);
  final past = history
      .where((p) => p.exercice == exercice && p.date.isBefore(day))
      .toList();
  if (past.isEmpty) return null;
  final lastDay = past
      .map((p) => DateTime(p.date.year, p.date.month, p.date.day))
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final t = templatesFrom(past
      .where((p) =>
          DateTime(p.date.year, p.date.month, p.date.day) == lastDay)
      .toList());
  return t.isEmpty ? null : t.first;
}

/// Premier exercice de la séance reprise qui n'est pas encore terminé
/// aujourd'hui (moins de séries faites que la dernière fois).
ExerciseTemplate? nextPending(
    List<ExerciseTemplate> templates, int Function(String) doneToday) {
  for (final t in templates) {
    if (doneToday(t.exercice) < t.series.length) return t;
  }
  return null;
}

/// Exercices des petites cartes de Saisie, dans l'ordre : ceux de la
/// séance reprise, puis ceux déjà faits aujourd'hui qui n'y étaient pas,
/// puis ceux ajoutés à la main. Sans doublon ; la planche garde la carte
/// principale (options variante / forme / élastique).
List<String> cardExercises(List<ExerciseTemplate> templates,
    Iterable<Perf> today, Iterable<String> added) {
  final out = <String>[];
  void add(String ex) {
    final e = ex.trim();
    if (e.isEmpty || Perf.isPlancheName(e) || out.contains(e)) return;
    out.add(e);
  }

  for (final t in templates) {
    add(t.exercice);
  }
  for (final p in today) {
    add(p.exercice);
  }
  for (final e in added) {
    add(e);
  }
  return out;
}

/// Valeurs de la dernière fois, au format de saisie rapide (« 30/25/20 »),
/// affichées en gris dans le champ vide.
String seriesHint(ExerciseTemplate t) => t.series
    .map((p) => p.performance % 1 == 0
        ? p.performance.toInt().toString()
        : p.performance.toString())
    .join('/');
