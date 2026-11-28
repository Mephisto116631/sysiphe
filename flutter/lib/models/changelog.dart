/// Nouveautés de chaque version, écrites pour les utilisateurs (pas pour les
/// développeurs). Affichées une fois après une mise à jour, et à tout moment
/// dans Réglages → Nouveautés. La plus récente en premier.
class ChangelogEntry {
  final String version; // « 2.21.0 »
  final String date; // « 24 nov. 2026 »
  final String title;
  final List<String> items;

  /// Visible seulement dans la version avec le module Course.
  final bool courseOnly;

  const ChangelogEntry(this.version, this.date, this.title, this.items,
      {this.courseOnly = false});
}

const kChangelog = <ChangelogEntry>[
  ChangelogEntry('2.24.0', '28 nov. 2026', 'Ton repos idéal', [
    '⚡ Calendrier → Récupération : le nombre de jours de repos qui précède '
        'tes meilleures séances, et l\'écart pour chaque repos.',
    '🔔 Réglages → Rappels : la « séance conseillée » peut suivre ton repos '
        'habituel, ton repos optimal, ou un nombre de jours que tu choisis.',
  ]),
  ChangelogEntry('2.23.2', '27 nov. 2026', 'Corriger une planche', [
    '✏️ En touchant une série de planche du jour, tu peux maintenant changer '
        'la variante, la forme, l\'élastique et la tension, pas seulement le '
        'temps. L\'effort est recalculé.',
  ]),
  ChangelogEntry('2.23.0', '27 nov. 2026', 'Tes séances cardio enregistrées', [
    '⏱️ Minuteur (HIIT, Tabata…) : à la fin, enregistre ta séance en un '
        'appui. Chaque cycle devient une série, avec le repos choisi et le '
        'repos vraiment pris.',
    '🔔 La notification « Repos terminé » reste affichée jusqu\'à ce que tu '
        'reviennes dans l\'app.',
  ]),
  ChangelogEntry('2.22.1', '25 nov. 2026', 'Stats en volume', [
    '📊 Dans Stats, chaque exercice s\'affiche en volume du jour (total des '
        'répétitions ou des secondes). Le bouton « Meilleure série » montre '
        'ta meilleure série à la place.',
  ]),
  ChangelogEntry('2.22.0', '24 nov. 2026', 'Une planche pour tous', [
    '⚖️ Le calcul de l\'effort de la planche est le même pour tout le monde. '
        'Toi, tu règles seulement ton poids (Réglages → Entraînement).',
    '🙈 Planche désactivée ? Elle n\'apparaît plus dans tes cartes '
        'd\'exercices ni dans la liste.',
  ]),
  ChangelogEntry('2.21.0', '24 nov. 2026', 'Nouveautés et mode d\'emploi', [
    '📰 Cette fenêtre ! Après chaque mise à jour, un résumé de ce qui change. '
        'Tout l\'historique dans Réglages → Nouveautés.',
    '📖 Un mode d\'emploi complet dans Réglages → Mode d\'emploi.',
    '🏃 Le module Course s\'active (ou se retire) directement depuis les '
        'Réglages, en un appui. Tes données restent.',
  ]),
  ChangelogEntry('2.20.0', '24 nov. 2026', 'Ta photo de profil', [
    '🖼️ Touche le rond de ton profil (Réglages) : choisis une couleur, une '
        'image (animaux, sports…) ou ta propre photo.',
  ]),
  ChangelogEntry('2.19.0', '24 nov. 2026', 'Tes réglages en un fichier', [
    '💾 Exporte tous tes réglages dans un fichier, et réimporte-les sur un '
        'autre téléphone (Réglages → Application).',
    '🏷️ Change la catégorie de plusieurs exercices d\'un coup : appui long sur '
        'un exercice dans Réglages → Exercices.',
    '📨 L\'admin peut t\'envoyer des réglages tout prêts et un message.',
  ]),
  ChangelogEntry('2.18.0', '24 nov. 2026', 'Le module Course', [
    '🏃 Suivi GPS de tes courses : distance, allure, carte du parcours.',
    '🔊 Une annonce vocale à chaque kilomètre, pause automatique aux feux '
        'rouges, objectif en distance ou en durée.',
    '🏆 Tes records (1 km, 5 km, 10 km) et ta distance par semaine.',
  ], courseOnly: true),
  ChangelogEntry('2.17.0', '23 nov. 2026', 'Sans réseau, ça marche', [
    '📶 Pas de réseau à la salle ? Enregistre normalement : tes séries partent '
        'toutes seules dès que le réseau revient.',
  ]),
  ChangelogEntry('2.16.0', '23 nov. 2026', 'Le repos, en mieux', [
    '⏳ Un son et « Repos terminé » à la fin de la pause, et un bandeau plus '
        'discret au-dessus de la saisie.',
    '📝 Le vrai temps de repos est noté sur chaque série (en orange si tu as '
        'écourté la pause).',
    '🎨 La planche s\'active ou se désactive pour chaque profil, avec tes '
        'propres couleurs d\'intensité.',
  ]),
  ChangelogEntry('2.15.0', '19 nov. 2026', 'Le chrono qui enchaîne', [
    '🔁 Plusieurs séries de suite : le repos puis la série suivante se lancent '
        'tout seuls.',
    '🗣️ Le chrono parle : « Partez », « 10 secondes », « Objectif atteint ».',
    '👆 Touche l\'écran n\'importe où pour arrêter la série.',
  ]),
];

(int, int, int)? _parse(String v) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(v);
  if (m == null) return null;
  return (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// a < b (versions « 2.20.0 »), false si l'une est illisible.
bool versionLess(String a, String b) {
  final x = _parse(a), y = _parse(b);
  if (x == null || y == null) return false;
  if (x.$1 != y.$1) return x.$1 < y.$1;
  if (x.$2 != y.$2) return x.$2 < y.$2;
  return x.$3 < y.$3;
}

/// Nouveautés à montrer après une mise à jour : celles entre la dernière
/// version vue (exclue) et la version installée (incluse). Jamais vue
/// (première fois) : la dernière seulement.
List<ChangelogEntry> unseenChangelog({
  required String? lastSeen,
  required String current,
  required bool course,
  List<ChangelogEntry> log = kChangelog,
}) {
  final visible = [
    for (final e in log)
      if ((course || !e.courseOnly) && !versionLess(current, e.version)) e
  ];
  if (lastSeen == null) return visible.take(1).toList();
  return [
    for (final e in visible)
      if (versionLess(lastSeen, e.version)) e
  ];
}
