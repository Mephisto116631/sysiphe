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
