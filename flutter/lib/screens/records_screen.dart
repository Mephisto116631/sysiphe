import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/stats.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/load_error.dart';

/// Records, comme l'onglet Records du web : planche par combinaison
/// variante / élastique / tension, musculation par meilleure séance.
class RecordsScreen extends StatefulWidget {
  final String userId;

  const RecordsScreen({super.key, required this.userId});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  List<PlancheRecord> _planche = [];
  List<VolumeRecord> _volume = [];
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
      final all = await SupabaseService.instance.getAllPerfs(widget.userId);
      if (!mounted) return;
      setState(() {
        _planche = plancheRecords(all);
        _volume = volumeRecords(all);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Records'),
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
              : _planche.isEmpty && _volume.isEmpty
                  ? Center(
                      child: Text('Aucun record',
                          style: theme.textTheme.bodyMedium))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_planche.isNotEmpty) ...[
                          Text('Planche', style: theme.textTheme.titleMedium),
                          Text('Meilleure série par variante, élastique et tension',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          for (var i = 0; i < _planche.length; i++)
                            _PlancheTile(
                              r: _planche[i],
                              // Intensité relative au meilleur effort.
                              ratio: (_planche[i].best.effortPondere ?? 0) /
                                  (_planche.first.best.effortPondere ?? 1),
                              first: i == 0,
                            ),
                          const SizedBox(height: 20),
                        ],
                        if (_volume.isNotEmpty) ...[
                          Text('Musculation', style: theme.textTheme.titleMedium),
                          Text('Meilleure séance (volume ou tonnage) et meilleure série',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          for (final r in _volume) _VolumeTile(r: r),
                        ],
                      ],
                    ),
    );
  }
}

String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
String _date(DateTime d) => DateFormat('d MMM yyyy', 'fr_FR').format(d);

/// Vert → orange → rouge selon l'intensité (comme _intensity_color du web).
Color intensityColor(double ratio) {
  final r = ratio.clamp(0.0, 1.0);
  return r < 0.5
      ? Color.lerp(const Color(0xFF22C55E), const Color(0xFFF59E0B), r / 0.5)!
      : Color.lerp(const Color(0xFFF59E0B), const Color(0xFFEF4444), (r - 0.5) / 0.5)!;
}

class _PlancheTile extends StatelessWidget {
  final PlancheRecord r;
  final double ratio;
  final bool first;

  const _PlancheTile({required this.r, required this.ratio, required this.first});

  @override
  Widget build(BuildContext context) {
    final color = intensityColor(ratio);
    final aide = r.elastique == 'Aucun'
        ? 'Sans élastique'
        : '${r.elastique} · ${r.tension}';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(first ? Icons.emoji_events : Icons.bolt, color: color),
        ),
        title: Text('${r.variante} · ${r.best.forme}'),
        subtitle: Text('$aide\n${_date(r.best.date)}'),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${r.best.effortPondere} pts',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text('${_fmt(r.best.performance)} s',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _VolumeTile extends StatelessWidget {
  final VolumeRecord r;

  const _VolumeTile({required this.r});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFF8E1),
          child: Icon(Icons.emoji_events, color: Color(0xFFFFC107)),
        ),
        title: Text(r.exercice),
        subtitle: Text('Meilleure série : ${_fmt(r.bestSerie)} · ${_date(r.date)}'),
        trailing: Text(
          r.tonnage ? '${_fmt(r.volume)} kg' : _fmt(r.volume),
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryBlue),
        ),
      ),
    );
  }
}
