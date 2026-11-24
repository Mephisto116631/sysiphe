import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/settings_bundle.dart';

/// Boîte « Importer des paramètres » : coller le texte du fichier, voir ce
/// qui sera appliqué, confirmer. Renvoie le fichier lu, ou null.
Future<SettingsBundle?> askSettingsBundle(BuildContext context,
        {String title = 'Importer des paramètres',
        String action = 'Appliquer'}) =>
    showDialog<SettingsBundle>(
      context: context,
      builder: (_) => _ImportDialog(title: title, action: action),
    );

class _ImportDialog extends StatefulWidget {
  final String title, action;
  const _ImportDialog({required this.title, required this.action});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _ctrl = TextEditingController();
  SettingsBundle? _bundle;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _check() {
    try {
      final b = SettingsBundle.parse(_ctrl.text);
      setState(() {
        _bundle = b;
        _error = b.isEmpty ? 'Aucun paramètre reconnu dans ce fichier.' : null;
      });
    } on FormatException catch (e) {
      setState(() {
        _bundle = null;
        _error = e.message;
      });
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text == null) return;
    _ctrl.text = d!.text!;
    _check();
  }

  @override
  Widget build(BuildContext context) {
    final b = _bundle;
    final ok = b != null && !b.isEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Colle le texte d\'un fichier de paramètres Sysiphe '
                '(.json, obtenu avec « Exporter mes paramètres »).'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('import-text'),
              controller: _ctrl,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: '{ "format": "sysiphe-parametres", … }',
                errorText: _error,
                errorMaxLines: 3,
              ),
              onChanged: (_) => _check(),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Coller'),
                onPressed: _paste,
              ),
            ),
            if (ok) ...[
              Text(
                  b.profileName == null
                      ? 'Sera appliqué :'
                      : 'Paramètres de ${b.profileName} — sera appliqué :',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final line in b.describe()) Text('• $line'),
              if (b.ignored.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${b.ignored.length} réglage(s) inconnu(s) ignoré(s)',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          key: const ValueKey('import-apply'),
          onPressed: ok ? () => Navigator.pop(context, b) : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
