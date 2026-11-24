-- ═══════════════════════════════════════════════════════════════════════════
-- Réglages envoyés par l'admin à un profil, et message de présentation
-- (v2.19.0). Additive : deux colonnes et une fonction.
--
-- admin_push_settings(profil, réglages, réglages de l'appareil, message) :
--   - admin seulement (is_admin) ;
--   - réglages du profil (poids, planche, intensité, coefficients…) écrits
--     directement dans user_settings, colonne par colonne (seules les clés
--     présentes changent) ;
--   - réglages de l'appareil (repos, son, rappels…) et recalcul des efforts :
--     déposés dans admin_push, appliqués par l'app du profil à sa prochaine
--     ouverture ;
--   - message (titre, texte) : déposé dans presentation, affiché une fois.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.user_settings add column if not exists admin_push jsonb;
alter table public.user_settings add column if not exists presentation jsonb;

create or replace function public.admin_push_settings(
    p_profile  uuid,
    p_settings jsonb default '{}',
    p_device   jsonb default '{}',
    p_message  jsonb default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
    s jsonb := coalesce(p_settings, '{}');
begin
    if not public.is_admin() then raise exception 'forbidden'; end if;
    if not exists (select 1 from public.profiles where id = p_profile) then
        raise exception 'not_found';
    end if;

    insert into public.user_settings (user_id) values (p_profile)
    on conflict (user_id) do nothing;

    update public.user_settings u set
        weight            = case when s ? 'weight' then (s->>'weight')::numeric else u.weight end,
        enable_charges    = case when s ? 'enable_charges' then (s->>'enable_charges')::boolean else u.enable_charges end,
        include_planche   = case when s ? 'include_planche' then (s->>'include_planche')::boolean else u.include_planche end,
        inactivity_days   = case when s ? 'inactivity_days' then (s->>'inactivity_days')::integer else u.inactivity_days end,
        nb_days_avg       = case when s ? 'nb_days_avg' then (s->>'nb_days_avg')::integer else u.nb_days_avg end,
        intensity_config  = case when s ? 'intensity_config' then s->'intensity_config' else u.intensity_config end,
        variantes_config  = case when s ? 'variantes_config' then s->'variantes_config' else u.variantes_config end,
        formes_config     = case when s ? 'formes_config' then s->'formes_config' else u.formes_config end,
        elastiques_config = case when s ? 'elastiques_config' then s->'elastiques_config' else u.elastiques_config end,
        tensions_config   = case when s ? 'tensions_config' then s->'tensions_config' else u.tensions_config end,
        ecartements_config = case when s ? 'ecartements_config' then s->'ecartements_config' else u.ecartements_config end,
        assistable_exercises = case when s ? 'assistable_exercises' then s->'assistable_exercises' else u.assistable_exercises end,
        admin_push = case when s <> '{}' or coalesce(p_device, '{}') <> '{}'
            then jsonb_build_object('id', gen_random_uuid(), 'at', now(),
                                    'device', coalesce(p_device, '{}'),
                                    'recalc', s <> '{}')
            else u.admin_push end,
        presentation = case when p_message is not null
            then p_message || jsonb_build_object('id', gen_random_uuid(), 'at', now())
            else u.presentation end,
        updated_at = now()
    where u.user_id = p_profile;
end $$;

revoke all on function public.admin_push_settings(uuid, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.admin_push_settings(uuid, jsonb, jsonb, jsonb) to authenticated;
