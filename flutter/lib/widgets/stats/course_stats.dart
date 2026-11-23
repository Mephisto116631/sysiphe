import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/course.dart';
import '../../services/data_events.dart';
import '../../services/supabase_service.dart';
import '../../theme.dart';
import 'stat_cards.dart';

/// Stats → Course (version course) : totaux de la période, distance par
/// semaine, allure moyenne de chaque course.
class CourseStatsTab extends StatefulWidget {
  final String userId;
  final int? days; // période (null = tout)

  /// Courses fournies directement (tests).
  final List<Course>? initialCourses;

  const CourseStatsTab(
      {super.key, required this.userId, this.days, this.initialCourses});

  @override
  State<CourseStatsTab> createState() => _CourseStatsTabState();
}

class _CourseStatsTabState extends State<CourseStatsTab> {
  List<Course>? _all;
  Object? _error;

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dataVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = widget.initialCourses ??
          await SupabaseService.instance.getCourses(widget.userId);
      if (mounted) setState(() => _all = c);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    if (all == null) {
      return _error != null
          ? const Center(child: Text('Courses indisponibles'))
          : const Center(child: CircularProgressIndicator());
    }
    final from = widget.days == null
        ? null
        : DateTime.now().subtract(Duration(days: widget.days!));
    final courses = [
      for (final c in all)
        if (from == null || !c.debut.isBefore(from)) c
    ]..sort((a, b) => a.debut.compareTo(b.debut));
    if (courses.isEmpty) {
      return Center(
          child: Text('Aucune course sur la période',
              style: Theme.of(context).textTheme.bodyMedium));
    }
    final dist = courses.fold<int>(0, (a, c) => a + c.distanceM);
    final dur = courses.fold<int>(0, (a, c) => a + c.dureeS);
    final weeks = weeklyDistance(courses).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final paced = [
      for (final c in courses)
        if (c.paceS != null) c
    ];
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(child: StatCard(label: 'Courses', value: '${courses.length}')),
          Expanded(child: StatCard(label: 'Distance', value: formatKm(dist.toDouble()))),
          Expanded(child: StatCard(label: 'Allure moy.', value: formatPace(dist < 50 ? null : dur / dist * 1000))),
        ]),
        const SizedBox(height: 12),
        Text('Distance par semaine (km)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            barGroups: [
              for (var i = 0; i < weeks.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                      toY: weeks[i].value / 1000,
                      width: (220 / weeks.length).clamp(3.0, 18.0),
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(2)),
                ]),
            ],
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppTheme.borderColor, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textSecondary)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    final every = (weeks.length / 5).ceil().clamp(1, 1000);
                    if (i < 0 || i >= weeks.length || i % every != 0) {
                      return const SizedBox.shrink();
                    }
                    return Text(DateFormat('d/MM').format(weeks[i].key),
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.textSecondary));
                  },
                ),
              ),
            ),
          )),
        ),
        if (paced.length >= 2) ...[
          const SizedBox(height: 20),
          Text('Allure moyenne (min/km)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: LineChart(LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < paced.length; i++)
                      FlSpot(i.toDouble(), paced[i].paceS! / 60),
                  ],
                  color: Colors.deepOrange,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                ),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppTheme.borderColor, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (v, _) => Text(formatPace(v * 60),
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.textSecondary)),
                  ),
                ),
              ),
            )),
          ),
        ],
      ],
    );
  }
}
