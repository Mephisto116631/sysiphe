import streamlit as st
import duckdb
import pandas as pd
from datetime import datetime
import plotly.express as px
import calendar

# =========================================================================
# 0. CONFIGURATION & MOTEUR DE CALCUL
# =========================================================================
con = duckdb.connect("sysiphe.db")

con.execute("""
    CREATE TABLE IF NOT EXISTS perfs (
        date DATE,
        exercice VARCHAR,
        serie INTEGER,
        performance FLOAT,
        variante VARCHAR,
        elastique VARCHAR,
        tension VARCHAR,
        forme VARCHAR,
        effort_pondere FLOAT,
        categorie VARCHAR,
        unite VARCHAR
    )
""")

# 1. NETTOYAGE DES CATÉGORIES (Fusion automatique des doublons de l'historique)
con.execute("""
    UPDATE perfs 
    SET categorie = 'Force Iso' 
    WHERE LOWER(trim(categorie)) IN ('force iso', 'force isometrique', 'statique')
""")
con.execute("""
    UPDATE perfs 
    SET categorie = 'Musculation' 
    WHERE LOWER(trim(categorie)) IN ('force', 'musculation') OR categorie IS NULL OR categorie = ''
""")

# 2. MIGRATION DES ANCIENNES PLANCHES (Normalisation des anciens titres Sheets)
con.execute("""
    UPDATE perfs 
    SET 
        variante = CASE 
            WHEN LOWER(exercice) LIKE '%straddle%' THEN 'Straddle'
            WHEN LOWER(exercice) LIKE '%adv%' THEN 'Adv_Tuck'
            WHEN LOWER(exercice) LIKE '%tuck%' THEN 'Tuck'
            WHEN LOWER(exercice) LIKE '%full%' THEN 'Full'
            WHEN LOWER(exercice) LIKE '%half%' THEN 'Half_Lay'
            WHEN LOWER(exercice) LIKE '%diamond%' THEN 'Diamond'
            WHEN LOWER(exercice) LIKE '%maltese%' THEN 'Maltese'
            ELSE variante 
        END,
        exercice = 'Planche'
    WHERE LOWER(exercice) LIKE '%planche%' AND LOWER(exercice) != 'planche'
""")

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
st.set_page_config(page_title="Sysiphe v13", layout="wide")
st.title("🪨 Sysiphe v13")

if 'date_seance' not in st.session_state:
    st.session_state.date_seance = datetime.now().date()

with st.sidebar:
    st.header("Statut")
    st.success("● Sauvegarde automatique")
    
    date_seance = st.date_input("Date de la séance", st.session_state.date_seance, key="date_picker")
    if date_seance != st.session_state.date_seance:
        st.session_state.date_seance = date_seance
        st.rerun()
    
    # FONCTION SUPPRIMER UN JOUR COMPLET
    if st.button("🗑️ Supprimer cette séance", type="secondary", use_container_width=True):
        con.execute("DELETE FROM perfs WHERE date = ?", (st.session_state.date_seance,))
        st.session_state.exos_du_jour = []
        st.toast(f"Séance du {st.session_state.date_seance.strftime('%d/%m/%Y')} supprimée", icon="🗑️")
        st.session_state.date_seance = datetime.now().date()
        st.rerun()
    
    st.write("---")
    st.write("🗄️ **Consulter un entraînement passé**")
    
    df_dates = con.execute("SELECT DISTINCT date FROM perfs ORDER BY date DESC").df()
    
    if not df_dates.empty:
        df_dates['date'] = pd.to_datetime(df_dates['date'])
        df_dates['Mois_Str'] = df_dates['date'].dt.month.map(MOIS_FR) + " " + df_dates['date'].dt.year.astype(str)
        
        liste_mois = df_dates['Mois_Str'].unique().tolist()
        mois_selectionne = st.selectbox("Filtrer par mois", liste_mois)
        
        df_mois = df_dates[df_dates['Mois_Str'] == mois_selectionne].copy()
        df_mois['📅 Séances du mois'] = df_mois['date'].dt.strftime('%d/%m/%Y')
        
        selection_sidebar = st.dataframe(
            df_mois[['📅 Séances du mois']], 
            hide_index=True, 
            use_container_width=True,
            on_select="rerun",
            selection_mode="single-row"
        )
        
        if selection_sidebar and selection_sidebar["selection"]["rows"]:
            idx_clic = selection_sidebar["selection"]["rows"][0]
            date_cliquee = df_mois.iloc[idx_clic]['date'].date()
            if date_cliquee != st.session_state.date_seance:
                st.session_state.date_seance = date_cliquee
                st.rerun()
    else:
        st.write("Aucun historique détecté.")

