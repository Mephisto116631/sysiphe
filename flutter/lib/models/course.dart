import 'dart:math';

/// Distance en mètres entre deux points GPS (formule de haversine).
double haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(min(1.0, sqrt(a)));
}

/// Une position reçue du GPS.
class GpsPoint {
  final double lat, lng;
  final double? alt;
  final double accuracy; // mètres
  final DateTime t;
  const GpsPoint(this.lat, this.lng, this.t, {this.alt, this.accuracy = 5});
}

/// Un point du tracé enregistré : position, distance cumulée (m) et temps en
/// mouvement cumulé (s). Sert à la carte, aux temps par km et aux records.
class TracePoint {
  final double lat, lng;
  final double m; // distance depuis le départ
  final double s; // temps en mouvement depuis le départ
  const TracePoint(this.lat, this.lng, this.m, this.s);

  List<num> toJson() => [
        double.parse(lat.toStringAsFixed(6)),
        double.parse(lng.toStringAsFixed(6)),
        m.round(),
        s.round(),
      ];

  factory TracePoint.fromJson(List l) => TracePoint(
      (l[0] as num).toDouble(),
      (l[1] as num).toDouble(),
      (l[2] as num).toDouble(),
      (l[3] as num).toDouble());
}

/// Objectif de la course : aucun, une distance (m) ou une durée (s).
enum GoalType { aucun, distance, duree }

class CourseGoal {
  final GoalType type;
  final int value;
  const CourseGoal(this.type, this.value);
  static const none = CourseGoal(GoalType.aucun, 0);

  bool reached(double distanceM, int dureeS) => switch (type) {
        GoalType.aucun => false,
        GoalType.distance => distanceM >= value,
        GoalType.duree => dureeS >= value,
      };

  /// Avancement 0..1 (null sans objectif).
  double? progress(double distanceM, int dureeS) => switch (type) {
        GoalType.aucun => null,
        GoalType.distance => (distanceM / value).clamp(0.0, 1.0),
        GoalType.duree => (dureeS / value).clamp(0.0, 1.0),
      };

  String get label => switch (type) {
        GoalType.aucun => 'Sans objectif',
        GoalType.distance => formatKm(value.toDouble()),
        GoalType.duree => formatDuration(value),
      };

  Map<String, dynamic>? toJson() =>
      type == GoalType.aucun ? null : {'type': type.name, 'value': value};

  static CourseGoal fromJson(Object? j) {
    if (j is! Map) return none;
    final t = GoalType.values.where((g) => g.name == j['type']);
    return t.isEmpty
        ? none
        : CourseGoal(t.first, (j['value'] as num?)?.toInt() ?? 0);
  }
}

/// Évènement du suivi, à annoncer.
sealed class TrackEvent {
  const TrackEvent();
}

class KmReached extends TrackEvent {
  final int km;
  final int splitS;
  const KmReached(this.km, this.splitS);
  @override
  bool operator ==(Object o) => o is KmReached && o.km == km && o.splitS == splitS;
  @override
  int get hashCode => Object.hash(km, splitS);
  @override
  String toString() => 'KmReached($km, $splitS s)';
}

class AutoPaused extends TrackEvent {
  const AutoPaused();
}

class AutoResumed extends TrackEvent {
  const AutoResumed();
}

/// Cumule les positions GPS d'une course : distance, temps en mouvement,
/// dénivelé positif, temps de chaque km, pause automatique.
///
/// - Les points imprécis (> [maxAccuracy] m) et les sauts impossibles
///   (> 12 m/s, soit 43 km/h) sont ignorés.
/// - Pause automatique : moins de 2 km/h pendant 5 s → pause (la distance et
///   le temps ne comptent plus) ; plus de 3 km/h → reprise.
class TrackAccumulator {
  TrackAccumulator({this.autoPause = true, this.maxAccuracy = 25});

  final bool autoPause;
  final double maxAccuracy;

  static const pauseSpeed = 2 / 3.6; // m/s
  static const resumeSpeed = 3 / 3.6;
  static const pauseDelay = Duration(seconds: 5);
  static const maxSpeed = 12.0;

  double distance = 0;
  double movingS = 0;
  double elevationGain = 0;
  final List<int> splits = [];
  final List<TracePoint> trace = [];
  bool autoPaused = false;

  GpsPoint? _last;
  DateTime? _slowSince;
  double? _altRef; // altitude de référence (hystérésis 3 m)
  double _lastSplitS = 0;

  GpsPoint? get last => _last;

  /// Reprise après une pause manuelle : la distance parcourue pendant la
  /// pause n'est pas comptée.
  void breakSegment() {
    _last = null;
    _slowSince = null;
  }

