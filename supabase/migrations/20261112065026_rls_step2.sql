-- Déjà appliquée sur le projet Sysiphe le 12/11/2026 (testée avant en transaction annulée).
-- Étape 2 : sécurité par ligne (RLS) sur perfs, user_settings et profiles.
-- Un appareil n'accède qu'aux profils auxquels il est rattaché (profile_members,
-- via is_profile_member). Le hash du PIN n'est plus lisible directement : tout
-- passe par les RPC (list_profiles, claim_profile, set_profile_pin, create_profile).

-- 1) Sans session (rôle anon) : plus aucun accès direct aux tables.
revoke all on public.perfs, public.user_settings, public.profiles from anon;

-- 2) perfs
alter table public.perfs enable row level security;
drop policy if exists "Chacun voit uniquement ses perfs" on public.perfs;
drop policy if exists perfs_membres on public.perfs;
create policy perfs_membres on public.perfs for all to authenticated
  using (public.is_profile_member(user_id))
  with check (public.is_profile_member(user_id));

-- 3) user_settings
alter table public.user_settings enable row level security;
drop policy if exists "Chacun voit uniquement ses settings" on public.user_settings;
drop policy if exists user_settings_membres on public.user_settings;
create policy user_settings_membres on public.user_settings for all to authenticated
  using (public.is_profile_member(user_id))
  with check (public.is_profile_member(user_id));

-- 4) profiles : lecture/renommage/suppression de ses propres profils seulement ;
--    création par RPC uniquement ; ni pin_hash ni role accessibles en direct.
alter table public.profiles enable row level security;
drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_update on public.profiles;
drop policy if exists profiles_delete on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (public.is_profile_member(id));
create policy profiles_update on public.profiles for update to authenticated
  using (public.is_profile_member(id)) with check (public.is_profile_member(id));
create policy profiles_delete on public.profiles for delete to authenticated
  using (public.is_profile_member(id));

revoke all on public.profiles from authenticated;
grant select (id, name, created_at, last_login, role) on public.profiles to authenticated;
grant update (name, last_login) on public.profiles to authenticated;
grant delete on public.profiles to authenticated;

-- 5) perfs et user_settings : pas de TRUNCATE / TRIGGER / REFERENCES pour les clients.
revoke truncate, trigger, references on public.perfs, public.user_settings from authenticated;
