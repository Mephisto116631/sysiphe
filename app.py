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

    # Planche
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

    # Musculation
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
                df_muscu["volume"] = df_muscu.apply(
                    lambda r: r["performance"] * r["charge"] if r["charge"] > 0 else r["performance"], axis=1
                )
                label_y = "Tonnage (kg)" if (df_muscu["charge"] > 0).any() else "Reps"
                df_g_vol = df_muscu.groupby(["date", "exercice"])["volume"].sum().reset_index()

                fig_v = px.line(df_g_vol, x="date", y="volume", color="exercice", markers=True,
                                title=f"Volume brut total ({label_y.lower()})", color_discrete_sequence=t_colors)
                fig_v.update_traces(hovertemplate="%{y:.0f}")
                fig_v = _apply_plotly_theme(fig_v, current_theme)
                st.plotly_chart(fig_v, use_container_width=True)

    # Volume par catégorie
    df_g_cat = df_period.groupby(["date", "categorie"]).size().reset_index(name="nb_series")
    pivot_cat = lisser_donnees(df_g_cat, "date", "categorie", "nb_series", fill_method="zero")
    if not pivot_cat.empty:
        df_melt_c = pivot_cat.reset_index().melt(id_vars="date", var_name="Catégorie", value_name="Séries")
        fig_c = px.line(df_melt_c, x="date", y="Séries", color="Catégorie",
                        title="Nombre de séries par catégorie", color_discrete_sequence=t_colors)
        fig_c.update_traces(connectgaps=True, hovertemplate="%{y:.0f} Séries")
        fig_c = _apply_plotly_theme(fig_c, current_theme)
        st.plotly_chart(fig_c, use_container_width=True)


# =========================================================================
# THEMES (Apparence)
# =========================================================================
def render_theme_tab():
    st.subheader("🎨 Apparence du Tableau de Bord")
    st.markdown("Choisis le thème de tes graphiques et de ton calendrier.")
    
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
# RECORDS
# =========================================================================
def render_records_tab(df_global: pd.DataFrame) -> None:
    if df_global.empty:
        st.write("Pas de données.")
        return

    c1, c2 = st.columns(2)
    with c1:
        st.write("#### 🤸 Record Planche")
        df_p = df_global[
            (df_global["exercice"].str.lower() == "planche") &
            (df_global["effort_pondere"] > 0)
        ].copy()
        if not df_p.empty:
            for col, default in [("variante", "Full"), ("elastique", "Aucun"), ("tension", "N/A")]:
                df_p[col] = df_p[col].fillna(default).replace("", default)
            df_p  = df_p.sort_values(["effort_pondere", "performance"], ascending=[False, False])
            df_pr = (
                df_p.drop_duplicates(subset=["variante", "elastique", "tension"])
                [["date", "variante", "elastique", "tension", "performance", "effort_pondere"]]
                .copy()
            )
            df_pr.columns = ["Date", "Variante", "Élastique", "Tension", "Temps (s)", "Effort"]
            df_pr[["Temps (s)", "Effort"]] = df_pr[["Temps (s)", "Effort"]].astype(int)
            st.dataframe(
                df_pr.style.background_gradient(subset=["Effort", "Temps (s)"], cmap="YlOrRd"),
                use_container_width=True, hide_index=True,
            )
        else:
            st.info("Aucun record de Planche enregistré.")

    with c2:
        st.write("#### 💪 Top Musculation (Volume max / séance)")
        df_m = df_global[df_global["exercice"].str.lower() != "planche"].copy()
        if not df_m.empty:
            if "charge" not in df_m.columns:
                df_m["charge"] = 0.0
            df_m["charge"] = pd.to_numeric(df_m["charge"], errors="coerce").fillna(0.0)
            df_m["volume"] = df_m.apply(
                lambda r: r["performance"] * r["charge"]
                          if r["charge"] > 0 else r["performance"],
                axis=1,
            )
            df_vol  = df_m.groupby(["exercice", "date"])["volume"].sum().reset_index()
            idx_max = df_vol.groupby("exercice")["volume"].idxmax()
            a_du_charge_global = (df_m["charge"] > 0).any()
            label   = "Tonnage Max (kg)" if a_du_charge_global else "Volume Max (reps)"
            df_pr_muscu = (
                df_vol.loc[idx_max]
                .rename(columns={"volume": label, "date": "Date du PR", "exercice": "Exercice"})
                [["Exercice", label, "Date du PR"]]
                .sort_values(label, ascending=False)
            )
            df_pr_muscu[label] = df_pr_muscu[label].astype(int)
            st.dataframe(
                df_pr_muscu.style.background_gradient(subset=[label], cmap="Blues"),
                use_container_width=True, hide_index=True,
            )
        else:
            st.info("Aucun exercice de musculation enregistré.")


# =========================================================================
# REPOS
# =========================================================================
def render_repos_tab(df_global: pd.DataFrame) -> None:
    st.subheader("💤 Analyse Mathématique de la Récupération")
    if df_global.empty:
        return

    df_all_dates = pd.DataFrame({"date": df_global["date"].unique()}).sort_values("date")
    if len(df_all_dates) <= 1:
        st.info("Ajoute au moins deux séances à des dates différentes pour générer l'analyse.")
        return

    df_all_dates["date_dt"]     = pd.to_datetime(df_all_dates["date"])
    df_all_dates["jours_repos"] = df_all_dates["date_dt"].diff().dt.days - 1
    df_repos_stats = df_all_dates.dropna()
    suggestion     = suggest_next_session(df_global["date"].unique().tolist())

    cr1, cr2 = st.columns([1, 2])
    with cr1:
        st.metric("Repos moyen",           f"{int(round(df_repos_stats['jours_repos'].mean()))} j")
        st.metric("Repos habituel (mode)", f"{suggestion['mode_repos']} j")
        st.metric("Plus longue coupure",   f"{int(df_repos_stats['jours_repos'].max())} j")
        if suggestion["next_session"] is not None:
            st.success(
                f"🔜 Prochaine séance optimale : "
                f"**{suggestion['next_session'].strftime('%A %d %B')}**"
            )
        habitudes = df_repos_stats["jours_repos"].value_counts().reset_index()
        habitudes.columns = ["Jours", "Nb"]
        habitudes["Jours"] = habitudes
