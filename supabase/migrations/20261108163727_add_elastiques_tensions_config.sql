-- Récupérée de la production (supabase_migrations.schema_migrations), absente du dépôt jusqu'ici.
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS elastiques_config jsonb DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS tensions_config   jsonb DEFAULT NULL;
