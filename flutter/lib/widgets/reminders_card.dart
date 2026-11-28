import 'package:flutter/material.dart';
import '../services/data_events.dart';
import '../services/reminders.dart';
import '../services/supabase_service.dart';
import '../services/timer_alerts.dart';
import '../services/ui_prefs.dart';
import '../screens/settings/common.dart' show errorText;
import '../theme.dart';

/// Réglages des rappels de séance : activés et heure (appareil), nombre de
/// jours sans séance avant le rappel (user_settings.inactivity_days, partagé
/// avec le web). Tout changement reprogramme les rappels (via la Saisie).
class RemindersCard extends StatefulWidget {
  final String userId;
  const RemindersCard({super.key, required this.userId});

  @override
  State<RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends State<RemindersCard> {
  bool _on = true;
  int _hour = Reminders.defaultHour;
  int _days = 2;
  RestTarget _target = RestTarget.habituel;
  int _chosen = 1;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await Reminders.enabled();
    final hour = await Reminders.hour();
    final target = await Reminders.target();
    final chosen = await Reminders.chosenDays();
    var days = 2;
    try {
      final s = await SupabaseService.instance.getSettings(widget.userId);
      days = (s['inactivity_days'] as num?)?.toInt() ?? 2;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _on = on;
      _hour = hour;
      _days = days.clamp(1, 30);
      _target = target;
      _chosen = chosen;
      _loading = false;
    });
  }

  Future<void> _setOn(bool v) async {
    setState(() => _on = v);
    await UiPrefs.setBool(Reminders.enabledKey, v);
    if (v) await TimerAlerts.requestPermission(); // Android 13+
    notifyDataChanged();
  }

  Future<void> _pickHour() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: 0),
      helpText: 'Heure des rappels',
    );
    if (t == null || !mounted) return;
    setState(() => _hour = t.hour);
    await UiPrefs.setInt(Reminders.hourKey, t.hour);
    notifyDataChanged();
  }

  Future<void> _setTarget(RestTarget t) async {
    setState(() => _target = t);
    await UiPrefs.setString(Reminders.targetKey, t.name);
    notifyDataChanged(); // la Saisie reprogramme les rappels
  }

  Future<void> _setChosen(int v) async {
    setState(() => _chosen = v);
    await UiPrefs.setInt(Reminders.chosenDaysKey, v);
    notifyDataChanged();
  }

  Future<void> _setDays(int v) async {
    final old = _days;
    setState(() => _days = v);
    try {
      await SupabaseService.instance
          .saveSettings(widget.userId, {'inactivity_days': v});
      notifyDataChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _days = old);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e)), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).textTheme.bodySmall;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined,
                color: AppTheme.primaryBlue),
            title: const Text('Rappels de séance'),
            subtitle: const Text(
                'Prochaine séance conseillée (après ton repos) et rappel '
                'après plusieurs jours sans séance'),
            value: _on,
            onChanged: _loading ? null : _setOn,
          ),
          if (_on) ...[
            ListTile(
              leading: const Icon(Icons.schedule, color: AppTheme.primaryBlue),
              title: const Text('Heure'),
              subtitle: Text('Réglage de l\'appareil', style: sub),
              trailing: Text('${_hour.toString().padLeft(2, '0')}:00',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              onTap: _pickHour,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Séance conseillée après', style: sub),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<RestTarget>(
                      key: const ValueKey('rest-target'),
                      segments: const [
                        ButtonSegment(
                            value: RestTarget.habituel,
                            label: Text('Habituel')),
                        ButtonSegment(
                            value: RestTarget.optimal, label: Text('Optimal')),
                        ButtonSegment(
                            value: RestTarget.choisi, label: Text('Choisi')),
                      ],
                      selected: {_target},
                      showSelectedIcon: false,
                      onSelectionChanged:
                          _loading ? null : (s) => _setTarget(s.first),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      switch (_target) {
                        RestTarget.habituel =>
                          'Ton repos le plus fréquent entre deux séances.',
                        RestTarget.optimal =>
                          'Le repos qui précède tes meilleures séances '
                              '(Calendrier → Récupération).',
                        RestTarget.choisi =>
                          'Le nombre de jours de repos que tu choisis.',
                      },
                      style: sub),
                ],
              ),
            ),
            if (_target == RestTarget.choisi)
              ListTile(
                key: const ValueKey('rest-chosen'),
                leading: const Icon(Icons.bedtime_outlined,
                    color: AppTheme.primaryBlue),
                title: Text(_chosen == 0
                    ? 'Tous les jours'
                    : '$_chosen jour${_chosen > 1 ? 's' : ''} de repos'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Moins de repos',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _chosen <= 0 ? null : () => _setChosen(_chosen - 1),
                    ),
                    IconButton(
                      tooltip: 'Plus de repos',
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed:
                          _chosen >= 14 ? null : () => _setChosen(_chosen + 1),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.hourglass_bottom,
                  color: AppTheme.primaryBlue),
              title:
                  Text('Après $_days jour${_days > 1 ? 's' : ''} sans séance'),
              subtitle: Text('Partagé avec le site', style: sub),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Moins',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _loading || _days <= 1
                        ? null
                        : () => _setDays(_days - 1),
                  ),
                  IconButton(
                    tooltip: 'Plus',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _loading || _days >= 30
                        ? null
                        : () => _setDays(_days + 1),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
