# Sysiphe — Plan d'actions

> Cocher une case : remplacer `[ ]` par `[x]` (sur GitHub : bouton ✏️ du fichier).
> Ce fichier est la référence du suivi : chaque session Claude le lit et le met à jour.
>
> Dernière mise à jour : 17 novembre 2026

**Cap** : l'app mobile est l'APK **Flutter** (saisie, réglages, consultation). Le site **Streamlit** reste sur
Streamlit Cloud en **consultation seule** (depuis le 17/11). Les deux partagent la même base **Supabase**.
Le NAS est abandonné. Le nom reste **Sysiphe** (bref passage à « Thésée » en v2.8.0, annulé le 17/11).

---

## Phase 0 — Déjà fait ✅

- [x] Diagnostic du projet et README réécrit en UTF-8, aligné sur le code
- [x] Flutter : colonne `performance` (valeur) distincte de `charge` (lest kg), comme l'app web
- [x] Flutter : réglages lus/écrits dans `user_settings` (au lieu de `settings`, inexistante)
- [x] Flutter : effort calculé seulement pour « Planche », avec la calibration de l'utilisateur
- [x] Web : bouton « recalcul des efforts » réparé (recherche insensible à la casse, puis upsert qui échouait toujours sur les colonnes NOT NULL)
- [x] NAS, APK WebView et Capacitor archivés dans `archive/` (rien de supprimé)

## Phase 1 — Rendre les données visibles dans Flutter 🔴 (bloquant)

Constaté dans les logs Supabase : toutes les requêtes Flutter qui chargent les séries
répondent **400**, et l'app reste bloquée sur un chargement infini.

- [x] Ne plus trier sur `perfs.created_at` (la colonne n'existe pas, d'où les erreurs 400) → tri sur `id`
- [x] `perfs.id` est un entier (`bigint`) et non un texte : lecture et suppression corrigées
- [x] Charger **tout** l'historique : Supabase ne renvoie que 1 000 lignes par requête (tu en as 1 260) → pagination
- [x] Stats / Records / Calendrier : afficher un message d'erreur et un bouton « Réessayer » au lieu d'un chargement infini
- [x] Ordre des profils identique au web
- [x] Build Flutter vert après la fusion de la PR #4 (vérifié par Claude)
- [x] **Toi** : installer le nouvel APK et vérifier Saisie, Stats, Calendrier et Records sur tes vraies données

## Phase 2 — Mise en production

