import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chrono_fx.dart';
import '../services/timer_alerts.dart';
import '../theme.dart';

/// Clé du réglage « départ dans X s » (préférence de l'appareil).
const kChronoPreKey = 'chrono_pre_seconds';
const kChronoPreChoices = [0, 5, 10, 15];

/// Clé de l'objectif (décompte) : suffixée par l'exercice quand il est connu,
/// pour que la planche et le gainage gardent chacun leur temps.
const kChronoTargetKey = 'chrono_target_seconds';
const kChronoTargetChoices = [0, 30, 45, 60, 90, 120]; // 0 = libre

/// Bips activés (défaut oui) et plein écran à l'ouverture (dernier choix).
const kChronoSoundKey = 'chrono_sound';
const kChronoFullKey = 'chrono_fullscreen';

String chronoTargetKey(String? exercice) {
  final e = exercice?.trim().toLowerCase() ?? '';
  return e.isEmpty ? kChronoTargetKey : '$kChronoTargetKey:$e';
}

/// « 90 », « 1:30 », « 1m30 », « 1 min 30 », « 45s » → secondes (null si invalide).
int? parseDuree(String raw) {
  final s = raw.trim().toLowerCase().replaceAll(' ', '');
  if (s.isEmpty) return null;
  final m =
      RegExp(r'^(\d{1,3})(?::|m|min|mn|\x27)(\d{0,2})(?:s|")?$').firstMatch(s);
  if (m != null) {
    final sec = m.group(2)!.isEmpty ? 0 : int.parse(m.group(2)!);
    if (sec >= 60) return null;
    return int.parse(m.group(1)!) * 60 + sec;
  }
  final n = RegExp(r'^(\d{1,4})(?:s|sec)?$').firstMatch(s);
  return n == null ? null : int.parse(n.group(1)!);
}

/// 75 → « 1:15 », 45 → « 45 s ».
String formatDuree(int s) =>
    s < 60 ? '$s s' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Mini chronomètre pour les exercices en secondes.
/// Démarrer → compte à rebours de préparation (pour se mettre en position)
/// → le chrono démarre tout seul → Arrêter renvoie la durée (secondes
/// entières) pour remplir le champ de saisie.
///
/// Avec un **objectif** (30 s, 1:00… ou un temps libre), le chrono décompte
/// jusqu'à zéro, vibre fort à l'objectif atteint puis continue en « +0:05 » :
/// on peut tenir plus longtemps, Arrêter renvoie toujours le temps total.
/// Préparation et objectif acceptent un temps personnalisé (bouton ✎).
///
/// Bips (désactivables) sur les 3 dernières secondes de la préparation et de
/// l'objectif, au départ et à l'objectif atteint. L'écran reste allumé
/// pendant la série, et le temps peut s'afficher en plein écran (lisible
/// depuis le sol en planche) ; le dernier choix est repris à la série suivante.
///
/// Basé sur l'horloge (pas sur un compteur) : reste juste même si l'app passe
/// en arrière-plan. Dans ce cas, avant l'objectif, une notification est
/// programmée pour l'heure de fin.
class Chrono extends StatefulWidget {
  final ValueChanged<int> onStop;
  final DateTime Function()? now; // injectable pour les tests
  /// Exercice en cours : l'objectif est mémorisé par exercice.
  final String? exercice;

  /// Sons et écran allumé (injectable pour les tests).
  final ChronoFx? fx;

  const Chrono(
      {super.key, required this.onStop, this.now, this.exercice, this.fx});

  @override
  State<Chrono> createState() => _ChronoState();
}

class _ChronoState extends State<Chrono> with WidgetsBindingObserver {
  DateTime? _start; // début réel du chrono (après la préparation)
  DateTime? _goAt; // fin du compte à rebours
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  int _pre = 0; // secondes de préparation
  int _target = 0; // objectif en secondes (0 = chrono libre)
  int _lastBeep = -1;
  bool _reached = false; // objectif atteint pendant cette série
  bool _alertsOn = false;
  bool _sound = true;
  bool _fullPref = false;
  Route<void>? _fullRoute;
  final _rev = ValueNotifier<int>(0); // redessine la vue plein écran

  DateTime _now() => (widget.now ?? DateTime.now)();
  ChronoFx get _fx => widget.fx ?? DeviceChronoFx.instance;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

  void _bip(Bip b) {
    if (_sound) _fx.bip(b);
  }

