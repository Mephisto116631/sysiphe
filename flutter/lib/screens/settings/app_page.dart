import 'package:flutter/material.dart';
import '../../app_version.dart';
import '../../services/update_service.dart';
import '../../theme.dart';
import '../../widgets/update_flow.dart';
import 'common.dart';

/// Réglages → Application : mises à jour, téléchargement automatique,
/// espace occupé, version.
class AppPage extends StatefulWidget {
  const AppPage({super.key});

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
          const SizedBox(height: 24),
          Center(
            child: Text('Sysiphe v$kAppVersion · Flutter',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
