import pandas as pd
from supabase import create_client

# Identifiants de connexion à ton projet Supabase
URL = "https://qzvfkscqcllfnoqywkwq.supabase.co"
KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6dmZrc2NxY2xsZm5vcXl3a3dxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2MzI5MjcsImV4cCI6MjA5NzIwODkyN30.JzcBS9-SDGLToN9YpdL1poRkkOdc8B67CZBcKiCyMTQ"

# Initialisation du client Supabase
supabase = create_client(URL, KEY)

# Chargement du fichier d'export
csv_filename = "2026-06-16T18-15_export.csv"

print(f"Chargement du fichier {csv_filename}...")
try:
    df = pd.read_csv(csv_filename)
except FileNotFoundError:
    print(f"Erreur : Le fichier '{csv_filename}' n'a pas été trouvé. Place-le dans le même dossier que ce script.")
    exit()

# Transformation et nettoyage des données pour correspondre à la table PostgreSQL
records = []
for _, row in df.iterrows():
    records.append({
        # Identifiant temporaire en attendant la liaison définitive avec les comptes Google
        "user_id": "00000000-0000-0000-0000-000000000000", 
        "date": row['Date'],
        "exercice": "Planche", 
        "performance": row['Temps (s)'],
        "variante": row['Variante'],
        "elastique": row['Élastique'],
        "tension": row['Tension'],
        "categorie": "Force Iso"
    })

# Envoi des lignes par paquets de 100 pour garantir la stabilité du transfert cloud
print(f"Début de la migration de {len(records)} lignes vers le Cloud...")
batch_size = 100

for i in range(0, len(records), batch_size):
    batch = records[i:i+batch_size]
    try:
        supabase.table("perfs").insert(batch).execute()
        print(f"Lignes {i} à {min(i + batch_size, len(records))} envoyées avec succès.")
    except Exception as e:
        print(f"Une erreur est survenue lors du transfert du paquet {i} : {e}")
        break

print("\nFélicitations, la migration est terminée ! Ton historique est en sécurité dans le Cloud.")