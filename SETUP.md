# Sysiphe v15 — Setup base de données

Trois changements côté Supabase sont nécessaires avant de déployer cette version.
Va dans **Supabase Dashboard → SQL Editor** et exécute les requêtes ci-dessous.

---

## 1. Nouvelle colonne `charge` sur la table `perfs`

Permet de suivre une charge externe (kg) pour les exercices lestés (tractions lestées, dips lestés...).

```sql
ALTER TABLE perfs ADD COLUMN IF NOT EXISTS charge NUMERIC DEFAULT 0;
```

Sans danger : les lignes existantes prennent `charge = 0`, donc rien ne change pour ton historique actuel.

---

## 2. Nouvelle table `user_settings` (persistance de la calibration)

Permet de sauvegarder durablement les scores de variantes planche (au lieu de les perdre à chaque refresh).

```sql
CREATE TABLE IF NOT EXISTS user_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    variantes_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ DEFAULT now()
);
```

Si cette table n'est pas créée, l'app fonctionne quand même : `load_user_settings` retombe
silencieusement sur les valeurs par défaut, et `save_user_settings` affiche juste un avertissement.

---

## 3. Row Level Security (RLS) — ⚠️ IMPORTANT

Sans RLS, n'importe qui en possession de ta clé `anon` (visible côté client) peut lire/écrire
les données de **tous** les utilisateurs de l'app, pas seulement les siennes.

```sql
-- Table perfs
ALTER TABLE perfs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own perfs"
ON perfs FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Table user_settings
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own settings"
ON user_settings FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
```

Vérifie ensuite dans **Authentication → Policies** que ces deux policies apparaissent comme actives.

---

## 4. Dépendances Python

Inchangées — `requirements.txt` reste :
```
streamlit
pandas
plotly
supabase
```
L'export `.ics` (rappel calendrier) est généré manuellement, sans librairie externe.

---

## 5. Lancer les tests

Les fonctions pures de `data.py` sont couvertes par `test_data.py` (24 tests, aucune connexion réseau requise) :

```bash
pip install pytest pandas numpy
pytest test_data.py -v
```
