import streamlit as st
import pandas as pd
from datetime import datetime, timedelta
import plotly.express as px
from supabase import create_client

# =========================================================================
# 0. CONFIGURATION & CONNEXION CLOUD
# =========================================================================
st.set_page_config(page_title="Sysiphe v13 Cloud", layout="wide")

@st.cache_resource
def init_connection():
    return create_client(st.secrets["SUPABASE_URL"], st.secrets["SUPABASE_KEY"])

supabase = init_connection()

# Initialisation des variables de session et des paramètres dynamiques
if 'user' not in st.session_state:
    st.session_state.user = None
if 'date_seance' not in st.session_state:
    st.session_state.date_seance = datetime.now().date()
if 'weight' not in st.session_state:
    st.session_state.weight = 97
if 'nb_days_avg' not in st.session_state:
    st.session_state.nb_days_avg = 5
if 'include_planche' not in st.session_state:
    st.session_state.include_planche = True

# --- RECONNAISSANCE AUTOMATIQUE DE L'APPAREIL (MÉMORISATION) ---
def restore_session():
    if st.session_state.user is None:
        try:
            session = supabase.auth.get_session()
            if session and session.user:
                st.session_state.user = session.user
        except Exception:
            pass

restore_session()

# =========================================================================
# 🔐 SYSTÈME D'AUTHENTIFICATION SÉCURISÉ (AVEC GOOGLE OAUTH PKCE)
# =========================================================================
def check_oauth_callback():
    if "code" in st.query_params:
        try:
            code = st.query_params["code"]
            res = supabase.auth.exchange_code_for_session({"auth_code": code})
            if res.user:
                st.session_state.user = res.user
            st.query_params.clear()
        except Exception as e:
            st.error(f"Erreur de validation du ticket de connexion : {e}")

check_oauth_callback()

if st.session_state.user is None:
    st.title("🔐 Accès Sécurisé Sysiphe")
    st.markdown("Connecte-toi pour accéder à ton tableau de bord personnel.")
    
    col_auth1, col_auth2, col_auth3 = st.columns([1, 2, 1])
    with col_auth2:
        res = supabase.auth.sign_in_with_oauth({
            "provider": "google",
            "options": {
                "redirect_to": "https://sysiphe-voseesdgwwcstfepbdepkh.streamlit.app/"
            }
        })
        st.link_button("🔵 Se connecter avec Google", url=res.url, type="primary", use_container_width=True)
        
        st.markdown("<div style='text-align: center; margin: 15px 0;'>— OU —</div>", unsafe_allow_html=True)
        
        choix = st.radio("Connexion classique :", ["Se connecter", "Créer un compte"], horizontal=True)
        email = st.text_input("Adresse Email")
        password = st.text_input("Mot de passe", type="password")
        
        if st.button("Valider l'Email", use_container_width=True):
            if choix == "Créer un compte":
                try:
                    supabase.auth.sign_up({"email": email, "password": password})
                    st.success("✅ Compte créé avec succès ! Tu peux te connecter.")
                except Exception as e:
                    st.error(f"Erreur : {e}")
            else:
                try:
                    response = supabase.auth.sign_in_with_password({"email": email, "password": password})
                    st.session_state.user = response.user
                    st.rerun()
                except Exception as e:
                    st.error("❌ Email ou mot de passe incorrect.")
    st.stop()

# =========================================================================
# 👤 UTILISATEUR CONNECTÉ : ISOLATION STRICTE DES DONNÉES
# =========================================================================
USER_ID = st.session_state.user.id

with st.sidebar:
    st.caption(f"Connecté : {st.session_state.user.email}")
    if st.button("🚪 Se déconnecter", use_container_width=True):
        supabase.auth.sign_out()
        st.session_state.user = None
        st.cache_data.clear()
        st.rerun()
    st.markdown("---")

CONFIG = {
    "elastiques": {"Aucun": 0, "Rouge/Violet": 35, "Jaune+Bleu": 40, "Jaune": 25, "Bleu": 15, "Vert": 45},
    "tensions": {"N/A": 0.70, "Ecarté": 0.85, "Normal": 0.70, "Serré": 0.60},
    "variantes": {"Full": 10, "Straddle": 9, "Half_Lay": 9, "Diamond": 5, "Maltese": 11, "Tuck": 2, "Adv_Tuck": 3},
    "formes": {"Normal": 47.6, "High": 34, "Bas": 66.64, "Dead": 93.296}
}

