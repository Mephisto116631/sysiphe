<p align="center">
  <img src="assets/logo/icon_512.png" alt="Sysiphe" width="120">
</p>

<h1 align="center">Sysiphe</h1>

<p align="center">
  <strong>Suivi d'entraînement au poids du corps : planche, force, calisthénie.</strong><br>
  App Android pour s'entraîner, site web pour consulter. Une seule base, partagée.
</p>

<p align="center">
  <a href="https://github.com/Mephisto116631/sysiphe/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Mephisto116631/sysiphe/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/Mephisto116631/sysiphe/releases/latest"><img alt="Dernière version" src="https://img.shields.io/github/v/release/Mephisto116631/sysiphe?label=APK&color=0D47A1"></a>
  <img alt="Flutter 3.24" src="https://img.shields.io/badge/Flutter-3.24-02569B">
  <img alt="Supabase" src="https://img.shields.io/badge/Supabase-RLS-3ECF8E">
</p>

---

Sysiphe enregistre chaque série, calcule un **effort pondéré** comparable d'une séance à
l'autre, même quand la variante, l'élastique ou l'écartement des mains changent, et montre la progression :
tendances, plateaux, records, récupération. Projet personnel, utilisé par quelques profils.

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Installer l'app](#installer-lapp)
- [Architecture](#architecture)
- [Sécurité des données](#sécurité-des-données)
- [Développement](#développement)
- [Publier une version](#publier-une-version)
- [Sauvegardes](#sauvegardes)
- [Documentation](#documentation)
- [Référence technique](#référence-technique)

## Fonctionnalités

### App Android (saisie et consultation)

| Onglet | Ce qu'on y fait |
|--------|-----------------|
| **Saisie** | Une carte par exercice, la séance précédente en exemple grisé, « 12/10/8 » pour plusieurs séries, enregistrement automatique, % de progression à série égale, repos automatique entre les séries, chronomètre et **minuteur HIIT** (préparation, exercice, repos, cycles, notifications en arrière-plan) |
| **Stats** | Courbes d'effort ou de volume par exercice, périodes, tendance et détection de plateau |
| **Calendrier** | Heatmap de l'activité, détail d'un jour, récupération entre les séances |
| **Records** | Meilleures séances et meilleures séries, filtrables (planche, musculation, recherche) |
| **Modèle** *(admin)* | Coefficients de l'effort (variantes, formes, élastiques, tensions), grille en temps réel, recalcul de tout l'historique |
| **Réglages** | Mises à jour intégrées, poids de corps, exercices assistables, profils et exercices, PIN, export CSV *(admin)* |

### Site web (consultation seule)

Stats, Calendrier, Records, Repos et Infos (export CSV, réglages en lecture), sur
[Streamlit Cloud](https://sysiphe-voseesdgwwcstfepbdepkh.streamlit.app). La saisie, les réglages et la gestion des
profils se font dans l'app : le site refuse toute écriture (`LECTURE_SEULE` dans `supabase_io.py`).

### Effort pondéré

```
poids effectif = poids du corps + lest − force de l'élastique × ratio de tension
planche        : effort = temps × (poids effectif / 100)² × (score variante × score forme)^1,2 / 100
assistables    : effort = reps  × (poids effectif / 100)² × coef. d'écartement^1,2
```

Les coefficients sont réglables par profil (onglet Modèle) et partagés entre l'app et le site.

## Installer l'app

1. Ouvre la [dernière Release](https://github.com/Mephisto116631/sysiphe/releases/latest) sur le téléphone et
   télécharge `sysiphe.apk` (la v2.8.0 s'appelait `thesee.apk`).
2. Autorise l'installation depuis le navigateur si Android le demande, puis installe.
3. Choisis ton profil et entre ton PIN **une seule fois** : l'appareil reste rattaché au profil.

Ensuite, les mises à jour se font depuis l'app : **Réglages → Mises à jour**.

## Architecture

```
┌──────────────────────┐        ┌─────────────────────────────┐
│ App Android (Flutter)│──────▶ │ Supabase                    │
│ saisie + consultation│        │ Postgres · RLS · RPC · Auth │
└──────────────────────┘        └─────────────────────────────┘
┌──────────────────────┐                     ▲
│ Site web (Streamlit) │─────────────────────┘
│ consultation seule   │
└──────────────────────┘
```

```
.
├── flutter/                 App Android (lib/models, screens, services, widgets ; test/)
├── app.py, auth.py          Site web : navigation, connexion par profil
├── supabase_io.py           Site web : accès aux données (écritures bloquées)
├── ui_stats.py, ui_helpers.py
├── data.py, test_data.py    Logique métier du site et ses tests
├── supabase/migrations/     Toutes les migrations appliquées en production
├── supabase/a_appliquer/    Changements de base prêts, à appliquer à la main
├── backup/                  Sauvegardes quotidiennes (Google Drive ou NAS)
├── assets/logo/             Logo et icônes
└── archive/                 Anciennes briques (NAS, APK WebView, Capacitor), plus utilisées
```

## Sécurité des données

- Chaque appareil ouvre une **session Supabase anonyme** persistante ; le PIN d'un profil est vérifié **par le
  serveur** (`claim_profile`), une seule fois, puis l'appareil est rattaché au profil.
- **RLS** sur toutes les tables : un appareil ne lit et n'écrit que les profils auxquels il est rattaché. Le hash
  du PIN et le rôle ne sont jamais lisibles par les apps.
- Anti force brute : 5 erreurs par appareil → 15 min ; 10 erreurs sur un profil → 1 h, puis 2 h, 4 h…
- Aucune clé secrète dans le code : l'URL et la clé publique Supabase sont injectées à la compilation
  (`--dart-define`) et dans les secrets Streamlit.

## Développement

```bash
# App Android
cd flutter
flutter pub get
flutter test
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=…

# Site web
pip install -r requirements.txt
python -m pytest test_data.py
# .streamlit/secrets.toml : SUPABASE_URL = "…", SUPABASE_KEY = "…"
streamlit run app.py
```

Prérequis : Flutter 3.24 (Dart 3.5), Java 17 et Android SDK pour construire l'APK, Python 3.11+.

## Publier une version

1. Ouvre une PR. La CI (`ci.yml`) lance `flutter analyze`, `flutter test`, un build APK de vérification,
   `pytest`, et refuse une PR qui modifie l'app **sans augmenter `version:`** dans `flutter/pubspec.yaml`.
2. Après la fusion, `build-flutter.yml` construit et signe l'APK, puis publie la Release `v<version>` avec
   `sysiphe.apk` (numéro de build = numéro du run, ex. `2.8.0+41`).
3. Les téléphones la voient dans **Réglages → Mises à jour**.

| Secret GitHub | Usage |
|---------------|-------|
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Injectés dans l'APK |
| `SIGNING_KEY`, `KEYSTORE_PASSWORD` | Keystore (base64) et mot de passe, alias `sysiphe` |

Les identifiants techniques gardent l'ancien nom pour que les mises à jour continuent de s'installer par-dessus
l'app existante : paquet Android `com.sysiphe.app`, alias de signature, paquet Dart `sysiphe`.

## Sauvegardes

L'offre Supabase gratuite ne fournit aucune sauvegarde téléchargeable. [`backup/README.md`](backup/README.md) :
un script Google Apps Script dépose chaque nuit un CSV par table dans Google Drive (recommandé), un script NAS fait
une copie complète restaurable. L'export admin de l'app (Réglages) dépanne à la main.

## Documentation

| Fichier | Contenu |
|---------|---------|
| [`PLAN.md`](PLAN.md) | Feuille de route cochée : ce qui est fait, ce qui reste |
| [`SETUP.md`](SETUP.md) | Schéma de la base, sécurité, recréer la base de zéro |
| [`supabase/a_appliquer/`](supabase/a_appliquer/) | Changements de base en attente, avec leur marche à suivre |
| [`backup/README.md`](backup/README.md) | Installer les sauvegardes |
| [`archive/`](archive/) | NAS, APK WebView, Capacitor : conservés pour mémoire, plus construits ni déployés |

## Référence technique

### Base de données

Projet Supabase (région eu-west-1, nommé « Sysiphe » dans le tableau de bord). Schéma complet : [`SETUP.md`](SETUP.md) et [`supabase/migrations/`](supabase/migrations/).

#### Table `profiles`

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | UUID (PK) | Identifiant du profil |
| `name` | text | Nom affiché |
| `pin_hash` | text \| null | Empreinte du PIN (`pin_digest`, null = pas de PIN). Illisible par les apps : tout passe par les RPC |
| `role` | text | `user` (défaut) ou `admin` (onglet Modèle, export de la base) |
| `last_login` | timestamptz | Dernière connexion |
| `created_at` | timestamptz | Date de création |

#### Table `perfs`

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | bigint identity (PK) | Croissant à l'insertion : sert d'ordre chronologique |
| `user_id` | UUID | Id du profil (pas de clé étrangère déclarée) |
| `date` | date | Date de la série |
| `exercice` | text | Nom de l'exercice |
| `variante` | text | Variante (planche : Full, Straddle…) |
| `forme` | text | Forme (planche : Normal, High, Bas, Dead) |
| `serie` | int | Numéro de série |
| `performance` | numeric | **Valeur de la série** : secondes, reps ou kg selon `unite` |
| `charge` | numeric | Lest externe en kg (tractions/dips lestés), `0` sinon |
| `unite` | text | `Sec` / `Reps` / `Kg` |
| `categorie` | text | `Force Iso` (planche, holds), `Gainage` ou `Musculation` |
| `elastique` | text | Élastique utilisé (planche, exercices assistables) |
| `tension` | text | Tension des mains (planche, exercices assistables) |
| `ecartement` | text | Écartement des mains (exercices assistables) |
| `effort_pondere` | numeric | Score d'effort (planche et exercices assistables, `0` sinon) |

> ⚠️ Il n'y a **pas** de colonne `created_at` dans `perfs` : trier dessus renvoie une erreur 400.
> Pour l'ordre d'insertion, trier sur `id`. Une requête renvoie au plus 1 000 lignes : paginer avec `range()`.
>
> ⚠️ Ne pas confondre `performance` (la valeur mesurée) et `charge` (le lest ajouté).
> Le volume d'une série lestée vaut `performance × charge`.
> La planche est identifiée par son **nom** (`exercice` = « Planche », insensible à la casse).

#### Table `user_settings`

Une ligne par utilisateur, partagée par l'app web et l'app Flutter (voir `SETUP.md` pour sa création).

| Colonne | Type | Description |
|---------|------|-------------|
| `user_id` | UUID (PK) | — |
| `weight` | float | Poids de corps (kg) |
| `variantes_config` | jsonb | Scores de variantes planche personnalisés |
| `formes_config` | jsonb | Facteurs de forme personnalisés |
| `elastiques_config` | jsonb | Force des élastiques personnalisée |
| `tensions_config` | jsonb | Ratios de tension personnalisés |
| `nb_days_avg` | int | Fenêtre de moyenne glissante (stats web) |
| `include_planche` | bool | Inclure la planche dans les stats globales |
| `enable_charges` | bool | Afficher le champ « Lest (kg) » |
| `assistable_exercises` | jsonb | Exercices assistables (élastique / tension / écartement) |
| `ecartements_config` | jsonb | Coefficients d'écartement des mains |
| `updated_at` | timestamptz | — |

> ⚠️ En production, `user_settings.user_id` référence encore `auth.users` au lieu de `profiles` : correctif prêt
> dans `supabase/a_appliquer/`.

#### Accès et sécurité (tables techniques)

| Table | Rôle |
|-------|------|
| `profile_members` | Appareils (session anonyme `auth.uid()`) rattachés à chaque profil après un PIN correct |
| `pin_attempts` | Anti force brute par appareil : 5 erreurs → 15 min |
| `profile_pin_lock` | Anti force brute par profil, tous appareils : 10 erreurs → 1 h, puis 2 h, 4 h… |

RLS active sur toutes les tables. Les apps passent par les RPC `list_profiles`, `claim_profile`, `create_profile`,
`set_profile_pin`, `profile_role`, `admin_export_perfs`. Détail et historique : `supabase/migrations/`.

Les configs JSONB sont **fusionnées** avec les valeurs par défaut de `data.py` : seules les clés modifiées y sont stockées. Les écritures se font par upsert partiel, pour qu'aucune app n'écrase les réglages de l'autre.

---

### Logique métier

Le calcul est identique dans `data.py` (site) et `flutter/lib/models/` (app) ; les deux suites de tests le vérifient.

#### Score d'effort planche (isométrique)

Formule adaptée pour normaliser la difficulté d'un hold de planche selon la variante, la forme des hanches, l'élastique et la tension des mains :

```
poids_effectif = poids_corps − (force_élastique × ratio_tension)
effort = round( (temps × (poids_effectif/100)² × (score_variante × score_forme)^1.2) / 100 )
```

**Tables de paramètres :**

| Variante | Score |
|----------|-------|
| Full | 10 |
| Maltese | 11 |
| Straddle / Half_Lay | 9 |
| Diamond | 5 |
| Adv_Tuck | 3 |
| Tuck | 2 |

| Forme | Facteur hanches (°) |
|-------|---------------------|
| Normal | 47.6 |
| High | 34.0 |
| Bas | 66.64 |
| Dead | 93.296 |

| Tension | Ratio |
|---------|-------|
| Normal / N/A | 0.70 |
| Écarté | 0.85 |
| Serré | 0.60 |

#### Détection plateau/progression

Régression linéaire sur une fenêtre glissante de 21 jours. Statuts : `progress`, `plateau`, `regression`, `insufficient_data`.

#### Lissage

Rééchantillonnage sur index date continu avec trois modes : `interpolate` (courbes lisses), `ffill` (dernier connu), `zero` (volumes journaliers).

---

*Projet personnel — usage privé.*
