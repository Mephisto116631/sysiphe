import 'package:flutter/material.dart';
import '../models/perf.dart';
import '../models/stats.dart';
import '../services/data_events.dart';
import '../services/supabase_service.dart';
import '../services/ui_prefs.dart';
import '../theme.dart';
import '../widgets/load_error.dart';
import '../widgets/stats/category_bars.dart';
import '../widgets/stats/multi_line_chart.dart';
import '../widgets/stats/series_legend.dart';
import '../widgets/stats/stat_cards.dart';

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

/// Nombre maximal d'exercices comparés (au-delà, illisible sur un téléphone).
const kMaxCompared = 5;
const _chartHeight = 260.0;

/// Onglet Stats : un exercice (courbe, record, tendance ; planche par
/// variante), comparaison de plusieurs exercices, séries par catégorie.
class StatsScreen extends StatefulWidget {
  final String userId;

  /// Historique fourni directement (tests) : pas d'accès réseau.
  final List<Perf>? initialPerfs;

  const StatsScreen({super.key, required this.userId, this.initialPerfs});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  List<Perf> _all = []; // tout l'historique, chargé une fois
  List<String> _exercices = []; // ordre alphabétique (menu)
  List<String> _recent = []; // du plus récent au plus ancien (comparaison)
  String? _selected;
  _Period _period = _Period.all;
  bool _plancheTime = false; // planche : effort (défaut) ou temps
  bool _byVariante = false; // planche : une courbe par variante
  final Set<String> _hiddenVariantes = {};
  List<String> _compared = [];
  bool _comparePct = true; // comparaison en % du record
  final Set<String> _hiddenCategories = {};
  bool _loading = true;
  Object? _error;

  void _onDataChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    dataVersion.removeListener(_onDataChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    dataVersion.addListener(_onDataChanged);
    _restorePrefs();
    _load();
  }

  String get _compareKey => 'stats_compare_${widget.userId}';

