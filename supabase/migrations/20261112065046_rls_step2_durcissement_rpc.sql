-- Étape 2 (suite) : les RPC ne sont appelables qu'avec une session (anonyme ou non),
-- jamais sans session. Déjà appliquée sur le projet Sysiphe.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
revoke execute on function public.is_profile_member(uuid) from public, anon;
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.admin_export_perfs() from public, anon;
revoke execute on function public.claim_profile(uuid, text) from public, anon;
revoke execute on function public.create_profile(text, text) from public, anon;
revoke execute on function public.list_profiles() from public, anon;
revoke execute on function public.profile_role(uuid) from public, anon;
revoke execute on function public.set_profile_pin(uuid, text) from public, anon;
grant execute on function public.is_profile_member(uuid), public.is_admin(), public.admin_export_perfs(),
  public.claim_profile(uuid, text), public.create_profile(text, text), public.list_profiles(),
  public.profile_role(uuid), public.set_profile_pin(uuid, text) to authenticated;
revoke all on public.profile_members, public.pin_attempts from anon;