def calculer_effort(variante, elastique, tension, forme, temps):
    try:
        force_e = CONFIG["elastiques"].get(elastique, 0)
        ratio_t = CONFIG["tensions"].get(tension, 0.70)
        score_v = CONFIG["variantes"].get(variante, 0)
        score_f = CONFIG["formes"].get(forme, 0)
        if score_v == 0 or score_f == 0 or not temps: return 0.0
        kg_traction = force_e * ratio_t
        poids_eff = st.session_state.weight - kg_traction
        facteur_e = (poids_eff / 100) ** 2
        facteur_m = (score_v * score_f) ** 1.2
        return round((float(temps) * facteur_e * facteur_m) / 100, 2)
    except: return 0.0

@st.cache_data(ttl=60)
def load_data(uid, current_weight):
    reponse = supabase.table("perfs").select("*").eq("user_id", uid).execute()
    if reponse.data:
        df = pd.DataFrame(reponse.data)
        df['date'] = pd.to_datetime(df['date']).dt.date
        
        for col in ['serie', 'forme', 'effort_pondere', 'unite']:
            if col not in df.columns:
                df[col] = None
                
        df['serie'] = df['serie'].fillna(1).astype(int)
        
        df['exercice'] = df['exercice'].astype(str).str.strip()
        df['forme'] = df['forme'].astype(str).str.strip().replace({'': 'Normal', 'nan': 'Normal', 'None': 'Normal'})
        df['unite'] = df['unite'].astype(str).str.strip().replace({'': 'Sec', 'nan': 'Sec', 'None': 'Sec'})
        df['elastique'] = df['elastique'].astype(str).str.strip().replace({'': 'Aucun', 'nan': 'Aucun', 'None': 'Aucun'})
        df['tension'] = df['tension'].astype(str).str.strip().replace({'': 'N/A', 'nan': 'N/A', 'None': 'N/A'})
        df['variante'] = df['variante'].astype(str).str.strip().replace({'Advanced Tuck': 'Adv_Tuck', 'Half Lay': 'Half_Lay', '': 'Tuck', 'nan': 'Tuck', 'None': 'Tuck'})
        
        df.loc[df['categorie'].str.lower().str.strip().isin(['force iso', 'force isometrique', 'statique']), 'categorie'] = 'Force Iso'
        df.loc[df['categorie'].str.lower().str.strip().isin(['force', 'musculation', '']), 'categorie'] = 'Musculation'
        df['categorie'].fillna('Musculation', inplace=True)
        
        df['effort_pondere'] = df.apply(
            lambda r: float(calculer_effort(r['variante'], r['elastique'], r['tension'], r['forme'], r['performance'])) if r['exercice'].lower() == 'planche' else 0.0,
            axis=1
        )
        return df
    return pd.DataFrame()

df_global = load_data(USER_ID, st.session_state.weight)

def lisser_donnees(df, index_col, columns_col, values_col, fill_zero=False):
    if df.empty: return pd.DataFrame()
    df[index_col] = pd.to_datetime(df[index_col])
    pivot = df.pivot_table(index=index_col, columns=columns_col, values=values_col, aggfunc='max')
    if len(pivot) > 1:
        idx = pd.date_range(pivot.index.min(), pivot.index.max(), name=index_col)
        pivot = pivot.reindex(idx)
        if fill_zero: 
            pivot = pivot.fillna(0)
        else: 
            pivot = pivot.interpolate(method='linear', limit_direction='both')
    return pivot

# =========================================================================
# 1. NAVIGATION PAR MINI-CALENDRIER (BARRE LATÉRALE)
# =========================================================================
st.title("🪨 Sysiphe v13 (Cloud)")

