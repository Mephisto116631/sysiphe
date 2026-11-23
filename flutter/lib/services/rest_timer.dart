import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../widgets/rest_bar.dart';
import 'chrono_fx.dart';
import 'timer_alerts.dart';
import 'ui_prefs.dart';

/// Repos réellement pris avant une série : [actual] secondes sur
/// [planned] prévues (avec les ±15 s). Plus court = repos passé ou raccourci.
class RestTaken {
  final int actual;
  final int planned;
  const RestTaken(this.actual, this.planned);

  bool get skipped => planned - actual > 10;

  @override
  bool operator ==(Object o) =>
      o is RestTaken && o.actual == actual && o.planned == planned;
  @override
  int get hashCode => Object.hash(actual, planned);
  @override
  String toString() => 'RestTaken($actual/$planned)';
}

/// Repos entre les séries de la Saisie : durée réglée (mémorisée sur
/// l'appareil), décompte, vibrations et bips sur les 3 dernières secondes,
/// bip long + « Repos terminé » à la fin (réglage son du chrono : voix, bips
/// ou muet), notification si l'app passe en arrière-plan.
///
/// Garde la durée réellement prise ([takeLastRest]) pour l'enregistrer avec
/// la série suivante.
///
/// [left] vaut le temps restant pendant un repos, null sinon (lu par
/// [RestBar]). Les changements de [seconds] sont notifiés (ChangeNotifier).
class RestTimer extends ChangeNotifier {
  RestTimer({DateTime Function()? now, ChronoFx? fx})
      : _nowFn = now ?? DateTime.now,
        _fxOverride = fx;

  static const prefKey = 'rest_seconds';

  final DateTime Function() _nowFn;
  final ChronoFx? _fxOverride;
  ChronoFx get _fx => _fxOverride ?? DeviceChronoFx.instance;
  final left = ValueNotifier<Duration?>(null);

  int _seconds = 90; // 0 = sans repos automatique
  DateTime? _end;
  DateTime? _startedAt;
  int _planned = 0; // durée prévue du repos en cours (± ajustements)
  RestTaken? _last; // dernier repos terminé, pas encore enregistré
  Completer<void>? _done;
  Timer? _tick;
  int _beep = -1;
  int _soundMode = 2; // 0 muet, 1 bips, 2 bips + voix

  int get seconds => _seconds;
  bool get running => _end != null;

  /// Se termine à la fin du repos (écoulé ou passé) ; tout de suite s'il n'y
  /// en a pas. Sert à enchaîner la série suivante du chrono.
  Future<void> waitDone() => _done?.future ?? Future.value();

  /// Repos pris avant la série qu'on enregistre, puis oublié (il ne sert
  /// qu'une fois). Repos encore en cours : la durée écoulée jusqu'ici.
  RestTaken? takeLastRest() {
    if (running) _last = _measure();
    final r = _last;
    _last = null;
    return r;
  }

  RestTaken _measure() {
    final started = _startedAt ?? _nowFn();
    final s = _nowFn().difference(started).inSeconds.clamp(0, _planned);
    return RestTaken(s, _planned);
  }

  /// Reprend la durée choisie la dernière fois.
  Future<void> load() async {
    final v = await UiPrefs.getInt(prefKey);
    if (v != null && RestBar.choices.contains(v)) {
      _seconds = v;
      notifyListeners();
    }
  }

  void setSeconds(int v) {
    _seconds = v;
    notifyListeners();
    UiPrefs.setInt(prefKey, v);
    if (v > 0) TimerAlerts.requestPermission(); // notifications (Android 13+)
  }

  /// Lance un repos (après une série enregistrée).
  void start() {
    if (_seconds <= 0) return;
    chronoSoundMode().then((m) => _soundMode = m);
    _startedAt = _nowFn();
    _planned = _seconds;
    _end = _startedAt!.add(Duration(seconds: _seconds));
    _beep = -1;
    _last = null;
    if (_done == null || _done!.isCompleted) _done = Completer<void>();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) => tick());
    tick();
  }

  @visibleForTesting
  void tick() {
    final end = _end;
    if (end == null) return;
    final l = end.difference(_nowFn());
    if (l <= Duration.zero) {
      _finish(RestTaken(_planned, _planned));
      HapticFeedback.heavyImpact();
      Future.delayed(
          const Duration(milliseconds: 250), HapticFeedback.heavyImpact);
      if (_soundMode >= 1) _fx.bip(Bip.depart);
      if (_soundMode == 2) _fx.say('Repos terminé');
      return;
    }
    final sec = (l.inMilliseconds / 1000).ceil();
    if (sec <= 3 && sec != _beep) {
      _beep = sec;
      HapticFeedback.selectionClick();
      if (_soundMode >= 1) _fx.bip(Bip.court);
    }
    left.value = l;
  }

  /// « Passer » : arrête le repos ; la durée réellement prise est gardée.
  void stop() {
    if (running) {
      _finish(_measure());
    } else {
      _finish(null);
    }
  }

  void _finish(RestTaken? taken) {
    _tick?.cancel();
    if (taken != null) _last = taken;
    _end = null;
    left.value = null;
    TimerAlerts.cancelAll();
    if (_done != null && !_done!.isCompleted) _done!.complete();
  }

  /// +15 s / −15 s pendant un repos.
  void adjust(int seconds) {
    final end = _end;
    if (end == null) return;
    _end = end.add(Duration(seconds: seconds));
    _planned = (_planned + seconds).clamp(0, 3600);
    tick();
  }

  /// Écran éteint ou autre appli : notification de fin de repos.
  void onLifecycle(AppLifecycleState state) {
    final end = _end;
    if (state == AppLifecycleState.paused && end != null) {
      final l = end.difference(_nowFn());
      if (l > Duration.zero) {
        TimerAlerts.schedule(
            [TimerAlert(l, 'Repos terminé', 'Prochaine série !')]);
      }
    } else if (state == AppLifecycleState.resumed) {
      TimerAlerts.cancelAll();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    left.dispose();
    super.dispose();
  }
}
