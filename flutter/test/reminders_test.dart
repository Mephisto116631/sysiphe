import 'package:flutter_test/flutter_test.dart';
import 'package:sysiphe/services/reminders.dart';

void main() {
  // Séances tous les 2 jours (repos habituel : 1 jour), la dernière le 17/11.
  final dates = [
    DateTime(2026, 11, 11, 9),
    DateTime(2026, 11, 13, 9),
    DateTime(2026, 11, 15, 9),
    DateTime(2026, 11, 17, 9),
  ];

  test('aucune séance : aucun rappel', () {
    expect(
        planReminders(
            sessionDates: const [],
            inactivityDays: 2,
            hour: 18,
            now: DateTime(2026, 11, 17, 12)),
        isEmpty);
  });

  test('prochaine séance conseillée puis inactivité', () {
    final r = planReminders(
        sessionDates: dates,
        inactivityDays: 2,
        hour: 18,
        now: DateTime(2026, 11, 17, 20));
    expect(r.map((e) => e.id), [kReminderNextId, kReminderInactivityId]);
    expect(r[0].at, DateTime(2026, 11, 19, 18)); // 17 + 1 jour de repos + 1
    expect(r[1].at, DateTime(2026, 11, 20, 18)); // 17 + 2 + 1
    expect(r[1].title, 'Ça fait 3 jours sans séance 💪');
  });

  test('pas de rappel « conseillée » le même jour que l\'inactivité', () {
    final r = planReminders(
        sessionDates: dates,
        inactivityDays: 1,
        hour: 18,
        now: DateTime(2026, 11, 17, 20));
    expect(r.map((e) => e.id), [kReminderInactivityId]);
    expect(r.single.at, DateTime(2026, 11, 19, 18));
  });

  test('inactivité déjà dépassée : prochaine occurrence de l\'heure', () {
    final before = planReminders(
        sessionDates: dates,
        inactivityDays: 2,
        hour: 18,
        now: DateTime(2026, 11, 25, 10));
    expect(before.single.at, DateTime(2026, 11, 25, 18)); // aujourd'hui 18 h
    expect(before.single.title, 'Ça fait 8 jours sans séance 💪');
    final after = planReminders(
        sessionDates: dates,
        inactivityDays: 2,
        hour: 18,
        now: DateTime(2026, 11, 25, 19));
    expect(after.single.at, DateTime(2026, 11, 26, 18)); // demain 18 h
  });

  test('séance faite aujourd\'hui : tout est décalé', () {
    final r = planReminders(
        sessionDates: [...dates, DateTime(2026, 11, 19, 8)],
        inactivityDays: 2,
        hour: 18,
        now: DateTime(2026, 11, 19, 9));
    expect(r.last.at, DateTime(2026, 11, 22, 18));
  });

  test('inactivité désactivée (0 jour) : seulement la séance conseillée', () {
    final r = planReminders(
        sessionDates: dates,
        inactivityDays: 0,
        hour: 7,
        now: DateTime(2026, 11, 17, 20));
    expect(r.single.id, kReminderNextId);
    expect(r.single.at, DateTime(2026, 11, 19, 7));
  });
}
