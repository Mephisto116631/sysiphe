# Sysiphe — Plan d'actions

> Cocher une case : remplacer `[ ]` par `[x]` (sur GitHub : bouton ✏️ du fichier).
> Ce fichier est la référence du suivi : chaque session Claude le lit et le met à jour.
>
> Dernière mise à jour : 9 novembre 2026

**Cap** : l'app mobile est l'APK **Flutter**. L'app web **Streamlit** reste sur Streamlit Cloud
(calibration, analyses avancées). Les deux partagent la même base **Supabase**. Le NAS est abandonné.

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
- [ ] **Toi** : installer le nouvel APK et vérifier Saisie, Stats, Calendrier et Records sur tes vraies données

## Phase 2 — Mise en production

- [x] Ouvrir la PR `ccr-6aa55910-p46qv7` → `main`
- [x] Relire et fusionner la PR [#4](https://github.com/Mephisto116631/sysiphe/pull/4) (CI verte, fusionnée le 9 novembre)
- [ ] Vérifier que Streamlit Cloud a redéployé l'app web sans erreur
- [ ] Désinstaller l'ancienne app WebView du téléphone
- [ ] Supprimer les secrets GitHub inutiles : `KEYSTORE_BASE64`, `KEY_ALIAS`
- [ ] Éteindre les conteneurs Sysiphe sur le NAS

## Phase 3 — Base de données et sécurité 🔐

- [ ] **Protéger les données (RLS)** — solution retenue le 9 novembre : session Supabase anonyme et
      persistante par appareil, PIN vérifié **par le serveur** une seule fois, puis la base ne sert que les
      profils rattachés à cette session. Aucune reconnexion, aucune latence ajoutée.
  - [x] Réglages Supabase : connexions anonymes, association manuelle d'identités, URL de retour de l'app (toi)
  - [x] Étape 1 (base, additive) : `profile_members`, anti force brute (5 essais → 15 min), RPC
        `list_profiles` / `claim_profile` / `create_profile` / `set_profile_pin` — testée en transaction
        annulée puis appliquée
  - [x] Étape 1 (app Flutter v2.2.0) : session anonyme, PIN vérifié par le serveur, hash du PIN plus jamais
        envoyé au téléphone
  - [x] Étape 1 (site web) : même principe, session gardée dans le cookie d'un an ; une session anonyme n'est jamais prise pour un compte Google
  - [ ] **Toi** : installer la v2.2.0 et confirmer ton PIN une dernière fois
  - [ ] Étape 2 (base) : activer la RLS sur `perfs`, `profiles`, `user_settings` + retirer l'accès direct aux
        hash de PIN — testée en transaction annulée d'abord
  - [ ] Étape 3 : bouton « Associer mon compte Google » (app + web)
- [ ] `user_settings.user_id` pointe sur `auth.users` : les profils « Dilbert 🐶 » et « Profil 3 » ne peuvent pas
      enregistrer de réglages (violation de clé étrangère). → Faire pointer la clé sur `profiles(id)`
- [ ] Harmoniser les catégories en base (`Force isométrique `, `Gainage`, `Force Iso`) : migration SQL
- [x] Hachage du PIN : `strip()` aussi à la vérification côté web, comme à l'enregistrement et dans Flutter
- [x] `SETUP.md` réécrit avec le schéma réel de production (3 tables, toutes les colonnes)

## Phase 4 — Parité fonctionnelle Flutter ↔ web

Pages et fonctions présentes sur le web, absentes ou simplifiées dans Flutter :

- [ ] **Saisie planche** multi-séries (S1 à S5) avec variante, forme, élastique et tension par série
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
- [ ] **Paramètres** : export CSV
- [ ] Rappel d'inactivité (`inactivity_days`) en notification locale

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
- [ ] Planche : bloc S1 à S5 avec forme par série et couleur d'intensité
- [~] « Tout sauvegarder » en un appui — remplacé par l'enregistrement carte par carte (v2.6.0)
- [x] Panneau du jour : séries ou effort du jour, séances du mois, reps de la semaine vs semaine précédente (port testé de `compute_period_comparison`)
- [ ] Rappel de prochaine séance dans l'agenda (`.ics`)

**Stats / Records**
- [ ] Graphe « séries par catégorie »
- [ ] Planche : une courbe par variante
- [ ] Comparer plusieurs exercices sur un même graphe
- [x] Records planche par combinaison variante / élastique / tension (couleur d'intensité) ; records muscu = meilleure séance (volume ou tonnage) + meilleure série

**Paramètres**
- [ ] « Inclure la planche » et taille de la moyenne glissante (`include_planche`, `nb_days_avg`)
- [x] Afficher / masquer le champ lest (`enable_charges`) — Réglages, v2.5.2
- [ ] Export CSV de l'historique

**Traces d'avant git (colonnes orphelines de `user_settings`)**
- [ ] Thèmes (`app_theme`, défaut « Abysse ») — **reporté** (décision du 9 novembre : pas prioritaire)
- [ ] Rappel après N jours sans séance (`inactivity_days`, défaut 2)
- [ ] Période de graphe mémorisée (`graph_period`)

**Connexion web à trancher** (lié à la RLS, phase 3)
- [ ] Comptes Google : **option d'association** à un profil existant (retrouver son profil sur un autre appareil ou sur le web, sans reconnexion à chaque ouverture) — à faire avec la RLS, en attente de validation

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

- [ ] Garder Streamlit à long terme, ou tout migrer dans Flutter une fois la phase 4 terminée ?
- [ ] Icône définitive de l'app Flutter
