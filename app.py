import streamlit as st
import pandas as pd
from supabase import create_client, Client

# ==========================================
# 1. CONNEXION AU CLOUD (SUPABASE)
# ==========================================
# @st.cache_resource permet de ne pas relancer la connexion à chaque clic
@st.cache_resource
def init_connection():
    # Streamlit ira chercher tes clés secrètes en ligne en toute sécurité
    url = st.secrets["SUPABASE_URL"]
    key = st.secrets["SUPABASE_KEY"]
    return create_client(url, key)

supabase = init_connection()

# ==========================================
# 2. INTERFACE UTILISATEUR
# ==========================================
st.set_page_config(page_title="Sysiphe - Calisthenics", page_icon="💪")
st.title("Sysiphe - Suivi d'Entraînement")

st.write("Bienvenue sur ta nouvelle application hébergée dans le Cloud ! ☁️")

# --- Formulaire d'ajout ---
st.subheader("Nouvelle Séance")
with st.form("ajout_perf"):
    col1, col2 = st.columns(2)
    with col1:
        date_seance = st.date_input("Date")
        temps_s = st.number_input("Temps (secondes)", min_value=0, step=1)
        variante = st.selectbox("Variante", ["Tuck", "Advanced Tuck", "Straddle", "Full"])
    with col2:
        elastique = st.selectbox("Élastique", ["Aucun", "Léger", "Moyen", "Fort"])
        tension = st.selectbox("Tension", ["Haute", "Moyenne", "Basse"])
    
    soumis = st.form_submit_button("Enregistrer la performance")

    if soumis:
        # Envoi de la nouvelle ligne vers Supabase
        nouvelle_ligne = {
            "user_id": "00000000-0000-0000-0000-000000000000", # En attendant Google Auth complet
            "date": str(date_seance),
            "exercice": "Planche",
            "performance": temps_s,
            "variante": variante,
            "elastique": elastique,
            "tension": tension,
            "categorie": "Force Iso"
        }
        supabase.table("perfs").insert(nouvelle_ligne).execute()
        st.success("Performance enregistrée avec succès dans le Cloud !")
        st.rerun() # Rafraîchit l'affichage

# --- Affichage de l'historique ---
st.subheader("Historique de tes performances")
try:
    # On télécharge les données depuis Supabase
    reponse = supabase.table("perfs").select("*").order("date", desc=True).execute()
    
    if reponse.data:
        df = pd.DataFrame(reponse.data)
        # On cache l'ID technique pour l'affichage
        df_a_afficher = df.drop(columns=["id", "user_id"])
        st.dataframe(df_a_afficher, use_container_width=True)
    else:
        st.info("Aucune donnée trouvée. Fais ton premier enregistrement !")
        
except Exception as e:
    st.error(f"Impossible de récupérer les données : {e}")
    st.info("Rappel : As-tu bien configuré tes st.secrets en local ou sur Streamlit Cloud ?")