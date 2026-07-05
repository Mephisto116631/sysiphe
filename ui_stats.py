"""
Sysiphe — Onglets de statistiques (Graphiques, Records, Repos, Paramètres, Apparence).
"""
from datetime import datetime, timedelta
import pandas as pd
import streamlit as st
import plotly.express as px
import plotly.graph_objects as go

from data import lisser_donnees, detect_plateau, suggest_next_session
from supabase_io import update_exercise_name, save_user_settings

# =========================================================================
# CONFIGURATION DES THÈMES
# =========================================================================
THEMES = {
    "Abysse": {
        "bg": "rgba(0,0,0,0)", "text": "#E2E8F0", "grid": "#334155",
        "colors": ["#00E5FF", "#39FF14", "#B026FF", "#FFD700"],
        "cal_event": "#00E5FF"
    },
    "Magma": {
        "bg": "#1E1E1E", "text": "#F5F5F5", "grid": "#424242",
        "colors": ["#F44336", "#FF9800", "#FFEB3B", "#FFFFFF"],
        "cal_event": "#FF9800"
    },
    "Analytique": {
        "bg": "#0F172A", "text": "#CBD5E1", "grid": "#1E293B",
        "colors": ["#38BDF8", "#818CF8", "#34D399", "#F472B6"],
        "cal_event": "#38BDF8"
    },
    "Épuré": {
        "bg": "#FFFFFF", "text": "#333333", "grid": "#E5E7EB",
        "colors": ["#1E3A8A", "#059669", "#D97706", "#DC2626"],
        "cal_event": "#1E3A8A"
    }
}

