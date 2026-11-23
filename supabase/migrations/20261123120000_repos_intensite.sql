-- ═══════════════════════════════════════════════════════════════════════════
-- v2.16 — additif, aucune donnée modifiée.
--  • perfs.repos_s / repos_prevu_s : repos réellement pris avant la série et
--    repos prévu (secondes). null = pas de repos automatique. Plus court que
--    prévu = repos passé ou raccourci.
--  • user_settings.intensity_config : seuils des couleurs d'intensité du
--    profil ({"orange": pts, "rouge": pts}) ; null = automatique.
-- (user_settings.include_planche existe déjà : planche activée par profil.)
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.perfs add column if not exists repos_s integer;
alter table public.perfs add column if not exists repos_prevu_s integer;
alter table public.perfs drop constraint if exists perfs_repos_positif;
alter table public.perfs add constraint perfs_repos_positif
    check ((repos_s is null or repos_s >= 0)
       and (repos_prevu_s is null or repos_prevu_s >= 0));

alter table public.user_settings add column if not exists intensity_config jsonb;
