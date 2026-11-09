import 'perf.dart';

/// Une valeur agrégée par jour de séance.
class DayPoint {
  final DateTime date;
  final double value;
  const DayPoint(this.date, this.value);
}

/// Ce que mesure la courbe d'un exercice (même logique que l'onglet Stats web).
enum StatMetric {
  /// Planche : effort pondéré maximal du jour.
  effort,

  /// Reps avec lest : tonnage du jour, Σ performance × charge.
  tonnage,

  /// Reps sans lest : volume du jour, Σ performance.
  volume,

  /// Autres (secondes, kg) : meilleure valeur du jour.
  best;

  String get label => switch (this) {
        StatMetric.effort => 'Effort pondéré',
        StatMetric.tonnage => 'Tonnage (kg)',
        StatMetric.volume => 'Volume (reps)',
        StatMetric.best => 'Meilleure valeur',
      };

  String unit(String unite) => switch (this) {
        StatMetric.effort => ' pts',
        StatMetric.tonnage => ' kg',
        StatMetric.volume => ' reps',
        StatMetric.best => unite == 'Sec' ? 's' : ' $unite',
      };
}

StatMetric metricFor(List<Perf> perfs) {
  if (perfs.isEmpty) return StatMetric.best;
  if (perfs.first.isPlanche) return StatMetric.effort;
  if (perfs.every((p) => p.unite == 'Reps')) {
    return perfs.any((p) => p.charge > 0)
        ? StatMetric.tonnage
        : StatMetric.volume;
  }
  return StatMetric.best;
}

/// Agrège les séries d'un exercice en une valeur par jour, triée par date.
List<DayPoint> dailySeries(List<Perf> perfs, StatMetric metric) {
  final byDay = <DateTime, double>{};
  for (final p in perfs) {
    final d = DateTime(p.date.year, p.date.month, p.date.day);
    final v = switch (metric) {
      StatMetric.effort => (p.effortPondere ?? 0).toDouble(),
      // Une série sans lest compte pour sa valeur brute, comme sur le web.
      StatMetric.tonnage => p.charge > 0 ? p.performance * p.charge : p.performance,
      StatMetric.volume => p.performance,
      StatMetric.best => p.performance,
    };
    final cumulative =
        metric == StatMetric.tonnage || metric == StatMetric.volume;
    final prev = byDay[d];
    byDay[d] = prev == null
        ? v
        : cumulative
            ? prev + v
            : (v > prev ? v : prev);
  }
  final out = byDay.entries.map((e) => DayPoint(e.key, e.value)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return out;
}

enum Trend { progress, plateau, regression, insufficientData }

class PlateauResult {
  final Trend status;
  final double slope;
  final double relativeSlope;
  final int nPoints;
  const PlateauResult(this.status, this.slope, this.relativeSlope, this.nPoints);
}

/// Port fidèle de `detect_plateau` (data.py) : régression linéaire sur les
/// [windowDays] derniers jours ; pente relative comparée à ±[threshold].
PlateauResult detectPlateau(List<DayPoint> points,
    {int windowDays = 21, double threshold = 0.05}) {
  if (points.isEmpty) {
    return const PlateauResult(Trend.insufficientData, 0, 0, 0);
  }
  final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
  final cutoff = sorted.last.date.subtract(Duration(days: windowDays));
  final win = sorted.where((p) => !p.date.isBefore(cutoff)).toList();
  if (win.length < 3) {
    return PlateauResult(Trend.insufficientData, 0, 0, win.length);
  }
  final x0 = win.first.date;
  // Jours entiers depuis le premier point (équivalent des ordinaux Python).
  final x = win
      .map((p) => DateTime.utc(p.date.year, p.date.month, p.date.day)
          .difference(DateTime.utc(x0.year, x0.month, x0.day))
          .inDays
          .toDouble())
      .toList();
  final y = win.map((p) => p.value).toList();
  final n = x.length;
  final sx = x.reduce((a, b) => a + b);
  final sy = y.reduce((a, b) => a + b);
  var sx2 = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sx2 += x[i] * x[i];
    sxy += x[i] * y[i];
  }
  final denom = n * sx2 - sx * sx;
  final slope = denom != 0 ? (n * sxy - sx * sy) / denom : 0.0;
  var mean = sy / n;
  if (mean == 0) mean = 1;
  final rel = (slope * windowDays) / mean;
  final status = rel > threshold
      ? Trend.progress
      : rel < -threshold
          ? Trend.regression
          : Trend.plateau;
  return PlateauResult(status, slope, rel, n);
}

