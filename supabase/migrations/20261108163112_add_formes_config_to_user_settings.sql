-- Récupérée de la production (supabase_migrations.schema_migrations), absente du dépôt jusqu'ici.
ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS formes_config jsonb DEFAULT NULL;
