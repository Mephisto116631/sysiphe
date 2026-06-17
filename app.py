import streamlit as st
import pandas as pd
from datetime import datetime
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

# --- DÉPLACEMENT DE LA CONFIGURATION POUR LE CALCUL RÉTROACTIF ---
CONFIG = {
    "poids_corporel": 97,
    "elastiques": {"Aucun": 0, "Rouge/Violet": 35, "Jaune+Bleu": 40, "Jaune": 25, "Bleu": 15, "Vert": 45},
    "tensions": {"N/A": 0.70, "Ecarté": 0.85, "Normal": 0.70, "Serré": 0.60},
    "variantes": {"Full": 10, "Straddle": 9, "Half_Lay": 9, "Diamond": 5, "Maltese": 11, "Tuck": 2, "Adv_Tuck": 3},
    "formes": {"Normal": 47.6, "High": 34, "Bas": 66.64, "Dead": 93.296}
}

MOIS_FR = {1: 'Janvier', 2: 'Février', 3: 'Mars', 4: 'Avril', 5: 'Mai', 6: 'Juin', 
           7: 'Juillet', 8: 'Août', 9: 'Septembre', 10: 'Octobre', 11: 'Novembre', 12: 'Décembre'}

def calculer_effort(variante, elastique, tension, forme, temps):
    try:
        force_e = CONFIG["elastiques"].get(elastique, 0)
        ratio_t = CONFIG["tensions"].get(tension, 0.70)
        score_v = CONFIG["variantes"].get(variante, 0)
        score_f = CONFIG["formes"].get(forme, 0)
        if score_v == 0 or score_f == 0 or not temps: return 0.0
        kg_traction = force_e * ratio_t
        poids_eff = CONFIG["poids_corporel"] - kg_traction
        facteur_e = (poids_eff / 100) ** 2
        facteur_m = (score_v * score_f) ** 1.2
        return round((float(temps) * facteur_e * facteur_m) / 100, 2)
    except: return 0.0

# --- MOTEUR D'AUTO-RÉPARATION DES DONNÉES HISTORIQUES ---
@st.cache_data(ttl=60)
def load_data():
    reponse = supabase.table("perfs").select("*").execute()
    if reponse.data:
        df = pd.DataFrame(reponse.data)
        df['date'] = pd.to_datetime(df['date']).dt.date
        
        # 1. Ajout des colonnes manquantes pour l'historique CSV
        for col in ['serie', 'forme', 'effort_pondere', 'unite']:
            if col not in df.columns:
                df[col] = None
                
        df['serie'] = df['serie'].fillna(1).astype(int)
        df['forme'] = df['forme'].fillna('Normal')
        df['unite'] = df['unite'].fillna('Sec')
        df['elastique'] = df['elastique'].fillna('Aucun').replace('', 'Aucun')
        df['tension'] = df['tension'].fillna('N/A').replace('', 'N/A')
        
        # 2. Nettoyage des variantes pour correspondre à la V13
        df['variante'] = df['variante'].replace({'Advanced Tuck': 'Adv_Tuck', 'Half Lay': 'Half_Lay'})
        df['variante'] = df['variante'].fillna('Tuck').replace('', 'Tuck')
        
        # 3. Nettoyage des anciennes catégories Sheets
        df.loc[df['categorie'].str.lower().str.strip().isin(['force iso', 'force isometrique', 'statique']), 'categorie'] = 'Force Iso'
        df.loc[df['categorie'].str.lower().str.strip().isin(['force', 'musculation', '']), 'categorie'] = 'Musculation'
        df['categorie'].fillna('Musculation', inplace=True)
        
      # 4. CALCUL RÉTROACTIF DE L'EFFORT POUR TES 1126 LIGNES
        # On force la colonne en décimal (float) dès le départ pour éviter le crash Pandas
        df['effort_pondere'] = pd.to_numeric(df['effort_pondere'], errors='coerce').fillna(0.0).astype(float)
        
        mask_recalc = (df['exercice'] == 'Planche') & (df['effort_pondere'] == 0.0)
        
        if mask_recalc.any():
            # On calcule et on force explicitement le format float sur les résultats
            efforts_calcules = df[mask_recalc].apply(
                lambda r: float(calculer_effort(r['variante'], r['elastique'], r['tension'], r['forme'], r['performance'])),
                axis=1
            )
            df.loc[mask_recalc, 'effort_pondere'] = efforts_calcules
        
        return df
    return pd.DataFrame()

