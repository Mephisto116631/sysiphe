-- Rôles : lecture du rôle d'un profil rattaché à l'appareil + export admin.
-- Additif (nouvelles fonctions). `profiles.role` existait déjà ('user' | 'admin').

create or replace function public.profile_role(p_profile uuid)
returns text
language sql stable security definer
set search_path = ''
as $$
  select case
    when public.is_profile_member(p_profile)
      then coalesce((select p.role from public.profiles p where p.id = p_profile), 'user')
    else 'user'
  end
$$;

-- Export de toutes les séries de tous les profils : réservé à un appareil
-- rattaché à un profil admin (vérifié côté serveur, indépendant de l'app).
create or replace function public.admin_export_perfs()
returns setof public.perfs
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.profile_members m
    join public.profiles p on p.id = m.profile_id
    where m.auth_uid = auth.uid() and p.role = 'admin'
  ) then
    raise exception 'Réservé à l''administrateur';
  end if;
  return query select * from public.perfs order by user_id, date, serie, id;
end
$$;

revoke all on function public.profile_role(uuid) from public;
revoke all on function public.admin_export_perfs() from public;
grant execute on function public.profile_role(uuid) to authenticated;
grant execute on function public.admin_export_perfs() to authenticated;
