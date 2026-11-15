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
      await _plugin.cancelAll();
      var id = 1000;
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

  static Future<void> cancelAll() async {
    try {
      await _init();
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
