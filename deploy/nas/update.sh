#!/bin/sh
# Récupère la dernière image Sysiphe et redémarre le conteneur si elle a changé.
# À planifier dans OMV : Système > Tâches planifiées, toutes les 15 min, utilisateur root :
#   sh /compose_data/sysiphe/update.sh >> /var/log/sysiphe-update.log 2>&1
cd "$(dirname "$0")" || exit 1

# Plugin Compose d'OMV : sysiphe.yml (+ compose.override.yml) ; sinon docker-compose.yml.
if [ -f sysiphe.yml ]; then
  set -- -p sysiphe -f sysiphe.yml
  [ -f compose.override.yml ] && set -- "$@" -f compose.override.yml
else
  set --
fi
# Fichiers d'environnement éventuels (OMV peut utiliser .env, sysiphe.env, ../global.env).
for e in ../global.env .env sysiphe.env; do
  [ -f "$e" ] && set -- "$@" --env-file "$e"
done

# --no-deps : ne touche jamais au conteneur Tailscale.
docker compose "$@" pull --quiet sysiphe
docker compose "$@" up -d --no-deps sysiphe
docker image prune -f --filter "label=org.opencontainers.image.source=https://github.com/Mephisto116631/sysiphe" >/dev/null