def _apply_plotly_theme(fig, theme_name: str):
    t = THEMES.get(theme_name, THEMES["Abysse"])
    fig.update_layout(
        plot_bgcolor=t["bg"], paper_bgcolor=t["bg"], font=dict(color=t["text"]),
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
        st.success(f"📈 {label} : en progression (21 derniers jours).")
    elif result["status"] == "regression":
        st.warning(f"📉 {label} : en baisse (21 derniers jours).")
    elif result["status"] == "plateau":
        st.info(f"➖ {label} : stable (21 derniers jours).")

# =========================================================================
# GRAPHIQUES
# =========================================================================
def render_graph_tab(df_global: pd.DataFrame, tous_les_exos: list, include_planche: bool, current_theme: str) -> None:
    if df_global.empty: return
    col_preset, col_custom = st.columns([1, 2])
    with col_preset:
        preset = st.selectbox("Période", ["Tout l'historique", "7 derniers jours", "30 derniers jours", "Ce mois", "3 derniers mois", "Personnalisée"])
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
    if df_period.empty: return
    
    t_colors = THEMES.get(current_theme, THEMES["Abysse"])["colors"]
    
    if include_planche:
        df_planche = df_period[df_period["exercice"].str.lower() == "planche"]
        if not df_planche.empty:
            df_g_p = df_planche.groupby(["date", "variante"])["effort_pondere"].max().reset_index()
            pivot_p = lisser_donnees(df_g_p, "date", "variante", "effort_pondere", fill_method="ffill")
            if not pivot_p.empty:
                df_melt_p = pivot_p.reset_index().melt(id_vars="date", var_name="Variante", value_name="Effort")
                fig_p = px.line(df_melt_p, x="date", y="Effort", color="Variante", title="Évolution Planche", color_discrete_sequence=t_colors)
                fig_p = _apply_plotly_theme(fig_p, current_theme)
                st.plotly_chart(fig_p, use_container_width=True)
                
    if tous_les_exos:
        select_exos = st.multiselect("Sélectionner les exercices", tous_les_exos, default=tous_les_exos[:3] if len(tous_les_exos) >= 3 else tous_les_exos)
        if select_exos:
            df_muscu = df_period[df_period["exercice"].str.lower().isin([e.lower().strip() for e in select_exos])].copy()
            if not df_muscu.empty:
                if "charge" not in df_muscu.columns: df_muscu["charge"] = 0.0
                df_muscu["charge"] = pd.to_numeric(df_muscu["charge"], errors="coerce").fillna(0.0)
                df_muscu["performance"] = pd.to_numeric(df_muscu["performance"], errors="coerce").fillna(0.0)
                df_muscu["volume"] = df_muscu.apply(lambda r: r["performance"] * r["charge"] if r["charge"] > 0 else r["performance"], axis=1)
                df_g_vol = df_muscu.groupby(["date", "exercice"])["volume"].sum().reset_index()
                fig_v = px.line(df_g_vol, x="date", y="volume", color="exercice", markers=True, title="Volume brut total", color_discrete_sequence=t_colors)
                fig_v = _apply_plotly_theme(fig_v, current_theme)
                st.plotly_chart(fig_v, use_container_width=True)

# =========================================================================
# RECORDS
# =========================================================================
def render_records_tab(df_global: pd.DataFrame) -> None:
    if df_global.empty: return
    c1, c2 = st.columns(2)
    with c1:
        st.write("#### 🤸 Record Planche")
        df_p = df_global[(df_global["exercice"].str.lower() == "planche") & (df_global["effort_pondere"] > 0)].copy()
        if not df_p.empty:
            for col, default in [("variante", "Full"), ("elastique", "Aucun"), ("tension", "N/A")]:
                df_p[col] = df_p[col].fillna(default).replace("", default)
            df_p  = df_p.sort_values(["effort_pondere", "performance"], ascending=[False, False])
            df_pr = df_p.drop_duplicates(subset=["variante", "elastique", "tension"])[["date", "variante", "elastique", "tension", "performance", "effort_pondere"]].copy()
            df_pr.columns = ["Date", "Variante", "Élastique", "Tension", "Temps (s)", "Effort"]
            st.dataframe(df_pr, use_container_width=True, hide_index=True)
    with c2:
        st.write("#### 💪 Top Musculation")
        df_m = df_global[df_global["exercice"].str.lower() != "planche"].copy()
        if not df_m.empty:
            if "charge" not in df_m.columns: df_m["charge"] = 0.0
            df_m["charge"] = pd.to_numeric(df_m["charge"], errors="coerce").fillna(0.0)
            df_m["volume"] = df_m.apply(lambda r: r["performance"] * r["charge"] if r["charge"] > 0 else r["performance"], axis=1)
            df_vol = df_m.groupby(["exercice", "date"])["volume"].sum().reset_index()
            idx_max = df_vol.groupby("exercice")["volume"].idxmax()
            df_pr_muscu = df_vol.loc[idx_max].sort_values("volume", ascending=False)
            st.dataframe(df_pr_muscu, use_container_width=True, hide_index=True)

# =========================================================================
# REPOS
# =========================================================================
def render_repos_tab(df_global: pd.DataFrame) -> None:
    if df_global.empty: return
    df_all_dates = pd.DataFrame({"date": df_global["date"].unique()}).sort_values("date")
    if len(df_all_dates) <= 1: return
    df_all_dates["date_dt"] = pd.to_datetime(df_all_dates["date"])
    df_all_dates["jours_repos"] = df_all_dates["date_dt"].diff().dt.days - 1
    suggestion = suggest_next_session(df_global["date"].unique().tolist())
    st.metric("Repos habituel", f"{suggestion['mode_repos']} j")

# =========================================================================
# THEMES ET PARAMÈTRES
# =========================================================================
def render_theme_tab():
    st.subheader("🎨 Apparence du Tableau de Bord")
    current = st.session_state.get("app_theme", "Abysse")
    col1, col2 = st.columns([1, 2])
    with col1:
        choix = st.radio("Thème global", list(THEMES.keys()), index=list(THEMES.keys()).index(current))
    with col2:
        st.write("**Aperçu :**")
        c_list = THEMES[choix]["colors"]
        html_colors = "".join([f"<div style='background-color:{c}; width:30px; height:30px; border-radius:50%; display:inline-block; margin-right:10px;'></div>" for c in c_list])
        st.markdown(html_colors, unsafe_allow_html=True)
    if st.button("✅ Appliquer le thème", use_container_width=True):
        st.session_state.app_theme = choix
        st.rerun()

def render_param_tab(df_global: pd.DataFrame, tous_les_exos: list, user_id: str) -> None:
    st.subheader("⚙️ Configuration")
    st.checkbox("Inclure la Planche", key="include_planche")
    if st.button("📥 Exporter CSV"): st.write("Export fonctionnel en production.")

# =========================================================================
# POINT D'ENTRÉE
# =========================================================================
def render_stats_tabs(df_global: pd.DataFrame, tous_les_exos: list, user_id: str) -> None:
    current_theme = st.session_state.get("app_theme", "Abysse")
    tab_graph, tab_records, tab_repos, tab_theme, tab_param = st.tabs([
        "📈 Graphiques", "🏆 Records", "💤 Repos", "🎨 Apparence", "⚙️ Paramètres"
    ])
    with tab_graph: render_graph_tab(df_global, tous_les_exos, st.session_state.include_planche, current_theme)
    with tab_records: render_records_tab(df_global)
    with tab_repos: render_repos_tab(df_global)
    with tab_theme: render_theme_tab()
    with tab_param: render_param_tab(df_global, tous_les_exos, user_id)