  bool get _running => _start != null;
  bool get _counting => _goAt != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(Chrono old) {
    super.didUpdateWidget(old);
    if (chronoTargetKey(old.exercice) != chronoTargetKey(widget.exercice) &&
        !_running &&
        !_counting) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final pre = p.getInt(kChronoPreKey) ?? 5; // 5 s par défaut
      final t = p.getInt(chronoTargetKey(widget.exercice)) ??
          p.getInt(kChronoTargetKey) ??
          0;
      final sound = p.getBool(kChronoSoundKey) ?? true;
      final full = p.getBool(kChronoFullKey) ?? false;
      if (!mounted) return;
      setState(() {
        _sound = sound;
        _fullPref = full;
        _pre = pre.clamp(0, 600);
        _target = t.clamp(0, 9999);
      });
    } catch (_) {/* préférences indisponibles : valeurs par défaut */}
  }

  Future<void> _setPre(int v) async {
    setState(() => _pre = v);
    try {
      (await SharedPreferences.getInstance()).setInt(kChronoPreKey, v);
    } catch (_) {}
  }

  Future<void> _savePref(String k, bool v) async {
    try {
      (await SharedPreferences.getInstance()).setBool(k, v);
    } catch (_) {}
  }

  void _toggleSound() {
    setState(() => _sound = !_sound);
    _savePref(kChronoSoundKey, _sound);
  }

  // ---------------------------------------------------------- plein écran

  void _openFull() {
    if (_fullRoute != null) return;
    _fullPref = true;
    _savePref(kChronoFullKey, true);
    final route = PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, __, ___) => _FullView(state: this),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    );
    _fullRoute = route;
    Navigator.of(context).push(route).then((_) {
      if (_fullRoute == route) _fullRoute = null;
    });
  }

  /// Bouton « réduire » ou retour Android : la série continue en petit.
  void _shrink() {
    _fullPref = false;
    _savePref(kChronoFullKey, false);
    _closeFull();
  }

  void _closeFull() {
    final r = _fullRoute;
    _fullRoute = null;
    if (r != null && r.isActive) r.navigator?.removeRoute(r);
  }

  Future<void> _setTarget(int v) async {
    setState(() => _target = v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(chronoTargetKey(widget.exercice), v);
      await p.setInt(kChronoTargetKey, v); // défaut des nouveaux exercices
    } catch (_) {}
  }

  Future<int?> _ask(String title, int current, {required bool allowZero}) {
    final ctrl = TextEditingController(
        text: current > 0 ? formatDuree(current).replaceAll(' s', '') : '');
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(builder: (ctx, setD) {
          void ok() {
            final v = parseDuree(ctrl.text);
            if (v == null || (!allowZero && v == 0) || v > 5999) {
              setD(() => err = 'Ex. 90, 1:30 ou 2m');
              return;
            }
            Navigator.pop(ctx, v);
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.datetime,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[\d:msinMSIN \x27"]'))
              ],
              decoration: InputDecoration(
                hintText: 'secondes ou min:s (ex. 1:30)',
                errorText: err,
              ),
              onSubmitted: (_) => ok(),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler')),
              FilledButton(onPressed: ok, child: const Text('OK')),
            ],
          );
        });
      },
    );
  }

  Future<void> _customPre() async {
    final v = await _ask('Départ dans…', _pre, allowZero: true);
    if (v != null && mounted) _setPre(v);
  }

  Future<void> _customTarget() async {
    final v = await _ask('Objectif', _target, allowZero: false);
    if (v != null && mounted) _setTarget(v);
  }

  void _press() {
    if (_running) return _end();
    if (_counting) return _cancel();
    _reached = false;
    _fx.keepAwake(true);
    _pre == 0 ? _begin(_now()) : _countdown();
    if (_fullPref) _openFull();
  }

  void _countdown() {
    _goAt = _now().add(Duration(seconds: _pre));
    _lastBeep = -1;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) => _onTick());
    _onTick();
  }

  void _onTick() {
    if (!mounted) return;
    final left = _goAt!.difference(_now());
    if (left <= Duration.zero) {
      _tick?.cancel();
      HapticFeedback.heavyImpact(); // top départ
      _bip(Bip.depart);
      _begin(_goAt!); // l'heure de départ est celle prévue, pas celle du tick
      return;
    }
    final sec = (left.inMilliseconds / 1000).ceil();
    if (sec != _lastBeep) {
      _lastBeep = sec;
      HapticFeedback.selectionClick(); // un tic par seconde
      if (sec <= 3) _bip(Bip.court);
    }
    setState(() {});
  }

  void _cancel() {
    _tick?.cancel();
    _cancelAlerts();
    _fx.keepAwake(false);
    _closeFull();
    setState(() {
      _goAt = null;
      _elapsed = Duration.zero;
    });
  }

  void _begin(DateTime at) {
    _tick?.cancel();
    _goAt = null;
    _start = at;
    _elapsed = _now().difference(at);
    _lastBeep = -1;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed = _now().difference(_start!));
      _targetFeedback();
    });
    setState(() {});
  }

  /// Tics sur les 3 dernières secondes de l'objectif, triple vibration à zéro.
  void _targetFeedback() {
    if (_target == 0 || _reached) return;
    final leftMs = _target * 1000 - _elapsed.inMilliseconds;
    if (leftMs <= 0) {
      _reached = true;
      _bip(Bip.objectif);
      HapticFeedback.heavyImpact();
      Future.delayed(
          const Duration(milliseconds: 180), HapticFeedback.heavyImpact);
      Future.delayed(
          const Duration(milliseconds: 360), HapticFeedback.heavyImpact);
      return;
    }
    final sec = (leftMs / 1000).ceil();
    if (sec <= 3 && sec != _lastBeep) {
      _lastBeep = sec;
      HapticFeedback.selectionClick();
      _bip(Bip.court);
    }
  }

  void _end() {
    _tick?.cancel();
    _cancelAlerts();
    _fx.keepAwake(false);
    _closeFull();
    final e = _now().difference(_start!);
    setState(() {
      _start = null;
      _elapsed = e;
    });
    final s = (e.inMilliseconds / 1000).round();
    if (s > 0) widget.onStop(s);
  }

  void _reset() => setState(() {
        _elapsed = Duration.zero;
        _reached = false;
      });

  // Écran éteint / autre app : notification à l'heure de l'objectif.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _target > 0 && !_reached) {
      final DateTime? start = _start ?? _goAt;
      if (start == null) return;
      final end = start.add(Duration(seconds: _target));
      _alertsOn = true;
      TimerAlerts.schedule([
        TimerAlert(end.difference(_now()), 'Objectif atteint 🎯',
            '${formatDuree(_target)} tenues — arrête le chrono dans l\'app'),
      ]);
    } else if (state == AppLifecycleState.resumed) {
      _cancelAlerts();
    }
  }

  void _cancelAlerts() {
    if (!_alertsOn) return;
    _alertsOn = false;
    TimerAlerts.cancelAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _cancelAlerts();
    if (_running || _counting) _fx.keepAwake(false);
    _closeFull();
    _rev.dispose();
    super.dispose();
  }

  static String _fmt(int ms, {bool tenths = true}) {
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final t = (ms % 1000) ~/ 100;
    final base = '$m:${s.toString().padLeft(2, '0')}';
    return tenths ? '$base.$t' : base;
  }

  bool get _over => _target > 0 && _elapsed.inMilliseconds >= _target * 1000;

  String get _label {
    if (_counting) {
      final left = _goAt!.difference(_now());
      return '${(left.inMilliseconds / 1000).ceil().clamp(1, 999)}';
    }
    final ms = _elapsed.inMilliseconds;
    if (_target > 0 && _running) {
      final left = _target * 1000 - ms;
      // Décompte arrondi à la seconde supérieure (« 0:01 » jusqu'au bout),
      // puis le dépassement en « +0:03 ».
      if (left > 0) return _fmt(((left + 999) ~/ 1000) * 1000, tenths: false);
      return '+${_fmt(-left, tenths: false)}';
    }
    return _fmt(ms);
  }

  String? get _hint {
    if (_counting) {
      return _target > 0
          ? 'Mets-toi en position… objectif ${formatDuree(_target)}'
          : 'Mets-toi en position…';
    }
    if (_running && _over) {
      return 'Objectif atteint 🎯 — total ${_fmt(_elapsed.inMilliseconds, tenths: false)}';
    }
    if (_running && _target > 0) return 'Objectif ${formatDuree(_target)}';
    return null;
  }

  double? get _progress => _target > 0 && _running
      ? (_elapsed.inMilliseconds / (_target * 1000)).clamp(0.0, 1.0)
      : null;

  Color? get _color {
    if (_counting) return Colors.orange;
    if (_running) return _over ? Colors.green : AppTheme.primaryBlue;
    return null;
  }

  Widget _chips({
    required String title,
    required List<int> choices,
    required int value,
    required String Function(int) label,
    required ValueChanged<int> onPick,
    required VoidCallback onCustom,
  }) {
    final custom = !choices.contains(value);
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(title,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        for (final c in choices)
          ChoiceChip(
            label: Text(label(c)),
            selected: value == c,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onPick(c),
          ),
        ChoiceChip(
          avatar: custom ? null : const Icon(Icons.edit, size: 16),
          label: Text(custom ? label(value) : 'Autre'),
          tooltip: 'Temps personnalisé',
          selected: custom,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onCustom(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final idle = !_running && !_counting;
    final showBar = _target > 0 && _running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
                _counting
                    ? Icons.hourglass_top
                    : _target > 0
                        ? Icons.flag_outlined
                        : Icons.timer_outlined,
                color: _counting
                    ? Colors.orange
                    : _over && _running
                        ? Colors.green
                        : AppTheme.textSecondary),
            const SizedBox(width: 8),
            // Le temps rétrécit au besoin : la ligne ne déborde jamais, même
            // dans une carte étroite avec le bouton « remettre à zéro ».
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _label,
                    key: const ValueKey('chrono-time'),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: _color,
                    ),
                  ),
                ),
              ),
            ),
            if (idle)
              IconButton(
                tooltip: _sound ? 'Couper les bips' : 'Activer les bips',
                onPressed: _toggleSound,
                icon: Icon(_sound ? Icons.volume_up : Icons.volume_off),
              )
            else
              IconButton(
                tooltip: 'Plein écran',
                onPressed: _openFull,
                icon: const Icon(Icons.fullscreen),
              ),
            if (idle && _elapsed > Duration.zero)
              IconButton(
                tooltip: 'Remettre à zéro',
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt),
              ),
            FilledButton.icon(
              onPressed: _press,
              icon: Icon(_running
                  ? Icons.stop
                  : _counting
                      ? Icons.close
                      : Icons.play_arrow),
              label: Text(_running
                  ? 'Arrêter'
                  : _counting
                      ? 'Annuler'
                      : 'Démarrer'),
            ),
          ],
        ),
        if (showBar)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(
              value: (_elapsed.inMilliseconds / (_target * 1000)).clamp(0, 1),
              color: _over ? Colors.green : AppTheme.primaryBlue,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        if (_running && _over)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Objectif atteint 🎯 — total ${_fmt(_elapsed.inMilliseconds, tenths: false)}',
                style: const TextStyle(color: Colors.green, fontSize: 12)),
          ),
        if (idle) ...[
          const SizedBox(height: 6),
          _chips(
            title: 'Départ dans',
            choices: kChronoPreChoices,
            value: _pre,
            label: (c) => c == 0 ? 'Sans' : formatDuree(c),
            onPick: _setPre,
            onCustom: _customPre,
          ),
          _chips(
            title: 'Objectif',
            choices: kChronoTargetChoices,
            value: _target,
            label: (c) => c == 0 ? 'Libre' : formatDuree(c),
            onPick: _setTarget,
            onCustom: _customTarget,
          ),
        ],
        if (_counting)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                _target > 0
                    ? 'Mets-toi en position… objectif ${formatDuree(_target)}'
                    : 'Mets-toi en position…',
                style: const TextStyle(color: Colors.orange, fontSize: 12)),
          ),
      ],
    );
  }
}

/// Temps en très gros chiffres sur tout l'écran, lisible depuis le sol.
/// Reflète l'état du petit chrono (même horloge, mêmes boutons).
class _FullView extends StatelessWidget {
  final _ChronoState state;
  const _FullView({required this.state});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) state._shrink();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: state._rev,
            builder: (context, _, __) {
              final s = state;
              final color = s._color ?? Colors.white;
              final hint = s._hint;
              final progress = s._progress;
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        tooltip: 'Réduire',
                        onPressed: s._shrink,
                        color: Colors.white70,
                        iconSize: 32,
                        icon: const Icon(Icons.fullscreen_exit),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Text(
                            s._label,
                            key: const ValueKey('chrono-full-time'),
                            style: TextStyle(
                              fontSize: 200,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              color: color,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (progress != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 14,
                          color: color,
                          backgroundColor: Colors.white12,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(hint,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: color, fontSize: 20)),
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 72,
                      child: FilledButton.icon(
                        onPressed: s._running || s._counting ? s._press : null,
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              s._counting ? Colors.orange : Colors.redAccent,
                          textStyle: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                        icon: Icon(s._counting ? Icons.close : Icons.stop,
                            size: 32),
                        label: Text(s._counting ? 'Annuler' : 'Arrêter'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
