import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/intensity.dart';

/// Réglage des couleurs d'intensité d'un profil : automatique (relatif au
/// meilleur effort) ou seuils en points (orange à partir de, rouge à partir
/// de), avec un aperçu du dégradé. Renvoie la nouvelle config, null si annulé.
Future<IntensityConfig?> askIntensity(
        BuildContext context, IntensityConfig current) =>
    showDialog<IntensityConfig>(
        context: context, builder: (_) => _IntensityDialog(current));

class _IntensityDialog extends StatefulWidget {
  final IntensityConfig current;
  const _IntensityDialog(this.current);

  @override
  State<_IntensityDialog> createState() => _IntensityDialogState();
}

class _IntensityDialogState extends State<_IntensityDialog> {
  late bool _auto = widget.current.auto;
  late final _orange =
      TextEditingController(text: '${widget.current.orange ?? 50}');
  late final _rouge =
      TextEditingController(text: '${widget.current.rouge ?? 100}');

  @override
  void dispose() {
    _orange.dispose();
    _rouge.dispose();
    super.dispose();
  }

  IntensityConfig get _config => _auto
      ? const IntensityConfig()
      : IntensityConfig(
          orange: int.tryParse(_orange.text), rouge: int.tryParse(_rouge.text));

  String? get _error {
    if (_auto) return null;
    final o = int.tryParse(_orange.text), r = int.tryParse(_rouge.text);
    if (o == null || r == null || o <= 0) return 'Deux nombres de points';
    if (r <= o) return 'Le rouge doit être au-dessus de l\'orange';
    return null;
  }

  Widget _field(String label, TextEditingController c) => Expanded(
        child: TextField(
          controller: c,
          enabled: !_auto,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: 'pts'),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final err = _error;
    final cfg = _config;
    final o = cfg.orange ?? 50, r = cfg.rouge ?? 100;
    final top = cfg.auto ? 100 : (r * 1.25).round();
    return AlertDialog(
      title: const Text('Couleurs d\'intensité'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatique'),
              subtitle: const Text('Relatif à ton meilleur effort'),
              value: _auto,
              onChanged: (v) => setState(() => _auto = v),
            ),
            Row(
              children: [
                _field('Orange dès', _orange),
                const SizedBox(width: 12),
                _field('Rouge dès', _rouge),
              ],
            ),
            if (err != null) ...[
              const SizedBox(height: 6),
              Text(err,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ],
            const SizedBox(height: 16),
            // Aperçu : effort de 0 à au-delà du rouge.
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  for (var i = 0; i < 24; i++)
                    Expanded(
                      child: Container(
                        height: 18,
                        color: cfg.colorFor(top * i / 23, best: top),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0', style: TextStyle(fontSize: 11)),
                if (!cfg.auto) ...[
                  Text('$o', style: const TextStyle(fontSize: 11)),
                  Text('$r', style: const TextStyle(fontSize: 11)),
                ],
                Text(cfg.auto ? 'meilleur' : '$top pts',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: err != null ? null : () => Navigator.pop(context, cfg),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
