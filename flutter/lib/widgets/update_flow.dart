import 'dart:io';
import 'package:flutter/material.dart';
import '../app_version.dart';
import '../services/update_service.dart';

/// Vérifie et propose la mise à jour depuis les Releases GitHub.
/// [silent] : au démarrage, ne rien afficher s'il n'y a rien de nouveau ou
/// si GitHub est injoignable.
Future<void> checkAndOfferUpdate(BuildContext context, {bool silent = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  UpdateInfo? info;
  try {
    info = await UpdateService.checkForUpdate();
  } catch (e) {
    if (!silent) {
      messenger.showSnackBar(SnackBar(
          content: Text('Vérification impossible : $e'),
          behavior: SnackBarBehavior.floating));
    }
    return;
  }
  if (!context.mounted) return;
  if (info == null) {
    if (!silent) {
      messenger.showSnackBar(SnackBar(
          content: Text(kAppVersion == 'dev'
              ? 'Build de développement : mise à jour désactivée'
              : 'Sysiphe est à jour ($kAppVersion)'),
          behavior: SnackBarBehavior.floating));
    }
    return;
  }
  final update = info;
  if (silent) {
    messenger.showSnackBar(SnackBar(
      content: Text('Nouvelle version ${update.label} disponible'),
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
          label: 'Installer',
          onPressed: () => _confirmAndInstall(context, update)),
    ));
    return;
  }
  await _confirmAndInstall(context, update);
}

Future<void> _confirmAndInstall(BuildContext context, UpdateInfo info) async {
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mise à jour disponible'),
      content: Text('Version ${info.label} '
          '(${(info.size / 1048576).toStringAsFixed(0)} Mo).\n'
          'Installée : $kAppVersion.\n\n'
          'Tes données ne sont pas touchées : elles sont sur le serveur.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Télécharger et installer')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final apk = await showDialog<File?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DownloadDialog(info: info),
  );
  if (apk == null || !context.mounted) return;
  final started = await UpdateService.install(apk);
  if (!started && context.mounted) {
    // Première fois : Android a ouvert « Installer des applis inconnues ».
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Autorisation Android'),
        content: const Text(
            'Active « Autoriser depuis cette source » pour Sysiphe dans l\'écran '
            'qui vient de s\'ouvrir, puis reviens ici et appuie sur Installer.'),
        actions: [
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await UpdateService.install(apk);
            },
            child: const Text('Installer'),
          ),
        ],
      ),
    );
  }
}

/// Téléchargement avec progression ; renvoie le fichier, ou null si erreur.
class _DownloadDialog extends StatefulWidget {
  final UpdateInfo info;
  const _DownloadDialog({required this.info});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() { _error = null; _progress = 0; });
    try {
      final f = await UpdateService.download(widget.info,
          onProgress: (p) => mounted ? setState(() => _progress = p) : null);
      if (mounted) Navigator.pop(context, f);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Téléchargement ${widget.info.label}'),
      content: _error == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                const SizedBox(height: 8),
                Text('${(_progress * 100).round()} %'),
              ],
            )
          : Text('Échec du téléchargement : $_error'),
      actions: _error == null
          ? null
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler')),
              FilledButton(onPressed: _start, child: const Text('Réessayer')),
            ],
    );
  }
}
