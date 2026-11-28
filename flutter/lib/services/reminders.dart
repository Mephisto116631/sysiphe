import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/perf.dart';
import '../models/stats.dart';
import 'timer_alerts.dart';
import 'ui_prefs.dart';

/// Un rappel de séance à programmer.
class PlannedReminder {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  const PlannedReminder(this.id, this.at, this.title, this.body);

  @override
  String toString() => 'PlannedReminder($id, $at, $title)';
}

/// Ids des rappels (hors de la plage du minuteur, 1000–1999).
const kReminderInactivityId = 2001;
const kReminderNextId = 2002;

/// Repos visé avant la « séance conseillée » : l'habituel (le plus
/// fréquent), l'optimal (celui qui précède tes meilleures séances, voir
/// [optimalRest]) ou un nombre de jours choisi.
enum RestTarget { habituel, optimal, choisi }

/// Repos retenu pour le rappel : nombre de jours et phrase du rappel.
class RestChoice {
  final int days;
  final String reason; // « Ton repos habituel », « Ton repos optimal »…
  const RestChoice(this.days, this.reason);
}

/// Repos à utiliser selon le réglage ; repli sur l'habituel si l'optimal
/// n'est pas encore calculable. null : rien à conseiller.
RestChoice? chooseRest(RestTarget target,
    {required RestStats? rest, OptimalRest? optimal, int chosenDays = 1}) {
  switch (target) {
    case RestTarget.choisi:
      return RestChoice(chosenDays.clamp(0, 14), 'Le repos que tu as choisi');
    case RestTarget.optimal:
      if (optimal != null) {
        return RestChoice(optimal.bestDays, 'Ton repos optimal');
      }
      break;
    case RestTarget.habituel:
      break;
  }
  return rest == null ? null : RestChoice(rest.mode, 'Ton repos habituel');
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Jours calendaires entre deux dates (insensible aux changements d'heure).
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

/// Rappels à programmer d'après les jours de séance :
/// - **prochaine séance conseillée** : le jour donné par le repos habituel
///   ([computeRest]), s'il est à venir et avant le rappel d'inactivité ;
/// - **inactivité** : dernière séance + [inactivityDays] + 1 jour, à [hour] h
///   (si ce moment est déjà passé : la prochaine occurrence de [hour] h).
///   [inactivityDays] ≤ 0 désactive ce rappel.
/// Aucune séance : aucun rappel.
List<PlannedReminder> planReminders({
  required Iterable<DateTime> sessionDates,
  required int inactivityDays,
  required int hour,
  required DateTime now,
  RestChoice? restChoice,
}) {
  final days = {for (final d in sessionDates) _day(d)}.toList()..sort();
  if (days.isEmpty) return const [];
  final last = days.last;
  DateTime at(DateTime day) => DateTime(day.year, day.month, day.day, hour);
  final out = <PlannedReminder>[];

  DateTime? inactivity;
  if (inactivityDays > 0) {
    var when =
        at(DateTime(last.year, last.month, last.day + inactivityDays + 1));
    if (!when.isAfter(now)) {
      when = at(now);
      if (!when.isAfter(now)) {
        when = at(DateTime(now.year, now.month, now.day + 1));
      }
    }
    inactivity = when;
    final n = _daysBetween(last, when);
    out.add(PlannedReminder(
      kReminderInactivityId,
      when,
      'Ça fait $n jours sans séance 💪',
      'Une petite séance aujourd\'hui ?',
    ));
  }

  final choice =
      restChoice ?? chooseRest(RestTarget.habituel, rest: computeRest(days));
  if (choice != null) {
    final r = choice.days;
    final when = at(DateTime(last.year, last.month, last.day + r + 1));
    if (when.isAfter(now) &&
        (inactivity == null || _day(when).isBefore(_day(inactivity)))) {
      out.insert(
          0,
          PlannedReminder(
            kReminderNextId,
            when,
            'Séance conseillée aujourd\'hui',
            r == 0
                ? '${choice.reason} : t\'entraîner tous les jours.'
                : '${choice.reason} (${r == 1 ? '1 jour' : '$r jours'}) est terminé.',
          ));
    }
  }
  return out;
}

/// Rappels de séance en notifications locales, reprogrammés à chaque
/// chargement de l'historique (ouverture, série enregistrée ou supprimée) :
/// pas de tâche de fond. Réglages de l'appareil : activés (défaut oui) et
/// heure (défaut 18 h) ; le nombre de jours vient de user_settings.
class Reminders {
  static const enabledKey = 'reminders_on';
  static const hourKey = 'reminders_hour';
  static const targetKey = 'reminders_rest_target';
  static const chosenDaysKey = 'reminders_rest_days';

  static Future<RestTarget> target() async {
    final n = await UiPrefs.getString(targetKey);
    return RestTarget.values.firstWhere((t) => t.name == n,
        orElse: () => RestTarget.habituel);
  }

  static Future<int> chosenDays() async =>
      (await UiPrefs.getInt(chosenDaysKey) ?? 1).clamp(0, 14);
  static const defaultHour = 18;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'rappels',
      'Rappels de séance',
      channelDescription: 'Prochaine séance conseillée et inactivité',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  static Future<bool> enabled() async =>
      await UiPrefs.getBool(enabledKey) ?? true;
  static Future<int> hour() async =>
      (await UiPrefs.getInt(hourKey) ?? defaultHour).clamp(0, 23);

  /// Recalcule et reprogramme les deux rappels. Jamais bloquant.
  /// [perfs] : l'historique, pour le repos optimal.
  static Future<void> reschedule(Iterable<DateTime> sessionDates,
      {required int inactivityDays, Iterable<Perf> perfs = const []}) async {
    try {
      final plugin = await TimerAlerts.plugin();
      await plugin.cancel(kReminderInactivityId);
      await plugin.cancel(kReminderNextId);
      if (!await enabled()) return;
      final t = await target();
      final plan = planReminders(
        sessionDates: sessionDates,
        inactivityDays: inactivityDays,
        hour: await hour(),
        now: DateTime.now(),
        restChoice: chooseRest(t,
            rest: computeRest(sessionDates),
            optimal: t == RestTarget.optimal ? optimalRest(perfs) : null,
            chosenDays: await chosenDays()),
      );
      for (final r in plan) {
        await plugin.zonedSchedule(
          r.id,
          r.title,
          r.body,
          tz.TZDateTime.from(r.at, tz.local),
          _details,
          // Un rappel n'a pas besoin d'être à la minute près.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {/* les rappels sont un confort : jamais bloquant */}
  }
}
