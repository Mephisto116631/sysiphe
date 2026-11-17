-- Récupérée de la production (supabase_migrations.schema_migrations), absente du dépôt jusqu'ici.
-- Rôles : admin / user. Additif ; tout le monde est « user » par défaut.
alter table public.profiles add column if not exists role text not null default 'user';
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('admin','user'));
update public.profiles set role = 'admin' where id = '9250e548-1d5a-48d1-98c0-5c97089a77d8';

-- Rôle d'un profil : lu seulement si cet appareil est rattaché au profil.
create or replace function public.profile_role(p_profile uuid)
returns text language sql stable security definer set search_path = public as $$
  select case when public.is_profile_member(p_profile)
              then (select role from public.profiles where id = p_profile)
              else 'user' end
$$;

-- Admin : cet appareil est rattaché à au moins un profil admin.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profile_members m
    join public.profiles p on p.id = m.profile_id
    where m.auth_uid = auth.uid() and p.role = 'admin')
$$;

-- Export de toutes les séries de tous les profils (admin uniquement).
create or replace function public.admin_export_perfs()
returns setof public.perfs language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return query select * from public.perfs order by user_id, date, id;
end $$;

revoke all on function public.profile_role(uuid)    from public, anon;
revoke all on function public.is_admin()            from public, anon;
revoke all on function public.admin_export_perfs()  from public, anon;
grant execute on function public.profile_role(uuid)   to authenticated;
grant execute on function public.is_admin()           to authenticated;
grant execute on function public.admin_export_perfs() to authenticated;
