#!/bin/sh
# Sauvegarde quotidienne de la base Supabase de Sysiphe, sur le NAS.
# Mode d'emploi : backup/README.md. À planifier dans OMV (Système > Tâches planifiées), utilisateur root :
#   sh /compose_data/sysiphe-backup/sauvegarde.sh >> /var/log/sysiphe-backup.log 2>&1
set -eu
cd "$(dirname "$0")"

# sauvegarde.env : SUPABASE_DB_URL=postgresql://...  (lu tel quel, sans l'exécuter :
# un mot de passe avec & $ ou ! ne pose pas de problème ; guillemets autour facultatifs).
lire() { sed -n "s/^$1=//p" sauvegarde.env | tail -n 1 | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"; }
SUPABASE_DB_URL=$(lire SUPABASE_DB_URL)
[ -n "$SUPABASE_DB_URL" ] || { echo "SUPABASE_DB_URL manquant dans sauvegarde.env" >&2; exit 1; }
GARDER_JOURS=$(lire GARDER_JOURS); GARDER_JOURS="${GARDER_JOURS:-60}"

JOUR=$(date +%F)
mkdir -p dumps
rm -f dumps/.en-cours.*

# pg_dump doit être au moins de la version du serveur (Postgres 17).
docker run --rm -e PGURL="$SUPABASE_DB_URL" -v "$PWD/dumps:/out" postgres:17-alpine sh -ec '
  # Copie complète du schéma public (tables, données, fonctions), restaurable avec pg_restore.
  pg_dump "$PGURL" --schema=public --no-owner --no-privileges \
    --format=custom --file=/out/.en-cours.dump
  pg_restore --list /out/.en-cours.dump >/dev/null   # le fichier est lisible
  # Les perfs en CSV, lisibles dans Excel sans rien installer.
  psql "$PGURL" -v ON_ERROR_STOP=1 -qc \
    "\copy (select * from public.perfs order by id) to /out/.en-cours.csv csv header"
'

mv dumps/.en-cours.dump "dumps/sysiphe-$JOUR.dump"
mv dumps/.en-cours.csv "dumps/perfs-$JOUR.csv"
chmod 600 dumps/*
find dumps -name 'sysiphe-*.dump' -mtime +"$GARDER_JOURS" -delete
find dumps -name 'perfs-*.csv' -mtime +"$GARDER_JOURS" -delete

echo "$(date '+%F %T') OK : sysiphe-$JOUR.dump ($(du -h "dumps/sysiphe-$JOUR.dump" | cut -f1)), $(($(wc -l < "dumps/perfs-$JOUR.csv") - 1)) perfs"
