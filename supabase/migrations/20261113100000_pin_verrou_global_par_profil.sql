-- Verrou anti force brute par PROFIL (et non plus seulement par appareil) :
-- avant, une nouvelle session anonyme repartait avec 5 essais neufs, ce qui permettait de
-- deviner un PIN à 4 chiffres en créant des sessions en série. Désormais, 10 échecs au total
-- (toutes sessions confondues) verrouillent le profil 1 h, puis 2 h, 4 h… (max ~5 jours).
-- Les appareils déjà rattachés ne sont pas concernés. Déjà appliquée, testée en transaction annulée.
create table if not exists public.profile_pin_lock (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  failures int not null default 0,
  lock_level int not null default 0,
  locked_until timestamptz
);
alter table public.profile_pin_lock enable row level security;
revoke all on public.profile_pin_lock from anon, authenticated;

create or replace function public.claim_profile(p_profile uuid, p_pin text default null)
 returns text language plpgsql security definer set search_path to ''
as $function$
declare
    v_uid  uuid := auth.uid();
    v_hash text;
    v_att  public.pin_attempts;
    v_lock public.profile_pin_lock;
begin
    if v_uid is null then return 'no_session'; end if;
    select pin_hash into v_hash from public.profiles where id = p_profile;
    if not found then return 'bad_pin'; end if;
    select * into v_lock from public.profile_pin_lock where profile_id = p_profile;
    if v_lock.locked_until is not null and v_lock.locked_until > now() then return 'locked'; end if;
    select * into v_att from public.pin_attempts where auth_uid = v_uid and profile_id = p_profile;
    if v_att.locked_until is not null and v_att.locked_until > now() then return 'locked'; end if;
    if v_hash is not null and v_hash is distinct from public.pin_digest(coalesce(p_pin, '')) then
        insert into public.pin_attempts (auth_uid, profile_id, failures, locked_until)
        values (v_uid, p_profile, 1, null)
        on conflict (auth_uid, profile_id) do update
           set failures = public.pin_attempts.failures + 1,
               locked_until = case when public.pin_attempts.failures + 1 >= 5 then now() + interval '15 minutes' end;
        insert into public.profile_pin_lock (profile_id, failures)
        values (p_profile, 1)
        on conflict (profile_id) do update
           set failures = case when public.profile_pin_lock.failures + 1 >= 10 then 0
                               else public.profile_pin_lock.failures + 1 end,
               lock_level = case when public.profile_pin_lock.failures + 1 >= 10
                                 then least(public.profile_pin_lock.lock_level + 1, 8)
                                 else public.profile_pin_lock.lock_level end,
               locked_until = case when public.profile_pin_lock.failures + 1 >= 10
                                   then now() + interval '1 hour' * power(2, least(public.profile_pin_lock.lock_level, 7))
                                   else public.profile_pin_lock.locked_until end;
        return 'bad_pin';
    end if;
    delete from public.pin_attempts where auth_uid = v_uid and profile_id = p_profile;
    delete from public.profile_pin_lock where profile_id = p_profile;
    insert into public.profile_members (auth_uid, profile_id) values (v_uid, p_profile) on conflict do nothing;
    update public.profiles set last_login = now() where id = p_profile;
    return 'ok';
end $function$;

revoke execute on function public.claim_profile(uuid, text) from public, anon;
grant execute on function public.claim_profile(uuid, text) to authenticated;
