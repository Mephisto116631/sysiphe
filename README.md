# Sysiphe 🏋️

Tracker de performance sportive personnel. Enregistrement des séances, calcul d'effort, statistiques, heatmap d'activité, records.

---

## Table des matières

- [Vue d'ensemble](#vue-densemble)
- [Architecture](#architecture)
- [Base de données](#base-de-données)
- [Logique métier](#logique-métier)
- [Application web — Streamlit](#application-web--streamlit)
- [Application mobile — Flutter](#application-mobile--flutter)
- [Hébergement](#hébergement)
- [CI/CD](#cicd)
- [Secrets & sécurité](#secrets--sécurité)
- [Développement local](#développement-local)
- [Sauvegardes](#sauvegardes)
- [Archives](#archives)

---

## Vue d'ensemble

Sysiphe est un tracker de performance individuel, utilisé par ~3 profils. Il couvre :

- **Saisie** de séries (reps, lest, temps) par cartes d'exercice, avec la séance précédente en exemple,
  % de progression, repos automatique entre les séries, chronomètre et **minuteur HIIT**
- **Effort pondéré** pour la planche (variante, forme, élastique, tension) et les exercices **assistables**
  (élastique, tension, écartement des mains)
- **Statistiques** : courbes de progression, détection de plateau/régression, comparaison de périodes
- **Calendrier** : heatmap de l'activité et récupération
- **Records** personnels par exercice, filtrables
- **Modèle** (admin) : coefficients de l'effort, grille et recalcul en temps réel
- **Réglages** : mises à jour intégrées, poids de corps, exercices assistables, PIN, export CSV (admin)

Connexion : chaque appareil a une **session Supabase anonyme et persistante** ; le PIN d'un profil est vérifié
**par le serveur** une seule fois (RPC `claim_profile`), puis l'appareil est rattaché au profil. La sécurité par
ligne (RLS) ne laisse lire et écrire que les profils rattachés à l'appareil.

---

## Architecture

```
sysiphe/
│
├── app.py                  # Entrypoint Streamlit (routing, session)
├── auth.py                 # Sélection de profil, vérification PIN
├── data.py                 # Logique métier pure (testable, sans Streamlit)
├── supabase_io.py          # Toutes les requêtes Supabase (lecture/écriture)
├── ui_saisie.py            # Onglet Saisie
├── ui_stats.py             # Onglets Stats, Calendrier, Records, Paramètres
├── ui_helpers.py           # Composants UI réutilisables
├── requirements.txt        # Dépendances Python
│
├── flutter/                # App Android Flutter (version : flutter/pubspec.yaml)
│   ├── lib/
│   │   ├── main.dart, theme.dart, app_version.dart
│   │   ├── models/         # perf, session, stats, effort_model, interval_plan, profile
│   │   ├── screens/        # 6 onglets + profils, minuteur, assistables, gestion
│   │   ├── services/       # supabase_service, session_store, update_service, rôle, alertes…
│   │   └── widgets/        # carte d'exercice, chrono, bandeau de repos, PIN, mise à jour
│   ├── test/               # tests Flutter (flutter test)
│   ├── pubspec.yaml
│   └── android/            # dont MainActivity.kt (installation des mises à jour)
│
├── supabase/
│   ├── migrations/         # toutes les migrations appliquées en production (même version)
│   └── a_appliquer/        # changements prêts, à appliquer à la main (voir son README)
├── backup/                 # sauvegardes quotidiennes : Google Drive (CSV) ou NAS
│
└── archive/                # Anciennes briques, plus utilisées (voir § Archives)
```

**Flux de données :**

```
Flutter app  ──────────────────────▶  Supabase Cloud
Streamlit  ──[ supabase_io.py ]────▶  Supabase Cloud
            (Streamlit Cloud)
```

Les deux apps partagent la même base. L'app Flutter communique **directement** avec Supabase, sans passer par Streamlit.

---

## Base de données

Projet Supabase hébergé sur `supabase.io`.

### Table `profiles`

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | UUID (PK) | Identifiant du profil |
| `name` | text | Nom affiché |
| `pin_hash` | text \| null | Empreinte du PIN (`pin_digest`, null = pas de PIN). Illisible par les apps : tout passe par les RPC |
| `role` | text | `user` (défaut) ou `admin` (onglet Modèle, export de la base) |
| `last_login` | timestamptz | Dernière connexion |
| `created_at` | timestamptz | Date de création |

### Table `perfs`

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

### Table `user_settings`

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

### Accès et sécurité (tables techniques)

| Table | Rôle |
|-------|------|
| `profile_members` | Appareils (session anonyme `auth.uid()`) rattachés à chaque profil après un PIN correct |
| `pin_attempts` | Anti force brute par appareil : 5 erreurs → 15 min |
| `profile_pin_lock` | Anti force brute par profil, tous appareils : 10 erreurs → 1 h, puis 2 h, 4 h… |

RLS active sur toutes les tables. Les apps passent par les RPC `list_profiles`, `claim_profile`, `create_profile`,
`set_profile_pin`, `profile_role`, `admin_export_perfs`. Détail et historique : `supabase/migrations/`.

Les configs JSONB sont **fusionnées** avec les valeurs par défaut de `data.py` : seules les clés modifiées y sont stockées. Les écritures se font par upsert partiel, pour qu'aucune app n'écrase les réglages de l'autre.

---

## Logique métier

Tout le code pur (sans Streamlit ni Supabase) est dans `data.py`. Il est couvert par `test_data.py`.

### Score d'effort planche (isométrique)

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

### Détection plateau/progression

Régression linéaire sur une fenêtre glissante de 21 jours. Statuts : `progress`, `plateau`, `regression`, `insufficient_data`.

### Lissage

Rééchantillonnage sur index date continu avec trois modes : `interpolate` (courbes lisses), `ffill` (dernier connu), `zero` (volumes journaliers).

---

## Application web — Streamlit

### Lancement local

```bash
pip install -r requirements.txt
# Créer .streamlit/secrets.toml :
# SUPABASE_URL = "https://xxx.supabase.co"
# SUPABASE_KEY = "eyJ..."
streamlit run app.py
```

### Structure des onglets

| Onglet | Fichier | Description |
|--------|---------|-------------|
| Saisie | `ui_saisie.py` | Formulaire série, autocomplete exercice, options planche |
| Stats | `ui_stats.py` | Courbes progression, plateau/régression |
| Calendrier | `ui_stats.py` | Heatmap d'activité (streamlit-calendar) |
| Records | `ui_stats.py` | Meilleures perfs par exercice |
| Paramètres | `ui_stats.py` | Poids de corps, PIN, export CSV/ICS |

### Authentification

- Page d'accueil : grille de profils (initiales)
- Session Supabase anonyme gardée dans un cookie d'un an ; PIN vérifié par le serveur (`claim_profile`)
- Le site ne gère pas encore les exercices assistables, les rôles ni le minuteur (voir `PLAN.md`, phase 6)

---

## Application mobile — Flutter

App native Android, connexion directe à Supabase. Mises à jour intégrées : Réglages → « Mises à jour »
télécharge l'APK de la dernière Release GitHub et l'installe.

### Dépendances principales

| Package | Usage |
|---------|-------|
| `supabase_flutter ^2.5.0` | Client Supabase officiel |
| `crypto ^3.0.3` | Repli de transition (PIN vérifié localement si la session anonyme est indisponible) |
| `fl_chart ^0.68.0` | Courbes de progression |
| `table_calendar ^3.1.0` | Heatmap calendrier |
| `shared_preferences` | Profil mémorisé, filtres et préférences d'affichage |
| `flutter_local_notifications`, `timezone`, `wakelock_plus` | Minuteur HIIT en arrière-plan, écran allumé |
| `share_plus` | Export CSV |
| `intl ^0.19.0` | Formats date fr_FR |

### Screens

```
ProfileScreen   → sélection / création de profil + PIN (une fois par appareil)
  └─ HomeScreen (BottomNavigationBar, IndexedStack)
       ├─ SaisieScreen    (cartes d'exercice, repos, chrono → MinuteurScreen)
       ├─ StatsScreen     (fl_chart, périodes, tendance)
       ├─ CalendarScreen  (table_calendar, heatmap, récupération)
       ├─ RecordsScreen   (records filtrables)
       ├─ ModelScreen     (admin : coefficients, grille, recalcul)
       └─ SettingsScreen  (mises à jour, poids, AssistableScreen, ManageScreen, PIN, export admin)
```

### Credentials à la compilation

Les clés Supabase ne sont **jamais** dans le code source. Elles sont injectées à la compilation via `--dart-define` :

```dart
const _supabaseUrl    = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
```

En local :

```bash
cd flutter
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

### Build Android manuel

```bash
cd flutter
flutter build apk --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
# APK : flutter/build/app/outputs/flutter-apk/app-release.apk
```

### Notes Gradle

Le projet utilise la **nouvelle API déclarative Flutter Gradle** (Flutter 3.16+) :

- `settings.gradle` : bloc `pluginManagement` + `plugins {}` (pas d'`apply from:` impératif)
- `app/build.gradle` : `plugins { id "dev.flutter.flutter-gradle-plugin" }` (pas d'`apply from: flutter.gradle`)
- Gradle wrapper : 8.4

**`dependency_overrides`** : `app_links` est épinglé à `< 6.4.0` car les versions 6.4.x référencent `flutter.compileSdkVersion` dans le build.gradle d'un projet *library*, ce qui n'est pas disponible pour les plugins Android.

---

## Hébergement

L'app web tourne uniquement sur **Streamlit Cloud** : `https://sysiphe-voseesdgwwcstfepbdepkh.streamlit.app`. Elle est redéployée automatiquement à chaque push sur `main`.

`APP_URL` (optionnel, dans `secrets.toml`) remplace l'URL publique utilisée pour les redirections d'authentification, par exemple en local. Par défaut, c'est l'URL Streamlit Cloud (`app.py`).

L'app mobile est l'**APK Flutter**, publié dans les Releases GitHub.

---

## CI/CD

Deux workflows actifs :

- **`ci.yml`** (sur chaque PR et chaque push sur `main`) : `flutter analyze` + `flutter test`, build APK debug
  (valide le code natif), `pytest test_data.py`, et sur les PR une vérification que **toute modification de
  l'app augmente `version:`** dans `flutter/pubspec.yaml`. Ne publie rien.
- **`build-flutter.yml`** : construit, signe et publie l'APK Flutter.

#### `build-flutter.yml`

Déclenché sur push vers `main` touchant `flutter/**` (ou le workflow lui-même), ou manuellement (*Run workflow*).

| Étape | Détail |
|-------|--------|
| Java 17 (Temurin) | — |
| Flutter 3.24.3 stable | `subosito/flutter-action@v2` |
| `local.properties` | `sdk.dir` + `flutter.sdk` depuis les vars d'env CI |
| `flutter pub get` | — |
| `flutter build apk --release` | Inject `SUPABASE_URL` + `SUPABASE_ANON_KEY` via `--dart-define` |
| Signature `apksigner` | Keystore base64 depuis `SIGNING_KEY`, alias `sysiphe` |
| GitHub Release | Tag `v{version}`, fichier `sysiphe.apk`, build = numéro du run (`2.7.0+N`) |

Une nouvelle version = un nouveau tag et une nouvelle Release. Rebuilder la même version remplace l'APK de sa
Release : d'où la vérification de version dans `ci.yml`.

---

## Secrets & sécurité

### Secrets GitHub Actions requis

| Secret | Usage |
|--------|-------|
| `SUPABASE_URL` | URL du projet Supabase |
| `SUPABASE_ANON_KEY` | Clé `anon` publique Supabase |
| `SIGNING_KEY` | Keystore JKS encodé en base64 |
| `KEYSTORE_PASSWORD` | Mot de passe du keystore (alias `sysiphe`) |

Les secrets `KEYSTORE_BASE64` et `KEY_ALIAS` ne servaient qu'au workflow Capacitor archivé : ils peuvent être supprimés des réglages GitHub.

### Règles

- Les fichiers `secrets.toml`, `.env`, et tout CSV de données sont dans `.gitignore`
- La clé `service_role` Supabase n'est **jamais** dans le code ni dans les secrets CI ; elle n'existe que dans
  les propriétés du script Google de sauvegarde (`backup/`)
- Les credentials Supabase sont injectés **uniquement à la compilation** via `--dart-define` pour Flutter, et via les *Secrets* de Streamlit Cloud (ou `.streamlit/secrets.toml` en local) pour Streamlit

---

## Développement local

### Prérequis

- Python 3.11+, `pip`
- Flutter 3.24+ (pour l'app mobile)
- Android SDK + Java 17 (pour le build APK)
- Un projet Supabase avec les tables `profiles`, `perfs`, `user_settings` (voir `SETUP.md`)

### Setup Streamlit

```bash
git clone https://github.com/Mephisto116631/sysiphe.git
cd sysiphe
pip install -r requirements.txt

mkdir -p .streamlit
cat > .streamlit/secrets.toml << 'EOF'
SUPABASE_URL = "https://xxx.supabase.co"
SUPABASE_KEY = "eyJ..."
EOF

streamlit run app.py
```

### Setup Flutter

```bash
cd flutter
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

### Tests

```bash
python -m pytest test_data.py -v     # logique web : calculer_effort, parse_reps, lissage, plateau
cd flutter && flutter test           # logique et écrans Flutter (effort, séances, stats, minuteur…)
```


---

## Sauvegardes

L'offre Supabase gratuite ne fournit aucune sauvegarde téléchargeable. `backup/README.md` décrit deux solutions
cumulables : un script Google Apps Script qui dépose chaque nuit un CSV par table dans Google Drive (recommandé),
et un script NAS (`pg_dump`, copie complète restaurable). L'export admin de l'app (Réglages) dépanne à la main.

---

## Archives

Le dossier `archive/` conserve, pour mémoire, les briques abandonnées depuis l'abandon du NAS. Elles ne sont **plus construites ni déployées** : les workflows archivés sont hors de `.github/workflows/`, donc GitHub ne les exécute plus.

| Dossier | Ancien rôle |
|---------|-------------|
| `archive/nas/` | Auto-hébergement sur NAS : `Dockerfile`, docker-compose OMV, Tailscale Funnel, `update.sh` |
| `archive/android-webview/` | APK WebView v1.4 (ouvrait l'URL du NAS, sinon une page hors ligne) |
| `archive/mobile-capacitor/` | Premier wrapper APK (Capacitor), `targets.json`, icône source |
| `archive/workflows/` | `docker-image.yml` (image `ghcr.io`), `build-apk.yml`, `android-apk.yml` |

Pour réactiver une brique : remettre son dossier à la racine et son workflow dans `.github/workflows/`. Les chemins internes n'ont pas été modifiés.

Les APK WebView déjà installés lisent `mobile/targets.json` sur `main`. Ce fichier n'y est plus, donc ils affichent leur page hors ligne : il faut les désinstaller au profit de l'APK Flutter.

---

*Projet personnel — usage privé.*
