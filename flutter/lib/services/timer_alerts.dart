import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Une alerte à déclencher dans [inDuration] (ex. changement de phase du minuteur).
class TimerAlert {
  final Duration inDuration;
  final String title;
  final String body;
  const TimerAlert(this.inDuration, this.title, this.body);
}

/// Notifications du minuteur quand l'app n'est plus à l'écran (écran éteint,
/// autre application) : programmées d'avance auprès d'Android, qui les
/// déclenche même si l'app est suspendue. Au premier plan, le minuteur
/// vibre lui-même : on n'envoie rien.
class TimerAlerts {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'minuteur',
      'Minuteur',
      channelDescription: 'Changements de phase du minuteur d\'intervalles',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    ),
  );

  /// Le plugin, prêt à l'emploi (partagé avec les rappels de séance).
  static Future<FlutterLocalNotificationsPlugin> plugin() async {
    await _init();
    return _plugin;
  }

  /// Ids réservés au minuteur, au repos et au chrono : [1000, 2000[.
  /// Les rappels de séance utilisent d'autres ids et ne sont jamais effacés ici.
  static const _firstId = 1000, _endId = 2000;
  static bool _ours(int? id) => id != null && id >= _firstId && id < _endId;

  static Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    _ready = true;
  }

  /// Demande l'autorisation d'envoyer des notifications (Android 13+).
  static Future<bool> requestPermission() async {
    try {
      await _init();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> schedule(List<TimerAlert> alerts) async {
    try {
      await _init();
      await _cancelOurs();
      var id = _firstId;
      for (final a in alerts) {
        if (a.inDuration <= Duration.zero) continue;
        final when = tz.TZDateTime.now(tz.local).add(a.inDuration);
        try {
          await _plugin.zonedSchedule(
            id++,
            a.title,
            a.body,
            when,
            _details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (_) {
          // Alarme exacte refusée : repli sur une alarme approximative.
          await _plugin.zonedSchedule(
            id++,
            a.title,
            a.body,
            when,
            _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    } catch (_) {/* les notifications sont un confort : jamais bloquant */}
  }

  /// Fin naturelle d'un décompte (repos, minuteur) : on n'efface les
  /// notifications que si l'app est à l'écran. En arrière-plan, celle qui
  /// vient de s'afficher reste jusqu'au retour dans l'app (effacée alors par
  /// le retour au premier plan).
  static Future<void> cancelIfForeground() async {
    final s = WidgetsBinding.instance.lifecycleState;
    if (s == null || s == AppLifecycleState.resumed) await cancelAll();
  }

  /// Annule les alertes programmées ou affichées du minuteur, du repos et
  /// du chrono (pas les rappels de séance).
  static Future<void> cancelAll() async {
    try {
      await _init();
      await _cancelOurs();
    } catch (_) {}
  }

  static Future<void> _cancelOurs() async {
    final ids = <int>{
      for (final r in await _plugin.pendingNotificationRequests())
        if (_ours(r.id)) r.id,
    };
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      for (final n in await android?.getActiveNotifications() ?? const []) {
        if (_ours(n.id)) ids.add(n.id!);
      }
    } catch (_) {/* Android < 6 : seulement les programmées */}
    for (final id in ids) {
      await _plugin.cancel(id);
    }
  }
}
