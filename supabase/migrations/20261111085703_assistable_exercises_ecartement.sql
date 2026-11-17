-- Étape 7 : exercices assistables (tractions avec élastique) + écartement des mains.
-- Additif : colonnes nullables, aucune donnée modifiée. Déjà appliquée sur le projet Sysiphe.
alter table public.perfs add column if not exists ecartement text;
alter table public.user_settings add column if not exists assistable_exercises jsonb default '[]'::jsonb;
alter table public.user_settings add column if not exists ecartements_config jsonb;
