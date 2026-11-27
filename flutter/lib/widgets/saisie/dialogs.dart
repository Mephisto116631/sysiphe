import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/perf.dart';
import '../../theme.dart';

/// Confirmation de suppression (bouton rouge). true si confirmé.
Future<bool> confirmDelete(BuildContext context,
    {required String title, required String content}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Correction d'une série enregistrée : nouvelle valeur et, pour la
/// planche, variante, forme, élastique et tension.
class PerfEdit {
  final double value;
  final String variante, forme, elastique, tension;
  const PerfEdit(
      this.value, this.variante, this.forme, this.elastique, this.tension);

  bool changes(Perf p) =>
      value != p.performance ||
      variante != p.variante ||
      forme != p.forme ||
      elastique != p.elastique ||
      tension != p.tension;
}

/// Listes des options de la planche (coefficients du modèle).
class PlancheChoices {
  final List<String> variantes, formes, elastiques, tensions;
  const PlancheChoices(
      this.variantes, this.formes, this.elastiques, this.tensions);
}

/// Boîte de correction (null si annulé ou invalide). [planche] : options de
/// la planche, modifiables aussi.
Future<PerfEdit?> askPerfEdit(BuildContext context, Perf p,
        {PlancheChoices? planche}) =>
    showDialog<PerfEdit>(
        context: context, builder: (_) => _PerfValueDialog(p, planche));

/// Le champ appartient à la boîte : libéré seulement quand elle disparaît
/// (pas pendant son animation de fermeture).
class _PerfValueDialog extends StatefulWidget {
  final Perf perf;
  final PlancheChoices? planche;
  const _PerfValueDialog(this.perf, this.planche);

  @override
  State<_PerfValueDialog> createState() => _PerfValueDialogState();
}

class _PerfValueDialogState extends State<_PerfValueDialog> {
  late final _ctrl = TextEditingController(
      text: widget.perf.performance % 1 == 0
          ? widget.perf.performance.toInt().toString()
          : widget.perf.performance.toString());
  late String _variante = widget.perf.variante,
      _forme = widget.perf.forme,
      _elastique = widget.perf.elastique,
      _tension = widget.perf.tension;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _drop(String label, String value, List<String> items,
      ValueChanged<String> onChanged) {
    final all = items.contains(value) ? items : [value, ...items];
    return DropdownButtonFormField<String>(
      key: ValueKey('edit-$label'),
      value: value,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final i in all)
          DropdownMenuItem(
              value: i, child: Text(i, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => v == null ? null : setState(() => onChanged(v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.perf;
    final c = widget.planche;
    return AlertDialog(
      title: Text('${p.exercice} · S${p.serie}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('edit-value'),
              controller: _ctrl,
              autofocus: c == null,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
              ],
              decoration: InputDecoration(
                  labelText: p.unite == 'Sec' ? 'Temps (s)' : 'Valeur'),
            ),
            if (c != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _drop('Variante', _variante, c.variantes,
                        (v) => _variante = v)),
                const SizedBox(width: 8),
                Expanded(
                    child: _drop(
                        'Forme', _forme, c.formes, (v) => _forme = v)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _drop('Élastique', _elastique, c.elastiques, (v) {
                  _elastique = v;
                  if (v == 'Aucun') _tension = 'N/A';
                })),
                const SizedBox(width: 8),
                Expanded(
                    child: _drop('Tension', _tension, c.tensions,
                        (v) => _tension = v)),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        TextButton(
          key: const ValueKey('edit-ok'),
          onPressed: () {
            final v = double.tryParse(_ctrl.text.replaceAll(',', '.'));
            if (v == null || v <= 0) return;
            Navigator.pop(
                context, PerfEdit(v, _variante, _forme, _elastique, _tension));
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

/// « + Ajouter un exercice » : liste des exercices connus, ou '' pour
/// « Nouvel exercice… » ; null si fermé.
Future<String?> pickExerciseSheet(BuildContext context, List<String> choices) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline,
                  color: AppTheme.primaryBlue),
              title: const Text('Nouvel exercice…'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final e in choices)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(e, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, e),
              ),
          ],
        ),
      ),
    );
