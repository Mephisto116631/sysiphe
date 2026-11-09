import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final days = await SupabaseService.instance
        .getActiveDays(widget.userId, months: 6);
    setState(() { _activeDays = days; _loading = false; });
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
