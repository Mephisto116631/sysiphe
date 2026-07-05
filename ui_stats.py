"""
Sysiphe — Onglets de statistiques (Graphiques, Records, Repos, Paramètres, Apparence).
"""
from datetime import datetime, timedelta
import pandas as pd
import streamlit as st
import plotly.express as px

from data import lisser_donnees, detect_plateau, suggest_next_session
from supabase_io import update_exercise_name, save_user_settings

# =========================================================================
# CONFIGURATION DES THÈMES
# =========================================================================
# Clés "historiques" (utilisées par Plotly) : bg, text, grid, colors, cal_event
# Nouvelles clés (immersion CSS globale) : app_gradient, sidebar_bg, accent,
#   accent_soft, text_main, font, card_bg, card_border
THEMES = {
    "Abysse": {
        "bg": "rgba(0,0,0,0)", "text": "#E2E8F0", "grid": "#334155",
        "colors": ["#00E5FF", "#39FF14", "#B026FF", "#FFD700"],
        "cal_event": "#00E5FF",
        "app_gradient": "linear-gradient(160deg, #050810 0%, #0A1128 45%, #0D1B3E 100%)",
        "sidebar_bg": "linear-gradient(180deg, #030509 0%, #0A1128 100%)",
        "accent": "#00E5FF",
        "accent_soft": "rgba(0, 229, 255, 0.15)",
        "text_main": "#E2E8F0",
        "font": "'JetBrains Mono', 'Courier New', monospace",
        "card_bg": "rgba(13, 27, 62, 0.55)",
        "card_border": "rgba(0, 229, 255, 0.35)",
    },
    "Magma": {
        "bg": "#1E1E1E", "text": "#F5F5F5", "grid": "#424242",
        "colors": ["#F44336", "#FF9800", "#FFEB3B", "#FFFFFF"],
        "cal_event": "#FF9800",
        "app_gradient": "linear-gradient(160deg, #140505 0%, #2B0E0E 45%, #3D1204 100%)",
        "sidebar_bg": "linear-gradient(180deg, #0D0303 0%, #2B0E0E 100%)",
        "accent": "#FF9800",
        "accent_soft": "rgba(255, 152, 0, 0.18)",
        "text_main": "#F5F5F5",
        "font": "'Barlow Condensed', 'Arial Narrow', sans-serif",
        "card_bg": "rgba(61, 18, 4, 0.55)",
        "card_border": "rgba(255, 152, 0, 0.35)",
    },
    "Analytique": {
        "bg": "#0F172A", "text": "#CBD5E1", "grid": "#1E293B",
        "colors": ["#38BDF8", "#818CF8", "#34D399", "#F472B6"],
        "cal_event": "#38BDF8",
        "app_gradient": "linear-gradient(160deg, #05070D 0%, #0F172A 50%, #131C33 100%)",
        "sidebar_bg": "linear-gradient(180deg, #05070D 0%, #0F172A 100%)",
        "accent": "#818CF8",
        "accent_soft": "rgba(129, 140, 248, 0.15)",
        "text_main": "#CBD5E1",
        "font": "'Inter', 'Segoe UI', sans-serif",
        "card_bg": "rgba(19, 28, 51, 0.55)",
        "card_border": "rgba(129, 140, 248, 0.35)",
    },
    "Épuré": {
        "bg": "#FFFFFF", "text": "#333333", "grid": "#E5E7EB",
        "colors": ["#1E3A8A", "#059669", "#D97706", "#DC2626"],
        "cal_event": "#1E3A8A",
        "app_gradient": "linear-gradient(160deg, #FFFFFF 0%, #F8FAFC 50%, #F1F5F9 100%)",
        "sidebar_bg": "linear-gradient(180deg, #FFFFFF 0%, #F1F5F9 100%)",
        "accent": "#1E3A8A",
        "accent_soft": "rgba(30, 58, 138, 0.08)",
        "text_main": "#1E293B",
        "font": "'Source Serif Pro', Georgia, serif",
        "card_bg": "rgba(255, 255, 255, 0.7)",
        "card_border": "rgba(30, 58, 138, 0.2)",
    }
}

