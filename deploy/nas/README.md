# Sysiphe sur le NAS (OMV + Docker + Tailscale Funnel)

Chaque commit sur `main` publie une nouvelle image (`ghcr.io/mephisto116631/sysiphe:latest`) ; le NAS la récupère tout seul via `update.sh`. Rien n'est construit sur le NAS. Streamlit Cloud reste actif en secours : l'app Android bascule dessus si le NAS ne répond pas.

## 1. Tailscale (une fois, depuis le navigateur)

1. Crée un compte sur https://login.tailscale.com (gratuit).
2. **Settings → General** : renomme le tailnet (nom lisible, il apparaît dans les URL).
3. **DNS** : active **MagicDNS** et **HTTPS Certificates**.
4. **Access controls** : remplace la policy par :
   ```json
   {
     "tagOwners": { "tag:nas": ["autogroup:admin"] },
     "grants": [
       { "src": ["autogroup:member"], "dst": ["tag:nas"], "ip": ["*"] }
     ],
     "nodeAttrs": [
       { "target": ["tag:nas"], "attr": ["funnel"] }
     ]
   }
   ```
   Les nœuds tagués n'expirent pas et ne peuvent joindre aucun de tes appareils.
5. **Settings → Keys → Generate auth key** : *Reusable* coché, *Ephemeral* décoché, *Tags* → `tag:nas`. Garde la clé `tskey-auth-…` dans ton gestionnaire de mots de passe.

## 2. Image publique

Déjà fait : le package `ghcr.io/mephisto116631/sysiphe` est Public (aucun secret dedans, ils sont montés au lancement).

## 3. Sur le NAS

**SSH** : prépare les fichiers à côté du compose.
```bash
mkdir -p /compose_data/sysiphe && cd /compose_data/sysiphe
BASE=https://raw.githubusercontent.com/Mephisto116631/sysiphe/main/deploy/nas
apt install -y curl   # absent par défaut sur OMV
for f in serve.json update.sh secrets.toml.example; do curl -fsSLO "$BASE/$f"; done
cp secrets.toml.example secrets.toml && nano secrets.toml   # valeurs Supabase de Streamlit Cloud
chown 1000:1000 secrets.toml && chmod 600 secrets.toml   # l'app tourne sous l'uid 1000
```

**OMV → Services → Compose → Fichiers → Ajouter** :
- Nom : `sysiphe`
- Fichier : colle `docker-compose.yml`
- Environnement : `TS_AUTHKEY=tskey-auth-…`
- Enregistre, puis **Up**.

Vérifie :
```bash
docker exec sysiphe-tailscale tailscale status          # sysiphe … tagged-devices
docker exec sysiphe-tailscale tailscale funnel status   # https://sysiphe.<tailnet>.ts.net (Funnel on)
```

Mets cette URL dans `APP_URL` de `secrets.toml`, puis `docker restart sysiphe`.

## 4. Mise à jour automatique

OMV → **Système → Tâches planifiées** → Ajouter : toutes les 15 min, utilisateur `root`, commande :

```
sh /compose_data/sysiphe/update.sh >> /var/log/sysiphe-update.log 2>&1
```

## 5. Supabase et Android

- Supabase → Authentication → URL Configuration → **Redirect URLs** : ajoute `https://sysiphe.<tailnet>.ts.net`.
- `mobile/targets.json` → `"nas": "https://sysiphe.<tailnet>.ts.net"` (un commit, sans recompiler l'APK).

## Dépannage

- `docker logs -f sysiphe` : erreurs de l'app.
- `docker logs sysiphe-tailscale` : authentification Tailscale (clé expirée, tag refusé…).
- `docker exec sysiphe-tailscale tailscale funnel status` : Funnel actif ?
- La 1re ouverture de l'URL peut prendre ~1 min (émission du certificat HTTPS).
