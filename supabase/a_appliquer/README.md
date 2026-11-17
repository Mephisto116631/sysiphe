# Changements de base à appliquer à la main

Ces scripts modifient la base de production : ils ne sont **pas** appliqués automatiquement.
Chacun a été testé sur la vraie base dans une transaction annulée (rien n'a été modifié).

## `20261117_reglages_profils_categories.sql`

- Les profils « Dilbert 🐶 » et « Profil 3 » peuvent enfin enregistrer leurs réglages (poids, coefficients).
- La catégorie `Force isométrique ` (1 série, avec un espace final) devient `Force Iso`. `Gainage` est gardé :
  ce sont les abdos tenus en secondes, distincts des abdos en reps.
- Supprime la ligne de réglages rattachée à un ancien compte de connexion (pas un profil, illisible depuis la RLS).

Test du 17/11/2026 (annulé) : clé → `REFERENCES profiles(id)`, enregistrement de réglages pour Dilbert accepté,
catégories `Force Iso 791 · Gainage 143 · Musculation 381`.

### Marche à suivre (sur ordi, ~3 min)

1. **Sauvegarde** : dans l'app, Réglages → « Exporter la base (admin) » (ou lance `sauvegarder` dans le script Drive).
2. Supabase → projet **Sysiphe** → **SQL Editor** → **New query**.
3. Colle tout le contenu du fichier `.sql` → **Run**.
   - `Success. No rows returned` : c'est appliqué.
   - Un message d'erreur : rien n'a été modifié (tout est annulé), envoie-moi le message.
4. Vérifie (nouvelle requête) :
   ```sql
   select categorie, count(*) from perfs group by 1 order by 1;
   ```
   Attendu : `Force Iso 791`, `Gainage 143`, `Musculation 381` (plus les séances faites entre-temps).
5. Dans l'app, sur le profil Dilbert : change le poids dans Réglages → il doit s'enregistrer sans erreur.
6. Dis-le-moi : je range le fichier dans `supabase/migrations/` avec la version donnée par Supabase.
