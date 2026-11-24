import 'package:flutter/material.dart';
import '../../app_flavor.dart';
import '../../theme.dart';

/// Une rubrique du mode d'emploi.
class HelpSection {
  final IconData icon;
  final String title;
  final List<String> lines;
  final bool courseOnly;
  const HelpSection(this.icon, this.title, this.lines,
      {this.courseOnly = false});
}

const kHelp = <HelpSection>[
  HelpSection(Icons.fitness_center, 'Saisir une séance', [
    'Onglet Saisie : choisis l\'exercice, tape le nombre de répétitions (ou '
        'de secondes), puis Enregistrer. Le numéro de série (S1, S2…) avance '
        'tout seul.',
    'Plusieurs séries d\'un coup : écris « 12 10 8 » dans le champ.',
    'Les petites cartes en dessous reprennent ta séance précédente : tape une '
        'valeur, elle s\'enregistre au bout de 3 secondes.',
    'Te tromper n\'est pas grave : touche une série de la liste du jour pour '
        'la corriger, ou la corbeille pour la supprimer.',
  ]),
  HelpSection(Icons.timer_outlined, 'Chrono et repos', [
    'Pour un exercice en secondes (gainage, planche…), lance le chrono : il '
        'remplit la valeur tout seul quand tu l\'arrêtes.',
    'Choisis un objectif (30 s, 1 min…) et un nombre de séries : le repos puis '
        'la série suivante s\'enchaînent seuls.',
    'Le bouton son passe de voix + bips à bips seuls, puis à muet.',
    'Après chaque série, le repos démarre (bandeau bleu) : −15 / +15 pour '
        'l\'ajuster, Passer pour l\'arrêter. Le vrai temps de repos est noté.',
  ]),
  HelpSection(Icons.accessibility_new, 'La planche', [
    'Réglages → Exercices → Planche : active ou désactive la planche pour ton '
        'profil.',
    'Activée, chaque série de planche reçoit un « effort » calculé avec ton '
        'poids, la variante, l\'élastique et la tension : on peut comparer des '
        'séries différentes.',
    'Ton poids se règle dans Réglages → Entraînement ; les efforts sont '
        'recalculés.',
    'Couleurs d\'intensité : automatiques, ou tes propres seuils (fiche '
        'Planche).',
  ]),
  HelpSection(Icons.bar_chart, 'Stats, Calendrier, Records', [
    'Stats : la courbe d\'un exercice, la comparaison de plusieurs exercices, '
        'tes séries par catégorie.',
    'Calendrier : tes jours d\'entraînement, plus foncés quand tu en as fait '
        'beaucoup, et ton temps de récupération.',
    'Records : ta meilleure série et ta meilleure séance pour chaque exercice.',
  ]),
  HelpSection(Icons.directions_run, 'La course', [
    'Onglet Course : choisis un objectif (distance ou durée), puis Démarrer. '
        'Tu peux éteindre l\'écran et mettre le téléphone en poche.',
    'Une voix annonce chaque kilomètre ; le chrono se met en pause tout seul '
        'aux feux rouges.',
    'Pour finir : appui long sur Terminer, puis Enregistrer.',
    'Tes courses comptent dans le Calendrier, les Stats et les Records.',
  ], courseOnly: true),
  HelpSection(Icons.label_outline, 'Exercices et catégories', [
    'Réglages → Exercices : touche un exercice pour le renommer, changer sa '
        'catégorie ou le rendre assistable (élastique).',
    'Plusieurs à la fois : appui long sur un exercice (ou ☑ en haut), coche, '
        'puis Changer la catégorie.',
  ]),
  HelpSection(Icons.cloud_off, 'Sans réseau', [
    'Tout fonctionne sans réseau : tes séries sont gardées sur le téléphone '
        '(petit nuage orange sur la série) et partent dès que le réseau '
        'revient.',
    'Le bandeau « Hors ligne » en haut de la Saisie a un bouton Réessayer.',
  ]),
  HelpSection(Icons.person_outline, 'Profil, photo et réglages', [
    'Touche le rond de ton profil en haut des Réglages pour choisir une '
        'couleur, une image ou ta photo.',
    'Rappels : une notification quand une séance est conseillée, ou après '
        'quelques jours sans séance.',
    'Application → Exporter mes paramètres : un fichier pour retrouver tous '
        'tes réglages sur un autre téléphone (Importer).',
    'Compte et sécurité : associe ton compte Google pour retrouver tes '
        'profils sans PIN sur un autre téléphone.',
  ]),
  HelpSection(Icons.system_update, 'Mises à jour', [
    'L\'app te propose les nouvelles versions au démarrage. Tes données ne '
        'sont jamais touchées : elles sont sur le serveur.',
    'Réglages → Nouveautés : ce qui a changé à chaque version.',
  ]),
];

/// Réglages → Mode d'emploi.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = [
      for (final s in kHelp)
        if (kCourse || !s.courseOnly) s
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Mode d\'emploi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                for (final s in sections)
                  ExpansionTile(
                    leading: Icon(s.icon, color: AppTheme.primaryBlue),
                    title: Text(s.title),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in s.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('• $l'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
