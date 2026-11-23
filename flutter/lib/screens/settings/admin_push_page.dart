import 'package:flutter/material.dart';
import '../../models/profile.dart';
import '../../models/settings_bundle.dart';
import '../../services/settings_transfer.dart';
import '../../services/supabase_service.dart';
import '../../theme.dart';
import '../../widgets/settings_import_dialog.dart';
import 'common.dart';

/// Envoi de l'admin à un profil (sans toucher à son téléphone) :
/// - des paramètres (fichier .json, ou les paramètres de l'admin) : réglages
///   du profil appliqués tout de suite, ceux de l'appareil à sa prochaine
///   ouverture de l'app (efforts de planche recalculés) ;
/// - un message de présentation, affiché une fois à l'ouverture.
class AdminPushPage extends StatefulWidget {
  final String userId; // profil de l'admin
  final String? profileName;

  /// Tests : profils et envoi fournis directement.
  final Future<List<Profile>> Function()? loadProfiles;
  final Future<void> Function(String profileId, SettingsBundle? bundle,
      Map<String, String>? message)? send;

  const AdminPushPage({
    super.key,
    required this.userId,
    this.profileName,
    this.loadProfiles,
    this.send,
  });

  @override
  State<AdminPushPage> createState() => _AdminPushPageState();
}

class _AdminPushPageState extends State<AdminPushPage> {
  List<Profile>? _profiles;
  String? _target;
  SettingsBundle? _bundle;
  final _title = TextEditingController();
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    (widget.loadProfiles ?? SupabaseService.instance.getProfiles)()
        .then((p) => mounted ? setState(() => _profiles = p) : null)
        .catchError((Object e) {
      if (mounted) showSnack(context, errorText(e), error: true);
      return null;
    });
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final b = await askSettingsBundle(context,
        title: 'Paramètres à envoyer', action: 'Choisir');
    if (b != null) setState(() => _bundle = b);
  }

  Future<void> _useMine() async {
    try {
      final b = await exportBundle(widget.userId,
          profileName: widget.profileName);
      setState(() => _bundle = b);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  bool get _hasMessage => _text.text.trim().isNotEmpty;

  Future<void> _send() async {
    final target = _target;
    if (target == null) return;
    final message = _hasMessage
        ? {'titre': _title.text.trim(), 'texte': _text.text.trim()}
        : null;
    setState(() => _sending = true);
    try {
      final send = widget.send ??
          (id, b, m) => SupabaseService.instance.adminPushSettings(id,
              settings: b?.profile ?? const {},
              device: b?.device ?? const {},
              message: m);
      await send(target, _bundle, message);
      if (!mounted) return;
      final name = _profiles?.firstWhere((p) => p.id == target).name ?? '';
      showSnack(context, 'Envoyé à $name ✓ (appliqué à sa prochaine ouverture)');
      setState(() {
        _bundle = null;
        _title.clear();
        _text.clear();
      });
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = _profiles;
    final b = _bundle;
    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer à un profil')),
      body: profiles == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('push-target'),
                  value: _target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Profil'),
                  items: [
                    for (final p in profiles)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => _target = v),
                ),
                const SizedBox(height: 16),
                Text('Paramètres', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                if (b == null)
                  Text('Aucun (seulement le message).',
                      style: theme.textTheme.bodyMedium)
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                  b.profileName == null
                                      ? 'Fichier de paramètres'
                                      : 'Paramètres de ${b.profileName}',
                                  style: theme.textTheme.titleSmall),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Retirer',
                              onPressed: () => setState(() => _bundle = null),
                            ),
                          ]),
                          for (final line in b.describe()) Text('• $line'),
                        ],
                      ),
                    ),
                  ),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text('Coller un fichier'),
                    onPressed: _pickFile,
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('push-mine'),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('Mes paramètres'),
                    onPressed: _useMine,
                  ),
                ]),
                const SizedBox(height: 16),
                Text('Message de présentation',
                    style: theme.textTheme.titleMedium),
                Text('Affiché une fois à sa prochaine ouverture de l\'app.',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                      labelText: 'Titre (facultatif)',
                      hintText: 'Bienvenue sur Sysiphe'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('push-text'),
                  controller: _text,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                      labelText: 'Texte',
                      hintText: 'Nouveautés, mode d\'emploi…'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('push-send'),
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer'),
                  onPressed: _sending ||
                          _target == null ||
                          (b == null && !_hasMessage)
                      ? null
                      : _send,
                ),
                const SizedBox(height: 8),
                Text(
                    'Les réglages du profil (poids, planche, intensité…) '
                    'changent tout de suite ; ceux de son téléphone (repos, '
                    'chrono, rappels…) à sa prochaine ouverture de l\'app.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppTheme.textSecondary)),
              ],
            ),
    );
  }
}
