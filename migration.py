import csv
import math
from supabase import create_client

# Identifiants Supabase
URL = "https://qzvfkscqcllfnoqywkwq.supabase.co"
KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6dmZrc2NxY2xsZm5vcXl3a3dxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2MzI5MjcsImV4cCI6MjA5NzIwODkyN30.JzcBS9-SDGLToN9YpdL1poRkkOdc8B67CZBcKiCyMTQ"

supabase = create_client(URL, KEY)
fichier_csv = "2026-06-16T18-15_export.csv"

print(f"Ouverture chirurgicale du fichier {fichier_csv}...")

records = []

try:
    # Lecture brute du fichier texte (gère les accents et caractères spéciaux)
    with open(fichier_csv, mode='r', encoding='utf-8-sig') as f:
        # Détection automatique du séparateur (virgule ou point-virgule)
        premiere_ligne = f.readline()
        separateur = ';' if ';' in premiere_ligne else ','
        f.seek(0) # Retour au début du fichier

        reader = csv.DictReader(f, delimiter=separateur)
        
        for row in reader:
            # Nettoyage des noms de colonnes invisibles (espaces)
            row = {k.strip(): str(v).strip() for k, v in row.items() if k}
            
            # 1. La Date (si elle est vide, c'est une ligne blanche, on saute)
            date_val = row.get('Date', '')
            if not date_val: 
                continue

            # 2. Le Temps (Sécurisation maximale des virgules françaises et cases vides)
            temps_str = row.get('Temps (s)', '0').replace(',', '.')
            if temps_str == "" or temps_str.lower() == "nan":
                temps = 0.0
            else:
                try:
                    temps = float(temps_str)
                    if math.isnan(temps): temps = 0.0
                except ValueError:
                    temps = 0.0

            # 3. La Variante
            variante = row.get('Variante', '').replace('Advanced Tuck', 'Adv_Tuck').replace('Half Lay', 'Half_Lay')
            if not variante: variante = "Tuck"
            
            # 4. Élastique et Tension
            elastique = row.get('Élastique', '')
            if not elastique: elastique = "Aucun"
            
            tension = row.get('Tension', '')
            if not tension: tension = "N/A"

            # Création de la ligne finale propre
            records.append({
                "user_id": "00000000-0000-0000-0000-000000000000",
                "date": date_val,
                "exercice": "Planche",
                "serie": 1,
                "performance": temps,
                "variante": variante,
                "elastique": elastique,
                "tension": tension,
                "forme": "Normal",
                "effort_pondere": 0.0,
                "categorie": "Force Iso",
                "unite": "Sec"
            })
            
except FileNotFoundError:
    print(f"❌ Erreur : Fichier introuvable. Assure-toi que {fichier_csv} est bien là.")
    exit()

print(f"✅ Fichier lu avec succès : {len(records)} lignes trouvées !")

if len(records) > 0:
    print("Début de l'envoi vers le Cloud Supabase...")
    for i in range(0, len(records), 100):
        batch = records[i:i+100]
        try:
            supabase.table("perfs").insert(batch).execute()
            print(f"➡️ Paquet expédié : Lignes {i} à {min(i+100, len(records))}")
        except Exception as e:
            print(f"❌ Erreur lors du transfert du paquet : {e}")
            break
    print("🚀 Migration terminée avec succès !")
else:
    print("⚠️ Le fichier semblait vide ou illisible.")