// ─── Récupération (onglet Repos du web) ─────────────────────────────────────

/// Repos entre deux séances : [restDays] jours sans séance avant [resume].
class RestGap {
  final DateTime resume;
  final int restDays;
  const RestGap(this.resume, this.restDays);
}

class RestStats {
  final List<RestGap> gaps; // chronologique
  final double mean;
  final int mode; // repos habituel
  final int longest;
  final DateTime nextSession;
  final Map<int, int> distribution; // jours de repos → nombre d'occurrences

  const RestStats(this.gaps, this.mean, this.mode, this.longest,
      this.nextSession, this.distribution);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Port de render_repos_tab + suggest_next_session (data.py) : repos entre
/// séances distinctes, repos habituel = mode (le plus petit en cas
/// d'égalité, comme pandas), prochaine séance = dernière + mode + 1 jour.
/// null s'il y a moins de deux jours de séance.
RestStats? computeRest(Iterable<DateTime> sessionDates) {
  final days = {for (final d in sessionDates) _day(d)}.toList()..sort();
  if (days.length < 2) return null;
  final gaps = <RestGap>[
    for (var i = 1; i < days.length; i++)
      RestGap(
        days[i],
        DateTime.utc(days[i].year, days[i].month, days[i].day)
                .difference(DateTime.utc(
                    days[i - 1].year, days[i - 1].month, days[i - 1].day))
                .inDays -
            1,
      ),
  ];
  final dist = <int, int>{};
  for (final g in gaps) {
    dist[g.restDays] = (dist[g.restDays] ?? 0) + 1;
  }
  final maxCount = dist.values.reduce((a, b) => a > b ? a : b);
  final mode = (dist.entries.where((e) => e.value == maxCount).map((e) => e.key).toList()
        ..sort())
      .first;
  final mean = gaps.map((g) => g.restDays).reduce((a, b) => a + b) / gaps.length;
  final longest = gaps.map((g) => g.restDays).reduce((a, b) => a > b ? a : b);
  final last = days.last;
  final next = DateTime(last.year, last.month, last.day + mode + 1);
  return RestStats(gaps, mean, mode, longest, next, dist);
}

// ─── Indicateurs de Saisie (panneau KPI et blocs exercice du web) ──────────

class PeriodComparison {
  final double current;
  final double previous;
  final double? deltaPct; // null si la période précédente est à 0
  const PeriodComparison(this.current, this.previous, this.deltaPct);
}

/// Port de compute_period_comparison (data.py) : somme de [value] sur deux
/// fenêtres de dates incluses ; delta arrondi à 0,1 %.
PeriodComparison comparePeriods(
  Iterable<Perf> perfs,
  double Function(Perf) value, {
  required DateTime currentStart,
  required DateTime currentEnd,
  required DateTime previousStart,
  required DateTime previousEnd,
}) {
  bool inRange(DateTime d, DateTime a, DateTime b) =>
      !_day(d).isBefore(_day(a)) && !_day(d).isAfter(_day(b));
  var cur = 0.0, prev = 0.0;
  for (final p in perfs) {
    if (inRange(p.date, currentStart, currentEnd)) cur += value(p);
    if (inRange(p.date, previousStart, previousEnd)) prev += value(p);
  }
  final delta =
      prev == 0 ? null : (((cur - prev) / prev * 100) * 10).round() / 10;
  return PeriodComparison(cur, prev, delta);
}

/// Semaine en cours (lundi → dimanche) vs semaine précédente, en volume de
/// reps, comme le panneau « Cette semaine vs précédente » du web.
PeriodComparison weekVolume(Iterable<Perf> perfs, DateTime today) {
  final monday = _day(today).subtract(Duration(days: today.weekday - 1));
  return comparePeriods(
    perfs.where((p) => p.unite == 'Reps'),
    (p) => p.performance,
    currentStart: monday,
    currentEnd: monday.add(const Duration(days: 6)),
    previousStart: monday.subtract(const Duration(days: 7)),
    previousEnd: monday.subtract(const Duration(days: 1)),
  );
}

/// Nombre de jours de séance dans le mois de [day].
int sessionsInMonth(Iterable<Perf> perfs, DateTime day) => {
      for (final p in perfs)
        if (p.date.year == day.year && p.date.month == day.month) _day(p.date)
    }.length;

/// Indicateurs d'un exercice, comme l'en-tête des blocs du web :
/// record en une série, volume moyen des [nbDaysAvg] dernières séances.
class ExerciseInsight {
  final double prSerie;
  final double avgVolume; // 0 si pas d'historique
  final int sessions;
  const ExerciseInsight(this.prSerie, this.avgVolume, this.sessions);

