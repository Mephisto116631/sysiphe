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