with st.sidebar:
    st.header("📅 Navigation")
    
    date_active = st.date_input("Choisir une date", st.session_state.date_seance, key="date_picker")
    if date_active != st.session_state.date_seance:
        st.session_state.date_seance = date_active
        st.rerun()

    # --- VISUALISATION DES JOURS ENTRAÎNÉS (PASTILLES) ---
    if not df_global.empty:
        st.write("") 
        
        dates_entrainees = set(df_global['date'].unique())
        mois_courant = date_active.month
        annee_courante = date_active.year
        
        jours_entraines = sorted([
            d.day for d in dates_entrainees 
            if d.month == mois_courant and d.year == annee_courante
        ])
        
        if jours_entraines:
            st.markdown(f"**🎯 {len(jours_entraines)} séance(s) ce mois-ci :**")
            pastilles_html = " ".join([f"<span style='background-color: #2e7d32; color: white; padding: 2px 8px; border-radius: 10px; font-size: 14px; font-weight: bold;'>{j}</span>" for j in jours_entraines])
            st.markdown(pastilles_html, unsafe_allow_html=True)
        else:
            st.caption("ℹ️ Aucune séance enregistrée pour ce mois.")
            
    st.markdown("---")
    
    if st.button("🗑️ Supprimer cette séance", type="secondary", use_container_width=True):
        supabase.table("perfs").delete().eq("user_id", USER_ID).eq("date", str(date_active)).execute()
        st.cache_data.clear()
        st.session_state.exos_du_jour = []
        st.toast(f"Séance du {date_active.strftime('%d/%m/%Y')} supprimée", icon="🗑️")
        st.session_state.date_seance = datetime.now().date()
        st.rerun()

# =========================================================================
# --- GESTION INTELLIGENTE DU CHANGEMENT DE DATE & DES EXERCICES ---
# =========================================================================
if 'last_seen_date' not in st.session_state or st.session_state.last_seen_date != date_active:
    st.session_state.last_seen_date = date_active
    
    if not df_global.empty:
        df_today = df_global[df_global['date'] == date_active]
        if not df_today.empty:
            st.session_state.exos_du_jour = df_today[df_today['exercice'].str.lower() != 'planche']['exercice'].unique().tolist()
        else:
            dates_passees = df_global[df_global['date'] < date_active]['date']
            if not dates_passees.empty:
                derniere_date = dates_passees.max()
                df_last = df_global[df_global['date'] == derniere_date]
                st.session_state.exos_du_jour = df_last[df_last['exercice'].str.lower() != 'planche']['exercice'].unique().tolist()
            else:
                st.session_state.exos_du_jour = []
    else:
        st.session_state.exos_du_jour = []

default_var, default_elas, default_tens = "Full", "Aucun", "N/A"
default_forms, default_times = {i: "Normal" for i in range(1, 6)}, {i: "" for i in range(1, 6)}

if not df_global.empty:
    df_planche_active = df_global[(df_global['date'] == date_active) & (df_global['exercice'].str.lower() == 'planche')]
    
    if not df_planche_active.empty:
        last_g = df_planche_active.iloc[0]
        default_var, default_elas, default_tens = last_g['variante'], last_g['elastique'], last_g['tension']
        for _, r in df_planche_active.iterrows():
            s = int(r['serie'])
            default_forms[s] = r['forme'] if pd.notna(r['forme']) else "Normal"
            default_times[s] = str(r['performance']) if pd.notna(r['performance']) else ""
    else:
        dates_passees_p = df_global[(df_global['date'] < date_active) & (df_global['exercice'].str.lower() == 'planche')]['date']
        if not dates_passees_p.empty:
            df_planche_past = df_global[(df_global['date'] == dates_passees_p.max()) & (df_global['exercice'].str.lower() == 'planche')]
            last_g = df_planche_past.iloc[0]
            default_var, default_elas, default_tens = last_g['variante'], last_g['elastique'], last_g['tension']
            for _, r in df_planche_past.iterrows():
                s = int(r['serie'])
                default_forms[s] = r['forme'] if pd.notna(r['forme']) else "Normal"

tous_les_exos = []
if not df_global.empty:
    tous_les_exos = sorted(df_global[df_global['exercice'].str.lower() != 'planche']['exercice'].unique().tolist())