- [x] Ouvrir la PR `ccr-6aa55910-p46qv7` → `main`
- [x] Relire et fusionner la PR [#4](https://github.com/Mephisto116631/sysiphe/pull/4) (CI verte, fusionnée le 9 novembre)
- [ ] Vérifier que Streamlit Cloud a redéployé l'app web sans erreur
- [ ] Désinstaller l'ancienne app WebView du téléphone
- [ ] Supprimer les secrets GitHub inutiles : `KEYSTORE_BASE64`, `KEY_ALIAS`
- [ ] Éteindre les conteneurs Sysiphe sur le NAS

## Phase 3 — Base de données et sécurité 🔐

- [x] **Protéger les données (RLS)** — solution retenue le 9 novembre : session Supabase anonyme et
      persistante par appareil, PIN vérifié **par le serveur** une seule fois, puis la base ne sert que les
      profils rattachés à cette session. Aucune reconnexion, aucune latence ajoutée.
  - [x] Réglages Supabase : connexions anonymes, association manuelle d'identités, URL de retour de l'app (toi)
  - [x] Étape 1 (base, additive) : `profile_members`, anti force brute (5 essais → 15 min), RPC
        `list_profiles` / `claim_profile` / `create_profile` / `set_profile_pin` — testée en transaction
        annulée puis appliquée
  - [x] Étape 1 (app Flutter v2.2.0) : session anonyme, PIN vérifié par le serveur, hash du PIN plus jamais
        envoyé au téléphone
  - [x] Étape 1 (site web) : même principe, session gardée dans le cookie d'un an ; une session anonyme n'est jamais prise pour un compte Google
  - [x] **Toi** : installer la v2.2.0 et confirmer ton PIN une dernière fois
  - [x] Étape 2 (base, 12/11/2026) : RLS activée sur `perfs`, `profiles`, `user_settings` (accès seulement aux profils
        rattachés à l'appareil), `pin_hash` et `role` illisibles/non modifiables en direct, plus aucun accès sans session ;
        testée en transaction annulée (accès, refus, admin) puis appliquée
        ⚠ les anciennes versions de l'app (sans session anonyme, < v2.2.0) ne fonctionnent plus : mettre à jour
  - [x] Étape 3 (v2.11.0, 18/11) : « Associer mon compte Google » (Réglages → Sécurité). Jeton à usage unique
        (`create_link_token` / `redeem_link_token`, table `link_tokens`, migration testée en transaction annulée puis
        appliquée) : le compte Google reçoit les profils du téléphone, existant ou non. Ailleurs : « Se connecter avec
        Google » (écran des profils, site web) → profils associés sans PIN
  - [ ] **Toi** : associer ton compte Google sur le téléphone, puis tester « Se connecter avec Google » sur le site
- [ ] `user_settings.user_id` pointe sur `auth.users` : les profils « Dilbert 🐶 » et « Profil 3 » ne peuvent pas
      enregistrer de réglages (violation de clé étrangère). → Faire pointer la clé sur `profiles(id)`
      → correctif testé sur la base (17/11), **à appliquer par toi** : `supabase/a_appliquer/README.md`
- [ ] Harmoniser les catégories en base (`Force isométrique `, `Gainage`, `Force Iso`) : migration SQL
      → même fichier que ci-dessus : `Force isométrique ` (1 série) → `Force Iso` ; `Gainage` gardé (abdos tenus
      en secondes, distincts des abdos en reps)
- [x] Hachage du PIN : `strip()` aussi à la vérification côté web, comme à l'enregistrement et dans Flutter
- [x] `SETUP.md` réécrit avec le schéma réel de production (3 tables, toutes les colonnes)

## Phase 4 — Parité fonctionnelle Flutter ↔ web

Pages et fonctions présentes sur le web, absentes ou simplifiées dans Flutter :

- [~] **Saisie planche** multi-séries (S1 à S5) avec variante, forme, élastique et tension par série — **abandonné (20/11)** : la saisie série par série (chrono, enchaînement) convient mieux
- [x] **Saisie lestée** : champ « Lest (kg) » pour les séries en reps (enregistré dans `charge`)
- [x] **Saisie** : options planche ouvertes automatiquement pour « Planche » ; bug du champ Exercice corrigé (curseur qui sautait)
- [x] **Saisie** : carte « Séance précédente » — un appui pré-remplit l'exercice avec la série suivante telle que faite la dernière fois (valeur, lest, options planche) ; après chaque enregistrement, la série suivante s'enchaîne
- [x] **Connexion** : profil mémorisé sur le téléphone (comme le cookie d'un an du web) — plus de liste ni de PIN à chaque ouverture ; PIN redemandé seulement après « Changer de profil »
- [x] **Stats planche** : sélecteur Effort (par défaut) / Temps
- [ ] **Saisie** : panneau « stats du jour et prochaine séance » (KPI)
- [x] **Stats** : une valeur par séance, choix de période (30 j / 3 mois / 6 mois / tout), badge progression / plateau / régression (port testé de `detect_plateau`)
- [x] **Stats** : effort pondéré pour la planche, tonnage (`performance × charge`) ou volume pour les reps
- [x] **Repos** : analyse de la récupération dans l'écran Calendrier (repos moyen / habituel / plus long, prochaine séance conseillée, dernières reprises) — port testé de `suggest_next_session`
- [x] **Records** : record planche basé sur l'effort pondéré, puis le temps ; autres exercices départagés par le lest
- [x] **Paramètres** : écran « Calibration planche » (variantes, formes, élastiques, tensions), partagé avec le web, + recalcul des efforts
- [x] **Paramètres** : gestion des profils (créer, renommer, supprimer sauf le profil actif)
- [x] **Paramètres** : renommer un exercice dans tout l'historique (avec confirmation si fusion)
- [x] Initiales des profils : l'emoji de « Dilbert 🐶 » n'est plus coupé en deux, un double espace ne fait plus planter
- [x] **Calendrier** : tout l'historique est chargé (avant : 6 derniers mois seulement, les mois plus anciens paraissaient vides)
- [~] **Paramètres** : export CSV — version admin (toute la base, PR #23) ; pas d'export par profil
- [x] Rappel d'inactivité (`inactivity_days`) en notification locale (v2.10.0)

## Phase 4 bis — Fonctions perdues (audit du 9 novembre) 🔎

Comparaison ligne à ligne du web (Streamlit) avec Flutter, plus les colonnes de `user_settings`
qui ne sont plus lues par aucun code : elles trahissent des fonctions d'**avant l'historique git**
(le dépôt commence le 14 octobre, déjà en v17/v18). Rien n'a été perdu côté web depuis.

**Demandé**
- [x] Créer un compte (nouveau profil, avec PIN facultatif) depuis l'écran de connexion
- [x] Créer un exercice (nom, unité, catégorie) depuis Saisie (bouton ⊕ à côté du champ Exercice)

**Saisie** (web → absent de Flutter)
- [x] Saisie rapide de plusieurs séries d'un coup : « 12 10 8 », « 12/10/8 » ou « 12+10+8 » (port testé de `parse_reps`)
- [x] Navigation ◀ jour précédent / retour à aujourd'hui (pas de saisie dans le futur)
- [x] Supprimer toute la séance du jour (avec confirmation)
- [x] Par exercice : record en série, moyenne des N dernières séances, écart du jour en % et alerte « Nouveau record » à l'enregistrement
- [x] Catégorie libre par exercice (choisie à la création, reprise de la séance précédente)
- [~] Planche : bloc S1 à S5 avec forme par série et couleur d'intensité — **abandonné (20/11)** : la saisie série par série (chrono, enchaînement) convient mieux
- [~] « Tout sauvegarder » en un appui — remplacé par l'enregistrement carte par carte (v2.6.0)
- [x] Panneau du jour : séries ou effort du jour, séances du mois, reps de la semaine vs semaine précédente (port testé de `compute_period_comparison`)
- [ ] Rappel de prochaine séance dans l'agenda (`.ics`)

**Stats / Records**
- [x] Graphe « séries par catégorie » (v2.12.0 : barres empilées par semaine, par mois sur « Tout »)
- [x] Planche : une courbe par variante (v2.12.0 : option « Par variante », légende masquable)
- [x] Comparer plusieurs exercices sur un même graphe (v2.12.0 : jusqu'à 5, en % du record ou valeurs brutes)
- [x] Records planche par combinaison variante / élastique / tension (couleur d'intensité) ; records muscu = meilleure séance (volume ou tonnage) + meilleure série

**Paramètres**
- [ ] « Inclure la planche » et taille de la moyenne glissante (`include_planche`, `nb_days_avg`)
- [x] Afficher / masquer le champ lest (`enable_charges`) — Réglages, v2.5.2
- [~] Export CSV de l'historique — version admin seulement (PR #23)

**Traces d'avant git (colonnes orphelines de `user_settings`)**
- [ ] Thèmes (`app_theme`, défaut « Abysse ») — **reporté** (décision du 9 novembre : pas prioritaire)
- [x] Rappel après N jours sans séance (`inactivity_days`, défaut 2) — v2.10.0
- [ ] Période de graphe mémorisée (`graph_period`)

**Connexion web à trancher** (lié à la RLS, phase 3)
- [x] Comptes Google : **option d'association** à un profil existant (v2.11.0) (retrouver son profil sur un autre appareil ou sur le web, sans reconnexion à chaque ouverture) — à faire avec la RLS, en attente de validation

## Demandes du 9 novembre (v2.3.0)

- [x] Stats : « Planche » sélectionnée par défaut dans le menu
- [x] Records : filtre Tout / Planche / Musculation + recherche (exercice, ou variante / élastique / tension)
- [x] Saisie : la séance précédente est remise directement (formulaire pré-rempli avec le premier exercice pas
      encore fait), enchaînement automatique sur l'exercice suivant quand ses séries sont faites
- [x] Saisie : liste « Récents » des anciens exercices, du plus récent au plus ancien ; un appui reprend la dernière
      fois où l'exercice a été fait (aussi pour l'autocomplétion)
- [x] **Toi** : v2.3.0 installée et validée sur le téléphone (« ça marche »)
- [x] Mise à jour intégrée (v2.4.0) : Paramètres → « Mises à jour » vérifie la dernière Release GitHub, télécharge
      l'APK et ouvre l'installeur Android ; nouvelle version signalée au démarrage
- [x] CI : build d'APK de test sur chaque PR (le code Android natif est validé avant fusion)
- [x] Récupération (Calendrier) : filtre de période 30 j / 3 mois / 6 mois / Tout (v2.4.1)
- [x] **Toi** : mise à jour intégrée testée sur le téléphone (v2.4.0 → v2.4.1) : ça marche
- [x] Onglet **Modèle** (v2.5.0) — la « vision d'ensemble » de l'ancien Excel : coefficients modifiables, grille
      variante × forme recalculée en direct, détail du calcul d'une case, impact sur l'historique (meilleur effort par
      variante avant / après) ; « Appliquer partout » enregistre et recalcule toutes les séries, les autres onglets se
      rafraîchissent
- [x] Générateur des formes (v2.5.1) : base × multiplicateur^rang, comme l'ancien Excel (34 × 1,4 → 34 · 47,6 ·
      66,64 · 93,296, retrouvé automatiquement à partir des valeurs actuelles)
- [x] Contraste des puces « Récents » : texte blanc sur gris clair (1,1:1) → texte foncé (≥ 4,5:1), testé
- [x] Onglet Modèle : la section ouverte se repliait (et le clavier se fermait) au premier chiffre tapé ; champs
      arrondis à l'affichage (66,6 au lieu de 66,64)
- [x] Autres générateurs de l'ancien Excel : aucun — variantes construites pas à pas depuis Fibonacci, élastiques =
      kg des élastiques du commerce (repères affichés dans l'onglet Modèle)
- [x] Champ « Lest (kg) » désactivable dans les Réglages (colonne `enable_charges`, respectée aussi par le web) (v2.5.2)
- [x] Petites cartes d'exercices sous la carte de saisie principale (v2.6.0) : une par exercice de la séance reprise
      (hors planche), champ vide avec la dernière fois en gris dedans, date et record en gris dessous, « 12/10/8 »,
      réenregistrer remplace les séries du jour ; « + Ajouter un exercice » (récents ou nouveau)
- [x] Réglages : section « Mises à jour » remontée avant « Entraînement » (v2.6.1)

## Phase 5 — Qualité et robustesse

- [x] Tests Flutter : `calculerEffort` donne les mêmes résultats que `data.py`, et `Perf.fromJson` est testé sur des lignes réelles (`flutter/test/`, 53 tests)
- [x] CI : `flutter analyze` + `flutter test` sur chaque PR, et pas seulement à la publication (`ci.yml`)
- [x] CI : `pytest test_data.py` sur chaque PR (28 tests)
- [x] Script de sauvegarde quotidienne vers le NAS (`backup/`) : copie complète restaurable + CSV des perfs, 60 jours
      (testé sur une base locale : mot de passe à caractères spéciaux, rotation, restauration, échec)
- [x] Script Google Apps Script : CSV quotidiens dans Drive « Sysiphe sauvegardes », 60 jours (`backup/google-drive`)
- [ ] Installer la sauvegarde Drive (toi, sur ordi : clé `service_role` + script, `backup/README.md` option A)
- [ ] (facultatif) Installer la sauvegarde NAS (`backup/README.md` option B)
- [ ] Vérifier la 1re sauvegarde réelle (fichiers du jour dans Drive)
- [ ] Mode hors ligne Flutter : cache local et saisie différée, synchronisée au retour du réseau
- [x] Numéro de version affiché dans l'app (bas de l'écran Paramètres, ex. `2.1.0+7`)
- [x] Version incrémentée à chaque build (`versionCode` = numéro du run CI) et notes de version générées depuis les PR → passage en **v2.1.0**

## Phase 6 — Plus tard / à décider

- [x] Garder Streamlit à long terme, ou tout migrer dans Flutter ? → gardé en consultation seule (17/11)
- [ ] Icône définitive de l'app Flutter

## Audit du 17 novembre 2026

- [x] PR #32 et #33 (même correctif « existe déjà ») : #33 fusionnée, #32 fermée ; comparaison sans accents reprise
- [x] Version bloquée à 2.6.1 depuis le 10/11 (13 PR publiées sous le même tag) → **v2.7.0** ; la CI refuse
      désormais une PR qui modifie l'app sans augmenter `version:`
- [x] Migrations : fichiers renommés à la version de production, 5 migrations absentes du dépôt ajoutées
      (dont `profile_pin_lock` et la création de `profiles.role`)
- [x] README et SETUP à jour (RLS, rôles, assistables, minuteur, sauvegardes, CI)
- [ ] **Toi** (Claude n'a pas le droit de supprimer des branches) : GitHub → Settings → General → cocher
      « Automatically delete head branches », puis supprimer les 15 branches de la page Branches sauf `main`.
      Rien n'est perdu : tout est fusionné ou repris (vérifié le 17/11 ; seul le message de blocage PIN de
      `feat/saisie-pct` manquait, repris dans la v2.7.0)
- [ ] **Toi** : appliquer `supabase/a_appliquer/20261117_reglages_profils_categories.sql` (marche à suivre dans le README du dossier)
- [x] Site web en **consultation seule** (décision du 17/11) : page Saisie retirée, réglages en lecture,
      création de profil / de compte retirée, toute écriture refusée dans `supabase_io.py` (`LECTURE_SEULE`)
- [x] Renommage en **Thésée** : noms affichés (app, site, Release, export, sauvegardes) et README réécrit en page
      de présentation. Identifiants techniques gardés (`com.sysiphe.app`, alias de signature, paquet Dart)
      pour que les mises à jour s'installent par-dessus l'app existante
- [x] **Annulé** (v2.9.0, 17/11) : le nom redevient **Sysiphe** partout (app, site, Release `sysiphe.apk`, export,
      sauvegardes, README). Les mises à jour depuis la v2.8.0 « Thésée » s'installent normalement (mêmes identifiants
      techniques) ; les anciens exports `thesee-export-*` sont toujours nettoyés
- [x] Découper `saisie_screen.dart` (v2.9.1) : 1 884 → 1 115 lignes ; composants dans `lib/widgets/saisie/`,
      repos dans `RestTimer`, calculs d'effort dans `EffortSettings`, dialogues partagés ; aucun changement visible

## Phase 7 — Retours de saisie (novembre 2026)

- [x] % de progression vs moyenne des 5 dernières séances, **à série égale** (planche : en points d'effort)
- [x] Plus de changement d'exercice automatique ; séries ajoutées à la suite depuis les cartes
- [x] Séries enregistrées corrigeables d'un appui ; autosave 3 s ; exercices faits en bleu dans le slider
- [x] Cartes : une par exercice, exercice ouvert non répété, terminés en bas ; options planche masquées hors planche
- [x] Exercices **assistables** (réglage dans « Profils et exercices ») : élastique, tension, écartement des mains
      (catégories : serré / standard / large / très large). Effort = `reps × (poids effectif / 100)² × coef_écartement^1,2`
      avec `poids effectif = poids + lest − force élastique × ratio de tension` (même logique que la planche).
      Colonnes ajoutées : `perfs.ecartement`, `user_settings.assistable_exercises`, `user_settings.ecartements_config`.
- [x] Rôles admin / user, validation avant modification de l'algo, export de la base, pop-up de mise à jour + maj auto (PR #21)
- [ ] Passkey ; module course GPS (à décider)

### Idée gardée pour plus tard — formule « reps équivalentes » (non retenue)

Alternative étudiée pour les exercices assistables, plus simple à comparer aux reps brutes :
`effort = reps × (poids effectif / poids du corps)^k × coef_écartement`, avec k = 1 par défaut (réglable).
Sans élastique ni lest, l'effort vaut exactement les reps → l'historique reste directement comparable.
Choix actuel : la formule type planche (ci-dessus), jugée plus cohérente avec le reste de l'app.

## Demande du 17 novembre — chrono des exercices en secondes (v2.9.0)

- [x] Mode **objectif** : décompte jusqu'à zéro (30 s, 45 s, 1:00, 1:30, 2:00 ou temps personnalisé), barre de
      progression, tics sur les 3 dernières secondes, triple vibration à zéro, puis dépassement affiché en « +0:05 » ;
      Arrêter renvoie toujours le temps total
- [x] Objectif mémorisé **par exercice** (la planche et le gainage gardent chacun le leur) ; « Libre » = chrono classique
- [x] « Départ dans » : temps personnalisé en plus de Sans / 5 / 10 / 15 s (saisie « 20 », « 1:30 » ou « 2m »)
- [x] Écran éteint ou autre app avant l'objectif : notification programmée à l'heure de fin
- [x] **Bips** sur les 3 dernières secondes de la préparation et de l'objectif, au départ et à l'objectif atteint
      (la musique est juste baissée le temps du bip) ; bouton 🔊 pour les couper, choix mémorisé
- [x] **Écran toujours allumé** pendant la préparation et la série
- [x] **Plein écran** (bouton ⛶ pendant la série) : temps en très gros chiffres, barre d'objectif, gros bouton
      Arrêter ; le dernier choix est repris à la série suivante, « réduire » ou retour pour revenir en petit
- [ ] **Toi** : tester la v2.9.0 sur le téléphone (son, écran allumé, plein écran)

## Prochains axes (décidés le 17/11)

- [x] Découpage de la saisie (v2.9.1)
- [x] Rappels (v2.10.0) : « Séance conseillée aujourd'hui » le jour donné par le repos habituel, et « Ça fait N jours
      sans séance » après `inactivity_days` jours (défaut 2, partagé avec le web), à l'heure choisie (défaut 18 h).
      Reprogrammés à chaque chargement de l'historique (ouverture, série enregistrée / supprimée), gardés après un
      redémarrage. Réglages → Rappels. Le minuteur, le repos et le chrono n'effacent plus que leurs propres notifications
- [ ] **Toi** : Réglages → Rappels, régler l'heure juste après l'heure actuelle pour voir arriver un rappel
- [x] Associer un compte Google : profils retrouvés sur un autre téléphone ou sur le web sans PIN (v2.11.0)

## Session de rattrapage — site web (mis de côté le 18/11, priorité à l'app)

- [ ] « Se connecter avec Google » sur le site demande encore le PIN. Piste : à l'ouverture, le site présélectionne le
      profil le plus récent et affiche directement l'écran PIN, qui masque le bouton Google (`auth.py`, repli « b »
      avant l'étape « a bis »)
- [ ] Rouvrir la **saisie** sur le site (en consultation seule depuis le 17/11, ce qui le rend peu utile pour toi)

## Décidé pour plus tard — module Course GPS (18/11)

- [ ] Pas dans tous les APK : la CI publie `sysiphe.apk` (sans course) et `sysiphe-course.apk` (avec). Réglages →
      Mises à jour → « Activer le module Course » bascule vers la version course et la garde à chaque mise à jour
      (même app, données conservées ; retour possible). Seule la version course demande la localisation.
      (Une app installée hors Play Store ne peut pas télécharger un module de code après coup.)

## Catégories des exercices (18/11, v2.13.0)

- [x] Réglages → **Catégories des exercices** : ranger chaque exercice avec ses propres catégories (Planche,
      Handstand…), appliqué à tout son historique ; exercices « mélangés » signalés (ex. Abdos : Gainage / Musculation)
- [x] Création d'un exercice : catégorie **proposée pendant la frappe**, apprise du rangement de l'utilisateur (pas de
      dictionnaire imposé) : le mot le plus caractéristique l'emporte (« Pompe de handstand » → Handstand), à égalité
      le premier du nom (« Planche to handstand » → Planche) ; rien de connu → catégorie par défaut ; toujours modifiable
- [ ] **Toi** : ranger tes exercices actuels (Réglages → Exercices) ; les propositions s'appuient dessus

## Réglages simplifiés (18/11, v2.14.0)

- [x] Écran principal court : en-tête du profil (poids, « Changer de profil ») + 5 entrées avec leur résumé —
      Entraînement, Exercices, Rappels, Compte et sécurité, Application (+ Admin pour un admin). Aucun réglage retiré
- [x] **Exercices** : une seule page (remplace « Profils et exercices », « Catégories » et « Assistables ») ; un appui
      sur un exercice → renommer, catégorie (proposition apprise), assistable
- [x] Correctif : les boîtes « Renommer » et « corriger une série » libéraient leur champ pendant leur fermeture
      (erreur possible) — révélé par les tests
- [ ] **Toi** : parcourir les Réglages ; chaque réglage d'avant doit se retrouver en 2 appuis au plus

## Chrono : enchaînement, annonces vocales, arrêt au toucher (19/11, v2.15.0)

- [x] **Enchaînement** : « Séries : 2 à 5 » (mémorisé par exercice). À chaque arrêt, la série est enregistrée tout de
      suite, le repos démarre, puis la série suivante se relance seule (avec la préparation). « Passer » saute le
      repos, ✕ arrête l'enchaînement. Dans la carte principale et les petites cartes
- [x] **Annonces vocales** (`flutter_tts`) : « Série 2 sur 3 », « Partez », « 10 secondes », « Objectif atteint »,
      chaque minute, « Repos », « Terminé, bravo ». Bouton son à 3 états : voix + bips (défaut) → bips → muet
- [x] **Plein écran** : toucher n'importe où arrête la série (ou passe le repos) ; le repos s'affiche en plein écran
- [x] Correctif (20/11) : deux planches enregistrées en S1 le même jour. Le numéro de série est maintenant relu sur le
      serveur juste avant chaque enregistrement (numéro déjà pris → suivant libre) ; les petites cartes gardent leur
      état (chrono en cours, saisie en attente) quand elles changent d'ordre
- [ ] **Toi** : essayer une planche en 3 séries, téléphone posé au sol
