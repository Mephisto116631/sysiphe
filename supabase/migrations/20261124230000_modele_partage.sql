-- ═══════════════════════════════════════════════════════════════════════════
-- Modèle de la planche unique (v2.22.0) : les coefficients de l'effort
-- (variantes, formes, élastiques, tensions) sont ceux de l'admin, pour tous
-- les profils. Chaque profil garde seulement son poids.
--
-- app_config : réglages communs à toute l'app (une ligne par clé), lisibles
-- par tous les appareils connectés, modifiables par l'admin seulement
-- (admin_set_config). updated_at sert de version : quand il change, chaque
-- app recalcule les efforts de son profil à l'ouverture.
-- Additive : une table et une fonction. Le modèle de départ est celui de
-- l'admin (ses coefficients actuels).
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.app_config (
    key        text primary key,
    value      jsonb not null,
    updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;
revoke all on public.app_config from anon;
revoke all on public.app_config from authenticated;
grant select on public.app_config to authenticated;
drop policy if exists app_config_lecture on public.app_config;
create policy app_config_lecture on public.app_config for select to authenticated
  using (true);

create or replace function public.admin_set_config(p_key text, p_value jsonb)
returns void language plpgsql security definer set search_path = '' as $$
begin
    if not public.is_admin() then raise exception 'forbidden'; end if;
    insert into public.app_config (key, value, updated_at)
    values (p_key, p_value, now())
    on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;

revoke all on function public.admin_set_config(text, jsonb) from public, anon;
grant execute on function public.admin_set_config(text, jsonb) to authenticated;

-- Modèle de départ : les coefficients actuels de l'admin.
insert into public.app_config (key, value)
select 'effort_model', jsonb_strip_nulls(jsonb_build_object(
        'variantes_config', s.variantes_config,
        'formes_config', s.formes_config,
        'elastiques_config', s.elastiques_config,
        'tensions_config', s.tensions_config))
from public.user_settings s
join public.profiles p on p.id = s.user_id
where p.role = 'admin'
order by s.updated_at desc nulls last
limit 1
on conflict (key) do nothing;