  /// Filtres mémorisés sur l'appareil : période, mode de la planche, options
  /// de comparaison (l'exercice est restauré au chargement, par profil).
  Future<void> _restorePrefs() async {
    final p = await UiPrefs.getString('stats_period');
    final t = await UiPrefs.getBool('stats_planche_time');
    final v = await UiPrefs.getBool('stats_par_variante');
    final pct = await UiPrefs.getBool('stats_compare_pct');
    if (!mounted) return;
    setState(() {
      for (final e in _Period.values) {
        if (e.name == p) _period = e;
      }
      _plancheTime = t ?? _plancheTime;
      _byVariante = v ?? _byVariante;
      _comparePct = pct ?? _comparePct;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = widget.initialPerfs ??
          await SupabaseService.instance.getAllPerfs(widget.userId);
      if (!mounted) return;
      final names = {
        for (final p in all)
          if (p.exercice.isNotEmpty) p.exercice
      }.toList()
        ..sort();
      final lastDay = <String, DateTime>{};
      for (final p in all) {
        final d = lastDay[p.exercice];
        if (d == null || p.date.isAfter(d)) lastDay[p.exercice] = p.date;
      }
      final recent = [...names]
        ..sort((a, b) => lastDay[b]!.compareTo(lastDay[a]!));
      final saved = await UiPrefs.getString('stats_exercice_${widget.userId}');
      final savedCompare = await UiPrefs.getString(_compareKey);
      if (!mounted) return;
      setState(() {
        _all = all;
        _exercices = names;
        _recent = recent;
        if (_selected == null && saved != null && names.contains(saved)) {
          _selected = saved; // dernier exercice regardé
        }
        if (_selected == null || !names.contains(_selected)) {
          // Par défaut : la planche si elle existe, sinon l'exercice le
          // plus récent.
          final planche = names.where(Perf.isPlancheName);
          _selected = planche.isNotEmpty
              ? planche.first
              : (recent.isNotEmpty ? recent.first : null);
        }
        final kept = (savedCompare ?? '')
            .split('\n')
            .where(names.contains)
            .take(kMaxCompared)
            .toList();
        // Par défaut : les 3 exercices les plus récents.
        _compared = kept.isNotEmpty ? kept : recent.take(3).toList();
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

  /// Séries de la période choisie (tous exercices).
  List<Perf> get _inPeriod {
    final days = _period.days;
    if (days == null) return _all;
    final from = DateTime.now().subtract(Duration(days: days));
    return _all.where((p) => !p.date.isBefore(from)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stats'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
                tooltip: 'Actualiser'),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Exercice'),
            Tab(text: 'Comparer'),
            Tab(text: 'Catégories'),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? LoadError(error: _error!, onRetry: _load)
                : _exercices.isEmpty
                    ? Center(
                        child: Text('Aucune donnée',
                            style: Theme.of(context).textTheme.bodyMedium))
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: _periodSelector(),
                          ),
                          Expanded(
                            child: TabBarView(children: [
                              _exerciseTab(context),
                              _compareTab(context),
                              _categoriesTab(context),
                            ]),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _periodSelector() => SizedBox(
        width: double.infinity,
        child: SegmentedButton<_Period>(
          segments: [
            for (final p in _Period.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {_period},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            setState(() => _period = s.first);
            UiPrefs.setString('stats_period', s.first.name);
          },
        ),
      );

  Widget _empty(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );

  // ─── Onglet Exercice ──────────────────────────────────────────────────────

  Widget _exerciseTab(BuildContext context) {
    final perfs = _inPeriod.where((p) => p.exercice == _selected).toList();
    final isPlanche = perfs.isNotEmpty && perfs.first.isPlanche;
    final metric =
        isPlanche && _plancheTime ? StatMetric.best : metricFor(perfs);
    final points = dailySeries(perfs, metric);
    final unit = metric.unit(perfs.isEmpty ? 'Sec' : perfs.first.unite);
    final variantes = isPlanche && _byVariante
        ? forwardFill(seriesByVariante(perfs, time: _plancheTime))
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          value: _selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Exercice'),
          items: _exercices
              .map((e) => DropdownMenuItem(
                  value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) {
            setState(() => _selected = v);
            if (v != null) {
              UiPrefs.setString('stats_exercice_${widget.userId}', v);
            }
          },
        ),
        if (isPlanche) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
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
              onSelectionChanged: (s) {
                setState(() => _plancheTime = s.first);
                UiPrefs.setBool('stats_planche_time', s.first);
              },
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              avatar: const Icon(Icons.stacked_line_chart, size: 18),
              label: const Text('Par variante'),
              selected: _byVariante,
              showCheckmark: false,
              onSelected: (v) {
                setState(() => _byVariante = v);
                UiPrefs.setBool('stats_par_variante', v);
              },
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (points.isEmpty)
          _empty(context, 'Aucune séance sur cette période')
        else ...[
          StatRow(points: points, unit: unit),
          const SizedBox(height: 12),
          TrendBadge(result: detectPlateau(points)),
          const SizedBox(height: 16),
          Text(
              variantes == null ? metric.label : '${metric.label} par variante',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (variantes == null)
            SizedBox(
              height: _chartHeight,
              child: MultiLineChart(series: [
                ChartSeries(_selected ?? '', points, AppTheme.primaryBlue)
              ], unit: unit),
            )
          else ...[
            SeriesLegend(
              items: [
                for (final (i, v) in variantes.keys.indexed)
                  (v, AppTheme.seriesColor(i))
              ],
              hidden: _hiddenVariantes,
              onToggle: (v) => setState(() => _hiddenVariantes.contains(v)
                  ? _hiddenVariantes.remove(v)
                  : _hiddenVariantes.add(v)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: _chartHeight,
              child: MultiLineChart(series: [
                for (final (i, e) in variantes.entries.indexed)
                  if (!_hiddenVariantes.contains(e.key))
                    ChartSeries(e.key, e.value, AppTheme.seriesColor(i)),
              ], unit: unit),
            ),
          ],
        ],
      ],
    );
  }

  // ─── Onglet Comparer ──────────────────────────────────────────────────────

  void _toggleCompared(String e) {
    setState(() {
      if (_compared.contains(e)) {
        _compared = [..._compared]..remove(e);
      } else if (_compared.length < kMaxCompared) {
        _compared = [..._compared, e];
      }
    });
    UiPrefs.setString(_compareKey, _compared.join('\n'));
  }

  Widget _compareTab(BuildContext context) {
    final period = _inPeriod;
    final raw = <String, List<DayPoint>>{};
    final units = <String, String>{};
    for (final e in _compared) {
      final perfs = period.where((p) => p.exercice == e).toList();
      final metric = metricFor(perfs);
      raw[e] = dailySeries(perfs, metric);
      units[e] = metric.unit(perfs.isEmpty ? 'Reps' : perfs.first.unite);
    }
    final lines = forwardFill({
      for (final e in raw.entries)
        e.key: _comparePct ? normalizeToBest(e.value) : e.value,
    });
    Color color(String e) => AppTheme.seriesColor(_compared.indexOf(e));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Exercices (jusqu\'à $kMaxCompared)',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final e in _recent)
              FilterChip(
                avatar: _compared.contains(e)
                    ? CircleAvatar(backgroundColor: color(e), radius: 6)
                    : null,
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(e, overflow: TextOverflow.ellipsis),
                ),
                selected: _compared.contains(e),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected:
                    !_compared.contains(e) && _compared.length >= kMaxCompared
                        ? null
                        : (_) => _toggleCompared(e),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('En % du record')),
              ButtonSegment(value: false, label: Text('Valeurs brutes')),
            ],
            selected: {_comparePct},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              setState(() => _comparePct = s.first);
              UiPrefs.setBool('stats_compare_pct', s.first);
            },
          ),
        ),
        const SizedBox(height: 16),
        if (_compared.isEmpty)
          _empty(context, 'Choisis des exercices à comparer')
        else if (lines.values.every((l) => l.isEmpty))
          _empty(context, 'Aucune séance sur cette période')
        else ...[
          Text(
              _comparePct
                  ? '100 % = meilleure séance de la période'
                  : 'Volume, tonnage, effort ou meilleure valeur selon '
                      'l\'exercice',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            height: _chartHeight,
            child: MultiLineChart(
              series: [
                for (final e in _compared)
                  ChartSeries(e, lines[e] ?? const [], color(e)),
              ],
              unitOf: (e) => _comparePct ? ' %' : units[e] ?? '',
            ),
          ),
          const SizedBox(height: 16),
          for (final e in _compared)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: CircleAvatar(backgroundColor: color(e), radius: 6),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        TrendBadge(result: detectPlateau(raw[e] ?? const [])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  // ─── Onglet Catégories ────────────────────────────────────────────────────

  Widget _categoriesTab(BuildContext context) {
    final bucket = _period == _Period.all ? Bucket.month : Bucket.week;
    final buckets = setsByCategory(_inPeriod, bucket);
    final totals = <String, int>{};
    for (final (_, m) in buckets) {
      m.forEach((c, n) => totals[c] = (totals[c] ?? 0) + n);
    }
    final categories = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    final shown = [
      for (final (d, m) in buckets)
        (
          d,
          {
            for (final e in m.entries)
              if (!_hiddenCategories.contains(e.key)) e.key: e.value
          }
        )
    ];
    final sum = totals.values.fold<int>(0, (a, b) => a + b);
    String label(String c) => '$c · ${totals[c]}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
            'Séries par catégorie, par '
            '${bucket == Bucket.month ? 'mois' : 'semaine'}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (buckets.isEmpty)
          _empty(context, 'Aucune séance sur cette période')
        else ...[
          SeriesLegend(
            items: [
              for (final (i, c) in categories.indexed)
                (label(c), AppTheme.seriesColor(i))
            ],
            hidden: {for (final c in _hiddenCategories) label(c)},
            onToggle: (l) {
              final c = categories.firstWhere((c) => label(c) == l);
              setState(() => _hiddenCategories.contains(c)
                  ? _hiddenCategories.remove(c)
                  : _hiddenCategories.add(c));
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: _chartHeight,
            child: CategoryBars(
                buckets: shown, categories: categories, bucket: bucket),
          ),
          const SizedBox(height: 12),
          Text('$sum séries sur la période',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}
