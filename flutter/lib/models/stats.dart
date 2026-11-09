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