df_global = load_data()

def lisser_donnees(df, index_col, columns_col, values_col, fill_zero=False):
    if df.empty: return pd.DataFrame()
    df[index_col] = pd.to_datetime(df[index_col])
    pivot = df.pivot(index=index_col, columns=columns_col, values=values_col)
    if len(pivot) > 1:
        idx = pd.date_range(pivot.index.min(), pivot.index.max(), name=index_col)
        pivot = pivot.reindex(idx)
        if fill_zero: pivot = pivot.fillna(0)
        else: pivot = pivot.interpolate(method='linear')
    return pivot

# =========================================================================
# 1. GESTION DE LA BARRE LATÉRALE (NAVIGATION & SUPPRESSION)
# =========================================================================
st.title("🪨 Sysiphe v13 (Cloud)")

if 'date_seance' not in st.session_state:
    st.session_state.date_seance = datetime.now().date()

with st.sidebar:
    st.header("Statut")
    st.success("● Cloud Connecté")
    
    date_seance = st.date_input("Date de la séance", st.session_state.date_seance, key="date_picker")
    if date_seance != st.session_state.date_seance:
        st.session_state.date_seance = date_seance
        st.rerun()
    
    if st.button("🗑️ Supprimer cette séance", type="secondary", use_container_width=True):
        supabase.table("perfs").delete().eq("date", str(st.session_state.date_seance)).execute()
        st.cache_data.clear()
        st.session_state.exos_du_jour = []
        st.toast(f"Séance du {st.session_state.date_seance.strftime('%d/%m/%Y')} supprimée", icon="🗑️")
        st.session_state.date_seance = datetime.now().date()
        st.rerun()
    
    st.write("---")
    st.write("🗄️ **Consulter un entraînement passé**")
    
    if not df_global.empty:
        dates_uniques = df_global['date'].unique()
        df_dates = pd.DataFrame({'date': dates_uniques}).sort_values('date', ascending=False)
        df_dates['date_dt'] = pd.to_datetime(df_dates['date'])
        df_dates['Mois_Str'] = df_dates['date_dt'].dt.month.map(MOIS_FR) + " " + df_dates['date_dt'].dt.year.astype(str)
        
        liste_mois = df_dates['Mois_Str'].unique().tolist()
        if liste_mois:
            mois_selectionne = st.selectbox("Filtrer par mois", liste_mois)
            
            df_mois = df_dates[df_dates['Mois_Str'] == mois_selectionne].copy()
            df_mois['📅 Séances du mois'] = df_mois['date_dt'].dt.strftime('%d/%m/%Y')
            
            selection_sidebar = st.dataframe(
                df_mois[['📅 Séances du mois']], 
                hide_index=True, 
                use_container_width=True,
                on_select="rerun",
                selection_mode="single-row"
            )
            
            if selection_sidebar and selection_sidebar["selection"]["rows"]:
                idx_clic = selection_sidebar["selection"]["rows"][0]
                date_cliquee = df_mois.iloc[idx_clic]['date']
                if date_cliquee != st.session_state.date_seance:
                    st.session_state.date_seance = date_cliquee
                    st.rerun()
    else:
        st.write("Aucun historique détecté.")

# --- Hydratation dynamique ---
date_active = st.session_state.date_seance
existe_aujourdhui = not df_global.empty and (date_active in df_global['date'].values)

target_date = date_active if existe_aujourdhui else None
if not existe_aujourdhui and not df_global.empty:
    dates_passees = df_global[df_global['date'] < date_active]['date']
    if not dates_passees.empty:
        target_date = dates_passees.max()

is_fallback = not existe_aujourdhui