# --- Hydratation dynamique et mémoire des exercices ---
date_active = st.session_state.date_seance
existe_aujourdhui = con.execute("SELECT COUNT(*) FROM perfs WHERE date = ?", (date_active,)).fetchone()[0] > 0
target_date = date_active if existe_aujourdhui else con.execute("SELECT MAX(date) FROM perfs WHERE date < ?", (date_active,)).fetchone()[0]
is_fallback = not existe_aujourdhui

default_var, default_elas, default_tens = "Full", "Aucun", "N/A"
default_forms, default_times = {i: "Normal" for i in range(1,6)}, {i: "" for i in range(1,6)}

if target_date:
    last_g = con.execute("SELECT variante, elastique, tension FROM perfs WHERE LOWER(trim(exercice)) = 'planche' AND date = ? LIMIT 1", (target_date,)).fetchone()
    if last_g: default_var, default_elas, default_tens = last_g[0], last_g[1], last_g[2]
    for r in con.execute("SELECT serie, forme, performance FROM perfs WHERE LOWER(trim(exercice)) = 'planche' AND date = ?", (target_date,)).fetchall():
        default_forms[r[0]] = r[1]
        if not is_fallback: default_times[r[0]] = str(r[2])

if 'exos_du_jour' not in st.session_state or st.session_state.get('current_date') != date_active:
    exos_sql = con.execute("SELECT DISTINCT exercice FROM perfs WHERE date = ? AND LOWER(trim(exercice)) != 'planche'", (target_date if target_date else date_active,)).fetchall()
    st.session_state.exos_du_jour = [e[0] for e in exos_sql]
    st.session_state.current_date = date_active

