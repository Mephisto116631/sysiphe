import 'dart:async';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Mini chronomètre pour les exercices en secondes : Démarrer → Arrêter
/// renvoie la durée (en secondes entières) pour remplir le champ de saisie.
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
  DateTime? _start;
  Duration _elapsed = Duration.zero;
  Timer? _tick;

  DateTime _now() => (widget.now ?? DateTime.now)();
  bool get _running => _start != null;

  void _begin() {
    _start = _now();
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
    final ms = _elapsed.inMilliseconds;
    final m = ms ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final t = (ms % 1000) ~/ 100;
    return '$m:${s.toString().padLeft(2, '0')}.$t';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.timer_outlined, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Text(
          _label,
          key: const ValueKey('chrono-time'),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: _running ? AppTheme.primaryBlue : null,
          ),
        ),
        const Spacer(),
        if (!_running && _elapsed > Duration.zero)
          IconButton(
            tooltip: 'Remettre à zéro',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
          ),
        FilledButton.icon(
          onPressed: _running ? _end : _begin,
          icon: Icon(_running ? Icons.stop : Icons.play_arrow),
          label: Text(_running ? 'Arrêter' : 'Démarrer'),
        ),
      ],
    );
  }
}
