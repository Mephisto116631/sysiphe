import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/interval_plan.dart';
import '../models/perf.dart';
import '../services/data_events.dart';
import '../services/supabase_service.dart';
import '../services/timer_alerts.dart';
import '../theme.dart';

/// Minuteur d'intervalles façon HIIT : Préparation → Exercice → Repos → … ×
/// cycles. Couleur par phase, gros décompte, vibrations sur les 3 dernières
/// secondes et à chaque changement, écran maintenu allumé, notifications si
/// l'app passe en arrière-plan.
class MinuteurScreen extends StatefulWidget {
  /// Profil : la séance est proposée à l'enregistrement à la fin (null :
  /// pas d'enregistrement).
  final String? userId;

  /// Tests : enregistrement et numéro de la première série fournis.
  final Future<bool> Function(List<Perf>)? save;
  final Future<int> Function(String exercice)? firstSerie;

  const MinuteurScreen({super.key, this.userId, this.save, this.firstSerie});

  @override
  State<MinuteurScreen> createState() => _MinuteurScreenState();
}

class _MinuteurScreenState extends State<MinuteurScreen>
    with WidgetsBindingObserver {
  static const _prefKey = 'minuteur_config'; // « prep,work,rest,cycles »

  IntervalConfig _cfg = const IntervalConfig();
  IntervalPlan? _plan;
  bool _running = false;
  bool _paused = false;
  bool _done = false;
  DateTime? _startAt;
  DateTime? _pausedAt;
  Duration _pausedTotal = Duration.zero;
  Duration _skipped = Duration.zero;
  Timer? _tick;
  int _lastIndex = -1;
  int _lastSec = -1;
  IntervalLog? _log; // cycles faits, pour l'enregistrement
  Duration _phaseStart = Duration.zero; // temps réel au début de la phase
  bool _offered = false; // enregistrement déjà proposé pour cette séance

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfig();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    WakelockPlus.disable();
    TimerAlerts.cancelAll();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = (p.getString(_prefKey) ?? '').split(',').map(int.tryParse).toList();
      if (v.length == 4 && !v.contains(null) && mounted) {
        setState(() => _cfg = IntervalConfig(
            prep: v[0]!, work: v[1]!, rest: v[2]!, cycles: v[3]!));
      }
    } catch (_) {}
  }

  Future<void> _saveConfig() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _prefKey, '${_cfg.prep},${_cfg.work},${_cfg.rest},${_cfg.cycles}');
    } catch (_) {}
  }

  Duration get _elapsed => _real + _skipped;

  /// Temps réellement passé (sans pauses ni phases sautées).
  Duration get _real {
    final ref = _pausedAt ?? DateTime.now();
    return ref.difference(_startAt!) - _pausedTotal;
  }

  /// La phase en cours se termine (fin, passée, ou séance arrêtée) : son
  /// temps réel est noté dans le journal.
  void _endPhase() {
    final plan = _plan, log = _log;
    if (plan == null || log == null || _lastIndex < 0) return;
    final s = ((_real - _phaseStart).inMilliseconds / 1000).round();
    log.phaseEnded(plan.phases[_lastIndex], s);
    _phaseStart = _real;
  }

  // ---------------------------------------------------------------- contrôle

  void _start() {
    final plan = IntervalPlan(_cfg);
    if (plan.phases.isEmpty) return;
    _saveConfig();
    TimerAlerts.requestPermission();
    WakelockPlus.enable();
    setState(() {
      _plan = plan;
      _running = true;
      _paused = false;
      _done = false;
      _startAt = DateTime.now();
      _pausedAt = null;
      _pausedTotal = Duration.zero;
      _skipped = Duration.zero;
      _lastIndex = -1;
      _lastSec = -1;
      _log = IntervalLog(_cfg);
      _phaseStart = Duration.zero;
      _offered = false;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) => _onTick());
    _onTick();
  }

  void _onTick() {
    if (!mounted || _plan == null || _paused || !_running) return;
    final pos = _plan!.at(_elapsed);
    if (pos.finished) {
      _endPhase();
      _lastIndex = -1;
      _finish();
      return;
    }
    if (pos.index != _lastIndex) {
      _endPhase();
      _lastIndex = pos.index;
      _lastSec = -1;
      HapticFeedback.heavyImpact(); // changement de phase
    }
    final left = (pos.left.inMilliseconds / 1000).ceil();
    if (left != _lastSec) {
      _lastSec = left;
      if (left <= 3 && left > 0) HapticFeedback.selectionClick();
    }
    setState(() {});
  }

  Future<void> _finish() async {
    _tick?.cancel();
    WakelockPlus.disable();
    // Écran éteint : la notification « Terminé » reste jusqu'au retour.
    TimerAlerts.cancelIfForeground();
    setState(() {
      _running = false;
      _done = true;
    });
    for (var i = 0; i < 3; i++) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 250));
    }
    await _offerSave();
  }

  /// Propose d'enregistrer la séance : un cycle = une série en secondes,
  /// avec le repos choisi et le repos réellement pris avant elle.
  Future<void> _offerSave() async {
    final log = _log;
    final uid = widget.userId;
    if (_offered || log == null || log.rounds.isEmpty || uid == null) return;
    _offered = true;
    if (!mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => IntervalSaveDialog(
          log: log, initialName: intervalExerciseName(log.config)),
    );
    if (name == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final first = await (widget.firstSerie ?? (ex) => _firstSerie(uid, ex))(name);
      final today = DateTime.now();
      final perfs = [
        for (var i = 0; i < log.rounds.length; i++)
          Perf(
            userId: uid,
            date: DateTime(today.year, today.month, today.day),
            exercice: name,
            serie: first + i,
            performance: log.rounds[i].workS.toDouble(),
            unite: 'Sec',
            categorie: 'Cardio',
            reposS: log.rounds[i].restBeforeS,
            reposPrevuS:
                log.rounds[i].restBeforeS == null ? null : log.rounds[i].restPlannedS,
          ),
      ];
      final sent =
          await (widget.save ?? SupabaseService.instance.savePerfs)(perfs);
      notifyDataChanged(); // Saisie, Stats, Calendrier
      messenger.showSnackBar(SnackBar(
        content: Text(sent
            ? '« $name » enregistré ✓ (${perfs.length} séries)'
            : '« $name » enregistré hors ligne ✓ (envoi automatique)'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Enregistrement impossible : $e'),
          behavior: SnackBarBehavior.floating));
    }
  }

  /// Numéro de la première série : après celles déjà faites aujourd'hui.
  static Future<int> _firstSerie(String uid, String ex) async {
    try {
      final today = await SupabaseService.instance
          .getPerfsForDate(uid, DateTime.now());
      final done = [
        for (final p in today)
          if (p.exercice.trim().toLowerCase() == ex.trim().toLowerCase())
            p.serie
      ];
      return done.isEmpty ? 1 : done.reduce((a, b) => a > b ? a : b) + 1;
    } catch (_) {
      return 1;
    }
  }

  void _pauseResume() {
    if (_paused) {
      _pausedTotal += DateTime.now().difference(_pausedAt!);
      setState(() {
        _pausedAt = null;
        _paused = false;
      });
    } else {
      setState(() {
        _pausedAt = DateTime.now();
        _paused = true;
      });
      TimerAlerts.cancelAll();
    }
  }

  void _skip() {
    final plan = _plan;
    if (plan == null) return;
    final pos = plan.at(_elapsed);
    if (pos.finished) return;
    _skipped += pos.left; // saute à la phase suivante
    _onTick();
  }

  Future<void> _stop() async {
    _tick?.cancel();
    WakelockPlus.disable();
    TimerAlerts.cancelAll();
    // Arrêt en cours de séance : la phase en cours compte (cycle entamé).
    if (_running) {
      _endPhase();
      _lastIndex = -1;
    }
    setState(() {
      _running = false;
      _paused = false;
      _done = false;
    });
    await _offerSave();
  }

  Future<bool> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arrêter le minuteur ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuer')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Arrêter')),
        ],
      ),
    );
    return ok ?? false;
  }

  // Au premier plan, le minuteur vibre ; en arrière-plan, on programme les
  // notifications des changements de phase restants.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _running && !_paused) {
      _scheduleBackground();
    } else if (state == AppLifecycleState.resumed) {
      TimerAlerts.cancelAll();
    }
  }

  void _scheduleBackground() {
    final plan = _plan;
    if (plan == null) return;
    final el = _elapsed;
    final alerts = <TimerAlert>[];
    for (var i = 1; i < plan.phases.length; i++) {
      final start = plan.startOf(i);
      if (start > el) {
        final p = plan.phases[i];
        alerts.add(TimerAlert(start - el, p.title(plan.config.cycles), p.body));
      }
    }
    alerts.add(TimerAlert(plan.total - el, 'Terminé 🎉', 'Bravo !'));
    TimerAlerts.schedule(alerts);
  }

  // ---------------------------------------------------------------------- UI

  Color _colorOf(IntervalKind k) => switch (k) {
        IntervalKind.prep => Colors.orange.shade800,
        IntervalKind.work => Colors.green.shade700,
        IntervalKind.rest => Colors.blue.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmStop() && mounted) {
          await _stop();
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: _running || _done ? _runningView() : _configView(),
    );
  }

  // ----- configuration

  Widget _configView() {
    final plan = IntervalPlan(_cfg);
    return Scaffold(
      appBar: AppBar(title: const Text('Minuteur')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final p in _presets)
                ActionChip(
                  label: Text(p.$1),
                  onPressed: () => setState(() => _cfg = p.$2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _StepperRow(
            label: 'Préparation',
            value: _cfg.prep == 0 ? 'Aucune' : formatSeconds(_cfg.prep),
            onMinus: _cfg.prep > 0
                ? () => setState(() => _cfg = _cfg.copyWith(prep: _cfg.prep - 5))
                : null,
            onPlus: _cfg.prep < 120
                ? () => setState(() => _cfg = _cfg.copyWith(prep: _cfg.prep + 5))
                : null,
          ),
          _StepperRow(
            label: 'Exercice',
            value: formatSeconds(_cfg.work),
            onMinus: _cfg.work > 5
                ? () => setState(() => _cfg = _cfg.copyWith(work: _cfg.work - 5))
                : null,
            onPlus: _cfg.work < 900
                ? () => setState(() => _cfg = _cfg.copyWith(work: _cfg.work + 5))
                : null,
          ),
          _StepperRow(
            label: 'Repos',
            value: _cfg.rest == 0 ? 'Aucun' : formatSeconds(_cfg.rest),
            onMinus: _cfg.rest > 0
                ? () => setState(() => _cfg = _cfg.copyWith(rest: _cfg.rest - 5))
                : null,
            onPlus: _cfg.rest < 900
                ? () => setState(() => _cfg = _cfg.copyWith(rest: _cfg.rest + 5))
                : null,
          ),
          _StepperRow(
            label: 'Cycles',
            value: '${_cfg.cycles}',
            onMinus: _cfg.cycles > 1
                ? () => setState(() => _cfg = _cfg.copyWith(cycles: _cfg.cycles - 1))
                : null,
            onPlus: _cfg.cycles < 99
                ? () => setState(() => _cfg = _cfg.copyWith(cycles: _cfg.cycles + 1))
                : null,
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('Durée totale : ${clock(plan.total)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppTheme.textSecondary)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Démarrer', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Le téléphone vibre à chaque changement et sur les 3 dernières '
            'secondes ; l\'écran reste allumé. Si tu quittes l\'app, des '
            'notifications t\'avertissent à chaque phase.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  static const _presets = <(String, IntervalConfig)>[
    ('Tabata 20/10 ×8', IntervalConfig(prep: 10, work: 20, rest: 10, cycles: 8)),
    ('HIIT 40/20 ×10', IntervalConfig(prep: 10, work: 40, rest: 20, cycles: 10)),
    ('Gainage 45/30 ×4', IntervalConfig(prep: 5, work: 45, rest: 30, cycles: 4)),
  ];

  // ----- en cours / terminé

  Widget _runningView() {
    final plan = _plan!;
    final pos = _done ? null : plan.at(_elapsed);
    final phase = pos?.phase;
    final bg = _done || phase == null
        ? Colors.grey.shade800
        : _colorOf(phase.kind);
    final label = _done || phase == null
        ? 'TERMINÉ'
        : switch (phase.kind) {
            IntervalKind.prep => 'PRÉPARATION',
            IntervalKind.work => 'EXERCICE',
            IntervalKind.rest => 'REPOS',
          };
    final next = pos == null ? null : plan.next(pos.index);
    final totalLeft = _done ? Duration.zero : plan.total - _elapsed;
    const white = Colors.white;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: white,
        elevation: 0,
        title: Text(_done
            ? 'Minuteur'
            : 'Cycle ${phase!.cycle == 0 ? 0 : phase.cycle}/${plan.config.cycles}'),
        actions: [
          if (!_done)
            IconButton(
                tooltip: 'Arrêter',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: () async {
                  if (await _confirmStop()) _stop();
                }),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Text(label,
                  style: const TextStyle(
                      color: white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _done || pos == null
                      ? '🎉'
                      : '${(pos.left.inMilliseconds / 1000).ceil()}',
                  style: const TextStyle(
                      color: white,
                      fontSize: 168,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              if (_paused)
                const Text('EN PAUSE',
                    style: TextStyle(
                        color: white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
              const Spacer(),
              if (next != null)
                Text('Ensuite : ${next.title(plan.config.cycles)} · ${next.body}',
                    style: const TextStyle(color: white, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Temps restant ${clock(totalLeft)}',
                  style: const TextStyle(color: white, fontSize: 16)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: _done
                      ? 1
                      : (_elapsed.inMilliseconds / plan.total.inMilliseconds)
                          .clamp(0.0, 1.0),
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(white),
                ),
              ),
              const SizedBox(height: 24),
              if (_done)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: white, foregroundColor: Colors.black87),
                    onPressed: _stop,
                    child: const Text('Terminer', style: TextStyle(fontSize: 18)),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: white,
                              foregroundColor: Colors.black87),
                          onPressed: _pauseResume,
                          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                          label: Text(_paused ? 'Reprendre' : 'Pause',
                              style: const TextStyle(fontSize: 18)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: white,
                            side: const BorderSide(color: Colors.white70)),
                        onPressed: _paused ? null : _skip,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Passer'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const _StepperRow(
      {required this.label,
      required this.value,
      required this.onMinus,
      required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            IconButton.filledTonal(
                onPressed: onMinus, icon: const Icon(Icons.remove)),
            SizedBox(
              width: 92,
              child: Text(value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            IconButton.filledTonal(
                onPressed: onPlus, icon: const Icon(Icons.add)),
          ],
        ),
      ),
    );
  }
}


/// « Enregistrer la séance ? » : résumé des cycles, nom de l'exercice.
/// Renvoie le nom choisi, ou null (ignorer).
class IntervalSaveDialog extends StatefulWidget {
  final IntervalLog log;
  final String initialName;
  const IntervalSaveDialog(
      {super.key, required this.log, required this.initialName});

  @override
  State<IntervalSaveDialog> createState() => _IntervalSaveDialogState();
}

class _IntervalSaveDialogState extends State<IntervalSaveDialog> {
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final n = log.rounds.length;
    return AlertDialog(
      title: const Text('Enregistrer la séance ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$n cycle${n > 1 ? 's' : ''} · '
              '${formatSeconds(log.totalWorkS)} d\'effort'
              '${log.config.rest > 0 && n > 1 ? ' · repos ${formatSeconds(log.config.rest)}' : ''}'),
          const SizedBox(height: 4),
          Text('Une série par cycle, en catégorie Cardio, avec le repos '
              'choisi et le repos réellement pris.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('interval-name'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Exercice'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ignorer')),
        FilledButton(
          key: const ValueKey('interval-save'),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _name.text.trim()),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
