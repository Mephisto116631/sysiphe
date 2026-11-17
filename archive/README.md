# Archives

Le dossier `archive/` conserve, pour mémoire, les briques abandonnées depuis l'abandon du NAS. Elles ne sont **plus construites ni déployées** : les workflows archivés sont hors de `.github/workflows/`, donc GitHub ne les exécute plus.

| Dossier | Ancien rôle |
|---------|-------------|
| `archive/nas/` | Auto-hébergement sur NAS : `Dockerfile`, docker-compose OMV, Tailscale Funnel, `update.sh` |
| `archive/android-webview/` | APK WebView v1.4 (ouvrait l'URL du NAS, sinon une page hors ligne) |
| `archive/mobile-capacitor/` | Premier wrapper APK (Capacitor), `targets.json`, icône source |
| `archive/workflows/` | `docker-image.yml` (image `ghcr.io`), `build-apk.yml`, `android-apk.yml` |

Pour réactiver une brique : remettre son dossier à la racine et son workflow dans `.github/workflows/`. Les chemins internes n'ont pas été modifiés.

Les APK WebView déjà installés lisent `mobile/targets.json` sur `main`. Ce fichier n'y est plus, donc ils affichent leur page hors ligne : il faut les désinstaller au profit de l'APK Flutter.

