import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/perf.dart';
import '../models/stats.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/load_error.dart';

/// Périodes proposées (mêmes choix que l'onglet Stats du web).
enum _Period {
  d30('30 j', 30),
  m3('3 mois', 90),
  m6('6 mois', 180),
  all('Tout', null);

  final String label;
  final int? days;
  const _Period(this.label, this.days);
}

class StatsScreen extends StatefulWidget {
  final String userId;

  const StatsScreen({super.key, required this.userId});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<Perf> _all = []; // tout l'historique, chargé une fois
  List<String> _exercices = [];
  String? _selected;
  _Period _period = _Period.all;
  bool _plancheTime = false; // planche : effort (défaut) ou temps
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await SupabaseService.instance.getAllPerfs(widget.userId);
      if (!mounted) return;
      final names = {
        for (final p in all)
          if (p.exercice.isNotEmpty) p.exercice
      }.toList()
        ..sort();
      setState(() {
        _all = all;
        _exercices = names;
        if (_selected == null || !names.contains(_selected)) {
          // Par défaut : l'exercice de la séance la plus récente.
          _selected = all.isNotEmpty ? all.first.exercice : null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<Perf> get _filtered {
    final days = _period.days;
    final from =
        days == null ? null : DateTime.now().subtract(Duration(days: days));
    return _all
        .where((p) =>
            p.exercice == _selected && (from == null || !p.date.isBefore(from)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
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
              : _exercices.isEmpty
                  ? Center(
                      child: Text('Aucune donnée',
                          style: Theme.of(context).textTheme.bodyMedium))
                  : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final perfs = _filtered;
    final isPlanche = perfs.isNotEmpty && perfs.first.isPlanche;
    final metric =
        isPlanche && _plancheTime ? StatMetric.best : metricFor(perfs);
    final points = dailySeries(perfs, metric);
    final unit = metric.unit(perfs.isEmpty ? 'Sec' : perfs.first.unite);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Exercice'),
            items: _exercices
                .map((e) => DropdownMenuItem(
                    value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() => _selected = v),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_Period>(
            segments: [
              for (final p in _Period.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          if (isPlanche) ...[
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Effort'),
                    icon: Icon(Icons.bolt, size: 18)),
                ButtonSegment(
                    value: true,
                    label: Text('Temps'),
                    icon: Icon(Icons.timer_outlined, size: 18)),
              ],
              selected: {_plancheTime},
              onSelectionChanged: (s) => setState(() => _plancheTime = s.first),
            ),
          ],
          const SizedBox(height: 16),
          if (points.isEmpty)
            Expanded(
              child: Center(
                child: Text('Aucune séance sur cette période',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            )
          else ...[
            _StatRow(points: points, unit: unit),
            const SizedBox(height: 12),
            _TrendBadge(result: detectPlateau(points)),
            const SizedBox(height: 16),
            Text(metric.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Expanded(child: _LineChart(points: points, unit: unit)),
          ],
        ],
      ),
    );
  }
}

String _fmt(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

class _StatRow extends StatelessWidget {
  final List<DayPoint> points;
  final String unit;

  const _StatRow({required this.points, required this.unit});

  @override
  Widget build(BuildContext context) {
    final best = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final last = points.last;
    return Row(
      children: [
        Expanded(
            child: _StatCard(label: 'Record', value: '${_fmt(best)}$unit')),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label:
                'Dernière séance\n${DateFormat('d MMM', 'fr_FR').format(last.date)}',
            value: '${_fmt(last.value)}$unit',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Séances', value: '${points.length}')),
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            FittedBox(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlue)),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Tendance des 21 derniers jours de séance (port de detect_plateau).
class _TrendBadge extends StatelessWidget {
  final PlateauResult result;

  const _TrendBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = switch (result.status) {
      Trend.progress => (
          Icons.trending_up,
          Colors.green.shade700,
          'En progression (+${(result.relativeSlope * 100).round()} % sur 21 j)'
        ),
      Trend.regression => (
          Icons.trending_down,
          Colors.red.shade700,
          'En baisse (${(result.relativeSlope * 100).round()} % sur 21 j)'
        ),
      Trend.plateau => (
          Icons.trending_flat,
          Colors.orange.shade800,
          'Plateau sur les 21 derniers jours'
        ),
      Trend.insufficientData => (
          Icons.info_outline,
          AppTheme.textSecondary,
          'Pas assez de séances récentes pour une tendance'
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  final List<DayPoint> points;
  final String unit;

  const _LineChart({required this.points, required this.unit});

  @override
  Widget build(BuildContext context) {
    final origin = points.first.date;
    final spots = [
      for (final p in points)
        FlSpot(p.date.difference(origin).inDays.toDouble(), p.value),
    ];
    final minX = spots.first.x;
    final maxX = spots.last.x == minX ? minX + 1 : spots.last.x;
    final ys = spots.map((s) => s.y);
    final minY =
        (ys.reduce((a, b) => a < b ? a : b) * 0.9).clamp(0.0, double.infinity);
    var maxY = ys.reduce((a, b) => a > b ? a : b) * 1.1;
    if (maxY <= minY) maxY = minY + 1;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            curveSmoothness: 0.25,
            color: AppTheme.primaryBlue,
            barWidth: 2.5,
            dotData: FlDotData(
              show: spots.length <= 30,
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
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppTheme.borderColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
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
              interval: ((maxX - minX) / 4).clamp(1, double.infinity),
              getTitlesWidget: (val, meta) {
                final date = origin.add(Duration(days: val.toInt()));
                return Text(
                  DateFormat('d/MM/yy').format(date),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched.map((s) {
              final p = points[s.spotIndex];
              return LineTooltipItem(
                '${_fmt(p.value)}$unit\n${DateFormat('d MMM yyyy', 'fr_FR').format(p.date)}',
                const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