# =========================================================================
# 2. INTERFACE DE SAISIE RÉACTIONNELLE EN LIGNE
# =========================================================================
col_saisie, col_vide = st.columns([2, 1])
with col_saisie:
    
    if st.session_state.include_planche:
        titre_planche = "🤸 PLANCHE"
        if not df_global.empty:
            df_p_historique = df_global[(df_global['exercice'].str.lower() == 'planche') & (df_global['effort_pondere'] > 0)]
            if not df_p_historique.empty:
                max_effort = df_p_historique['effort_pondere'].max()
                titre_planche = f"🤸 PLANCHE (Record : {max_effort:.1f} pts)"

        with st.expander(titre_planche, expanded=True):
            idx_v = list(CONFIG["variantes"].keys()).index(default_var) if default_var in CONFIG["variantes"] else 0
            idx_e = list(CONFIG["elastiques"].keys()).index(default_elas) if default_elas in CONFIG["elastiques"] else 0
            idx_t = list(CONFIG["tensions"].keys()).index(default_tens) if default_tens in CONFIG["tensions"] else 0
            
            c1, c2, c3 = st.columns(3)
            with c1: var_g = st.selectbox("Variante", list(CONFIG["variantes"].keys()), index=idx_v, key=f"var_g_{date_active}")
            with c2: elas_g = st.selectbox("Élastique", list(CONFIG["elastiques"].keys()), index=idx_e, key=f"elas_g_{date_active}")
            with c3: tens_g = st.selectbox("Tension", list(CONFIG["tensions"].keys()), index=idx_t, key=f"tens_g_{date_active}")
            
            st.write("---")
            formes_temp, temps_temp = {}, {}
            for s in range(1, 6):
                c1, c2, c3 = st.columns([1, 2, 1])
                with c1: t = st.text_input(f"S{s}(s)", value=default_times.get(s, ""), key=f"p_t_{s}_{date_active}")
                with c2: f = st.select_slider(f"F{s}", options=list(CONFIG["formes"].keys()), value=default_forms.get(s, "Normal"), key=f"p_f_{s}_{date_active}")
                with c3:
                    if t:
                        eff = calculer_effort(var_g, elas_g, tens_g, f, t)
                        st.metric("Effort", f"{eff}")
                    else: st.metric("Effort", "0.0")
                temps_temp[s] = t
                formes_temp[s] = f
                
            if st.button("💾 Enregistrer la Planche", type="primary", use_container_width=True):
                supabase.table("perfs").delete().eq("user_id", USER_ID).eq("date", str(date_active)).ilike("exercice", "planche").execute()
                lignes_a_inserer = []
                for s in range(1, 6):
                    t = temps_temp[s]
                    f = formes_temp[s]
                    if t:
                        eff = calculer_effort(var_g, elas_g, tens_g, f, t)
                        lignes_a_inserer.append({
                            "user_id": USER_ID,
                            "date": str(date_active), "exercice": "Planche", "serie": s, "performance": float(t),
                            "variante": var_g, "elastique": elas_g, "tension": tens_g, "forme": f,
                            "effort_pondere": eff, "categorie": "Force Iso", "unite": "Sec"
                        })
                if lignes_a_inserer:
                    supabase.table("perfs").insert(lignes_a_inserer).execute()
                    st.cache_data.clear()
                    st.success("Planche enregistrée !")
                    st.rerun()

    for nom_exo in list(st.session_state.exos_du_jour):
        titre_dynamique = f"💪 {nom_exo.upper()}"
        if not df_global.empty:
            df_historique_exo = df_global[df_global['exercice'].str.lower() == nom_exo.lower().strip()]
            if not df_historique_exo.empty:
                pr_absolu = int(df_historique_exo['performance'].max())
                total_par_seance = df_historique_exo.groupby('date')['performance'].sum().sort_index(ascending=False)
                window_size = int(st.session_state.nb_days_avg)
                volume_moyen_glissant = total_par_seance.head(window_size).mean()
                titre_dynamique = f"💪 {nom_exo.upper()} (PR : {pr_absolu} | Moy. {window_size} séances : {volume_moyen_glissant:.1f})"
            else:
                titre_dynamique = f"💪 {nom_exo.upper()} (Nouvel Exercice)"

        with st.expander(titre_dynamique, expanded=True):
            p_today = []
            cat_init = "Musculation"
            if not df_global.empty:
                df_exo_today = df_global[(df_global['date'] == date_active) & (df_global['exercice'].str.lower() == nom_exo.lower().strip())]
                if not df_exo_today.empty:
                    p_today = df_exo_today['performance'].tolist()
                    cat_init = df_exo_today.iloc[0]['categorie']
            
            val_init = " ".join([str(int(p) if float(p).is_integer() else p) for p in p_today if pd.notna(p)])
            c_input, c_m1, c_m2, c_btn = st.columns([2.5, 1, 1, 0.5])
            
            with c_input: 
                raw_input = st.text_input("Séries", value=val_init, key=f"perf_{nom_exo}_{date_active}", placeholder="ex: 12 10 8", label_visibility="collapsed")
                cat_exo = st.text_input("Catégorie", value=cat_init, key=f"cat_{nom_exo}_{date_active}", label_visibility="collapsed")
            
            total_reps, nb_series = 0, 0
            if raw_input:
                try:
                    liste_reps = [float(v) for v in raw_input.split()]
                    total_reps = int(sum(liste_reps))
                    nb_series = len(liste_reps)
                except ValueError: pass
            
            with c_m1: st.metric("Total Reps", f"{total_reps}")
            with c_m2: st.metric("Séries", f"{nb_series}")
                
            with c_btn:
                st.write("")
                if st.button("🗑️", key=f"rem_{nom_exo}_{date_active}", use_container_width=True):
                    st.session_state.exos_du_jour.remove(nom_exo)
                    supabase.table("perfs").delete().eq("user_id", USER_ID).eq("date", str(date_active)).ilike("exercice", nom_exo).execute()
                    st.cache_data.clear()
                    st.rerun()
            
            if st.button(f"Enregistrer {nom_exo}", key=f"save_{nom_exo}_{date_active}"):
                supabase.table("perfs").delete().eq("user_id", USER_ID).eq("date", str(date_active)).ilike("exercice", nom_exo).execute()
                if raw_input:
                    try:
                        lignes = []
                        for i, v in enumerate(raw_input.split()):
                            lignes.append({
                                "user_id": USER_ID,
                                "date": str(date_active), "exercice": nom_exo, "serie": i+1, "performance": float(v),
                                "variante": "", "elastique": "", "tension": "", "forme": "", "effort_pondere": 0.0,
                                "categorie": cat_exo, "unite": "Reps"
                            })
                        if lignes:
                            supabase.table("perfs").insert(lignes).execute()
                            st.cache_data.clear()
                            st.success(f"{nom_exo} sauvegardé !")
                            st.rerun()
                    except ValueError: pass

    col_sel, col_add = st.columns([3, 1])
    with col_sel:
        new_sel = st.selectbox("Exercices Habituels", ["--- Sélectionner ---"] + tous_les_exos)
        new_txt = st.text_input("...ou taper un nouvel exercice")
    with col_add:
        if st.button("➕ Ajouter", use_container_width=True):
            exo_ok = new_txt.strip() if new_txt else new_sel
            if exo_ok and exo_ok != "--- Sélectionner ---" and exo_ok not in st.session_state.exos_du_jour:
                st.session_state.exos_du_jour.append(exo_ok)
                st.rerun()

