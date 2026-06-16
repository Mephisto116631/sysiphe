import duckdb
import pandas as pd

print("⏳ Lecture du fichier CSV...")
df = pd.read_csv("historique.csv")

# 1. Renommer les colonnes pour matcher avec Sysiphe
df = df.rename(columns={
    "Date": "date",
    "Exercice": "exercice",
    "Série": "serie",
    "Performance": "performance",
    "Variante": "variante",
    "Élastique": "elastique",
    "Tension": "tension",
    "Forme": "forme",
    "Temps Pondéré": "effort_pondere",
    "Catégorie": "categorie",
    "Unité": "unite"
})

# 2. Nettoyage des formats
print("🧹 Nettoyage des données...")
# Forcer le format date
df['date'] = pd.to_datetime(df['date'], dayfirst=True).dt.date

# Extraire uniquement le chiffre de la colonne série (ex: "Serie 1" -> 1)
df['serie'] = df['serie'].astype(str).str.extract(r'(\d+)').astype(int)

# Combler les cases vides pour éviter les erreurs SQL
df['variante'] = df['variante'].fillna("")
df['elastique'] = df['elastique'].fillna("")
df['tension'] = df['tension'].fillna("")
df['forme'] = df['forme'].fillna("")
df['effort_pondere'] = df['effort_pondere'].fillna(0.0)

# Réorganiser l'ordre exact des colonnes pour DuckDB
df = df[["date", "exercice", "serie", "performance", "variante", "elastique", "tension", "forme", "effort_pondere", "categorie", "unite"]]

# 3. Injection dans la base de données locale
print("💾 Injection dans Sysiphe.db...")
con = duckdb.connect("sysiphe.db")

# Écriture de tout le dataframe d'un coup
con.execute("INSERT INTO perfs SELECT * FROM df")

print(f"✅ Migration terminée ! {len(df)} lignes ont été ajoutées avec succès.")