import 'package:flutter/material.dart';
import '../services/data_events.dart';
import '../services/reminders.dart';
import '../services/supabase_service.dart';
import '../services/timer_alerts.dart';
import '../services/ui_prefs.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await Reminders.enabled();
    final hour = await Reminders.hour();
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
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
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
                'Prochaine séance conseillée (repos habituel) et rappel '
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
