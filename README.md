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
- [Archives](#archives)

---

## Vue d'ensemble

Sysiphe est un tracker de performance individuel, utilisé par ~3 profils. Il couvre :

- **Saisie** de séries (reps, charge, temps), incluant des exercices de force (planche isométrique avec calcul d'effort pondéré)
- **Statistiques** : courbes de progression sur 180 jours, détection de plateau/régression, lissage
- **Calendrier** : heatmap GitHub-style de l'activité
- **Records** personnels par exercice
- **Paramètres** : poids de corps, PIN, déconnexion

L'authentification est légère : sélection de profil + PIN optionnel (hash SHA-256, stocké dans Supabase).

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
├── flutter/                # App native Flutter v2.0 (Android)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── theme.dart
│   │   ├── models/         # perf.dart, profile.dart
│   │   ├── screens/        # 5 onglets
│   │   └── services/       # supabase_service.dart
│   ├── pubspec.yaml
│   └── android/
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
| `pin_hash` | text \| null | SHA-256 du PIN (null = pas de PIN) |
| `last_login` | timestamptz | Dernière connexion |
| `created_at` | timestamptz | Date de création |

### Table `perfs`

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | UUID (PK) | — |
| `user_id` | UUID (FK → profiles) | — |
| `date` | date | Date de la série |
| `exercice` | text | Nom de l'exercice |
| `variante` | text | Variante (planche : Full, Straddle…) |
| `forme` | text | Forme (planche : Normal, High, Bas, Dead) |
| `serie` | int | Numéro de série |
| `performance` | float | **Valeur de la série** : secondes, reps ou kg selon `unite` |
| `charge` | numeric | Lest externe en kg (tractions/dips lestés), `0` sinon |
| `unite` | text | `Sec` / `Reps` / `Kg` |
| `categorie` | text | `Force Iso` (planche, holds) ou `Musculation` |
| `elastique` | text | Élastique utilisé (planche) |
| `tension` | text | Tension des mains (planche) |
| `effort_pondere` | int | Score d'effort calculé (planche uniquement, `0` sinon) |
| `created_at` | timestamptz | — |

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
| `updated_at` | timestamptz | — |

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

- Page d'accueil : grille de profils (CircleAvatar avec initiales)
- PIN optionnel : hash SHA-256 comparé à `profiles.pin_hash`
- Session PKCE avec TTL via `streamlit-cookies-controller`

---

## Application mobile — Flutter

App native Android (v2.0.0+), connexion directe à Supabase.

### Dépendances principales

| Package | Usage |
|---------|-------|
| `supabase_flutter ^2.5.0` | Client Supabase officiel |
| `crypto ^3.0.3` | SHA-256 pour vérification PIN |
| `fl_chart ^0.68.0` | Courbes de progression |
| `table_calendar ^3.1.0` | Heatmap calendrier |
| `intl ^0.19.0` | Formats date fr_FR |

### Screens

```
ProfileScreen   → sélection profil + PIN
  └─ HomeScreen (BottomNavigationBar, IndexedStack)
       ├─ SaisieScreen    (formulaire + liste du jour)
       ├─ StatsScreen     (fl_chart, 180 jours)
       ├─ CalendarScreen  (table_calendar, heatmap)
       ├─ RecordsScreen   (records par exercice)
       └─ SettingsScreen  (poids, PIN, déconnexion)
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

Un seul workflow actif : `.github/workflows/build-flutter.yml`, qui produit l'APK Flutter.

Déclenché sur push vers `main` touchant `flutter/**` (ou le workflow lui-même), ou manuellement (*Run workflow*).

| Étape | Détail |
|-------|--------|
| Java 17 (Temurin) | — |
| Flutter 3.24.3 stable | `subosito/flutter-action@v2` |
| `local.properties` | `sdk.dir` + `flutter.sdk` depuis les vars d'env CI |
| `flutter pub get` | — |
| `flutter build apk --release` | Inject `SUPABASE_URL` + `SUPABASE_ANON_KEY` via `--dart-define` |
| Signature `apksigner` | Keystore base64 depuis `SIGNING_KEY`, alias `sysiphe` |
| GitHub Release | Tag `v{version}`, fichier `sysiphe.apk` |

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
- La clé `service_role` Supabase n'est **jamais** dans le code ni dans les secrets CI
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
python -m pytest test_data.py -v
```

Les tests couvrent `calculer_effort`, `parse_reps`, `lisser_donnees`, `detect_plateau`.


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
