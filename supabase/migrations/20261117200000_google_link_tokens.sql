-- ═══════════════════════════════════════════════════════════════════════════
-- Sécurité, étape 3/3 — Associer un compte Google aux profils d'un appareil.
--
-- Le téléphone (session anonyme rattachée à ses profils) crée un jeton à usage
-- unique, ouvre une session Google, puis échange le jeton : le compte Google
-- est rattaché aux mêmes profils. Il les retrouve ensuite sur un autre
-- téléphone ou sur le web, sans PIN. Aucune donnée copiée : seulement des
-- lignes profile_members. Fonctionne aussi si le compte Google existe déjà.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.link_tokens (
    token_hash text primary key,              -- SHA-256 du jeton, jamais le jeton
    auth_uid   uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null,
    used_at    timestamptz
);
alter table public.link_tokens enable row level security;  -- aucune policy : RPC seulement
revoke all on public.link_tokens from public, anon, authenticated;

-- Jeton en clair renvoyé une seule fois (valable 10 minutes).
-- Refusé sans session ou si la session n'a accès à aucun profil.
create or replace function public.create_link_token()
returns text language plpgsql security definer set search_path = '' as $$
declare
    v_uid   uuid := auth.uid();
    v_token text;
begin
    if v_uid is null then raise exception 'no_session'; end if;
    if not exists (select 1 from public.profiles p where public.is_profile_member(p.id)) then
        raise exception 'no_profile';
    end if;
    delete from public.link_tokens where expires_at < now() - interval '1 day';
    v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    insert into public.link_tokens (token_hash, auth_uid, expires_at)
    values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_uid,
            now() + interval '10 minutes');
    return v_token;
end $$;

-- Rattache la session courante (le compte Google) aux profils de l'émetteur
-- du jeton. Renvoie le nombre de profils accessibles grâce au jeton.
-- Erreurs : no_session, invalid, used, expired.
create or replace function public.redeem_link_token(p_token text)
returns int language plpgsql security definer set search_path = '' as $$
declare
    v_uid uuid := auth.uid();
    v_tok public.link_tokens;
    v_n   int;
begin
    if v_uid is null then raise exception 'no_session'; end if;
    select * into v_tok from public.link_tokens
     where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     for update;
    if not found then raise exception 'invalid'; end if;
    if v_tok.used_at is not null then raise exception 'used'; end if;
    if v_tok.expires_at < now() then raise exception 'expired'; end if;

    update public.link_tokens set used_at = now() where token_hash = v_tok.token_hash;
    if v_tok.auth_uid = v_uid then return 0; end if;  -- même session : rien à faire

    -- Profils de l'émetteur : rattachements, ou compte historique dont l'id est le profil.
    insert into public.profile_members (auth_uid, profile_id)
    select v_uid, p.id from public.profiles p
     where p.id = v_tok.auth_uid
        or exists (select 1 from public.profile_members m
                    where m.auth_uid = v_tok.auth_uid and m.profile_id = p.id)
    on conflict do nothing;

    select count(*) into v_n from public.profiles p
     where p.id = v_tok.auth_uid
        or exists (select 1 from public.profile_members m
                    where m.auth_uid = v_tok.auth_uid and m.profile_id = p.id);
    return v_n;
end $$;

revoke all on function public.create_link_token()       from public, anon;
revoke all on function public.redeem_link_token(text)   from public, anon;
grant execute on function public.create_link_token()     to authenticated;
grant execute on function public.redeem_link_token(text) to authenticated;