# =========================================================================
# INJECTION CSS — IMMERSION DU THÈME DANS TOUTE L'APP
# =========================================================================
def inject_theme_css(theme_name: str) -> None:
    """Applique le thème choisi à l'ensemble de l'interface Streamlit
    (fond de page, sidebar, cartes/metrics, boutons, onglets, labels,
    champs de saisie, headers d'expander), pas seulement aux graphiques
    Plotly."""
    t = THEMES.get(theme_name, THEMES["Abysse"])

    css = f"""
    <style>
    @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Barlow+Condensed:wght@400;600&family=Inter:wght@400;600&family=Source+Serif+Pro:wght@400;600&display=swap');

    /* Fond principal de l'app */
    .stApp {{
        background: {t['app_gradient']};
        transition: background 0.4s ease;
    }}

    /* Typo globale */
    html, body, [class*="css"] {{
        font-family: {t['font']};
        color: {t['text_main']};
    }}

    /* Sidebar */
    section[data-testid="stSidebar"] {{
        background: {t['sidebar_bg']};
        border-right: 1px solid {t['card_border']};
    }}
    section[data-testid="stSidebar"] * {{
        color: {t['text_main']} !important;
    }}

    /* Titres */
    h1, h2, h3, h4, h5, h6 {{
        color: {t['text_main']} !important;
        text-shadow: 0 0 18px {t['accent_soft']};
    }}

    /* Texte courant, markdown, listes */
    p, li, span, .stMarkdown, div[data-testid="stMarkdownContainer"] {{
        color: {t['text_main']} !important;
    }}

    /* Labels de widgets (number_input, text_input, selectbox, checkbox...) */
    div[data-testid="stWidgetLabel"] p,
    div[data-testid="stWidgetLabel"] label,
    label {{
        color: {t['text_main']} !important;
        opacity: 1 !important;
        font-weight: 500;
    }}

    /* Captions / textes d'aide (petit gris) */
    [data-testid="stCaptionContainer"], .stCaption, small {{
        color: {t['text_main']} !important;
        opacity: 0.75 !important;
    }}

    /* Cartes metric (KPI) */
    div[data-testid="stMetric"] {{
        background: {t['card_bg']};
        border: 1px solid {t['card_border']};
        border-radius: 12px;
        padding: 12px 16px;
        box-shadow: 0 0 20px {t['accent_soft']};
    }}
    div[data-testid="stMetricLabel"], div[data-testid="stMetricValue"], div[data-testid="stMetricDelta"] {{
        color: {t['text_main']} !important;
    }}

    /* Onglets (st.tabs) */
    button[data-baseweb="tab"] {{
        color: {t['text_main']} !important;
        font-family: {t['font']};
    }}
    button[data-baseweb="tab"] p {{
        color: {t['text_main']} !important;
    }}
    button[data-baseweb="tab"][aria-selected="true"] {{
        color: {t['accent']} !important;
    }}
    button[data-baseweb="tab"][aria-selected="true"] p {{
        color: {t['accent']} !important;
    }}
    button[data-baseweb="tab"][aria-selected="true"] {{
        border-bottom: 2px solid {t['accent']} !important;
    }}

    /* Boutons principaux */
    .stButton > button, .stDownloadButton > button {{
        background: {t['accent_soft']};
        border: 1px solid {t['accent']};
        color: {t['text_main']} !important;
        border-radius: 8px;
        transition: all 0.2s ease;
    }}
    .stButton > button p, .stDownloadButton > button p {{
        color: {t['text_main']} !important;
    }}
    .stButton > button:hover, .stDownloadButton > button:hover {{
        background: {t['accent']};
        box-shadow: 0 0 16px {t['accent_soft']};
    }}
    .stButton > button:hover p, .stDownloadButton > button:hover p {{
        color: #05070D !important;
    }}

    /* Champs de saisie : text_input, number_input, text_area, selectbox, date_input */
    div[data-baseweb="input"],
    div[data-baseweb="textarea"],
    div[data-baseweb="select"] > div {{
        background-color: {t['card_bg']} !important;
        border: 1px solid {t['card_border']} !important;
        border-radius: 8px !important;
    }}
    div[data-baseweb="input"] input,
    div[data-baseweb="textarea"] textarea,
    div[data-baseweb="select"] span,
    .stNumberInput input,
    .stTextInput input,
    textarea {{
        background-color: transparent !important;
        color: {t['text_main']} !important;
    }}
    input::placeholder, textarea::placeholder {{
        color: {t['text_main']} !important;
        opacity: 0.45 !important;
    }}
    /* Boutons +/- des number_input */
    button[data-testid="stNumberInputStepDown"],
    button[data-testid="stNumberInputStepUp"] {{
        background: {t['accent_soft']} !important;
        color: {t['text_main']} !important;
        border: 1px solid {t['card_border']} !important;
    }}

    /* Expanders — header (résumé cliquable) + contenu */
    div[data-testid="stExpander"] {{
        background: {t['card_bg']};
        border: 1px solid {t['card_border']};
        border-radius: 10px;
        overflow: hidden;
    }}
    div[data-testid="stExpander"] summary {{
        background: {t['card_bg']} !important;
        color: {t['text_main']} !important;
    }}
    div[data-testid="stExpander"] summary:hover {{
        background: {t['accent_soft']} !important;
    }}
    div[data-testid="stExpander"] summary p,
    div[data-testid="stExpander"] summary span {{
        color: {t['text_main']} !important;
    }}
    div[data-testid="stExpander"] summary svg {{
        fill: {t['text_main']} !important;
    }}

    /* Conteneurs à bordure (st.container(border=True)) */
    div[data-testid="stVerticalBlockBorderWrapper"] {{
        border-color: {t['card_border']} !important;
    }}
    </style>
    """
    st.markdown(css, unsafe_allow_html=True)

