-- ═══════════════════════════════════════════════════════════════════════════
-- Réglages des profils (user_settings) : la clé étrangère vers auth.users date
-- de l'ancien fonctionnement (un compte Supabase = un utilisateur). Depuis les
-- profils, user_id est l'identifiant du profil, absent de auth.users pour tous
-- sauf le premier : enregistrer un réglage (planche, poids, intensité…)
-- échouait avec « violates foreign key constraint user_settings_user_id_fkey ».
-- On retire cette contrainte (comme perfs, qui n'en a pas). Les droits restent
-- assurés par la RLS (is_profile_member). Rien n'est supprimé.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.user_settings drop constraint if exists user_settings_user_id_fkey;
