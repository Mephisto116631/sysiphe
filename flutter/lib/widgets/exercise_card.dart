import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/session.dart';
import '../theme.dart';

/// Type d'exercice : détermine les options affichées dans la carte.
enum CardKind { plain, planche, assist }

/// Une série saisie dans une carte, avec ses options.
class CardEntry {
  final double value;
  final int serie;
  final String unite;
  final double lest;
  final String variante, forme, elastique, tension, ecartement;
  const CardEntry({
    required this.value,
    required this.serie,
    required this.unite,
    required this.lest,
    required this.variante,
    required this.forme,
    required this.elastique,
    required this.tension,
    required this.ecartement,
  });
}

String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Carte d'exercice complète, identique au formulaire principal : série
/// (− / +), unité, valeur, options (planche / assistable), Enregistrer.
/// Une seule saisie par série ; enregistrement automatique 3 s après la
/// dernière frappe.
class ExerciseCard extends StatefulWidget {
  final String exercice;
  final String unite;
  final CardKind kind;
  final int done; // séries déjà enregistrées aujourd'hui
  final ExerciseTemplate? last; // dernière séance (indices + préremplissage)
  final String? helper; // ex. « Dernière fois le 10 nov. · record série 30 »
  final Widget? insight; // record, moyenne, % vs moyenne
  final bool enableCharges;
  final List<String> variantes, formes, elastiques, tensions, ecartements;
  final Future<bool> Function(CardEntry) onSave;

  const ExerciseCard({
    super.key,
    required this.exercice,
    required this.unite,
    required this.kind,
    required this.done,
    required this.last,
    required this.helper,
    required this.insight,
    required this.enableCharges,
    required this.variantes,
    required this.formes,
    required this.elastiques,
    required this.tensions,
    required this.ecartements,
    required this.onSave,
  });

  @override
  State<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<ExerciseCard> {
  final _value = TextEditingController();
  final _lest = TextEditingController();
  Timer? _auto;
  late int _serie;
  late String _unite;
  String _variante = 'Full', _forme = 'Normal';
  String _elastique = 'Aucun', _tension = 'N/A', _ecartement = 'Standard';
  String? _lestHint;
  bool _showOptions = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serie = widget.done + 1;
    _unite = widget.unite;
    final p = widget.last?.series.last;
    if (p != null) {
      if (widget.variantes.contains(p.variante)) _variante = p.variante;
      if (widget.formes.contains(p.forme)) _forme = p.forme;
      if (widget.elastiques.contains(p.elastique)) _elastique = p.elastique;
      if (widget.tensions.contains(p.tension)) _tension = p.tension;
      if (widget.ecartements.contains(p.ecartement)) {
        _ecartement = p.ecartement;
      }
      if (p.charge > 0) _lestHint = _fmt(p.charge); // exemple, pas une saisie
    }
    _showOptions = widget.kind == CardKind.assist;
  }

  @override
  void didUpdateWidget(ExerciseCard old) {
    super.didUpdateWidget(old);
    if (old.done != widget.done) _serie = widget.done + 1;
  }

  @override
  void dispose() {
    _auto?.cancel();
    _value.dispose();
    _lest.dispose();
    super.dispose();
  }

  /// Indice gris : la même série de la dernière fois.
  String? get _hint {
    final t = widget.last;
    if (t == null) return null;
    return 'ex. ${_fmt(t.seriesFor(_serie).performance)}';
  }

  Future<void> _save() async {
    _auto?.cancel();
    if (_saving) return;
    final v = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) {
      if (_value.text.trim().isNotEmpty) {
        setState(() => _error = 'Valeur invalide');
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSave(CardEntry(
      value: v,
      serie: _serie,
      unite: _unite,
      lest: _unite == 'Reps' && widget.enableCharges
          ? (double.tryParse(_lest.text.trim().replaceAll(',', '.')) ?? 0)
          : 0,
      variante: _variante,
      forme: _forme,
      elastique: _elastique,
      tension: _tension,
      ecartement: _ecartement,
    ));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _value.clear();
        _serie++; // la mise à jour du parent (done) confirmera
      }
    });
  }

  Widget _drop(String label, String value, Iterable<String> items,
      ValueChanged<String> onChanged) {
    final list = items.toList();
    return DropdownButtonFormField<String>(
      value: list.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final i in list)
          DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))
      ],
      onChanged: (v) => v == null ? null : setState(() => onChanged(v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_unite) { 'Sec' => 'Temps (s)', 'Kg' => 'Kg', _ => 'Reps' };
    final k = widget.kind;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.exercice,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (widget.insight != null) ...[
              const SizedBox(height: 6),
              widget.insight!,
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const Text('Série',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed:
                              _serie > 1 ? () => setState(() => _serie--) : null,
                          icon: const Icon(Icons.remove),
                        ),
                        SizedBox(
                          width: 32,
                          child: Text('$_serie',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w700)),
                        ),
                        IconButton.filledTonal(
                          onPressed: () => setState(() => _serie++),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _drop('Unité', _unite, const ['Reps', 'Sec', 'Kg'],
                      (v) => _unite = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _value,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
                    ],
                    decoration: InputDecoration(
                      labelText: label,
                      hintText: _hint,
                      errorText: _error,
                      helperText: 'Enregistré après 3 s',
                      helperStyle: const TextStyle(fontSize: 10),
                    ),
                    onChanged: (_) {
                      _auto?.cancel();
                      if (_error != null) setState(() => _error = null);
                      if (_value.text.trim().isEmpty) return;
                      _auto = Timer(const Duration(seconds: 3), () {
                        if (mounted) _save();
                      });
                    },
                    onSubmitted: (_) => _save(),
                  ),
                ),
                if (_unite == 'Reps' && widget.enableCharges) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _lest,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
                      ],
                      decoration: InputDecoration(
                          labelText: 'Lest (kg)',
                          hintText: _lestHint == null ? null : 'ex. $_lestHint'),
                    ),
                  ),
                ],
              ],
            ),
            if (k == CardKind.planche) ...[
              InkWell(
                onTap: () => setState(() => _showOptions = !_showOptions),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      const Text('Options planche',
                          style: TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.w600)),
                      Icon(
                          _showOptions
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: AppTheme.primaryBlue),
                    ],
                  ),
                ),
              ),
              if (_showOptions) ...[
                Row(children: [
                  Expanded(
                      child: _drop('Variante', _variante,
                          widget.variantes, (v) => _variante = v)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _drop(
                          'Forme', _forme, widget.formes, (v) => _forme = v)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _drop('Élastique', _elastique,
                          widget.elastiques, (v) => _elastique = v)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _drop('Tension', _tension, widget.tensions,
                          (v) => _tension = v)),
                ]),
              ],
            ],
            if (k == CardKind.assist) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _drop('Élastique', _elastique, widget.elastiques,
                        (v) => _elastique = v)),
                const SizedBox(width: 10),
                Expanded(
                    child: _drop('Tension', _tension, widget.tensions,
                        (v) => _tension = v)),
              ]),
              const SizedBox(height: 10),
              _drop('Écartement des mains', _ecartement,
                  widget.ecartements, (v) => _ecartement = v),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
              ),
            ),
            if (widget.helper != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(widget.helper!,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
