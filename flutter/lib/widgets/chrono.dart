import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chrono_fx.dart';
export '../services/chrono_fx.dart' show kChronoSoundKey, kChronoSoundModeKey;
import '../services/rest_timer.dart';
import '../services/timer_alerts.dart';
import '../theme.dart';

/// Clé du réglage « départ dans X s » (préférence de l'appareil).
const kChronoPreKey = 'chrono_pre_seconds';
const kChronoPreChoices = [0, 5, 10, 15];

/// Clé de l'objectif (décompte) : suffixée par l'exercice quand il est connu,
/// pour que la planche et le gainage gardent chacun leur temps.
const kChronoTargetKey = 'chrono_target_seconds';
const kChronoTargetChoices = [0, 30, 45, 60, 90, 120]; // 0 = libre

/// Plein écran à l'ouverture (dernier choix). Les clés du son
/// (kChronoSoundKey, kChronoSoundModeKey) sont dans chrono_fx.dart, partagées
/// avec le repos.
const kChronoFullKey = 'chrono_fullscreen';

/// Nombre de séries enchaînées (1 = une seule), mémorisé par exercice.
const kChronoSetsKey = 'chrono_sets';
const kChronoSetsChoices = [1, 2, 3, 4, 5];

String chronoSetsKey(String? exercice) {
  final e = exercice?.trim().toLowerCase() ?? '';
  return e.isEmpty ? kChronoSetsKey : '$kChronoSetsKey:$e';
}

/// « 1 minute », « 2 minutes ».
String minutesFr(int m) => m == 1 ? '1 minute' : '$m minutes';

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
/// **Annonces vocales** (réglables avec le bouton son : voix, bips, muet) :
/// « 10 secondes », « Objectif atteint », chaque minute en chrono libre,
/// numéro de série et repos en enchaînement.
///
/// **Enchaînement** ([onChainStop] fourni) : « Séries : 3 » → à chaque arrêt
/// la série est enregistrée tout de suite, le repos de la Saisie ([rest])
/// démarre, puis la série suivante se relance seule (avec la préparation).
/// En plein écran, toucher n'importe où arrête la série (ou passe le repos).
///
/// Basé sur l'horloge (pas sur un compteur) : reste juste même si l'app passe
/// en arrière-plan. Dans ce cas, avant l'objectif, une notification est
/// programmée pour l'heure de fin.
class Chrono extends StatefulWidget {
  final ValueChanged<int> onStop;

  /// Enregistre la série tout de suite (enchaînement) ; true si réussi.
  final Future<bool> Function(int seconds)? onChainStop;

  /// Repos entre les séries : la série suivante attend sa fin.
  final RestTimer? rest;
  final DateTime Function()? now; // injectable pour les tests
  /// Exercice en cours : l'objectif est mémorisé par exercice.
  final String? exercice;

  /// Sons et écran allumé (injectable pour les tests).
  final ChronoFx? fx;

  const Chrono({
    super.key,
    required this.onStop,
    this.now,
    this.exercice,
    this.fx,
    this.onChainStop,
    this.rest,
  });

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
  int _soundMode = 2; // 0 muet, 1 bips, 2 bips + voix
  bool _fullPref = false;
  int _sets = 1; // séries à enchaîner
  int _setIdx = 1; // série en cours (enchaînement)
  bool _chain = false; // enchaînement en cours
  bool _waitingRest = false; // entre deux séries
  bool _saving = false;
  int _lastSpoken = -1; // dernière annonce (secondes restantes / minutes)
  Route<void>? _fullRoute;
  final _rev = ValueNotifier<int>(0); // redessine la vue plein écran

  DateTime _now() => (widget.now ?? DateTime.now)();
  ChronoFx get _fx => widget.fx ?? DeviceChronoFx.instance;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

  bool get _sound => _soundMode >= 1;
  bool get _voice => _soundMode == 2;

  void _bip(Bip b) {
    if (_sound) _fx.bip(b);
  }

  void _say(String text) {
    if (_voice) _fx.say(text);
  }

  void _onRestTick() {
    if (_waitingRest && mounted) setState(() {});
  }