default_var, default_elas, default_tens = "Full", "Aucun", "N/A"
default_forms, default_times = {i: "Normal" for i in range(1,6)}, {i: "" for i in range(1,6)}

if target_date and not df_global.empty:
    df_target_planche = df_global[(df_global['date'] == target_date) & (df_global['exercice'].str.lower() == 'planche')]
    if not df_target_planche.empty:
        last_g = df_target_planche.iloc[0]
        default_var, default_elas, default_tens = last_g['variante'], last_g['elastique'], last_g['tension']
        
        for _, r in df_target_planche.iterrows():
            s = int(r['serie'])
            default_forms[s] = r['forme'] if pd.notna(r['forme']) else "Normal"
            if not is_fallback: 
                default_times[s] = str(r['performance']) if pd.notna(r['performance']) else ""

if 'exos_du_jour' not in st.session_state or st.session_state.get('current_date') != date_active:
    if target_date and not df_global.empty:
        exos_cible = df_global[(df_global['date'] == (target_date if target_date else date_active)) & (df_global['exercice'].str.lower() != 'planche')]
        st.session_state.exos_du_jour = exos_cible['exercice'].unique().tolist()
    else:
        st.session_state.exos_du_jour = []
    st.session_state.current_date = date_active

tous_les_exos = []
if not df_global.empty:
    tous_les_exos = sorted(df_global[df_global['exercice'].str.lower() != 'planche']['exercice'].unique().tolist())

