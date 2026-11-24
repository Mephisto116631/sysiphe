-- ═══════════════════════════════════════════════════════════════════════════
-- Avatar des profils (v2.20.0) : lettres colorées (défaut), image prédéfinie
-- (emoji) ou petite photo (JPEG ~256 px en base64, quelques Ko).
-- profiles.avatar jsonb :
--   {"type":"lettres","couleur":2} | {"type":"image","emoji":"🦊","couleur":4}
--   | {"type":"photo","data":"<base64>"}
-- Modifiable par les appareils rattachés au profil (comme le nom), renvoyé
-- par list_profiles pour l'écran de choix du profil.
-- Additive : une colonne ; list_profiles renvoie une colonne de plus.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.profiles add column if not exists avatar jsonb;

-- Photo limitée à ~200 Ko de texte (une photo réduite fait ~15 Ko).
alter table public.profiles drop constraint if exists profiles_avatar_taille;
alter table public.profiles add constraint profiles_avatar_taille
    check (avatar is null or pg_column_size(avatar) < 200000);

grant select (avatar) on public.profiles to authenticated;
grant update (avatar) on public.profiles to authenticated;

-- Le type de retour change : on recrée la fonction (mêmes droits).
drop function if exists public.list_profiles();
create function public.list_profiles()
returns table (id uuid, name text, has_pin boolean, last_login timestamptz,
               is_member boolean, avatar jsonb)
language sql stable security definer set search_path = '' as $$
    select p.id, p.name, p.pin_hash is not null, p.last_login,
           public.is_profile_member(p.id), p.avatar
    from public.profiles p
    order by p.last_login desc nulls last, p.created_at asc
$$;
revoke all on function public.list_profiles() from public, anon;
grant execute on function public.list_profiles() to authenticated;
