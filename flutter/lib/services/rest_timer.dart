import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../widgets/rest_bar.dart';
import 'timer_alerts.dart';
import 'ui_prefs.dart';

/// Repos entre les séries de la Saisie : durée réglée (mémorisée sur
/// l'appareil), décompte, vibrations sur les 3 dernières secondes et à la fin,
/// notification si l'app passe en arrière-plan.
///
/// [left] vaut le temps restant pendant un repos, null sinon (lu par
/// [RestBar]). Les changements de [seconds] sont notifiés (ChangeNotifier).
class RestTimer extends ChangeNotifier {
  RestTimer({DateTime Function()? now}) : _nowFn = now ?? DateTime.now;

  static const prefKey = 'rest_seconds';

  final DateTime Function() _nowFn;
  final left = ValueNotifier<Duration?>(null);

  int _seconds = 90; // 0 = sans repos automatique
  DateTime? _end;
  Timer? _tick;
  int _beep = -1;

  int get seconds => _seconds;
  bool get running => _end != null;

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
    _end = _nowFn().add(Duration(seconds: _seconds));
    _beep = -1;
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
      stop();
      HapticFeedback.heavyImpact();
      Future.delayed(
          const Duration(milliseconds: 250), HapticFeedback.heavyImpact);
      return;
    }
    final sec = (l.inMilliseconds / 1000).ceil();
    if (sec <= 3 && sec != _beep) {
      _beep = sec;
      HapticFeedback.selectionClick();
    }
    left.value = l;
  }

  void stop() {
    _tick?.cancel();
    _end = null;
    left.value = null;
    TimerAlerts.cancelAll();
  }

  /// +15 s / −15 s pendant un repos.
  void adjust(int seconds) {
    final end = _end;
    if (end == null) return;
    _end = end.add(Duration(seconds: seconds));
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
