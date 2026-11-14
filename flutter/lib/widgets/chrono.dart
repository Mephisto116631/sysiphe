import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';

/// Clé du réglage « départ dans X s » (préférence de l'appareil).
const kChronoPreKey = 'chrono_pre_seconds';
const kChronoPreChoices = [0, 5, 10, 15];

/// Mini chronomètre pour les exercices en secondes.
/// Démarrer → compte à rebours de préparation (pour se mettre en position,
/// réglable : sans, 5, 10 ou 15 s) → le chrono démarre tout seul → Arrêter
/// renvoie la durée (secondes entières) pour remplir le champ de saisie.
/// Basé sur l'horloge (pas sur un compteur) : reste juste si l'écran se met
/// en veille ou si l'app passe un instant en arrière-plan.
class Chrono extends StatefulWidget {
  final ValueChanged<int> onStop;
  final DateTime Function()? now; // injectable pour les tests

  const Chrono({super.key, required this.onStop, this.now});

  @override
  State<Chrono> createState() => _ChronoState();
}

class _ChronoState extends State<Chrono> {
  DateTime? _start; // début réel du chrono (après la préparation)
  DateTime? _goAt; // fin du compte à rebours
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  int _pre = 0; // secondes de préparation (réglage chargé au démarrage)
  int _lastBeep = -1;

  DateTime _now() => (widget.now ?? DateTime.now)();
  bool get _running => _start != null;
  bool get _counting => _goAt != null;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getInt(kChronoPreKey) ?? 5; // 5 s par défaut
      if (mounted && kChronoPreChoices.contains(v)) setState(() => _pre = v);
    });
  }

  Future<void> _setPre(int v) async {
    setState(() => _pre = v);
    (await SharedPreferences.getInstance()).setInt(kChronoPreKey, v);
  }

  void _press() {
    if (_running) return _end();
    if (_counting) return _cancel();
    _pre == 0 ? _begin(_now()) : _countdown();
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
      _begin(_goAt!); // l'heure de départ est celle prévue, pas celle du tick
      return;
    }
    final sec = (left.inMilliseconds / 1000).ceil();
    if (sec != _lastBeep) {
      _lastBeep = sec;
      HapticFeedback.selectionClick(); // un tic par seconde
    }
    setState(() {});
  }

  void _cancel() {
    _tick?.cancel();
    setState(() {
      _goAt = null;
      _elapsed = Duration.zero;
    });
  }

  void _begin(DateTime at) {
    _tick?.cancel();
    _goAt = null;
    _start = at;
    _elapsed = Duration.zero;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _elapsed = _now().difference(_start!));
    });
    setState(() {});
  }

  void _end() {
    _tick?.cancel();
    final e = _now().difference(_start!);
    setState(() {
      _start = null;
      _elapsed = e;
    });
    final s = (e.inMilliseconds / 1000).round();
    if (s > 0) widget.onStop(s);
  }

  void _reset() => setState(() => _elapsed = Duration.zero);

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _label {
    if (_counting) {
      final left = _goAt!.difference(_now());
      return '${(left.inMilliseconds / 1000).ceil().clamp(1, 99)}';
    }
    final ms = _elapsed.inMilliseconds;
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final t = (ms % 1000) ~/ 100;
    return '$m:${s.toString().padLeft(2, '0')}.$t';
  }

  @override
  Widget build(BuildContext context) {
    final idle = !_running && !_counting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_counting ? Icons.hourglass_top : Icons.timer_outlined,
                color: _counting ? Colors.orange : AppTheme.textSecondary),
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
                      color: _counting
                          ? Colors.orange
                          : _running
                              ? AppTheme.primaryBlue
                              : null,
                    ),
                  ),
                ),
              ),
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
        if (idle)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Départ dans',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                for (final c in kChronoPreChoices)
                  ChoiceChip(
                    label: Text(c == 0 ? 'Sans' : '$c s'),
                    selected: _pre == c,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _setPre(c),
                  ),
              ],
            ),
          ),
        if (_counting)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Mets-toi en position…',
                style: TextStyle(color: Colors.orange, fontSize: 12)),
          ),
      ],
    );
  }
}
