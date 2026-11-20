-- ═══════════════════════════════════════════════════════════════════════════
-- Suppression d'un profil réservée aux admins.
--
-- Avant : tout appareil rattaché à un profil pouvait le supprimer (policy
-- profiles_delete). Désormais la suppression directe est retirée et passe par
-- admin_delete_profile(), qui exige un appareil rattaché à un profil admin.
-- Un profil admin ne peut pas être supprimé (pour ne jamais perdre l'accès
-- admin). Les séries (perfs) ne sont pas liées aux profils : elles restent
-- en base ; seuls les rattachements et verrous PIN partent en cascade.
-- ═══════════════════════════════════════════════════════════════════════════

drop policy if exists profiles_delete on public.profiles;
revoke delete on public.profiles from authenticated;

create or replace function public.admin_delete_profile(p_profile uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
    if not public.is_admin() then raise exception 'forbidden'; end if;
    if exists (select 1 from public.profiles
                where id = p_profile and role = 'admin') then
        raise exception 'admin_profile';
    end if;
    delete from public.profiles where id = p_profile;
    if not found then raise exception 'not_found'; end if;
end $$;

revoke all on function public.admin_delete_profile(uuid) from public, anon;
grant execute on function public.admin_delete_profile(uuid) to authenticated;