  List<TrackEvent> add(GpsPoint p) {
    final events = <TrackEvent>[];
    if (p.accuracy > maxAccuracy) return events;
    final prev = _last;
    if (prev == null) {
      _last = p;
      _altRef ??= p.alt;
      if (trace.isEmpty) trace.add(TracePoint(p.lat, p.lng, distance, movingS));
      return events;
    }
    final dt = p.t.difference(prev.t).inMilliseconds / 1000;
    if (dt <= 0) return events;
    final d = haversine(prev.lat, prev.lng, p.lat, p.lng);
    final v = d / dt;
    if (v > maxSpeed) return events; // saut GPS

    if (autoPause) {
      if (v < pauseSpeed) {
        _slowSince ??= prev.t;
        if (!autoPaused && p.t.difference(_slowSince!) >= pauseDelay) {
          autoPaused = true;
          events.add(const AutoPaused());
        }
      } else if (v >= resumeSpeed) {
        _slowSince = null;
        if (autoPaused) {
          autoPaused = false;
          events.add(const AutoResumed());
          _last = p; // repart d'ici : le temps arrêté ne compte pas
          return events;
        }
      }
    }
    _last = p;
    if (autoPaused) return events;

    final before = distance;
    distance += d;
    movingS += dt;
    _elevation(p.alt);

    // Kilomètres franchis (plusieurs si les points sont espacés).
    for (var k = (before ~/ 1000) + 1; k * 1000 <= distance; k++) {
      final f = d == 0 ? 1.0 : (k * 1000 - before) / d;
      final at = movingS - dt + dt * f;
      final split = (at - _lastSplitS).round();
      _lastSplitS = at;
      splits.add(split);
      events.add(KmReached(k, split));
    }

    final lastT = trace.isEmpty ? null : trace.last;
    if (lastT == null || distance - lastT.m >= 10) {
      trace.add(TracePoint(p.lat, p.lng, distance, movingS));
    }
    return events;
  }

  void _elevation(double? alt) {
    if (alt == null) return;
    final ref = _altRef;
    if (ref == null) {
      _altRef = alt;
    } else if (alt - ref >= 3) {
      elevationGain += alt - ref;
      _altRef = alt;
    } else if (ref - alt >= 3) {
      _altRef = alt;
    }
  }

  /// Dernier point pour un tracé complet (même à moins de 10 m du précédent).
  List<TracePoint> finalTrace() {
    final l = _last;
    if (l == null || trace.isEmpty || trace.last.m == distance) {
      return List.of(trace);
    }
    return [...trace, TracePoint(l.lat, l.lng, distance, movingS)];
  }

  /// Allure récente (s/km) sur les [window] derniers mètres ; null si pas
  /// assez de points.
  double? recentPace({double window = 200}) {
    final t = finalTrace();
    if (t.length < 2) return null;
    final end = t.last;
    var i = t.length - 2;
    while (i > 0 && end.m - t[i].m < window) {
      i--;
    }
    final dm = end.m - t[i].m, ds = end.s - t[i].s;
    if (dm < 30 || ds <= 0) return null;
    return ds / dm * 1000;
  }
}

/// Une course enregistrée.
class Course {
  final int? id;
  final String userId;
  final String? clientId;
  final DateTime debut;
  final int distanceM;
  final int dureeS;
  final int dureeTotaleS;
  final int deniveleM;
  final List<int> splitsS;
  final List<TracePoint> trace;
  final CourseGoal objectif;

  const Course({
    this.id,
    required this.userId,
    this.clientId,
    required this.debut,
    required this.distanceM,
    required this.dureeS,
    required this.dureeTotaleS,
    this.deniveleM = 0,
    this.splitsS = const [],
    this.trace = const [],
    this.objectif = CourseGoal.none,
  });

  bool get pending => (id ?? 0) < 0;
  DateTime get date => DateTime(debut.year, debut.month, debut.day);

  /// Allure moyenne en s/km (null si moins de 50 m).
  double? get paceS => distanceM < 50 ? null : dureeS / distanceM * 1000;