def _apply_plotly_theme(fig, theme_name: str):
    t = THEMES.get(theme_name, THEMES["Abysse"])
    fig.update_layout(
        plot_bgcolor=t["bg"],
        paper_bgcolor=t["bg"],
        font=dict(color=t["text"]),
        xaxis=dict(showgrid=True, gridcolor=t["grid"], tickformat="%d/%m"),
        yaxis=dict(showgrid=True, gridcolor=t["grid"]),
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="center", x=0.5, font=dict(color=t["text"])),
        margin=dict(l=10, r=10, t=40, b=10)
    )
    fig.update_traces(line=dict(width=3))
    return fig

def _plateau_badge(dates, values, label: str) -> None:
    result = detect_plateau(list(dates), list(values), window_days=21)
    if result["status"] == "progress":
        st.success(f"📈 {label} : en progression sur les 21 derniers jours.")
    elif result["status"] == "regression":
        st.warning(f"📉 {label} : en baisse sur les 21 derniers jours — envisage un deload.")
    elif result["status"] == "plateau":
        st.info(f"➖ {label} : stable sur les 21 derniers jours (plateau).")

# =========================================================================
# GRAPHIQUES
# =========================================================================
def render_graph_tab(df_global: pd.DataFrame, tous_les_exos: list, include_planche: bool, current_theme: str) -> None:
    if df_global.empty:
        st.write("Pas de données pour les graphiques.")
        return

    col_preset, col_custom = st.columns([1, 2])
    with col_preset:
        preset = st.selectbox("Période", [
            "Tout l'historique", "7 derniers jours", "30 derniers jours",
            "Ce mois", "3 derniers mois", "Personnalisée",
        ])

    today = datetime.now().date()
    min_db_date = df_global["date"].min()
    max_db_date = df_global["date"].max()

    if preset == "7 derniers jours": start_date, end_date = today - timedelta(days=7), today
    elif preset == "30 derniers jours": start_date, end_date = today - timedelta(days=30), today
    elif preset == "Ce mois": start_date, end_date = today.replace(day=1), today
    elif preset == "3 derniers mois": start_date, end_date = today - timedelta(days=90), today
    elif preset == "Tout l'historique": start_date, end_date = min_db_date, max_db_date
    else:
        with col_custom:
            sel = st.date_input("Période personnalisée", [min_db_date, max_db_date])
            start_date, end_date = (sel[0], sel[1]) if len(sel) == 2 else (min_db_date, max_db_date)

    df_period = df_global[(df_global["date"] >= start_date) & (df_global["date"] <= end_date)]

    if df_period.empty:
        st.warning("Aucune donnée disponible pour cette période.")
        return

    t_colors = THEMES.get(current_theme, THEMES["Abysse"])["colors"]

    # Planche
    if include_planche:
        df_planche = df_period[df_period["exercice"].str.lower() == "planche"]
        if not df_planche.empty:
            df_g_p = df_planche.groupby(["date", "variante"])["effort_pondere"].max().reset_index()
            pivot_p = lisser_donnees(df_g_p, "date", "variante", "effort_pondere", fill_method="ffill")
            if not pivot_p.empty:
                df_melt_p = pivot_p.reset_index().melt(id_vars="date", var_name="Variante", value_name="Effort")
                fig_p = px.line(df_melt_p, x="date", y="Effort", color="Variante", title="Évolution Planche — effort pondéré", color_discrete_sequence=t_colors)
                fig_p.update_traces(connectgaps=True, hovertemplate="%{y:.0f} pts")
                fig_p = _apply_plotly_theme(fig_p, current_theme)
                st.plotly_chart(fig_p, use_container_width=True)
                df_best = df_planche.groupby("date")["effort_pondere"].max().reset_index()
                _plateau_badge(df_best["date"], df_best["effort_pondere"], "Planche")

    # Musculation
    if tous_les_exos:
        select_exos = st.multiselect("Sélectionner les exercices", tous_les_exos, default=tous_les_exos[:3] if len(tous_les_exos) >= 3 else tous_les_exos)
        if select_exos:
            df_muscu = df_period[df_period["exercice"].str.lower().isin([e.lower().strip() for e in select_exos])].copy()
            if not df_muscu.empty:
                if "charge" not in df_muscu.columns: df_muscu["charge"] = 0.0
                df_muscu["charge"] = pd.to_numeric(df_muscu["charge"], errors="coerce").fillna(0.0)
                df_muscu["performance"] = pd.to_numeric(df_muscu["performance"], errors="coerce").fillna(0.0)
                df_muscu["volume"] = df_muscu.apply(lambda r: r["performance"] * r["charge"] if r["charge"] > 0 else r["performance"], axis=1)
                label_y = "Tonnage (kg)" if (df_muscu["charge"] > 0).any() else "Reps"
                df_g_vol = df_muscu.groupby(["date", "exercice"])["volume"].sum().reset_index()

                fig_v = px.line(df_g_vol, x="date", y="volume", color="exercice", markers=True, title=f"Volume brut total ({label_y.lower()})", color_discrete_sequence=t_colors)
                fig_v.update_traces(hovertemplate="%{y:.0f}")
                fig_v = _apply_plotly_theme(fig_v, current_theme)
                st.plotly_chart(fig_v, use_container_width=True)

