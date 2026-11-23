import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../models/course.dart';
import 'chrono_fx.dart';
import 'offline_store.dart';

/// Source des positions GPS (injectable : les tests passent un faux flux).
abstract class PositionSource {
  /// Demande la permission de localisation (et l'activation du GPS).
  /// null si tout est prêt, sinon un message pour l'utilisateur.
  Future<String?> prepare();
  Stream<GpsPoint> positions();
}

/// GPS réel (geolocator). Sur Android, un service de premier plan (une
/// notification « Course en cours ») garde le suivi actif écran éteint.
class DevicePositionSource implements PositionSource {
  const DevicePositionSource();

  @override
  Future<String?> prepare() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Active la localisation du téléphone pour suivre la course.';
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied) {
        return 'Autorise la localisation pour suivre la course.';
      }
      if (p == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return 'Localisation refusée : autorise-la dans les réglages du '
            'téléphone (Applis → Sysiphe → Autorisations).';
      }
      return null;
    } catch (e) {
      return 'GPS indisponible ($e)';
    }
  }

  @override
  Stream<GpsPoint> positions() {
    final LocationSettings settings = defaultTargetPlatform ==
            TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Sysiphe · Course en cours',
              notificationText: 'Suivi GPS actif',
              notificationChannelName: 'Course',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.best);
    return Geolocator.getPositionStream(locationSettings: settings).map(
        (p) => GpsPoint(p.latitude, p.longitude, p.timestamp,
            alt: p.altitude == 0 ? null : p.altitude, accuracy: p.accuracy));
  }
}

enum TrackState { pret, enCours, pause, termine }

/// Suivi d'une course : démarrage, pause manuelle ou automatique, annonces
/// (chaque km, pause, reprise, objectif), fin. [Course] prête à enregistrer.
class CourseTracker extends ChangeNotifier {
  CourseTracker({
    PositionSource? source,
    ChronoFx? fx,
    DateTime Function()? now,
    Future<int> Function()? soundMode,
  })  : _source = source ?? const DevicePositionSource(),
        _fxOverride = fx,
        _now = now ?? DateTime.now,
        _soundModeFn = soundMode ?? chronoSoundMode;

  final PositionSource _source;
  final ChronoFx? _fxOverride;
  ChronoFx get _fx => _fxOverride ?? DeviceChronoFx.instance;
  final DateTime Function() _now;
  final Future<int> Function() _soundModeFn;

  TrackState state = TrackState.pret;
  TrackAccumulator acc = TrackAccumulator();
  CourseGoal goal = CourseGoal.none;
  bool autoPause = true;
  bool goalReached = false;
  GpsPoint? position; // dernière position reçue (même imprécise)
  DateTime? startedAt;
  DateTime? endedAt;
  String? lastAnnouncement;

  StreamSubscription<GpsPoint>? _sub;
  Timer? _tick;
  int _soundMode = 2;

  bool get active => state == TrackState.enCours || state == TrackState.pause;
  bool get paused => state == TrackState.pause || acc.autoPaused;

  /// Temps en mouvement, à la seconde, y compris depuis le dernier point
  /// (l'affichage avance chaque seconde même si le GPS est plus lent).
  int get movingSeconds {
    var s = acc.movingS;
    final last = acc.last;
    if (state == TrackState.enCours && !acc.autoPaused && last != null) {
      final extra = _now().difference(last.t).inMilliseconds / 1000;
      if (extra > 0 && extra < 10) s += extra;
    }
    return s.floor();
  }

  int get totalSeconds {
    final s = startedAt;
    if (s == null) return 0;
    return (endedAt ?? _now()).difference(s).inSeconds;
  }

  double? get averagePace =>
      acc.distance < 50 ? null : acc.movingS / acc.distance * 1000;

  /// Démarre ; renvoie un message d'erreur (permission, GPS) ou null.
  Future<String?> start({CourseGoal? goal, bool? autoPause}) async {
    if (active) return null;
    final err = await _source.prepare();
    if (err != null) return err;
    this.goal = goal ?? this.goal;
    this.autoPause = autoPause ?? this.autoPause;
    acc = TrackAccumulator(autoPause: this.autoPause);
    goalReached = false;
    position = null;
    startedAt = _now();
    endedAt = null;
    lastAnnouncement = null;
    _soundMode = await _soundModeFn();
    state = TrackState.enCours;
    _sub = _source.positions().listen(_onPoint, onError: (_) {});
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _say('Course démarrée');
    notifyListeners();
    return null;
  }

  void _onPoint(GpsPoint p) {
    position = p;
    if (state != TrackState.enCours) {
      notifyListeners();
      return;
    }
    for (final e in acc.add(p)) {
      switch (e) {
        case KmReached(:final km, :final splitS):
          _say(kmAnnouncement(km, splitS));
        case AutoPaused():
          _say('Pause');
        case AutoResumed():
          _say('Reprise');
      }
    }
    _checkGoal();
    notifyListeners();
  }

  void _onTick() {
    if (state == TrackState.enCours) _checkGoal();
    notifyListeners();
  }

  void _checkGoal() {
    if (goalReached || !goal.reached(acc.distance, movingSeconds)) return;
    goalReached = true;
    HapticFeedback.heavyImpact();
    if (_soundMode >= 1) _fx.bip(Bip.objectif);
    _say('Objectif atteint');
  }

  void _say(String text) {
    lastAnnouncement = text;
    if (_soundMode == 2) _fx.say(text);
  }

  /// Pause manuelle.
  void pause() {
    if (state != TrackState.enCours) return;
    state = TrackState.pause;
    _say('Pause');
    notifyListeners();
  }

  void resume() {
    if (state != TrackState.pause) return;
    acc.breakSegment(); // pas de distance « pendant » la pause
    state = TrackState.enCours;
    _say('Reprise');
    notifyListeners();
  }

  /// Termine la course (le GPS s'arrête) ; renvoie la course à enregistrer.
  Course finish(String userId) {
    _stop();
    endedAt = _now();
    state = TrackState.termine;
    _say('Course terminée, ${formatKm(acc.distance)}');
    notifyListeners();
    return toCourse(userId);
  }

  Course toCourse(String userId) => Course(
        userId: userId,
        clientId: newClientId(),
        debut: startedAt ?? _now(),
        distanceM: acc.distance.round(),
        dureeS: acc.movingS.round(),
        dureeTotaleS: totalSeconds,
        deniveleM: acc.elevationGain.round(),
        splitsS: List.of(acc.splits),
        trace: acc.finalTrace(),
        objectif: goal,
      );

  /// Retour à l'écran de départ (course enregistrée ou abandonnée).
  void reset() {
    _stop();
    state = TrackState.pret;
    acc = TrackAccumulator(autoPause: autoPause);
    position = null;
    startedAt = null;
    endedAt = null;
    notifyListeners();
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