  Map<String, dynamic> toJson() => {
        if (id != null && id! > 0) 'id': id,
        'user_id': userId,
        if (clientId != null) 'client_id': clientId,
        'debut': debut.toUtc().toIso8601String(),
        'date':
            '${debut.year.toString().padLeft(4, '0')}-${debut.month.toString().padLeft(2, '0')}-${debut.day.toString().padLeft(2, '0')}',
        'distance_m': distanceM,
        'duree_s': dureeS,
        'duree_totale_s': dureeTotaleS,
        'denivele_m': deniveleM,
        'splits_s': splitsS,
        'trace': [for (final p in trace) p.toJson()],
        'objectif': objectif.toJson(),
      };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: (j['id'] as num?)?.toInt(),
        userId: j['user_id'] as String? ?? '',
        clientId: j['client_id'] as String?,
        debut: DateTime.parse(j['debut'] as String).toLocal(),
        distanceM: (j['distance_m'] as num?)?.toInt() ?? 0,
        dureeS: (j['duree_s'] as num?)?.toInt() ?? 0,
        dureeTotaleS: (j['duree_totale_s'] as num?)?.toInt() ?? 0,
        deniveleM: (j['denivele_m'] as num?)?.toInt() ?? 0,
        splitsS: [
          for (final s in (j['splits_s'] as List?) ?? const [])
            (s as num).toInt()
        ],
        trace: [
          for (final p in (j['trace'] as List?) ?? const [])
            TracePoint.fromJson(p as List)
        ],
        objectif: CourseGoal.fromJson(j['objectif']),
      );
}

/// Meilleur temps (s) pour couvrir [meters] d'un seul tenant dans le tracé
/// (fenêtre glissante, interpolée) ; null si la course est plus courte.
double? bestEffort(List<TracePoint> trace, double meters) {
  if (trace.length < 2 || trace.last.m - trace.first.m < meters) return null;
  double? best;
  var j = 0;
  for (var i = 0; i < trace.length; i++) {
    final start = trace[i];
    if (j < i) j = i;
    while (j < trace.length && trace[j].m - start.m < meters) {
      j++;
    }
    if (j >= trace.length) break;
    final a = trace[j - 1], b = trace[j];
    final need = start.m + meters;
    final f = b.m == a.m ? 1.0 : (need - a.m) / (b.m - a.m);
    final at = a.s + (b.s - a.s) * f;
    final t = at - start.s;
    if (best == null || t < best) best = t;
  }
  return best;
}

/// Un record de course : temps (s) sur une distance, ou plus longue course.
class CourseRecord {
  final String label;
  final double meters;
  final double? timeS;
  final Course? course;
  const CourseRecord(this.label, this.meters, this.timeS, this.course);
}

/// Records : meilleur temps sur 1 km, 5 km, 10 km, puis plus longue course.
List<CourseRecord> courseRecords(Iterable<Course> courses) {
  final out = <CourseRecord>[];
  for (final (label, m) in const [('1 km', 1000.0), ('5 km', 5000.0), ('10 km', 10000.0)]) {
    double? best;
    Course? bestC;
    for (final c in courses) {
      final t = bestEffort(c.trace, m);
      if (t != null && (best == null || t < best)) {
        best = t;
        bestC = c;
      }
    }
    out.add(CourseRecord(label, m, best, bestC));
  }
  Course? longest;
  for (final c in courses) {
    if (longest == null || c.distanceM > longest.distanceM) longest = c;
  }
  out.add(CourseRecord('Plus longue', (longest?.distanceM ?? 0).toDouble(),
      longest?.dureeS.toDouble(), longest));
  return out;
}

/// Distance (m) par semaine (lundi), pour les Stats.
Map<DateTime, double> weeklyDistance(Iterable<Course> courses) {
  final out = <DateTime, double>{};
  for (final c in courses) {
    final d = c.date;
    final monday = d.subtract(Duration(days: d.weekday - 1));
    out[monday] = (out[monday] ?? 0) + c.distanceM;
  }
  return out;
}

// ── Formats ─────────────────────────────────────────────────────────────

String formatDuration(int s) {
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

String formatKm(double m) {
  final km = m / 1000;
  return '${km.toStringAsFixed(km >= 100 ? 0 : 2).replaceAll('.', ',')} km';
}

/// Allure « 5'32" /km » ; « –'–– » si inconnue ou aberrante.
String formatPace(double? sPerKm) {
  if (sPerKm == null || !sPerKm.isFinite || sPerKm <= 0 || sPerKm >= 3600) {
    return '–\'––"';
  }
  final s = sPerKm.round();
  return '${s ~/ 60}\'${(s % 60).toString().padLeft(2, '0')}"';
}

/// Annonce vocale d'un kilomètre : « 2 kilomètres, 5 minutes 32 ».
String kmAnnouncement(int km, int splitS) {
  final m = splitS ~/ 60, s = splitS % 60;
  final t = m == 0 ? '$s secondes' : (s == 0 ? '$m minutes' : '$m minutes $s');
  return '$km kilomètre${km > 1 ? 's' : ''}, $t';
}