# =========================================================================
# 3. STATISTIQUES & GRAPHIQUES AVEC FILTRES DYNAMIQUES
# =========================================================================
st.write("---")
tab_graph, tab_records, tab_repos, tab_param = st.tabs(["📈 Graphiques", "🏆 Records (PRs)", "💤 Analyse du Repos", "⚙️ Paramètres"])

with tab_graph:
    if not df_global.empty:
        col_preset, col_custom = st.columns([1, 2])
        with col_preset:
            preset = st.selectbox("Période", ["Tout l'historique", "7 derniers jours", "30 derniers jours", "Ce mois", "3 derniers mois", "Personnalisée"])
        
        today = datetime.now().date()
        min_db_date = df_global['date'].min()
        max_db_date = df_global['date'].max()
        
        if preset == "7 derniers jours":
            start_date, end_date = today - timedelta(days=7), today
        elif preset == "30 derniers jours":
            start_date, end_date = today - timedelta(days=30), today
        elif preset == "Ce mois":
            start_date, end_date = today.replace(day=1), today
        elif preset == "3 derniers mois":
            start_date, end_date = today - timedelta(days=90), today
        elif preset == "Tout l'historique":
            start_date, end_date = min_db_date, max_db_date
        else:
            with col_custom:
                sel_dates = st.date_input("Période personnalisée", [min_db_date, max_db_date])
                if len(sel_dates) == 2:
                    start_date, end_date = sel_dates[0], sel_dates[1]
                else:
                    start_date, end_date = min_db_date, max_db_date

        df_period = df_global[(df_global['date'] >= start_date) & (df_global['date'] <= end_date)]
        
        if not df_period.empty:
            if st.session_state.include_planche:
                df_planche = df_period[df_period['exercice'].str.lower() == 'planche']
                if not df_planche.empty:
                    df_g_planche = df_planche.groupby(['date', 'variante'])['effort_pondere'].max().reset_index()
                    pivot_planche = lisser_donnees(df_g_planche, 'date', 'variante', 'effort_pondere')
                    if not pivot_planche.empty:
                        df_melt_p = pivot_planche.reset_index().melt(id_vars='date', var_name='Variante', value_name='Effort')
                        fig_p = px.line(df_melt_p, x='date', y='Effort', color='Variante')
                        fig_p.update_traces(connectgaps=True, hovertemplate='%{y:.1f} pts')
                        fig_p.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Effort Pondéré")
                        st.plotly_chart(fig_p, use_container_width=True)
            
            if tous_les_exos:
                select_exos = st.multiselect("Sélectionner les exercices", tous_les_exos, default=tous_les_exos[:3] if len(tous_les_exos)>=3 else tous_les_exos)
                if select_exos:
                    df_muscu = df_period[df_period['exercice'].str.lower().isin([e.lower().strip() for e in select_exos])]
                    if not df_muscu.empty:
                        df_g_muscu = df_muscu.groupby(['date', 'exercice'])['performance'].max().reset_index()
                        pivot_muscu = lisser_donnees(df_g_muscu, 'date', 'exercice', 'performance')
                        if not pivot_muscu.empty:
                            df_melt_m = pivot_muscu.reset_index().melt(id_vars='date', var_name='Exercice', value_name='Performance')
                            fig_m = px.line(df_melt_m, x='date', y='Performance', color='Exercice')
                            fig_m.update_traces(connectgaps=True, hovertemplate='%{y:.0f} Reps')
                            fig_m.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Répétitions")
                            st.plotly_chart(fig_m, use_container_width=True)

            df_g_cat = df_period.groupby(['date', 'categorie']).size().reset_index(name='nb_series')
            pivot_cat = lisser_donnees(df_g_cat, 'date', 'categorie', 'nb_series', fill_zero=True)
            if not pivot_cat.empty:
                df_melt_c = pivot_cat.reset_index().melt(id_vars='date', var_name='Catégorie', value_name='Séries')
                fig_c = px.line(df_melt_c, x='date', y='Séries', color='Catégorie')
                fig_c.update_traces(connectgaps=True, hovertemplate='%{y:.0f} Séries')
                fig_c.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Volume (Séries)")
                st.plotly_chart(fig_c, use_container_width=True)
        else:
            st.warning("Aucune donnée disponible pour cette période.")
    else:
        st.write("Pas de données pour les graphiques.")

