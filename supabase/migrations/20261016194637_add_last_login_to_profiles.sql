-- Récupérée de la production (supabase_migrations.schema_migrations), absente du dépôt jusqu'ici.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_login timestamptz;
