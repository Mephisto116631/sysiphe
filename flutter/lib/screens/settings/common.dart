import 'package:flutter/material.dart';
import '../../theme.dart';

/// Titre de section en petites capitales.
class SectionLabel extends StatelessWidget {
  final String label;
  const SectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            letterSpacing: 1.1,
          ),
        ),
      );
}

/// Ligne qui ouvre une sous-page : icône, titre, résumé, chevron.
class NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback onTap;

  const NavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppTheme.primaryBlue),
        title: Text(title),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(trailingText!,
                    style: const TextStyle(color: AppTheme.textSecondary)),
              ),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
        onTap: onTap,
      );
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Colors.red.shade700 : null,
    behavior: SnackBarBehavior.floating,
  ));
}

/// Boîte de saisie d'un nom ; null si annulée ou inchangée.
Future<String?> askName(BuildContext context, String title,
    {String initial = ''}) async {
  final res = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial),
  );
  final name = res?.trim() ?? '';
  if (name.isEmpty || name == initial.trim()) return null;
  return name;
}

/// Le champ appartient à la boîte : libéré seulement quand elle disparaît
/// (pas pendant son animation de fermeture).
class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  const _NameDialog({required this.title, required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nom'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _ctrl.text),
              child: const Text('Valider')),
        ],
      );
}

/// Confirmation (bouton rouge). true si confirmé.
Future<bool> confirmAction(BuildContext context, String title, String body,
    {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}