tous_les_exos = sorted([e[0] for e in con.execute("SELECT DISTINCT exercice FROM perfs WHERE LOWER(trim(exercice)) != 'planche'").fetchall()])

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
        
        con.execute("DELETE FROM perfs WHERE date = ? AND LOWER(trim(exercice)) = 'planche'", (date_active,))
        for s in range(1, 6):
            c1, c2, c3 = st.columns([1, 2, 1])
            with c1: t = st.text_input(f"S{s}(s)", value=default_times.get(s, ""), key=f"p_t_{s}_{date_active}")
            with c2: f = st.select_slider(f"F{s}", options=list(CONFIG["formes"].keys()), value=default_forms.get(s, "Normal"), key=f"p_f_{s}_{date_active}")
            with c3:
                if t:
                    eff = calculer_effort(var_g, elas_g, tens_g, f, t)
                    st.metric("Effort", f"{eff}")
                    con.execute("INSERT INTO perfs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                (date_active, "Planche", s, float(t), var_g, elas_g, tens_g, f, eff, "Force Iso", "Sec"))
                else: st.metric("Effort", "0.0")

    # --- AUTRES EXERCICES (BOX DE RÉSULTATS EN LIGNE) ---
    for nom_exo in list(st.session_state.exos_du_jour):
        with st.expander(f"💪 {nom_exo.upper()}", expanded=True):
            p_today = con.execute("SELECT performance, categorie FROM perfs WHERE date = ? AND LOWER(trim(exercice)) = ?", (date_active, nom_exo.lower().strip())).fetchall()
            val_init = " ".join([str(int(p[0]) if p[0].is_integer() else p[0]) for p in p_today])
            cat_init = p_today[0][1] if p_today else "Musculation"
            
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
                    con.execute("DELETE FROM perfs WHERE date = ? AND LOWER(trim(exercice)) = ?", (date_active, nom_exo.lower().strip()))
                    st.rerun()
            
            con.execute("DELETE FROM perfs WHERE date = ? AND LOWER(trim(exercice)) = ?", (date_active, nom_exo.lower().strip()))
            if raw_input:
                try:
                    for i, v in enumerate(raw_input.split()):
                        con.execute("INSERT INTO perfs VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                    (date_active, nom_exo, i+1, float(v), "", "", "", "", 0.0, cat_exo, "Reps"))
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
    dates_minmax = con.execute("SELECT MIN(date), MAX(date) FROM perfs").fetchone()
    curseur_dates = st.slider("🔍 Période d'analyse", min_value=dates_minmax[0], max_value=dates_minmax[1], value=(dates_minmax[0], dates_minmax[1])) if dates_minmax[0] and dates_minmax[1] and dates_minmax[0] != dates_minmax[1] else (date_active, date_active)

    # Graph Planche
    df_g_planche = con.execute("SELECT date, variante, MAX(effort_pondere) as max_effort FROM perfs WHERE LOWER(trim(exercice)) = 'planche' AND date BETWEEN ? AND ? GROUP BY date, variante ORDER BY date ASC", (curseur_dates[0], curseur_dates[1])).df()
    pivot_planche = lisser_donnees(df_g_planche, 'date', 'variante', 'max_effort')
    if not pivot_planche.empty:
        df_melt_p = pivot_planche.reset_index().melt(id_vars='date', var_name='Variante', value_name='Effort')
        fig_p = px.line(df_melt_p, x='date', y='Effort', color='Variante')
        fig_p.update_traces(hovertemplate='%{y:.1f} pts')
        fig_p.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Effort Pondéré")
        st.plotly_chart(fig_p, use_container_width=True)
    
    # Graph Muscu
    select_exos = st.multiselect("Sélectionner les exercices", tous_les_exos, default=tous_les_exos[:3] if len(tous_les_exos)>=3 else tous_les_exos)
    if select_exos:
        placeholders = ','.join(['?'] * len(select_exos))
        df_g_muscu = con.execute(f"SELECT date, exercice, MAX(performance) as reps FROM perfs WHERE LOWER(trim(exercice)) IN ({placeholders}) AND date BETWEEN ? AND ? GROUP BY date, exercice ORDER BY date ASC", (*[e.lower().strip() for e in select_exos], curseur_dates[0], curseur_dates[1])).df()
        pivot_muscu = lisser_donnees(df_g_muscu, 'date', 'exercice', 'reps')
        if not pivot_muscu.empty:
            df_melt_m = pivot_muscu.reset_index().melt(id_vars='date', var_name='Exercice', value_name='Performance')
            fig_m = px.line(df_melt_m, x='date', y='Performance', color='Exercice')
            fig_m.update_traces(hovertemplate='%{y:.0f} Reps')
            fig_m.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Répétitions")
            st.plotly_chart(fig_m, use_container_width=True)

    # Graph Volume
    df_g_cat = con.execute("SELECT date, categorie, COUNT(*) as nb_series FROM perfs WHERE date BETWEEN ? AND ? GROUP BY date, categorie ORDER BY date ASC", (curseur_dates[0], curseur_dates[1])).df()
    pivot_cat = lisser_donnees(df_g_cat, 'date', 'categorie', 'nb_series', fill_zero=True)
    if not pivot_cat.empty:
        df_melt_c = pivot_cat.reset_index().melt(id_vars='date', var_name='Catégorie', value_name='Séries')
        fig_c = px.line(df_melt_c, x='date', y='Séries', color='Catégorie')
        fig_c.update_traces(hovertemplate='%{y:.0f} Séries')
        fig_c.update_layout(hovermode="x unified", xaxis_title="", yaxis_title="Volume (Séries)")
        st.plotly_chart(fig_c, use_container_width=True)

with tab_records:
    c1, c2 = st.columns(2)
    with c1:
        st.write("#### Record Planche")
        df_pr_planche = con.execute("""
            SELECT 
                date as "Date",
                coalesce(nullif(trim(variante), ''), 'Full') as "Variante", 
                coalesce(nullif(trim(elastique), ''), 'Aucun') as "Élastique", 
                coalesce(nullif(trim(tension), ''), 'N/A') as "Tension", 
                performance as "Temps (s)", 
                effort_pondere as "Effort Absolu"
            FROM (
                SELECT *, 
                       ROW_NUMBER() OVER (
                           PARTITION BY LOWER(trim(coalesce(variante, ''))), LOWER(trim(coalesce(elastique, ''))), LOWER(trim(coalesce(tension, '')))
                           ORDER BY effort_pondere DESC, performance DESC
                       ) as rn
                FROM perfs 
                WHERE LOWER(trim(exercice)) = 'planche'
            ) WHERE rn = 1 AND effort_pondere > 0
            ORDER BY "Effort Absolu" DESC
        """).df()
        st.dataframe(df_pr_planche, use_container_width=True, hide_index=True)

    with c2:
        st.write("#### 💪 Top Musculation (Reps Max)")
        df_pr_muscu = con.execute("""
            SELECT exercice as "Exercice", MAX(performance) as "Reps Max (1 série)"
            FROM perfs 
            WHERE LOWER(trim(exercice)) != 'planche' 
            GROUP BY exercice 
            ORDER BY 2 DESC
        """).df()
        st.dataframe(df_pr_muscu, use_container_width=True, hide_index=True)

with tab_repos:
    st.subheader("💤 Analyse Mathématique de la Récupération")
    df_all_dates = con.execute("SELECT DISTINCT date FROM perfs ORDER BY date ASC").df()
    if len(df_all_dates) > 1:
        df_all_dates['date'] = pd.to_datetime(df_all_dates['date'])
        df_all_dates['jours_repos'] = df_all_dates['date'].diff().dt.days - 1
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
            fig_bar_repos = px.bar(df_repos_stats, x='date', y='jours_repos', title="Chronologie des jours de repos accordés")
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