  /// Écart en % d'un volume par rapport à la moyenne (null sans moyenne).
  double? deltaPct(double volume) =>
      avgVolume > 0 ? (volume / avgVolume - 1) * 100 : null;
}

/// [history] : séries passées de l'exercice. La séance du jour est exclue
/// de la moyenne pour que la comparaison « aujourd'hui vs moyenne » ait un
/// sens (le web l'incluait).
ExerciseInsight? insightFor(List<Perf> history, DateTime today,
    {int nbDaysAvg = 5}) {
  final past = history.where((p) => _day(p.date).isBefore(_day(today)));
  if (past.isEmpty) return null;
  final pr = past.map((p) => p.performance).reduce((a, b) => a > b ? a : b);
  final byDay = <DateTime, double>{};
  for (final p in past) {
    byDay[_day(p.date)] = (byDay[_day(p.date)] ?? 0) + p.performance;
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  final recent = days.take(nbDaysAvg).map((d) => byDay[d]!).toList();
  final avg = recent.reduce((a, b) => a + b) / recent.length;
  return ExerciseInsight(pr, avg, byDay.length);
}

// ─── Records (onglet Records du web) ───────────────────────────────────────

class PlancheRecord {
  final String variante, elastique, tension;
  final Perf best;
  const PlancheRecord(this.variante, this.elastique, this.tension, this.best);
}

/// Meilleure série de planche (effort, puis temps) pour chaque combinaison
/// variante / élastique / tension, triées par effort décroissant.
List<PlancheRecord> plancheRecords(Iterable<Perf> perfs) {
  final best = <String, Perf>{};
  for (final p in perfs) {
    if (!p.isPlanche || (p.effortPondere ?? 0) <= 0) continue;
    final k = '${p.variante}|${p.elastique}|${p.tension}';
    final cur = best[k];
    if (cur == null || isBetterRecord(p, cur)) best[k] = p;
  }
  final out = [
    for (final p in best.values)
      PlancheRecord(p.variante, p.elastique, p.tension, p),
  ]..sort((a, b) {
      final c = (b.best.effortPondere ?? 0).compareTo(a.best.effortPondere ?? 0);
      return c != 0 ? c : b.best.performance.compareTo(a.best.performance);
    });
  return out;
}

class VolumeRecord {
  final String exercice;
  final double volume; // Σ reps, ou Σ reps × kg si lesté
  final bool tonnage;
  final DateTime date;
  final double bestSerie;
  const VolumeRecord(
      this.exercice, this.volume, this.tonnage, this.date, this.bestSerie);
}

/// Hors planche : meilleure séance (volume ou tonnage du jour) et meilleure
/// série de chaque exercice, triés par volume décroissant.
List<VolumeRecord> volumeRecords(Iterable<Perf> perfs) {
  final byEx = <String, List<Perf>>{};
  for (final p in perfs) {
    if (!p.isPlanche) (byEx[p.exercice] ??= []).add(p);
  }
  final out = <VolumeRecord>[];
  byEx.forEach((ex, list) {
    final metric = metricFor(list);
    final series = dailySeries(
        list,
        metric == StatMetric.tonnage || metric == StatMetric.volume
            ? metric
            : StatMetric.best);
    final top = series.reduce((a, b) => b.value > a.value ? b : a);
    final bestSerie =
        list.map((p) => p.performance).reduce((a, b) => a > b ? a : b);
    out.add(VolumeRecord(
        ex, top.value, metric == StatMetric.tonnage, top.date, bestSerie));
  });
  out.sort((a, b) => b.volume.compareTo(a.volume));
  return out;
}