# =========================================================================
# RECORDS
# =========================================================================
def render_records_tab(df_global: pd.DataFrame) -> None:
    if df_global.empty:
        st.write("Pas de données.")
        return

    c1, c2 = st.columns(2)
    with c1:
        st.write("#### 🤸 Record Planche")
        df_p = df_global[(df_global["exercice"].str.lower() == "planche") & (df_global["effort_pondere"] > 0)].copy()
        if not df_p.empty:
            for col, default in [("variante", "Full"), ("elastique", "Aucun"), ("tension", "N/A")]:
                df_p[col] = df_p[col].fillna(default).replace("", default)
            df_p = df_p.sort_values(["effort_pondere", "performance"], ascending=[False, False])
            df_pr = df_p.drop_duplicates(subset=["variante", "elastique", "tension"])[["date", "variante", "elastique", "tension", "performance", "effort_pondere"]].copy()
            df_pr.columns = ["Date", "Variante", "Élastique", "Tension", "Temps (s)", "Effort"]
            df_pr[["Temps (s)", "Effort"]] = df_pr[["Temps (s)", "Effort"]].astype(int)
            st.dataframe(df_pr.style.background_gradient(subset=["Effort", "Temps (s)"], cmap="YlOrRd"), use_container_width=True, hide_index=True)
        else:
            st.info("Aucun record de Planche enregistré.")

    with c2:
        st.write("#### 💪 Top Musculation (Volume max / séance)")
        df_m = df_global[df_global["exercice"].str.lower() != "planche"].copy()
        if not df_m.empty:
            if "charge" not in df_m.columns: df_m["charge"] = 0.0
            df_m["charge"] = pd.to_numeric(df_m["charge"], errors="coerce").fillna(0.0)
            df_m["volume"] = df_m.apply(lambda r: r["performance"] * r["charge"] if r["charge"] > 0 else r["performance"], axis=1)
            df_vol = df_m.groupby(["exercice", "date"])["volume"].sum().reset_index()
            idx_max = df_vol.groupby("exercice")["volume"].idxmax()
            a_du_charge_global = (df_m["charge"] > 0).any()
            label = "Tonnage Max (kg)" if a_du_charge_global else "Volume Max (reps)"
            df_pr_muscu = df_vol.loc[idx_max].rename(columns={"volume": label, "date": "Date du PR", "exercice": "Exercice"})[["Exercice", label, "Date du PR"]].sort_values(label, ascending=False)
            df_pr_muscu[label] = df_pr_muscu[label].astype(int)
            st.dataframe(df_pr_muscu.style.background_gradient(subset=[label], cmap="Blues"), use_container_width=True, hide_index=True)
        else:
            st.info("Aucun exercice de musculation enregistré.")

