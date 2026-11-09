import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/perf.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class RecordsScreen extends StatefulWidget {
  final String userId;

  const RecordsScreen({super.key, required this.userId});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final records = await SupabaseService.instance.getRecords(widget.userId);
    setState(() { _records = records; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
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
          : _records.isEmpty
              ? Center(
                  child: Text('Aucun record',
                      style: Theme.of(context).textTheme.bodyMedium),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final entry = _records[i];
                    final exercice = entry['exercice'] as String;
                    final perf = entry['perf'] as Perf;
                    return _RecordTile(exercice: exercice, perf: perf);
                  },
                ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final String exercice;
  final Perf perf;

  const _RecordTile({required this.exercice, required this.perf});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.emoji_events,
                  color: Color(0xFFFFC107), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exercice,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${perf.isPlanche ? "${perf.variante} · ${perf.forme} · " : ""}${DateFormat('d MMM yyyy', 'fr_FR').format(perf.date)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  perf.displayValue,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlue),
                ),
                if ((perf.effortPondere ?? 0) > 0)
                  Text(
                    '${perf.effortPondere} pts',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
