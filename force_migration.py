import csv
import math
from datetime import datetime
from supabase import create_client

URL = "https://qzvfkscqcllfnoqywkwq.supabase.co"
KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF6dmZrc2NxY2xsZm5vcXl3a3dxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2MzI5MjcsImV4cCI6MjA5NzIwODkyN30.JzcBS9-SDGLToN9YpdL1poRkkOdc8B67CZBcKiCyMTQ"
supabase = create_client(URL, KEY)
fichier_csv = "2026-06-16T18-15_export.csv"

print("--- DÉMARRAGE DE LA LECTURE EXTRÊME ---")
records = []

try:
    with open(fichier_csv, mode='r', encoding='utf-8-sig') as f:
        lignes_brutes = f.read().splitlines()
        
    print(f"👉 Découpage forcé : {len(lignes_brutes)} lignes physiques trouvées.")
    
    if len(lignes_brutes) <= 1:
        print("\n❌ STOP ! Le fichier ne contient pas assez de données.")
        exit()

    en_tetes = lignes_brutes[0]
    separateur = ';' if ';' in en_tetes else ','
    
    lecteur = csv.DictReader(lignes_brutes, delimiter=separateur)
    
    for row in lecteur:
        row = {k.strip(): str(v).strip() for k, v in row.items() if k}
        
        date_brute = row.get('Date', '')
        if not date_brute: continue

        # --- CONVERSION DU FORMAT DE DATE POUR SUPABASE (PostgreSQL) ---
        try:
            # On isole la date si jamais il y a une heure attachée
            date_brute = date_brute.split()[0]
            if '/' in date_brute:
                date_obj = datetime.strptime(date_brute, "%d/%m/%Y")
            elif '-' in date_brute:
                parts = date_brute.split('-')
                if len(parts[0]) == 4: # Déjà au format international AAAA-MM-JJ
                    date_obj = datetime.strptime(date_brute, "%Y-%m-%d")
                else: # Format JJ-MM-AAAA
                    date_obj = datetime.strptime(date_brute, "%d-%m-%Y")
            else:
                raise ValueError
            date_val = date_obj.strftime("%Y-%m-%d") # Transformation en AAAA-MM-JJ
        except Exception:
            print(f"⚠️ Ligne ignorée - Date mal formatée : {date_brute}")
            continue

        temps_str = row.get('Temps (s)', '0').replace(',', '.')
        if temps_str == "" or temps_str.lower() == "nan": temps = 0.0
        else:
            try:
                temps = float(temps_str)
                if math.isnan(temps): temps = 0.0
            except ValueError:
                temps = 0.0

        variante = row.get('Variante', '').replace('Advanced Tuck', 'Adv_Tuck').replace('Half Lay', 'Half_Lay')
        if not variante: variante = "Tuck"
        
        elastique = row.get('Élastique', '')
        if not elastique: elastique = "Aucun"
        
        tension = row.get('Tension', '')
        if not tension: tension = "N/A"

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
    print(f"❌ Erreur : Fichier {fichier_csv} introuvable.")
    exit()

print(f"✅ {len(records)} données prêtes et converties pour le Cloud !")

if len(records) > 0:
    for i in range(0, len(records), 100):
        batch = records[i:i+100]
        try:
            supabase.table("perfs").insert(batch).execute()
            print(f"➡️ Paquet expédié : Lignes {i} à {min(i+100, len(records))}")
        except Exception as e:
            print(f"❌ Erreur d'envoi : {e}")
            break
    print("🚀 MIGRATION TERMINÉE AVEC SUCCÈS !")