# =========================================================================
# REPOS
# =========================================================================
def render_repos_tab(df_global: pd.DataFrame) -> None:
    st.subheader("💤 Analyse Mathématique de la Récupération")
    if df_global.empty: return

    df_all_dates = pd.DataFrame({"date": df_global["date"].unique()}).sort_values("date")
    if len(df_all_dates) <= 1:
        st.info("Ajoute au moins deux séances à des dates différentes pour générer l'analyse.")
        return

    df_all_dates["date_dt"] = pd.to_datetime(df_all_dates["date"])
    df_all_dates["jours_repos"] = df_all_dates["date_dt"].diff().dt.days - 1
    df_repos_stats = df_all_dates.dropna()
    suggestion = suggest_next_session(df_global["date"].unique().tolist())

    cr1, cr2 = st.columns([1, 2])
    with cr1:
        st.metric("Repos moyen", f"{int(round(df_repos_stats['jours_repos'].mean()))} j")
        st.metric("Repos habituel (mode)", f"{suggestion['mode_repos']} j")
        st.metric("Plus longue coupure", f"{int(df_repos_stats['jours_repos'].max())} j")
        if suggestion["next_session"] is not None:
            st.success(f"🔜 Prochaine séance optimale : **{suggestion['next_session'].strftime('%A %d %B')}**")
        
        habitudes = df_repos_stats["jours_repos"].value_counts().reset_index()
        habitudes.columns = ["Jours", "Nb"]
        habitudes["Jours"] = habitudes["Jours"].astype(int).astype(str) + " j"
        fig_pie = px.pie(habitudes, values="Nb", names="Jours", title="Répartition des formats de repos")
        st.plotly_chart(fig_pie, use_container_width=True)

    with cr2:
        fig_bar = px.bar(df_repos_stats, x="date_dt", y="jours_repos", title="Chronologie des jours de repos accordés")
        fig_bar.update_traces(marker_color="#1f77b4")
        st.plotly_chart(fig_bar, use_container_width=True)

# =========================================================================
# THEMES (Apparence)
# =========================================================================
def render_theme_tab():
    st.subheader("🎨 Apparence du Tableau de Bord")
    current = st.session_state.get("app_theme", "Abysse")
    col1, col2 = st.columns([1, 2])
    with col1:
        choix = st.radio("Thème global", list(THEMES.keys()), index=list(THEMES.keys()).index(current))
    with col2:
        st.write("**Aperçu des couleurs principales :**")
        c_list = THEMES[choix]["colors"]
        html_colors = "".join([f"<div style='background-color:{c}; width:40px; height:40px; border-radius:50%; display:inline-block; margin-right:10px;'></div>" for c in c_list])
        st.markdown(html_colors, unsafe_allow_html=True)
        st.caption(f"Fond des graphiques : {THEMES[choix]['bg']}")

    if st.button("✅ Appliquer le thème", use_container_width=True):
        st.session_state.app_theme = choix
        st.rerun()