with tab_records:
    c1, c2 = st.columns(2)
    if not df_global.empty:
        with c1:
            st.write("#### Record Planche")
            df_p = df_global[(df_global['exercice'].str.lower() == 'planche') & (df_global['effort_pondere'] > 0)].copy()
            if not df_p.empty:
                df_p['variante'] = df_p['variante'].fillna('Full').replace('', 'Full')
                df_p['elastique'] = df_p['elastique'].fillna('Aucun').replace('', 'Aucun')
                df_p['tension'] = df_p['tension'].fillna('N/A').replace('', 'N/A')
                df_p = df_p.sort_values(by=['effort_pondere', 'performance'], ascending=[False, False])
                df_pr_planche = df_p.drop_duplicates(subset=['variante', 'elastique', 'tension'])
                df_pr_planche = df_pr_planche[['date', 'variante', 'elastique', 'tension', 'performance', 'effort_pondere']]
                df_pr_planche.columns = ["Date", "Variante", "Élastique", "Tension", "Temps (s)", "Effort Absolu"]
                
                df_styled_planche = df_pr_planche.style.background_gradient(subset=["Effort Absolu", "Temps (s)"], cmap="YlOrRd")
                st.dataframe(df_styled_planche, use_container_width=True, hide_index=True)
            else:
                st.info("Aucun record de Planche enregistré.")
                
        with c2:
            st.write("#### 💪 Top Musculation (Reps Max)")
            df_m = df_global[df_global['exercice'].str.lower() != 'planche']
            if not df_m.empty:
                df_pr_muscu = df_m.groupby('exercice')['performance'].max().reset_index()
                df_pr_muscu.columns = ["Exercice", "Reps Max (1 série)"]
                df_pr_muscu = df_pr_muscu.sort_values('Reps Max (1 série)', ascending=False)
                
                df_styled_muscu = df_pr_muscu.style.background_gradient(subset=["Reps Max (1 série)"], cmap="Blues")
                st.dataframe(df_styled_muscu, use_container_width=True, hide_index=True)
            else:
                st.info("Aucun exercice de musculation enregistré.")

