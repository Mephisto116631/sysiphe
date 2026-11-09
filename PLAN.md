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
- [x] Web : bouton « recalcul des efforts » réparé (recherche insensible à la casse)
- [x] NAS, APK WebView et Capacitor archivés dans `archive/` (rien de supprimé)

## Phase 1 — Rendre les données visibles dans Flutter 🔴 (bloquant)

Constaté dans les logs Supabase : toutes les requêtes Flutter qui chargent les séries
répondent **400**, et l'app reste bloquée sur un chargement infini.

- [x] Ne plus trier sur `perfs.created_at` (la colonne n'existe pas, d'où les erreurs 400) → tri sur `id`
- [x] `perfs.id` est un entier (`bigint`) et non un texte : lecture et suppression corrigées
- [x] Charger **tout** l'historique : Supabase ne renvoie que 1 000 lignes par requête (tu en as 1 260) → pagination
- [x] Stats / Records / Calendrier : afficher un message d'erreur et un bouton « Réessayer » au lieu d'un chargement infini
- [x] Ordre des profils identique au web
- [ ] **Toi** : vérifier que le build Flutter passe au vert (onglet *Actions* sur GitHub)
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
- [ ] Hachage du PIN : appliquer `strip()` aussi à la vérification côté web (`supabase_io.py:146`)
- [ ] Mettre à jour `SETUP.md` avec le schéma réel (colonnes `app_theme`, `inactivity_days`, `enable_charges`, `graph_period`)

## Phase 4 — Parité fonctionnelle Flutter ↔ web

Pages et fonctions présentes sur le web, absentes ou simplifiées dans Flutter :

- [ ] **Saisie planche** multi-séries (S1 à S5) avec variante, forme, élastique et tension par série
- [ ] **Saisie lestée** : champ « charge (kg) » pour tractions et dips lestés
- [ ] **Saisie** : panneau « stats du jour et prochaine séance » (KPI)
- [ ] **Stats** : choix de période, lissage, détection plateau / progression / régression
- [ ] **Stats** : volume lesté (`performance × charge`) et effort planche
- [ ] **Repos** : nouvelle page d'analyse de la récupération
- [ ] **Records** : record planche basé sur l'effort pondéré, pas seulement sur le temps
- [ ] **Paramètres** : édition de la calibration planche (variantes, formes, élastiques, tensions) + recalcul
- [ ] **Paramètres** : gestion des profils (créer, renommer, supprimer)
- [ ] **Paramètres** : renommer un exercice
- [ ] **Paramètres** : export CSV
- [ ] Rappel d'inactivité (`inactivity_days`) en notification locale

## Phase 5 — Qualité et robustesse

- [x] Tests Flutter : `calculerEffort` donne les mêmes résultats que `data.py`, et `Perf.fromJson` est testé sur des lignes réelles (`flutter/test/perf_test.dart`, 12 tests)
- [x] CI : `flutter analyze` + `flutter test` sur chaque PR, et pas seulement à la publication (`ci.yml`)
- [x] CI : `pytest test_data.py` sur chaque PR (28 tests)
- [ ] Mode hors ligne Flutter : cache local et saisie différée, synchronisée au retour du réseau
- [ ] Numéro de version affiché dans l'app, tiré de `pubspec.yaml`
- [ ] Version incrémentée à chaque build (`versionCode` = numéro du run CI) : aujourd'hui chaque build écrase la Release `v2.0.0`, et on ne distingue pas les APK entre eux

## Phase 6 — Plus tard / à décider

- [ ] Garder Streamlit à long terme, ou tout migrer dans Flutter une fois la phase 4 terminée ?
- [ ] Icône définitive de l'app Flutter
