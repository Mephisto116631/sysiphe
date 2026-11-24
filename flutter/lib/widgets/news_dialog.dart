import 'package:flutter/material.dart';
import '../app_flavor.dart';
import '../app_version.dart';
import '../models/changelog.dart';
import '../services/ui_prefs.dart';

const kNewsSeenKey = 'news_seen_version';

/// Une version : titre, date, puis ses nouveautés.
class ChangelogCard extends StatelessWidget {
  final ChangelogEntry e;
  const ChangelogCard({super.key, required this.e});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.title, style: theme.textTheme.titleMedium),
          Text('Version ${e.version} · ${e.date}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          for (final i in e.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(i),
            ),
        ],
      ),
    );
  }
}

/// Après une mise à jour : « Quoi de neuf ? », une seule fois par version.
/// [current] et [prefsSeen] injectables pour les tests.
Future<void> showNewsIfUpdated(BuildContext context,
    {String? current}) async {
  final version = (current ?? kAppVersion).split('+').first;
  if (version == 'dev') return; // build local
  final seen = await UiPrefs.getString(kNewsSeenKey);
  if (seen == version) return;
  final entries =
      unseenChangelog(lastSeen: seen, current: version, course: kCourse);
  await UiPrefs.setString(kNewsSeenKey, version);
  if (entries.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Quoi de neuf ? 🎉'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [for (final e in entries) ChangelogCard(e: e)],
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Super !')),
      ],
    ),
  );
}

/// Réglages → Nouveautés : tout l'historique.
class NewsPage extends StatelessWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final e in kChangelog)
        if (kCourse || !e.courseOnly) e
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveautés')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final e in entries)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: ChangelogCard(e: e),
              ),
            ),
        ],
      ),
    );
  }
}
