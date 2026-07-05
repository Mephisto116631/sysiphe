"""
Sysiphe — Onglets de statistiques (Graphiques, Records, Repos, Paramètres, Apparence, Calendrier).
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
    """Applique le thème sélectionné au graphique Plotly."""
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

    if   preset == "7 derniers jours":   start_date, end_date = today - timedelta(days=7),  today
    elif preset == "30 derniers jours":  start_date, end_date = today - timedelta(days=30), today
    elif preset == "Ce mois":            start_date, end_date = today.replace(day=1), today
    elif preset == "3 derniers mois":    start_date, end_date = today - timedelta(days=90), today
    elif preset == "Tout l'historique":  start_date, end_date = min_db_date, max_db_date
    else:
        with col_custom:
            sel = st.date_input("Période personnalisée", [min_db_date, max_db_date])
            start_date, end_date = (sel[0], sel[1]) if len(sel) == 2 else (min_db_date, max_db_date)

    df_period = df_global[(df_global["date"] >= start_date) & (df_global["date"] <= end_date)]

    if df_period.empty:
        st.warning("Aucune donnée disponible pour cette période.")
        return
        
    t_colors = THEMES.get(current_theme, THEMES["Abysse"])["colors"]

    # Planche — ffill
    if include_planche:
        df_planche = df_period[df_period["exercice"].str.lower() == "planche"]
        if not df_planche.empty:
            df_g_p  = df_planche.groupby(["date", "variante"])["effort_pondere"].max().reset_index()
            pivot_p = lisser_donnees(df_g_p, "date", "variante", "effort_pondere", fill_method="ffill")
            if not pivot_p.empty:
                df_melt_p = pivot_p.reset_index().melt(id_vars="date", var_name="Variante", value_name="Effort")
                fig_p = px.line(df_melt_p, x="date", y="Effort", color="Variante",
                                title="Évolution Planche — effort pondéré", color_discrete_sequence=t_colors)
                fig_p.update_traces(connectgaps=True, hovertemplate="%{y:.0f} pts")
                fig_p = _apply_plotly_theme(fig_p, current_theme)
                st.plotly_chart(fig_p, use_container_width=True)
                df_best = df_planche.groupby("date")["effort_pondere"].max().reset_index()
                _plateau_badge(df_best["date"], df_best["effort_pondere"], "Planche")

    # Musculation — brut (sans lissage)
    if tous_les_exos:
        select_exos = st.multiselect("Sélectionner les exercices", tous_les_exos,
                                     default=tous_les_exos[:3] if len(tous_les_exos) >= 3 else tous_les_exos)
        if select_exos:
            df_muscu = df_period[df_period["exercice"].str.lower().isin([e.lower().strip() for e in select_exos])].copy()
            if not df_muscu.empty:
                if "charge" not in df_muscu.columns:
                    df_muscu["charge"] = 0.0
                df_muscu["charge"] = pd.to_numeric(df_muscu["charge"], errors="coerce").fillna(0.0)
                df_muscu["performance"] = pd.to_numeric(df_muscu["performance"], errors="coerce").fillna(0.0)
                df_muscu["volume
