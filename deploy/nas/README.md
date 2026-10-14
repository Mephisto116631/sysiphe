# Sysiphe sur le NAS (OMV + Docker + Tailscale Funnel)

Chaque commit sur `main` publie une nouvelle image (`ghcr.io/mephisto116631/sysiphe:latest`) ; le NAS la récupère tout seul via `update.sh`. Streamlit Cloud reste actif en secours : l'app Android bascule dessus si le NAS ne répond pas.

## 1. Tailscale (une fois, depuis le navigateur)

1. Crée un compte sur https://login.tailscale.com (gratuit).
2. **DNS** → active **MagicDNS** et **HTTPS Certificates**.
3. **Access controls** → ajoute l'attribut Funnel dans la policy :
   ```json
   "nodeAttrs": [{ "target": ["autogroup:member"], "attr": ["funnel"] }]
   ```
4. **Settings → Keys → Generate auth key** : coche *Reusable*, garde la clé `tskey-auth-…`.

## 2. Sur le NAS (SSH)

```bash
mkdir -p /srv/compose_data/sysiphe && cd /srv/compose_data/sysiphe
BASE=https://raw.githubusercontent.com/Mephisto116631/sysiphe/main/deploy/nas
for f in docker-compose.yml serve.json update.sh secrets.toml.example; do curl -fsSLO "$BASE/$f"; done
cp secrets.toml.example secrets.toml && nano secrets.toml   # valeurs Supabase de Streamlit Cloud
echo "TS_AUTHKEY=tskey-auth-XXXX" > .env && chmod 600 .env secrets.toml
docker compose up -d
docker exec sysiphe-tailscale tailscale status   # affiche sysiphe.<tailnet>.ts.net
```

Mets l'URL `https://sysiphe.<tailnet>.ts.net` dans `APP_URL` de `secrets.toml`, puis `docker compose restart sysiphe`.

## 3. Mise à jour automatique

OMV → **Système → Tâches planifiées** → Ajouter : toutes les 15 min, utilisateur `root`, commande :

```
sh /srv/compose_data/sysiphe/update.sh >> /srv/compose_data/sysiphe/update.log 2>&1
```

## Dépannage

- `docker compose logs -f sysiphe` — erreurs de l'app.
- `docker exec sysiphe-tailscale tailscale funnel status` — Funnel actif ?
- Connexion Google : ajoute l'URL NAS dans Supabase → Authentication → URL Configuration → Redirect URLs.
