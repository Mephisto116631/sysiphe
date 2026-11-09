# Sysiphe — Plan d'actions

> Cocher une case : remplacer `[ ]` par `[x]` (sur GitHub : bouton ✏️ du fichier).
> Ce fichier est la référence du suivi : chaque session Claude le lit et le met à jour.
>
> Dernière mise à jour : 9 novembre 2026

**Cap** : l'app mobile est l'APK **Flutter**. L'app web **Streamlit** reste sur Streamlit Cloud
(calibration, analyses avancées). Les deux partagent la même base **Supabase**. Le NAS est abandonné.

---

## Phase 0 — Déjà fait ✅

- [x] Diagnostic du projet et README réécrit en UTF-8, aligné sur le code
- [x] Flutter : colonne `performance` (valeur) distincte de `charge` (lest kg), comme l'app web
- [x] Flutter : réglages lus/écrits dans `user_settings` (au lieu de `settings`, inexistante)
- [x] Flutter : effort calculé seulement pour « Planche », avec la calibration de l'utilisateur
- [x] Web : bouton « recalcul des efforts » réparé (recherche insensible à la casse, puis upsert qui échouait toujours sur les colonnes NOT NULL)
- [x] NAS, APK WebView et Capacitor archivés dans `archive/` (rien de supprimé)

## Phase 1 — Rendre les données visibles dans Flutter 🔴 (bloquant)

Constaté dans les logs Supabase : toutes les requêtes Flutter qui chargent les séries
répondent **400**, et l'app reste bloquée sur un chargement infini.

- [x] Ne plus trier sur `perfs.created_at` (la colonne n'existe pas, d'où les erreurs 400) → tri sur `id`
- [x] `perfs.id` est un entier (`bigint`) et non un texte : lecture et suppression corrigées
- [x] Charger **tout** l'historique : Supabase ne renvoie que 1 000 lignes par requête (tu en as 1 260) → pagination
- [x] Stats / Records / Calendrier : afficher un message d'erreur et un bouton « Réessayer » au lieu d'un chargement infini
- [x] Ordre des profils identique au web
- [x] Build Flutter vert après la fusion de la PR #4 (vérifié par Claude)
- [ ] **Toi** : installer le nouvel APK et vérifier Saisie, Stats, Calendrier et Records sur tes vraies données

## Phase 2 — Mise en production

- [x] Ouvrir la PR `ccr-6aa55910-p46qv7` → `main`
- [x] Relire et fusionner la PR [#4](https://github.com/Mephisto116631/sysiphe/pull/4) (CI verte, fusionnée le 9 novembre)
- [ ] Vérifier que Streamlit Cloud a redéployé l'app web sans erreur
- [ ] Désinstaller l'ancienne app WebView du téléphone
- [ ] Supprimer les secrets GitHub inutiles : `KEYSTORE_BASE64`, `KEY_ALIAS`
- [ ] Éteindre les conteneurs Sysiphe sur le NAS

## Phase 3 — Base de données et sécurité 🔐

- [ ] **RLS désactivée** sur `perfs`, `profiles` et `user_settings` (alerte *critique* de Supabase) :
      n'importe qui possédant la clé `anon` (présente dans l'APK) peut lire et modifier toutes les données.
      Des policies `auth.uid() = user_id` existent mais ne sont pas actives, et les activer telles quelles
      **casserait les deux apps**, car la connexion par profil + PIN n'utilise pas l'authentification Supabase.
      → Choisir une solution (proposition : connexion anonyme Supabase + fonction RPC de vérification du PIN qui
      renvoie un jeton lié au profil), puis l'implémenter dans les deux apps
- [ ] `user_settings.user_id` pointe sur `auth.users` : les profils « Dilbert 🐶 » et « Profil 3 » ne peuvent pas
      enregistrer de réglages (violation de clé étrangère). → Faire pointer la clé sur `profiles(id)`
- [ ] Harmoniser les catégories en base (`Force isométrique `, `Gainage`, `Force Iso`) : migration SQL
- [x] Hachage du PIN : `strip()` aussi à la vérification côté web, comme à l'enregistrement et dans Flutter
- [x] `SETUP.md` réécrit avec le schéma réel de production (3 tables, toutes les colonnes)

## Phase 4 — Parité fonctionnelle Flutter ↔ web

Pages et fonctions présentes sur le web, absentes ou simplifiées dans Flutter :

- [ ] **Saisie planche** multi-séries (S1 à S5) avec variante, forme, élastique et tension par série
- [x] **Saisie lestée** : champ « Lest (kg) » pour les séries en reps (enregistré dans `charge`)
- [x] **Saisie** : options planche ouvertes automatiquement pour « Planche » ; bug du champ Exercice corrigé (curseur qui sautait)
- [ ] **Saisie** : panneau « stats du jour et prochaine séance » (KPI)
- [x] **Stats** : une valeur par séance, choix de période (30 j / 3 mois / 6 mois / tout), badge progression / plateau / régression (port testé de `detect_plateau`)
- [x] **Stats** : effort pondéré pour la planche, tonnage (`performance × charge`) ou volume pour les reps
- [ ] **Repos** : nouvelle page d'analyse de la récupération
- [x] **Records** : record planche basé sur l'effort pondéré, puis le temps ; autres exercices départagés par le lest
- [x] **Paramètres** : écran « Calibration planche » (variantes, formes, élastiques, tensions), partagé avec le web, + recalcul des efforts
- [x] **Paramètres** : gestion des profils (créer, renommer, supprimer sauf le profil actif)
- [x] **Paramètres** : renommer un exercice dans tout l'historique (avec confirmation si fusion)
- [x] Initiales des profils : l'emoji de « Dilbert 🐶 » n'est plus coupé en deux, un double espace ne fait plus planter
- [ ] **Paramètres** : export CSV
- [ ] Rappel d'inactivité (`inactivity_days`) en notification locale

## Phase 5 — Qualité et robustesse

- [x] Tests Flutter : `calculerEffort` donne les mêmes résultats que `data.py`, et `Perf.fromJson` est testé sur des lignes réelles (`flutter/test/`, 26 tests)
- [x] CI : `flutter analyze` + `flutter test` sur chaque PR, et pas seulement à la publication (`ci.yml`)
- [x] CI : `pytest test_data.py` sur chaque PR (28 tests)
- [ ] Mode hors ligne Flutter : cache local et saisie différée, synchronisée au retour du réseau
- [x] Numéro de version affiché dans l'app (bas de l'écran Paramètres, ex. `2.1.0+7`)
- [x] Version incrémentée à chaque build (`versionCode` = numéro du run CI) et notes de version générées depuis les PR → passage en **v2.1.0**

## Phase 6 — Plus tard / à décider

- [ ] Garder Streamlit à long terme, ou tout migrer dans Flutter une fois la phase 4 terminée ?
- [ ] Icône définitive de l'app Flutter
