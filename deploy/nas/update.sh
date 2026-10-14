#!/bin/sh
# Récupère la dernière image Sysiphe et redémarre le conteneur si elle a changé.
# À planifier dans OMV : Système > Tâches planifiées, toutes les 15 min, utilisateur root :
#   sh /srv/compose_data/sysiphe/update.sh >> /srv/compose_data/sysiphe/update.log 2>&1
cd "$(dirname "$0")" || exit 1
docker compose pull --quiet sysiphe
docker compose up -d sysiphe
docker image prune -f --filter "label=org.opencontainers.image.source=https://github.com/Mephisto116631/sysiphe" >/dev/null
