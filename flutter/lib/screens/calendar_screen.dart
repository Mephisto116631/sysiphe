import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../models/stats.dart';
import '../theme.dart';
import '../widgets/load_error.dart';

class CalendarScreen extends StatefulWidget {
  final String userId;

  const CalendarScreen({super.key, required this.userId});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  Map<DateTime, int> _activeDays = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final days = await SupabaseService.instance
          .getActiveDays(widget.userId); // tout l'historique
      if (!mounted) return;
      setState(() { _activeDays = days; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  int _countFor(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _activeDays[key] ?? 0;
  }

  Color _colorFor(int count) {
    if (count == 0) return Colors.transparent;
    if (count <= 2) return AppTheme.primaryBlue.withOpacity(0.25);
    if (count <= 4) return AppTheme.primaryBlue.withOpacity(0.55);
    return AppTheme.primaryBlue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendrier'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'Actualiser'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? LoadError(error: _error!, onRetry: _load)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: TableCalendar(
                        locale: 'fr_FR',
                        firstDay: DateTime(2020),
                        lastDay: DateTime.now().add(const Duration(days: 1)),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) =>
                            isSameDay(_selectedDay, day),
                        onDaySelected: (sel, foc) =>
                            setState(() {
                              _selectedDay = sel;
                              _focusedDay = foc;
                            }),
                        onPageChanged: (d) =>
                            setState(() => _focusedDay = d),
                        calendarStyle: const CalendarStyle(
                          outsideDaysVisible: false,
                          weekendTextStyle:
                              TextStyle(color: AppTheme.textPrimary),
                          selectedDecoration: BoxDecoration(
                            color: AppTheme.primaryBlue,
                            shape: BoxShape.circle,
                          ),
                          todayDecoration: BoxDecoration(
                            color: Color(0xFFBBDEFB),
                            shape: BoxShape.circle,
                          ),
                          todayTextStyle: TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.bold),
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        calendarBuilders: CalendarBuilders(
                          defaultBuilder: (ctx, day, focusedDay) {
                            final count = _countFor(day);
                            return Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _colorFor(count),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: count >= 4
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Légende
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Intensité',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _Legend(color: Colors.grey.shade200, label: '0'),
                              _Legend(
                                  color: AppTheme.primaryBlue.withOpacity(0.25),
                                  label: '1–2'),
                              _Legend(
                                  color: AppTheme.primaryBlue.withOpacity(0.55),
                                  label: '3–4'),
                              _Legend(
                                  color: AppTheme.primaryBlue, label: '5+'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Stats globales
                  const SizedBox(height: 10),
                  _GlobalStats(activeDays: _activeDays),

                  // Récupération (onglet Repos du web)
                  const SizedBox(height: 10),
                  _RestCard(dates: _activeDays.keys.toList()),
                ],
              ),
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.borderColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _GlobalStats extends StatelessWidget {
  final Map<DateTime, int> activeDays;

  const _GlobalStats({required this.activeDays});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonth = activeDays.keys
        .where((d) => d.year == now.year && d.month == now.month)
        .length;
    final thisYear = activeDays.keys.where((d) => d.year == now.year).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(value: '$thisMonth', label: 'Ce mois'),
            _StatItem(value: '$thisYear', label: 'Cette année'),
            _StatItem(value: '${activeDays.length}', label: 'Total (6 mois)'),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryBlue)),
        Text(label,
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// Repos entre séances : moyenne, habitude, plus longue coupure, prochaine
/// séance suggérée et dernières tranches de récupération.
/// Période d'analyse de la récupération (comme les Stats).
enum _RestPeriod {
  d30('30 j', 30),
  m3('3 mois', 90),
  m6('6 mois', 180),
  all('Tout', null);

  final String label;
  final int? days;
  const _RestPeriod(this.label, this.days);
}

/// Repos entre séances sur la période choisie : moyenne, habitude, plus
/// longue coupure, prochaine séance suggérée et dernières reprises.
class _RestCard extends StatefulWidget {
  final List<DateTime> dates;

  const _RestCard({required this.dates});

  @override
  State<_RestCard> createState() => _RestCardState();
}

class _RestCardState extends State<_RestCard> {
  _RestPeriod _period = _RestPeriod.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = sessionDatesSince(widget.dates, _period.days);
    final r = computeRest(dates);
    final sessions = {for (final d in dates) DateTime(d.year, d.month, d.day)}.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Récupération', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_RestPeriod>(
                segments: [
                  for (final p in _RestPeriod.values)
                    ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {_period},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
            const SizedBox(height: 12),
            if (r == null)
              Text(
                sessions == 0
                    ? 'Aucune séance sur cette période.'
                    : 'Une seule séance sur cette période : il en faut au moins '
                        'deux pour analyser la récupération.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              Text('$sessions séances analysées',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _RestMetric('${r.mean.round()} j', 'Repos moyen'),
                  _RestMetric('${r.mode} j', 'Habituel'),
                  _RestMetric('${r.longest} j', 'Plus longue\ncoupure'),
                ],
              ),
              const SizedBox(height: 12),
              _NextSession(next: r.nextSession),
              const SizedBox(height: 12),
              Text('Dernières reprises', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final g in r.gaps.reversed.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(DateFormat('EEEE d MMMM yyyy', 'fr_FR')
                            .format(g.resume)),
                      ),
                      Text(g.restDays == 0
                          ? 'enchaîné'
                          : '${g.restDays} j de repos'),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RestMetric extends StatelessWidget {
  final String value;
  final String label;

  const _RestMetric(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryBlue)),
        Text(label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _NextSession extends StatelessWidget {
  final DateTime next;

  const _NextSession({required this.next});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final delta = next.difference(today).inDays;
    final (String text, Color color) = delta > 0
        ? ('Prochaine séance conseillée : '
              '${DateFormat('EEEE d MMMM', 'fr_FR').format(next)}',
            Colors.green.shade700)
        : delta == 0
            ? ('Séance conseillée aujourd\'hui', Colors.green.shade700)
            : ('Séance conseillée depuis le '
                  '${DateFormat('d MMMM', 'fr_FR').format(next)} '
                  '(${-delta} j de retard)',
                Colors.orange.shade800);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}
