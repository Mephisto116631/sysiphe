import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/perf.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/load_error.dart';

/// Coefficients du calcul d'effort planche, partagés avec l'app web
/// (colonnes *_config de user_settings).
class CalibrationScreen extends StatefulWidget {
  final String userId;

  const CalibrationScreen({super.key, required this.userId});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _Section {
  final String key; // colonne user_settings
  final String title;
  final String help;
  final Map<String, double> defaults;
  const _Section(this.key, this.title, this.help, this.defaults);
}

const _sections = [
  _Section('variantes_config', 'Variantes', 'Score de difficulté de la variante',
      kVariantes),
  _Section('formes_config', 'Formes', 'Facteur de position des hanches', kFormes),
  _Section('elastiques_config', 'Élastiques', 'Aide de l\'élastique (kg)',
      kElastiques),
  _Section('tensions_config', 'Tensions', 'Part de l\'aide transmise (0–1)',
      kTensions),
];

class _CalibrationScreenState extends State<CalibrationScreen> {
  // section → clé → contrôleur
  final _ctrls = <String, Map<String, TextEditingController>>{};
  double _weight = 97;
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final m in _ctrls.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final s = await SupabaseService.instance.getSettings(widget.userId);
      if (!mounted) return;
      setState(() {
        _weight = (s['weight'] as num?)?.toDouble() ?? 97;
        for (final sec in _sections) {
          final merged = mergeConfig(s[sec.key], sec.defaults);
          final m = _ctrls.putIfAbsent(sec.key, () => {});
          merged.forEach((k, v) {
            (m[k] ??= TextEditingController()).text = _fmt(v);
          });
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  static String _fmt(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  /// Lit les champs ; null si l'un d'eux est invalide.
  Map<String, Map<String, double>>? _read() {
    final out = <String, Map<String, double>>{};
    for (final sec in _sections) {
      final m = <String, double>{};
      for (final e in _ctrls[sec.key]!.entries) {
        final v = double.tryParse(e.value.text.replaceAll(',', '.'));
        if (v == null || v < 0) return null;
        m[e.key] = v;
      }
      out[sec.key] = m;
    }
    return out;
  }

  void _resetDefaults() {
    setState(() {
      for (final sec in _sections) {
        sec.defaults.forEach((k, v) => _ctrls[sec.key]![k]?.text = _fmt(v));
      }
    });
    _snack('Valeurs par défaut rétablies — pensez à enregistrer');
  }

  Future<void> _save({required bool recalc}) async {
    final cfg = _read();
    if (cfg == null) {
      _snack('Valeur invalide : nombres positifs uniquement', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await SupabaseService.instance.saveSettings(widget.userId, cfg);
      var msg = 'Calibration enregistrée';
      if (recalc) {
        final n = await SupabaseService.instance.recalculateEfforts(
          widget.userId,
          weight: _weight,
          variantes: cfg['variantes_config']!,
          formes: cfg['formes_config']!,
          elastiques: cfg['elastiques_config']!,
          tensions: cfg['tensions_config']!,
        );
        msg = '$msg · $n séries de planche recalculées';
      }
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack('Erreur : $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibration planche'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Valeurs par défaut',
            onPressed: _loading || _busy ? null : _resetDefaults,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? LoadError(error: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Effort = temps × (poids effectif / 100)² × '
                      '(variante × forme)^1,2 / 100\n'
                      'Poids effectif = poids (${_fmt(_weight)} kg) − élastique × tension',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    for (final sec in _sections) _buildSection(context, sec),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _save(recalc: true),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.calculate),
                      label: const Text('Enregistrer et recalculer'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _save(recalc: false),
                      child: const Text('Enregistrer sans recalculer'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Le recalcul met à jour l\'effort de toutes vos séries de '
                      'planche avec ces coefficients et votre poids actuel.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _buildSection(BuildContext context, _Section sec) {
    final ctrls = _ctrls[sec.key]!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sec.title, style: Theme.of(context).textTheme.titleMedium),
            Text(sec.help, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final e in ctrls.entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: e.value,
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                        ],
                        decoration: InputDecoration(
                          isDense: true,
                          helperText: sec.defaults.containsKey(e.key)
                              ? 'défaut ${_fmt(sec.defaults[e.key]!)}'
                              : null,
                          helperStyle: const TextStyle(
                              fontSize: 10, color: AppTheme.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
