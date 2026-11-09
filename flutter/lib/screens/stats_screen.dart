import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/perf.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class StatsScreen extends StatefulWidget {
  final String userId;

  const StatsScreen({super.key, required this.userId});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<String> _exercices = [];
  String? _selected;
  List<Perf> _perfs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExercices();
  }

  Future<void> _loadExercices() async {
    setState(() => _loading = true);
    final names =
        await SupabaseService.instance.getExerciceNames(widget.userId);
    setState(() {
      _exercices = names;
      _selected = names.isNotEmpty ? names.first : null;
      _loading = false;
    });
    if (_selected != null) _loadPerfs(_selected!);
  }

  Future<void> _loadPerfs(String exercice) async {
    setState(() { _loading = true; _perfs = []; });
    final all = await SupabaseService.instance
        .getRecentPerfs(widget.userId, days: 180);
    setState(() {
      _perfs = all.where((p) => p.exercice == exercice).toList();
      _loading = false;
    });
  }

  List<FlSpot> get _spots {
    if (_perfs.isEmpty) return [];
    final origin = _perfs.first.date;
    return _perfs.map((p) {
      final x = p.date.difference(origin).inDays.toDouble();
      return FlSpot(x, p.performance);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Sélecteur d'exercice
            if (_exercices.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selected,
                decoration: const InputDecoration(labelText: 'Exercice'),
                items: _exercices
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selected = v);
                    _loadPerfs(v);
                  }
                },
              ),
            const SizedBox(height: 20),

            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_perfs.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _selected == null
                        ? 'Aucune donnée'
                        : 'Aucune perf pour "$_selected"',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stat rapide
                    _StatRow(perfs: _perfs),
                    const SizedBox(height: 20),
                    Text('Progression',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Expanded(child: _LineChart(spots: _spots, perfs: _perfs)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final List<Perf> perfs;

  const _StatRow({required this.perfs});

  @override
  Widget build(BuildContext context) {
    final max = perfs.map((p) => p.performance).reduce((a, b) => a > b ? a : b);
    final last = perfs.last;
    final unite = perfs.first.unite;
    final suffix = unite == 'Sec' ? 's' : unite;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Record',
            value:
                '${max % 1 == 0 ? max.toInt() : max.toStringAsFixed(1)}$suffix',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Dernière perf',
            value:
                '${last.performance % 1 == 0 ? last.performance.toInt() : last.performance.toStringAsFixed(1)}$suffix',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(label: 'Séries (total)', value: '${perfs.length}'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue)),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final List<Perf> perfs;

  const _LineChart({required this.spots, required this.perfs});

  @override
  Widget build(BuildContext context) {
    final minX = spots.first.x;
    final maxX = spots.last.x;
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 0.9;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.1;
    final origin = perfs.first.date;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY.clamp(0, double.infinity),
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: AppTheme.primaryBlue,
            barWidth: 2.5,
            dotData: FlDotData(
              show: spots.length <= 20,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: AppTheme.primaryBlue,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primaryBlue.withOpacity(0.08),
            ),
          ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY.clamp(0, double.infinity)) / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppTheme.borderColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (val, meta) => Text(
                val.toInt().toString(),
                style: const TextStyle(
                    fontSize: 10, color: AppTheme.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (maxX - minX).clamp(1, double.infinity) / 4,
              getTitlesWidget: (val, meta) {
                final date = origin.add(Duration(days: val.toInt()));
                return Text(
                  DateFormat('d/MM').format(date),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              final p = perfs[s.spotIndex];
              return LineTooltipItem(
                '${p.displayValue}\n${DateFormat('d MMM', 'fr_FR').format(p.date)}',
                const TextStyle(
                    color: Colors.white, fontSize: 12, height: 1.4),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
