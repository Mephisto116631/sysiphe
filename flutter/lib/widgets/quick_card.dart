import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/session.dart';
import '../theme.dart';

/// Petite carte d'exercice : champ vide (la dernière fois apparaît en gris
/// dans le champ), « 12/10/8 » pour plusieurs séries, Enregistrer.
class QuickCard extends StatefulWidget {
  final String exercice;
  final String unite;
  final String? hint; // dernière fois, ex. « 30/25/20 »
  final String? helper; // ligne grise sous le champ
  final Widget? insight; // record, moyenne et % vs moyenne
  final int done; // séries déjà enregistrées aujourd'hui
  final Future<bool> Function(List<double>) onSave;

  const QuickCard({
    super.key,
    required this.exercice,
    required this.unite,
    required this.hint,
    required this.helper,
    this.insight,
    required this.done,
    required this.onSave,
  });

  @override
  State<QuickCard> createState() => _QuickCardState();
}

class _QuickCardState extends State<QuickCard> {
  final _ctrl = TextEditingController();
  Timer? _auto; // enregistrement auto 10 s après la dernière frappe
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _auto?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _insertSeparator() {
    final t = _ctrl.text;
    if (t.isEmpty || t.endsWith(' ')) return;
    _ctrl.value = TextEditingValue(
      text: '$t ',
      selection: TextSelection.collapsed(offset: t.length + 1),
    );
  }

  Future<void> _save() async {
    _auto?.cancel();
    if (_saving) return;
    List<double> vals;
    try {
      vals = parseSeries(_ctrl.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (vals.isEmpty || vals.any((v) => v <= 0)) {
      setState(() => _error = 'Saisis au moins une valeur');
      return;
    }
    setState(() { _saving = true; _error = null; });
    final ok = await widget.onSave(vals);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = switch (widget.unite) { 'Sec' => 's', 'Kg' => 'kg', _ => 'reps' };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.exercice,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis),
                ),
                if (widget.done > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                      const SizedBox(width: 4),
                      Text('${widget.done} série${widget.done > 1 ? 's' : ''}',
                          style: TextStyle(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
              ],
            ),
            if (widget.insight != null) ...[
              const SizedBox(height: 6),
              widget.insight!,
            ],
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.,/+; ]')),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Séries ($unit)',
                      // La dernière fois, en gris DANS le champ (vide).
                      hintText: widget.hint ?? 'ex. 12/10/8',
                      hintStyle: const TextStyle(color: AppTheme.textSecondary),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      helperText: widget.helper,
                      helperStyle: const TextStyle(color: AppTheme.textSecondary),
                      errorText: _error,
                      // Le pavé numérique Android n'a pas toujours de « / »
                      // ni d'espace : ce bouton insère un séparateur.
                      suffixIcon: IconButton(
                        tooltip: 'Série suivante',
                        icon: const Icon(Icons.add),
                        onPressed: _insertSeparator,
                      ),
                    ),
                    onChanged: (_) {
                      _auto?.cancel();
                      if (_ctrl.text.trim().isEmpty) return;
                      _auto = Timer(const Duration(seconds: 10), () {
                        if (mounted) _save();
                      });
                    },
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: FilledButton.tonal(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 14)),
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
