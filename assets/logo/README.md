# Logo Sysiphe

| Fichier | Usage |
|---|---|
| `source_illustration.jpg` | Illustration d'origine (fond blanc) |
| `logo_transparent.png` | Logo complet détouré, upscale x2 |
| `emblem_transparent.png` | Emblème seul (sans texte), détouré |
| `logo_sysiphe.png` | Logo complet 1024 px, fond vert sombre + halo |
| `icon_512.png` | Icône de l'app 512 px (Play Store, aperçu) |
| `generate_logo.py` | Régénère tout, y compris les icônes Android |

Icônes Android : `flutter/android/app/src/main/res/mipmap-*` (+ adaptative dans `mipmap-anydpi-v26`, fond `#141A14` dans `values/colors.xml`).

Régénérer : `python assets/logo/generate_logo.py` (pillow, numpy, scipy).
