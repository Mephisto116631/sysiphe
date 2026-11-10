# Sauvegarde de la base Sysiphe sur le NAS

L'offre Supabase gratuite ne fournit aucune sauvegarde téléchargeable. Ce script en fait une **chaque nuit sur le
NAS** :

- `dumps/sysiphe-AAAA-MM-JJ.dump` : copie complète (tables, données, fonctions), restaurable telle quelle ;
- `dumps/perfs-AAAA-MM-JJ.csv` : toutes les perfs, à ouvrir dans Excel.

Les fichiers de plus de 60 jours sont supprimés. Rien ne s'installe sur le NAS : le script utilise l'image Docker
`postgres:17-alpine`. Le dossier est dans `/compose_data`, donc il est aussi recopié par `backup-nas.sh`.

## 1. Chaîne de connexion (une fois)

Supabase → projet **Sysiphe** → bouton **Connect** (en haut) → **Session pooler**. Copie l'URI : elle ressemble à
`postgresql://postgres.qzvfkscqcllfnoqywkwq:[YOUR-PASSWORD]@aws-…-eu-west-1.pooler.supabase.com:5432/postgres`.

Remplace `[YOUR-PASSWORD]` par le mot de passe de la base. Si tu ne l'as plus : **Project Settings → Database →
Reset database password**. Ça ne touche pas l'app ni le site (ils utilisent la clé API, pas ce mot de passe).

> Prends bien **Session pooler** (port 5432) : la connexion « Direct » n'est joignable qu'en IPv6.

## 2. Sur le NAS (SSH)

```bash
mkdir -p /compose_data/sysiphe-backup && cd /compose_data/sysiphe-backup
BASE=https://raw.githubusercontent.com/Mephisto116631/sysiphe/main/backup
curl -fsSLO "$BASE/sauvegarde.sh" && curl -fsSLO "$BASE/sauvegarde.env.example"
cp sauvegarde.env.example sauvegarde.env && chmod 600 sauvegarde.env
nano sauvegarde.env        # colle ton URI après SUPABASE_DB_URL=
sh sauvegarde.sh           # 1er essai : doit finir par « OK : sysiphe-….dump (…), N perfs »
```

Si le mot de passe contient `@ : / ? # %`, remplace ces caractères dans l'URI par `%40 %3A %2F %3F %23 %25`.

## 3. Tous les jours, automatiquement

OMV → **Système → Tâches planifiées** → Ajouter : tous les jours à 3 h 17, utilisateur `root`, commande :

```
sh /compose_data/sysiphe-backup/sauvegarde.sh >> /var/log/sysiphe-backup.log 2>&1
```

Contrôle : `tail /var/log/sysiphe-backup.log` (une ligne `OK` par jour). En cas d'échec, le script s'arrête avec
une erreur et ne crée aucun fichier daté.

## Restaurer

Dans un projet Supabase vide (ou après avoir vidé les tables) :

```bash
cd /compose_data/sysiphe-backup
docker run --rm -v "$PWD/dumps:/d" postgres:17-alpine \
  pg_restore --no-owner --no-privileges -d "URI_DU_PROJET" /d/sysiphe-AAAA-MM-JJ.dump
```

Le message `schema "public" already exists` est normal et sans conséquence.
