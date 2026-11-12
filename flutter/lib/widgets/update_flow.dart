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
    // Au lancement : pop-up directement (une seule fois par lancement).
    if (update.build == await UpdateService.skippedBuild()) return;
    // Téléchargement automatique activé : on récupère l'APK avant de
    // proposer, l'installation se fait alors en un appui.
    if (await UpdateService.autoDownload() &&
        await UpdateService.cachedApk(update) == null) {
      try {
        await UpdateService.download(update);
      } catch (_) {/* on proposera le téléchargement manuel */}
    }
    if (!context.mounted) return;
    await _confirmAndInstall(context, update, offerSkip: true);
    return;
  }
  await _confirmAndInstall(context, update);
}

Future<void> _confirmAndInstall(BuildContext context, UpdateInfo info,
    {bool offerSkip = false}) async {
  if (!context.mounted) return;
  final cached = await UpdateService.cachedApk(info);
  if (!context.mounted) return;
  // 1 = installer, 0 = plus tard, -1 = ignorer cette version
  // (un appui hors de la fenêtre = plus tard, jamais « ignorer »)
  final choice = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mise à jour disponible'),
      content: Text('Version ${info.label} '
          '(${(info.size / 1048576).toStringAsFixed(0)} Mo).\n'
          'Installée : $kAppVersion.\n\n'
          '${cached != null ? 'Déjà téléchargée : prête à installer.\n\n' : ''}'
          'Tes données ne sont pas touchées : elles sont sur le serveur.'),
      actions: [
        if (offerSkip)
          TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text('Ignorer cette version')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Plus tard')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: Text(cached != null ? 'Installer' : 'Télécharger et installer')),
      ],
    ),
  );
  if (choice == -1) {
    await UpdateService.skipBuild(info.build);
    return;
  }
  if (choice != 1 || !context.mounted) return;
  final apk = cached ??
      await showDialog<File?>(
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
