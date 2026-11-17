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

/// Nouvelle valeur d'une série enregistrée (null si annulé ou invalide).
Future<double?> askPerfValue(BuildContext context, Perf p) async {
  final ctrl = TextEditingController(
      text: p.performance % 1 == 0
          ? p.performance.toInt().toString()
          : p.performance.toString());
  final v = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${p.exercice} · S${p.serie}'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
        decoration: InputDecoration(
            labelText: p.unite == 'Sec' ? 'Temps (s)' : 'Valeur'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.pop(
              ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
          child: const Text('Valider'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return v;
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