  bool get _running => _start != null;
  bool get _counting => _goAt != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.rest?.left.addListener(_onRestTick);
    _load();
  }

  @override
  void didUpdateWidget(Chrono old) {
    super.didUpdateWidget(old);
    if (old.rest != widget.rest) {
      old.rest?.left.removeListener(_onRestTick);
      widget.rest?.left.addListener(_onRestTick);
    }
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
      final mode = p.getInt(kChronoSoundModeKey) ??
          (p.getBool(kChronoSoundKey) == false ? 0 : 2);
      final full = p.getBool(kChronoFullKey) ?? false;
      final sets = p.getInt(chronoSetsKey(widget.exercice)) ?? 1;
      if (!mounted) return;
      setState(() {
        _soundMode = mode.clamp(0, 2);
        _sets = sets.clamp(1, 20);
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

  /// Voix → bips → muet → voix.
  void _toggleSound() {
    setState(() => _soundMode = (_soundMode + 2) % 3);
    SharedPreferences.getInstance()
        .then((p) => p.setInt(kChronoSoundModeKey, _soundMode))
        .catchError((_) => true);
  }

  Future<void> _setSets(int v) async {
    setState(() => _sets = v);
    try {
      (await SharedPreferences.getInstance())
          .setInt(chronoSetsKey(widget.exercice), v);
    } catch (_) {}
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

  bool get _canChain => widget.onChainStop != null;

  void _press() {
    if (_saving) return;
    if (_running) return _end();
    if (_counting) return _cancel();
    if (_waitingRest) return _skipRest();
    _chain = _canChain && _sets > 1;
    _setIdx = 1;
    _startSet();
  }

  void _startSet() {
    _reached = false;
    _lastSpoken = -1;
    _fx.keepAwake(true);
    if (_chain) _say('Série $_setIdx sur $_sets');
    _pre == 0 ? _begin(_now()) : _countdown();
    if (_fullPref) _openFull();
  }

  /// Passe le repos : la série suivante démarre.
  void _skipRest() => widget.rest?.stop();

  /// Arrête l'enchaînement (pendant le repos).
  void _stopChain() {
    _chain = false;
    _fx.keepAwake(false);
    _closeFull();
    setState(() => _waitingRest = false);
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
      _say('Partez');
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
    _chain = false;
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
      _announce();
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
      _say('Objectif atteint');
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

  /// Annonces vocales pendant la série : « 10 secondes » avant l'objectif,
  /// puis chaque minute (chrono libre, ou au-delà de l'objectif).
  void _announce() {
    if (!_voice) return;
    final sec = _elapsed.inSeconds;
    if (_target >= 20 && !_reached) {
      final left = _target - sec;
      if (left == 10 && _lastSpoken != -10) {
        _lastSpoken = -10;
        _say('10 secondes');
      }
      return;
    }
    final min = sec ~/ 60;
    if (min >= 1 && sec % 60 == 0 && _lastSpoken != min) {
      _lastSpoken = min;
      _say(minutesFr(min));
    }
  }

  void _end() {
    _tick?.cancel();
    _cancelAlerts();
    final e = _now().difference(_start!);
    setState(() {
      _start = null;
      _elapsed = e;
    });
    final s = (e.inMilliseconds / 1000).round();
    if (_chain && s > 0) {
      _continueChain(s);
      return;
    }
    _chain = false;
    _fx.keepAwake(false);
    _closeFull();
    if (s > 0) widget.onStop(s);
  }

  /// Enchaînement : enregistre la série, attend la fin du repos, relance.
  Future<void> _continueChain(int s) async {
    final last = _setIdx >= _sets;
    setState(() {
      _saving = true;
      _waitingRest = !last;
    });
    final ok = await widget.onChainStop!(s);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok || last) {
      if (ok) _say('Terminé, bravo');
      _stopChain();
      return;
    }
    _say('Repos');
    await (widget.rest?.waitDone() ?? Future<void>.value());
    if (!mounted || !_chain) return;
    setState(() {
      _waitingRest = false;
      _setIdx++;
      _elapsed = Duration.zero;
    });
    _startSet();
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
    widget.rest?.left.removeListener(_onRestTick);
    _tick?.cancel();
    _cancelAlerts();
    if (_running || _counting || _chain) _fx.keepAwake(false);
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
    if (_waitingRest) {
      final l = widget.rest?.left.value;
      return l == null
          ? '…'
          : _fmt(((l.inMilliseconds + 999) ~/ 1000) * 1000, tenths: false);
    }
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

  String get _setTag => _chain ? 'Série $_setIdx/$_sets · ' : '';

  String? get _hint {
    if (_waitingRest) {
      return 'Repos · série ${_setIdx + 1}/$_sets ensuite';
    }
    if (_counting) {
      return _target > 0
          ? '${_setTag}Mets-toi en position… objectif ${formatDuree(_target)}'
          : '${_setTag}Mets-toi en position…';
    }
    if (_running && _over) {
      return '${_setTag}Objectif atteint 🎯 — total '
          '${_fmt(_elapsed.inMilliseconds, tenths: false)}';
    }
    if (_running && _target > 0) {
      return '${_setTag}Objectif ${formatDuree(_target)}';
    }
    if (_running && _chain) return 'Série $_setIdx/$_sets';
    return null;
  }

  double? get _progress => _target > 0 && _running
      ? (_elapsed.inMilliseconds / (_target * 1000)).clamp(0.0, 1.0)
      : null;

  Color? get _color {
    if (_waitingRest) return Colors.teal;
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
    final idle = !_running && !_counting && !_waitingRest;
    final showBar = _target > 0 && _running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
                _waitingRest
                    ? Icons.self_improvement
                    : _counting
                        ? Icons.hourglass_top
                        : _target > 0
                            ? Icons.flag_outlined
                            : Icons.timer_outlined,
                color: _waitingRest
                    ? Colors.teal
                    : _counting
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
                tooltip: switch (_soundMode) {
                  2 => 'Voix et bips (appuyer : bips seuls)',
                  1 => 'Bips seuls (appuyer : muet)',
                  _ => 'Muet (appuyer : voix et bips)',
                },
                onPressed: _toggleSound,
                icon: Icon(switch (_soundMode) {
                  2 => Icons.record_voice_over,
                  1 => Icons.volume_up,
                  _ => Icons.volume_off,
                }),
              )
            else ...[
              if (_waitingRest)
                IconButton(
                  tooltip: 'Arrêter l\'enchaînement',
                  onPressed: _stopChain,
                  icon: const Icon(Icons.close),
                ),
              IconButton(
                tooltip: 'Plein écran',
                onPressed: _openFull,
                icon: const Icon(Icons.fullscreen),
              ),
            ],
            if (idle && _elapsed > Duration.zero)
              IconButton(
                tooltip: 'Remettre à zéro',
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt),
              ),
            FilledButton.icon(
              onPressed: _saving ? null : _press,
              icon: Icon(_waitingRest
                  ? Icons.skip_next
                  : _running
                      ? Icons.stop
                      : _counting
                          ? Icons.close
                          : Icons.play_arrow),
              label: Text(_waitingRest
                  ? 'Passer'
                  : _running
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
          if (_canChain)
            Wrap(
              spacing: 6,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Séries',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                for (final c in kChronoSetsChoices)
                  ChoiceChip(
                    label: Text(c == 1 ? 'Une' : '$c'),
                    tooltip: c == 1
                        ? 'Une série à la fois'
                        : '$c séries enchaînées avec le repos',
                    selected: _sets == c,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _setSets(c),
                  ),
              ],
            ),
        ],
        if (_counting || _waitingRest || (_running && _chain && !_over))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_hint ?? '',
                style: TextStyle(
                    color: _waitingRest
                        ? Colors.teal
                        : _counting
                            ? Colors.orange
                            : AppTheme.textSecondary,
                    fontSize: 12)),
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
              final touch = s._running
                  ? 'Touche l\'écran pour arrêter'
                  : s._waitingRest
                      ? 'Touche l\'écran pour passer le repos'
                      : null;
              // Toucher n'importe où : arrête la série (ou passe le repos),
              // sans viser le bouton depuis la position de planche.
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: s._running || s._waitingRest ? s._press : null,
                child: Padding(
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
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(hint,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: color, fontSize: 20)),
                        ),
                      if (touch != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(touch,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 15)),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 72,
                        child: FilledButton.icon(
                          onPressed: !s._saving &&
                                  (s._running || s._counting || s._waitingRest)
                              ? s._press
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: s._waitingRest
                                ? Colors.teal
                                : s._counting
                                    ? Colors.orange
                                    : Colors.redAccent,
                            textStyle: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w700),
                          ),
                          icon: Icon(
                              s._waitingRest
                                  ? Icons.skip_next
                                  : s._counting
                                      ? Icons.close
                                      : Icons.stop,
                              size: 32),
                          label: Text(s._waitingRest
                              ? 'Passer le repos'
                              : s._counting
                                  ? 'Annuler'
                                  : 'Arrêter'),
                        ),
                      ),
                      if (s._waitingRest)
                        TextButton(
                          onPressed: s._stopChain,
                          child: const Text('Arrêter l\'enchaînement',
                              style: TextStyle(color: Colors.white70)),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
