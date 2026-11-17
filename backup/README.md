# Sauvegardes de la base Sysiphe

L'offre Supabase gratuite ne fournit aucune sauvegarde téléchargeable. Deux solutions, cumulables :

- **Google Drive** (recommandé) : un script Google chaque nuit, des CSV dans ton Drive, rien à allumer ;
- **NAS** : une copie complète restaurable (tables + fonctions) + CSV, sur le NAS.

# Option A — Google Drive (CSV)

Chaque nuit vers 3 h, dans le dossier Drive **Sysiphe sauvegardes** : `perfs-AAAA-MM-JJ.csv`,
`profiles-…`, `user_settings-…`, `profile_members-…`. Les fichiers de plus de 60 jours vont à la corbeille.
Ils s'ouvrent dans Google Sheets / Excel et se réimportent dans Supabase (Table Editor → Import data from CSV).

## Installation (sur ordi, ~5 min)

1. **Clé** : Supabase → projet Sysiphe → **Project Settings → API Keys** → copie la clé **`service_role`**
   (onglet « Legacy » si besoin). Elle donne un accès complet à la base : ne la mets nulle part ailleurs.
2. https://script.google.com → **Nouveau projet** → renomme-le « Sysiphe sauvegarde ».
3. Remplace le contenu de `Code.gs` par celui de [`google-drive/Code.gs`](google-drive/Code.gs) → **Enregistrer**.
4. ⚙️ **Paramètres du projet** → **Propriétés du script** → Ajouter : nom `SUPABASE_SERVICE_KEY`, valeur = la clé.
5. Retour à l'éditeur, choisis la fonction **`sauvegarder`** → **Exécuter**. Google demande l'autorisation
   (Drive + accès externe) : accepte (« Paramètres avancés → Accéder à Sysiphe sauvegarde » si l'alerte s'affiche,
   c'est ton propre script). Le journal doit finir par `OK AAAA-MM-JJ : perfs N, …` et le dossier apparaît dans Drive.
6. Choisis la fonction **`installerDeclencheur`** → **Exécuter** : c'est programmé tous les jours.

Si une nuit échoue (clé changée, Supabase en pause…), Google t'envoie un e-mail d'erreur.

# Option B — NAS (copie complète)

## B1. Chaîne de connexion (une fois)

Supabase → projet **Sysiphe** → bouton **Connect** (en haut) → **Session pooler**. Copie l'URI : elle ressemble à
`postgresql://postgres.qzvfkscqcllfnoqywkwq:[YOUR-PASSWORD]@aws-…-eu-west-1.pooler.supabase.com:5432/postgres`.

Remplace `[YOUR-PASSWORD]` par le mot de passe de la base. Si tu ne l'as plus : **Project Settings → Database →
Reset database password**. Ça ne touche pas l'app ni le site (ils utilisent la clé API, pas ce mot de passe).

> Prends bien **Session pooler** (port 5432) : la connexion « Direct » n'est joignable qu'en IPv6.

## B2. Sur le NAS (SSH)

```bash
mkdir -p /compose_data/sysiphe-backup && cd /compose_data/sysiphe-backup
BASE=https://raw.githubusercontent.com/Mephisto116631/sysiphe/main/backup
curl -fsSLO "$BASE/sauvegarde.sh" && curl -fsSLO "$BASE/sauvegarde.env.example"
cp sauvegarde.env.example sauvegarde.env && chmod 600 sauvegarde.env
nano sauvegarde.env        # colle ton URI après SUPABASE_DB_URL=
sh sauvegarde.sh           # 1er essai : doit finir par « OK : sysiphe-….dump (…), N perfs »
```

Si le mot de passe contient `@ : / ? # %`, remplace ces caractères dans l'URI par `%40 %3A %2F %3F %23 %25`.

## B3. Tous les jours, automatiquement

OMV → **Système → Tâches planifiées** → Ajouter : tous les jours à 3 h 17, utilisateur `root`, commande :

```
sh /compose_data/sysiphe-backup/sauvegarde.sh >> /var/log/sysiphe-backup.log 2>&1
```

Contrôle : `tail /var/log/sysiphe-backup.log` (une ligne `OK` par jour). En cas d'échec, le script s'arrête avec
une erreur et ne crée aucun fichier daté.

## B4. Restaurer

Dans un projet Supabase vide (ou après avoir vidé les tables) :

```bash
cd /compose_data/sysiphe-backup
docker run --rm -v "$PWD/dumps:/d" postgres:17-alpine \
  pg_restore --no-owner --no-privileges -d "URI_DU_PROJET" /d/sysiphe-AAAA-MM-JJ.dump
```

Le message `schema "public" already exists` est normal et sans conséquence.
