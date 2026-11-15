/// Minuteur façon HIIT : Préparation → (Exercice → Repos) × cycles.
/// Logique pure (aucune dépendance Flutter) : facile à tester.
enum IntervalKind { prep, work, rest }

class IntervalConfig {
  final int prep; // secondes de préparation (0 = aucune)
  final int work; // secondes d'exercice
  final int rest; // secondes de repos entre deux exercices (0 = aucun)
  final int cycles; // nombre d'exercices (cycles)

  const IntervalConfig(
      {this.prep = 5, this.work = 30, this.rest = 30, this.cycles = 4});

  IntervalConfig copyWith({int? prep, int? work, int? rest, int? cycles}) =>
      IntervalConfig(
        prep: prep ?? this.prep,
        work: work ?? this.work,
        rest: rest ?? this.rest,
        cycles: cycles ?? this.cycles,
      );

  @override
  bool operator ==(Object o) =>
      o is IntervalConfig &&
      o.prep == prep &&
      o.work == work &&
      o.rest == rest &&
      o.cycles == cycles;

  @override
  int get hashCode => Object.hash(prep, work, rest, cycles);
}

class IntervalPhase {
  final IntervalKind kind;
  final Duration duration;
  final int cycle; // 1-based ; 0 pour la préparation
  const IntervalPhase(this.kind, this.duration, this.cycle);

  /// Titre court, ex. « Exercice 3/8 ».
  String title(int cycles) => switch (kind) {
        IntervalKind.prep => 'Préparation',
        IntervalKind.work => 'Exercice $cycle/$cycles',
        IntervalKind.rest => 'Repos',
      };

  String get body => formatSeconds(duration.inSeconds);
}

/// Position dans le plan à un instant donné.
class PlanPosition {
  final IntervalPhase? phase; // null = terminé
  final int index;
  final Duration left; // temps restant dans la phase
  const PlanPosition(this.phase, this.index, this.left);
  bool get finished => phase == null;
}

class IntervalPlan {
  final IntervalConfig config;
  final List<IntervalPhase> phases;

  IntervalPlan(this.config) : phases = _build(config);

  static List<IntervalPhase> _build(IntervalConfig c) {
    final out = <IntervalPhase>[];
    if (c.prep > 0) {
      out.add(IntervalPhase(IntervalKind.prep, Duration(seconds: c.prep), 0));
    }
    for (var i = 1; i <= c.cycles; i++) {
      out.add(IntervalPhase(IntervalKind.work, Duration(seconds: c.work), i));
      if (c.rest > 0 && i < c.cycles) {
        out.add(IntervalPhase(IntervalKind.rest, Duration(seconds: c.rest), i));
      }
    }
    return out;
  }

  Duration get total =>
      phases.fold(Duration.zero, (a, p) => a + p.duration);

  /// Décalage de début de la phase [i].
  Duration startOf(int i) {
    var t = Duration.zero;
    for (var k = 0; k < i; k++) {
      t += phases[k].duration;
    }
    return t;
  }

  PlanPosition at(Duration elapsed) {
    var start = Duration.zero;
    for (var i = 0; i < phases.length; i++) {
      final end = start + phases[i].duration;
      if (elapsed < end) {
        return PlanPosition(phases[i], i, end - (elapsed < start ? start : elapsed));
      }
      start = end;
    }
    return const PlanPosition(null, -1, Duration.zero);
  }

  IntervalPhase? next(int index) =>
      index >= 0 && index + 1 < phases.length ? phases[index + 1] : null;
}

/// « 30 s », « 1:30 », « 12:05 ».
String formatSeconds(int s) {
  if (s < 60) return '$s s';
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

/// Chrono « m:ss » (toujours deux chiffres pour les secondes).
String clock(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
