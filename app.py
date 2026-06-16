import streamlit as st
import pandas as pd
import plotly.express as px
from supabase import create_client

# ==========================================
# 1. CONFIGURATION DE LA PAGE & STYLE
# ==========================================
st.set_page_config(page_title="Sysiphe - Calisthenics Dashboard", page_icon="💪", layout="wide")

# Style CSS personnalisé pour épurer l'interface
st.markdown("""
    <style>
    .main { background-color: #f8f9fa; }
    .stMetric { background-color: #ffffff; padding: 15px; border-radius: 10px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }
    </style>
""", unsafe_index=True)

# ==========================================
# 2. CONNEXION SUPABASE & CHARGEMENT
# ==========================================
@st.cache_resource
def init_connection():
    return create_client(st.secrets["SUPABASE_URL"], st.secrets["SUPABASE_KEY"])

supabase = init_connection()

def load_data():
    try:
        # Récupération des données triées par date
        reponse = supabase.table("perfs").select("*").order("date", desc=False).execute()
        if reponse.data:
            df = pd.DataFrame(reponse.data)
            df['date'] = pd.to_datetime(df['date'])
            # Tri chronologique pour les graphiques
            return df.sort_values('date')
        return pd.DataFrame()
    except Exception as e:
        st.error(f"Erreur de connexion à la base de données : {e}")
        return pd.DataFrame()

df = load_data()

# ==========================================
# 3. BARRE LATÉRALE (SIDEBAR) & FILTRES
# ==========================================
st.sidebar.title("Configuration")
st.sidebar.write("Application connectée au Cloud Supabase ☁️")

if not df.empty:
    variantes_disponibles = ["Toutes"] + sorted(df['variante'].unique().tolist())
    variante_filtre = st.sidebar.selectbox("Filtrer par variante", variantes_disponibles)
    
    if variante_filtre != "Toutes":
        df_filtre = df[df['variante'] == variante_filtre]
    else:
        df_filtre = df
else:
    df_filtre = df

# ==========================================
# 4. EN-TÊTE & STATISTIQUES (KPIs)
# ==========================================
st.title("Sysiphe — Suivi d'Entraînement")
st.markdown("---")

if not df_filtre.empty:
    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Séances Totales", len(df_filtre))
    with col2:
        st.metric("Temps Max (s)", f"{df_filtre['performance'].max()}s")
    with col3:
        st.metric("Moyenne (s)", f"{round(df_filtre['performance'].mean(), 1)}s")
    with col4:
        derniere_date = df_filtre['date'].max().strftime('%d/%m/%Y')
        st.metric("Dernière Séance", derniere_date)

# ==========================================
# 5. GRAPHISMES ET VISUALISATION
# ==========================================
st.subheader("Progression des Performances")

if not df_filtre.empty:
    # Graphique interactif temporel
    fig = px.line(
        df_filtre, 
        x='date', 
        y='performance', 
        color='variante',
        markers=True,
        labels={"date": "Date", "performance": "Temps de maintien (s)", "variante": "Variante"},
        template="plotly_white"
    )
    fig.update_layout(margin=dict(l=20, r=20, t=20, b=20))
    st.plotly_chart(fig, use_container_width=True)
else:
    st.info("Ajoute des séances ou vérifie la configuration de ta base de données pour générer les graphiques.")

st.markdown("---")

# ==========================================
# 6. ENREGISTREMENT & HISTORIQUE (2 COLONNES)
# ==========================================
col_form, col_table = st.columns([1, 2])

with col_form:
    st.subheader("Nouvelle Séance")
    with st.form("ajout_perf", clear_on_submit=True):
        date_seance = st.date_input("Date")
        temps_s = st.number_input("Temps (secondes)", min_value=0, step=1)
        variante = st.selectbox("Variante", ["Tuck", "Advanced Tuck", "Straddle", "Full"])
        elastique = st.selectbox("Élastique", ["Aucun", "Léger", "Moyen", "Fort"])
        tension = st.selectbox("Tension", ["Haute", "Moyenne", "Basse"])
        
        soumis = st.form_submit_button("Enregistrer la performance")

        if soumis:
            nouvelle_ligne = {
                "user_id": "00000000-0000-0000-0000-000000000000",
                "date": str(date_seance),
                "exercice": "Planche",
                "performance": temps_s,
                "variante": variante,
                "elastique": elastique,
                "tension": tension,
                "categorie": "Force Iso"
            }
            try:
                supabase.table("perfs").insert(nouvelle_ligne).execute()
                st.success("Données synchronisées !")
                st.rerun()
            except Exception as e:
                st.error(f"Erreur d'envoi : {e}")

with col_table:
    st.subheader("Historique des Séances")
    if not df.empty:
        # Inversion pour voir les plus récentes en haut du tableau
        df_affichage = df.copy().sort_values('date', ascending=False)
        df_affichage['date'] = df_affichage['date'].dt.strftime('%d/%m/%Y')
        st.dataframe(
            df_affichage.drop(columns=["id", "user_id"], errors='ignore'), 
            use_container_width=True,
            height=300
        )
    else:
        st.info("Aucune donnée disponible pour le moment.")