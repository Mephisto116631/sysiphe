-- ═══════════════════════════════════════════════════════════════════════════
-- Sécurité, étape 1/3 — ADDITIVE : n'active pas encore la RLS.
--
-- Principe : chaque appareil (ou navigateur) ouvre une session Supabase
-- anonyme et persistante. Le PIN est vérifié UNE fois côté serveur
-- (claim_profile) : la session est alors rattachée au profil dans
-- profile_members. L'étape 2 activera la RLS sur is_profile_member().
-- Une identité Google peut ensuite être liée à cette session (étape 3).
-- ═══════════════════════════════════════════════════════════════════════════

-- Rattachement session Supabase ↔ profil
create table if not exists public.profile_members (
    auth_uid   uuid not null references auth.users(id) on delete cascade,
    profile_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (auth_uid, profile_id)
);
alter table public.profile_members enable row level security;
-- Chacun ne voit que ses propres rattachements ; écriture uniquement via RPC.
create policy "voir ses rattachements" on public.profile_members
    for select to authenticated using (auth_uid = auth.uid());
revoke insert, update, delete on public.profile_members from anon, authenticated;

-- Anti force brute du PIN : 5 essais ratés → 15 minutes de blocage
create table if not exists public.pin_attempts (
    auth_uid     uuid not null references auth.users(id) on delete cascade,
    profile_id   uuid not null references public.profiles(id) on delete cascade,
    failures     int  not null default 0,
    locked_until timestamptz,
    primary key (auth_uid, profile_id)
);
alter table public.pin_attempts enable row level security;  -- aucune policy : RPC seulement
revoke all on public.pin_attempts from anon, authenticated;

-- Hachage identique aux apps : SHA-256 hex du PIN sans espaces autour
create or replace function public.pin_digest(p_pin text)
returns text language sql immutable set search_path = '' as $$
    select encode(sha256(convert_to(btrim(p_pin), 'UTF8')), 'hex')
$$;

-- La session courante a-t-elle accès au profil ? (base des policies RLS)
-- auth.uid() = profil : comptes Google historiques dont l'id EST le profil.
create or replace function public.is_profile_member(p_profile uuid)
returns boolean language sql stable security definer set search_path = '' as $$
    select auth.uid() is not null and (
        auth.uid() = p_profile
        or exists (select 1 from public.profile_members m
                   where m.auth_uid = auth.uid() and m.profile_id = p_profile)
    )
$$;

-- Liste des profils pour l'écran de connexion, sans exposer pin_hash
create or replace function public.list_profiles()
returns table (id uuid, name text, has_pin boolean, last_login timestamptz,
               is_member boolean)
language sql stable security definer set search_path = '' as $$
    select p.id, p.name, p.pin_hash is not null, p.last_login,
           public.is_profile_member(p.id)
    from public.profiles p
    order by p.last_login desc nulls last, p.created_at asc
$$;

-- Vérifie le PIN côté serveur et rattache la session au profil.
-- Retourne 'ok', 'bad_pin', 'locked' ou 'no_session'.
create or replace function public.claim_profile(p_profile uuid, p_pin text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
    v_uid  uuid := auth.uid();
    v_hash text;
    v_att  public.pin_attempts;
begin
    if v_uid is null then return 'no_session'; end if;
    select pin_hash into v_hash from public.profiles where id = p_profile;
    if not found then return 'bad_pin'; end if;

    select * into v_att from public.pin_attempts
     where auth_uid = v_uid and profile_id = p_profile;
    if v_att.locked_until is not null and v_att.locked_until > now() then
        return 'locked';
    end if;

    if v_hash is not null and v_hash is distinct from public.pin_digest(coalesce(p_pin, '')) then
        insert into public.pin_attempts (auth_uid, profile_id, failures, locked_until)
        values (v_uid, p_profile, 1, null)
        on conflict (auth_uid, profile_id) do update
           set failures = public.pin_attempts.failures + 1,
               locked_until = case when public.pin_attempts.failures + 1 >= 5
                                   then now() + interval '15 minutes' end;
        return 'bad_pin';
    end if;

    delete from public.pin_attempts where auth_uid = v_uid and profile_id = p_profile;
    insert into public.profile_members (auth_uid, profile_id)
    values (v_uid, p_profile) on conflict do nothing;
    update public.profiles set last_login = now() where id = p_profile;
    return 'ok';
end $$;

-- Création de compte : profil + PIN facultatif, rattaché à la session
create or replace function public.create_profile(p_name text, p_pin text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
    v_uid uuid := auth.uid();
    v_id  uuid;
begin
    if v_uid is null then raise exception 'no_session'; end if;
    if coalesce(btrim(p_name), '') = '' then raise exception 'empty_name'; end if;
    insert into public.profiles (name, pin_hash, last_login)
    values (btrim(p_name),
            case when coalesce(btrim(p_pin), '') = '' then null else public.pin_digest(p_pin) end,
            now())
    returning id into v_id;
    insert into public.profile_members (auth_uid, profile_id) values (v_uid, v_id);
    return v_id;
end $$;

-- Changer le PIN d'un profil auquel on a accès
create or replace function public.set_profile_pin(p_profile uuid, p_pin text)
returns void language plpgsql security definer set search_path = '' as $$
begin
    if not public.is_profile_member(p_profile) then raise exception 'forbidden'; end if;
    update public.profiles
       set pin_hash = case when coalesce(btrim(p_pin), '') = '' then null
                           else public.pin_digest(p_pin) end
     where id = p_profile;
end $$;

-- Fonctions appelables par les sessions connectées (anonymes incluses)
revoke all on function public.claim_profile(uuid, text)   from public, anon;
revoke all on function public.create_profile(text, text)  from public, anon;
revoke all on function public.set_profile_pin(uuid, text) from public, anon;
revoke all on function public.list_profiles()             from public, anon;
grant execute on function public.claim_profile(uuid, text)   to authenticated;
grant execute on function public.create_profile(text, text)  to authenticated;
grant execute on function public.set_profile_pin(uuid, text) to authenticated;
grant execute on function public.list_profiles()             to authenticated;
grant execute on function public.is_profile_member(uuid)     to authenticated;