with tab_repos:
    st.subheader("💤 Analyse Mathématique de la Récupération")
    if not df_global.empty:
        df_all_dates = pd.DataFrame({'date': df_global['date'].unique()}).sort_values('date')
        if len(df_all_dates) > 1:
            df_all_dates['date_dt'] = pd.to_datetime(df_all_dates['date'])
            df_all_dates['jours_repos'] = df_all_dates['date_dt'].diff().dt.days - 1
            df_repos_stats = df_all_dates.dropna()
            
            cr1, cr2 = st.columns([1, 2])
            with cr1:
                st.metric("Moyenne de repos entre séances", f"{round(df_repos_stats['jours_repos'].mean(), 1)} jours")
                st.metric("Plus longue coupure de repos", f"{int(df_repos_stats['jours_repos'].max())} jours")
                habitudes = df_repos_stats['jours_repos'].value_counts().reset_index()
                habitudes.columns = ['Jours de repos', 'Nombre de fois']
                habitudes['Jours de repos'] = habitudes['Jours de repos'].astype(int).astype(str) + " jour(s)"
                fig_pie = px.pie(habitudes, values='Nombre de fois', names='Jours de repos', title="Répartition de tes formats de repos")
                st.plotly_chart(fig_pie, use_container_width=True)
                
            with cr2:
                fig_bar_repos = px.bar(df_repos_stats, x='date_dt', y='jours_repos', title="Chronologie des jours de repos accordés")
                fig_bar_repos.update_layout(xaxis_title="Fil du temps", yaxis_title="Nombre de jours de repos consécutifs")
                fig_bar_repos.update_traces(marker_color='#1f77b4', hovertemplate='Date de reprise : %{x}<br>Repos : %{y} jours')
                st.plotly_chart(fig_bar_repos, use_container_width=True)
                
                st.write("#### 📜 Dernières tranches de récupération")
                df_log_repos = df_repos_stats[['date', 'jours_repos']].copy()
                df_log_repos.columns = ['Date de Reprise', 'Jours de Repos Effectués']
                df_log_repos['Jours de Repos Effectués'] = df_log_repos['Jours de Repos Effectués'].astype(int)
                st.dataframe(df_log_repos.sort_values(by='Date de Reprise', ascending=False), use_container_width=True, hide_index=True)
        else:
            st.info("Ajoute au moins deux séances à des dates différentes pour générer l'analyse du repos.")

with tab_param:
    st.subheader("⚙️ Configuration Générale de l'Application")
    st.markdown("Ajuste ici les variables structurelles. Les changements modifient immédiatement les calculs d'isométrie et les filtres.")
    
    st.checkbox("Inclure la Planche dans l'interface de saisie", key="include_planche")
    
    st.write("---")
    st.number_input(
        "Taille de la moyenne glissante (Nombre de séances prises en compte)", 
        min_value=1, 
        max_value=30, 
        step=1, 
        key="nb_days_avg"
    )
    
    st.write("---")
    st.number_input(
        "Poids de référence actuel pour le calcul d'isométrie (kg)", 
        min_value=40, 
        max_value=200, 
        step=1, 
        key="weight"
    )