# =========================================================================
# 2. INTERFACE DE SAISIE REACTIONNELLE EN LIGNE
# =========================================================================
col_saisie, col_vide = st.columns([2, 1])
with col_saisie:
    # --- PLANCHE ---
    with st.expander("🤸 PLANCHE", expanded=True):
        idx_v = list(CONFIG["variantes"].keys()).index(default_var) if default_var in CONFIG["variantes"] else 0
        idx_e = list(CONFIG["elastiques"].keys()).index(default_elas) if default_elas in CONFIG["elastiques"] else 0
        idx_t = list(CONFIG["tensions"].keys()).index(default_tens) if default_tens in CONFIG["tensions"] else 0
        
        c1, c2, c3 = st.columns(3)
        with c1: var_g = st.selectbox("Variante", list(CONFIG["variantes"].keys()), index=idx_v, key=f"var_g_{date_active}")
        with c2: elas_g = st.selectbox("Élastique", list(CONFIG["elastiques"].keys()), index=idx_e, key=f"elas_g_{date_active}")
        with c3: tens_g = st.selectbox("Tension", list(CONFIG["tensions"].keys()), index=idx_t, key=f"tens_g_{date_active}")
        
        st.write("---")
        c_times = st.columns([1, 2, 1])
        
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
            supabase.table("perfs").delete().eq("date", str(date_active)).ilike("exercice", "planche").execute()
            lignes_a_inserer = []
            for s in range(1, 6):
                t = temps_temp[s]
                f = formes_temp[s]
                if t:
                    eff = calculer_effort(var_g, elas_g, tens_g, f, t)
                    lignes_a_inserer.append({
                        "user_id": "00000000-0000-0000-0000-000000000000",
                        "date": str(date_active), "exercice": "Planche", "serie": s, "performance": float(t),
                        "variante": var_g, "elastique": elas_g, "tension": tens_g, "forme": f,
                        "effort_pondere": eff, "categorie": "Force Iso", "unite": "Sec"
                    })
            if lignes_a_inserer:
                supabase.table("perfs").insert(lignes_a_inserer).execute()
                st.cache_data.clear()
                st.success("Planche enregistrée !")
                st.rerun()

    # --- AUTRES EXERCICES ---
    for nom_exo in list(st.session_state.exos_du_jour):
        with st.expander(f"💪 {nom_exo.upper()}", expanded=True):
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
                    supabase.table("perfs").delete().eq("date", str(date_active)).ilike("exercice", nom_exo).execute()
                    st.cache_data.clear()
                    st.rerun()
            
            if st.button(f"Enregistrer {nom_exo}", key=f"save_{nom_exo}_{date_active}"):
                supabase.table("perfs").delete().eq("date", str(date_active)).ilike("exercice", nom_exo).execute()
                if raw_input:
                    try:
                        lignes = []
                        for i, v in enumerate(raw_input.split()):
                            lignes.append({
                                "user_id": "00000000-0000-0000-0000-000000000000",
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

    # --- AJOUT EXERCICES ---
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
# 3. STATISTIQUES & PR HISTORIQUES GLOBALS
# =========================================================================
st.write("---")
tab_graph, tab_records, tab_repos = st.tabs(["📈 Graphiques", "🏆 Records (PRs)", "💤 Analyse du Repos"])

with tab_graph:
    if not df_global.empty:
        min_date, max_date = df_global['date'].min(), df_global['date'].max()
        curseur_dates = st.slider("🔍 Période d'analyse", min_value=min_date, max_value=max_date, value=(min_date, max_date)) if min_date != max_date else (date_active, date_active)
        
        df_period = df_global[(df_global['date'] >= curseur_dates[0]) & (df_global['date'] <= curseur_dates[1])]
        
        # Graph Planche
        df_planche = df_period[df_period['exercice'].str.lower() == 'planche']
        if not df_planche.empty:
            df_g_planche = df_planche.groupby(['date', 'variante'])['effort_pondere'].max().reset_index()
            pivot_planche = lisser_donnees(df_g_planche, 'date', 'variante', 'effort_pondere')
            if not pivot_planche.empty:
                df_melt_p = pivot_planche.reset_index().melt(id_vars='date', var_name='Variante', value_name='Effort')
                fig_p = px.line(df_melt_p, x='date', y='Effort', color='Variante')
                fig_p.update_traces(hovertemplate='%{y:.1f} pts')
                fig_p.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Effort Pondéré")
                st.plotly_chart(fig_p, use_container_width=True)
        
        # Graph Muscu
        select_exos = st.multiselect("Sélectionner les exercices", tous_les_exos, default=tous_les_exos[:3] if len(tous_les_exos)>=3 else tous_les_exos)
        if select_exos:
            df_muscu = df_period[df_period['exercice'].str.lower().isin([e.lower().strip() for e in select_exos])]
            if not df_muscu.empty:
                df_g_muscu = df_muscu.groupby(['date', 'exercice'])['performance'].max().reset_index()
                pivot_muscu = lisser_donnees(df_g_muscu, 'date', 'exercice', 'performance')
                if not pivot_muscu.empty:
                    df_melt_m = pivot_muscu.reset_index().melt(id_vars='date', var_name='Exercice', value_name='Performance')
                    fig_m = px.line(df_melt_m, x='date', y='Performance', color='Exercice')
                    fig_m.update_traces(hovertemplate='%{y:.0f} Reps')
                    fig_m.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Répétitions")
                    st.plotly_chart(fig_m, use_container_width=True)

        # Graph Volume
        df_g_cat = df_period.groupby(['date', 'categorie']).size().reset_index(name='nb_series')
        pivot_cat = lisser_donnees(df_g_cat, 'date', 'categorie', 'nb_series', fill_zero=True)
        if not pivot_cat.empty:
            df_melt_c = pivot_cat.reset_index().melt(id_vars='date', var_name='Catégorie', value_name='Séries')
            fig_c = px.line(df_melt_c, x='date', y='Séries', color='Catégorie')
            fig_c.update_traces(hovertemplate='%{y:.0f} Séries')
            fig_c.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Volume (Séries)")
            st.plotly_chart(fig_c, use_container_width=True)
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
                st.dataframe(df_pr_planche, use_container_width=True, hide_index=True)

        with c2:
            st.write("#### 💪 Top Musculation (Reps Max)")
            df_m = df_global[df_global['exercice'].str.lower() != 'planche']
            if not df_m.empty:
                df_pr_muscu = df_m.groupby('exercice')['performance'].max().reset_index()
                df_pr_muscu.columns = ["Exercice", "Reps Max (1 série)"]
                df_pr_muscu = df_pr_muscu.sort_values('Reps Max (1 série)', ascending=False)
                st.dataframe(df_pr_muscu, use_container_width=True, hide_index=True)

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