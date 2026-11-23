-- ═══════════════════════════════════════════════════════════════════════════
-- v2.17 — mode hors ligne. Additif, aucune donnée modifiée.
-- Chaque série reçoit un identifiant créé sur le téléphone (client_id) : si
-- un envoi aboutit mais que la réponse se perd (réseau coupé), le renvoi de la
-- même série est ignoré (INSERT … ON CONFLICT (client_id) DO NOTHING) au lieu
-- de créer un doublon. Les séries existantes gardent client_id = null (les
-- valeurs nulles ne se gênent pas entre elles dans un index unique).
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.perfs add column if not exists client_id uuid;
create unique index if not exists perfs_client_id_key on public.perfs (client_id);
