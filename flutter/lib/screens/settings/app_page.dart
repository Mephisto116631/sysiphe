import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../app_flavor.dart';
import '../../app_version.dart';
import '../../services/settings_transfer.dart';
import '../../services/update_service.dart';
import '../../theme.dart';
import '../../widgets/settings_import_dialog.dart';
import '../../widgets/update_flow.dart';
import 'common.dart';

/// Réglages → Application : mises à jour, téléchargement automatique,
/// espace occupé, version.
class AppPage extends StatefulWidget {
  /// Profil actif (export / import de ses paramètres) ; null : masqué.
  final String? userId;
  final String? profileName;
  const AppPage({super.key, this.userId, this.profileName});

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  int _cacheRefresh = 0; // relance le calcul de l'espace utilisé
  bool _autoUpdate = false; // préférence de l'appareil (pas du profil)

  @override
  void initState() {
    super.initState();
    UpdateService.autoDownload().then((v) {
      if (mounted) setState(() => _autoUpdate = v);
    });
  }

  /// Fichier .json des paramètres (profil + appareil), partagé.
  Future<void> _export() async {
    try {
      final b = await exportBundle(widget.userId!,
          profileName: widget.profileName);
      final slug = (widget.profileName ?? 'profil')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final name = 'sysiphe-parametres-${slug.isEmpty ? 'profil' : slug}.json';
      final file = File('${Directory.systemTemp.path}/$name');
      await file.writeAsString(b.encode(), flush: true);
      await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/json', name: name)],
          subject: 'Paramètres Sysiphe');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _import() async {
    final b = await askSettingsBundle(context);
    if (b == null || !mounted) return;
    try {
      await importBundle(widget.userId!, b);
      if (mounted) showSnack(context, 'Paramètres appliqués ✓');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Application')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update,
                      color: AppTheme.primaryBlue),
                  title: const Text('Mises à jour'),
                  subtitle: Text('Version $kAppVersion · vérifier'),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppTheme.textSecondary),
                  onTap: () => checkAndOfferUpdate(context),
                ),
                ListTile(
                  key: const ValueKey('switch-flavor'),
                  leading: const Icon(Icons.directions_run,
                      color: Colors.deepOrange),
                  title: Text(kCourse
                      ? 'Revenir à la version sans course'
                      : 'Activer le module Course'),
                  subtitle: Text(kCourse
                      ? 'Module Course installé (GPS, carte). Les données '
                          'restent.'
                      : 'Suivi GPS des courses : installe la version avec '
                          'course (même app, données gardées).'),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppTheme.textSecondary),
                  onTap: () => switchFlavor(context),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.download_for_offline_outlined,
                      color: AppTheme.primaryBlue),
                  title: const Text('Télécharger automatiquement'),
                  subtitle: const Text(
                      'Récupère la mise à jour au lancement ; il ne reste '
                      'qu\'à confirmer l\'installation. Réglage de '
                      'l\'appareil, commun à tous les profils.'),
                  value: _autoUpdate,
                  onChanged: (v) {
                    setState(() => _autoUpdate = v);
                    UpdateService.setAutoDownload(v);
                  },
                ),
                FutureBuilder<int>(
                  key: ValueKey(_cacheRefresh),
                  future: UpdateService.cacheBytes(),
                  builder: (context, snap) {
                    final mo = (snap.data ?? 0) / 1048576;
                    return ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined,
                          color: AppTheme.primaryBlue),
                      title: const Text('Libérer de l\'espace'),
                      subtitle: Text(snap.hasData
                          ? 'Anciennes mises à jour et exports : '
                              '${mo.toStringAsFixed(mo < 10 ? 1 : 0)} Mo'
                          : 'Calcul…'),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppTheme.textSecondary),
                      onTap: () async {
                        final freed = await UpdateService.cleanup();
                        if (!context.mounted) return;
                        setState(() => _cacheRefresh++);
                        showSnack(context,
                            '${(freed / 1048576).toStringAsFixed(0)} Mo libérés');
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          if (widget.userId != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    key: const ValueKey('export-params'),
                    leading: const Icon(Icons.ios_share,
                        color: AppTheme.primaryBlue),
                    title: const Text('Exporter mes paramètres'),
                    subtitle: const Text('Fichier texte (.json) : poids, '
                        'planche, intensité, repos, chrono, rappels…'),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppTheme.textSecondary),
                    onTap: _export,
                  ),
                  ListTile(
                    key: const ValueKey('import-params'),
                    leading: const Icon(Icons.file_download_outlined,
                        color: AppTheme.primaryBlue),
                    title: const Text('Importer des paramètres'),
                    subtitle: const Text('Coller le texte d\'un fichier '
                        'exporté (autre profil ou téléphone)'),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppTheme.textSecondary),
                    onTap: _import,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text(
                'Sysiphe v$kAppVersion${kCourse ? ' · Course' : ''} · Flutter',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
