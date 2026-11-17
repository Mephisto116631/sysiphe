-- À appliquer à la main (Supabase → SQL Editor), après une sauvegarde : voir supabase/a_appliquer/README.md.
-- Une fois appliqué, déplacer ce fichier dans supabase/migrations/ avec la version donnée par Supabase.
--
-- 1) user_settings.user_id référençait auth.users (comptes de connexion) au lieu de profiles :
--    « Dilbert 🐶 » et « Profil 3 » ne pouvaient pas enregistrer leurs réglages (clé étrangère violée).
-- 2) Une seule série porte la catégorie « Force isométrique  » (avec espace final) : ramenée à « Force Iso ».
--    « Gainage » est gardé : ce sont les abdos tenus en secondes (avant juillet), distincts des abdos en reps.
--
-- Tout se fait dans une transaction : la moindre erreur annule tout, rien n'est modifié.

begin;

-- Réglages rattachés à un ancien compte de connexion, et non à un profil : inaccessibles
-- depuis la mise en place de la RLS (aucun appareil n'y est rattaché). Ils sont supprimés.
delete from public.user_settings s
where not exists (select 1 from public.profiles p where p.id = s.user_id);

alter table public.user_settings drop constraint if exists user_settings_user_id_fkey;
alter table public.user_settings
  add constraint user_settings_user_id_fkey
  foreign key (user_id) references public.profiles(id) on delete cascade;

update public.perfs set categorie = 'Force Iso' where categorie = 'Force isométrique ';

-- Contrôles : si un résultat est inattendu, tout est annulé.
do $$
begin
  if (select pg_get_constraintdef(oid) from pg_constraint
      where conname = 'user_settings_user_id_fkey') not like '%profiles(id)%' then
    raise exception 'Clé étrangère non modifiée';
  end if;
  if exists (select 1 from public.perfs where categorie = 'Force isométrique ') then
    raise exception 'Catégorie non harmonisée';
  end if;
end $$;

commit;

-- Résultat attendu (à relancer seul pour vérifier) :
--   select pg_get_constraintdef(oid) from pg_constraint where conname = 'user_settings_user_id_fkey';
--     → FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
--   select categorie, count(*) from perfs group by 1 order by 1;
--     → Force Iso 791 · Gainage 143 · Musculation 381