# =========================================================================
# PARAMÈTRES (Le retour !)
# =========================================================================
def render_param_tab(df_global: pd.DataFrame, tous_les_exos: list, user_id: str) -> None:
    st.subheader("⚙️ Configuration Générale")

    st.checkbox("Inclure la Planche dans la saisie", key="include_planche")
    st.number_input("Taille de la moyenne glissante (séances)", min_value=1, max_value=30, step=1, key="nb_days_avg")
    st.number_input("Poids de référence pour le calcul d'isométrie (kg)", min_value=40, max_value=200, step=1, key="weight")

    st.write("---")
    st.subheader("📥 Export de données")
    if not df_global.empty:
        st.download_button(
            "📥 Télécharger tout mon historique (CSV)",
            data=df_global.to_csv(index=False).encode("utf-8"),
            file_name=f"sysiphe_export_{datetime.now().strftime('%Y%m%d')}.csv",
            mime="text/csv",
            use_container_width=True,
        )
        st.caption(f"{len(df_global)} lignes · {df_global['date'].nunique()} séances")
    else:
        st.caption("Aucune donnée à exporter.")

    st.write("---")
    st.subheader("🎛️ Calibration du modèle isométrique")
    st.caption("Ces scores pondèrent la difficulté de chaque variante.")
    
    updated_scores = {}
    for var, score in st.session_state.config_variantes.items():
        updated_scores[var] = st.number_input(var, min_value=1, max_value=20, value=int(score), step=1, key=f"cal_{var}")
        
    if st.button("✅ Appliquer et sauvegarder la calibration", use_container_width=True):
        st.session_state.config_variantes = updated_scores
        ok = save_user_settings(user_id, updated_scores)
        st.cache_data.clear()
        if ok:
            st.success("Scores mis à jour et sauvegardés.")
        else:
            st.warning("Échec de sauvegarde.")
        st.rerun()

    st.write("---")
    st.subheader("✏️ Renommer un exercice")
    if tous_les_exos:
        exo_a_renommer = st.selectbox("Exercice à modifier", tous_les_exos)
        nouveau_nom = st.text_input("Nouveau nom")
        
        if st.button("Renommer", use_container_width=True):
            nv = nouveau_nom.strip()
            if not nv:
                st.error("Le nouveau nom ne peut pas être vide.")
            elif nv == exo_a_renommer:
                st.warning("Le nouveau nom est identique à l'ancien.")
            elif nv in tous_les_exos:
                st.error(f"⚠️ '{nv}' existe déjà.")
            else:
                try:
                    update_exercise_name(user_id, exo_a_renommer, nv)
                    st.cache_data.clear()
                    st.success(f"✅ '{exo_a_renommer}' → '{nv}'")
                    st.rerun()
                except Exception as e:
                    st.error(f"Erreur : {e}")
    else:
        st.caption("Aucun exercice personnalisé enregistré.")

# =========================================================================
# POINT D'ENTRÉE UNIQUE
# =========================================================================
def render_stats_tabs(df_global: pd.DataFrame, tous_les_exos: list, user_id: str) -> None:
    current_theme = st.session_state.get("app_theme", "Abysse")
    
    # On affiche TOUJOURS les onglets, même sans données
    tab_graph, tab_records, tab_repos, tab_theme, tab_param = st.tabs([
        "📈 Graphiques", "🏆 Records", "💤 Repos", "🎨 Apparence", "⚙️ Paramètres"
    ])
    
    with tab_graph:
        render_graph_tab(df_global, tous_les_exos, st.session_state.get("include_planche", True), current_theme)
    with tab_records:
        render_records_tab(df_global)
    with tab_repos:
        render_repos_tab(df_global)
    with tab_theme:
        render_theme_tab()
    with tab_param:
        render_param_tab(df_global, tous_les_exos, user_id)

