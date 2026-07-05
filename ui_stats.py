"""
Sysiphe — Onglets de statistiques (Graphiques, Records, Repos, Paramètres, Calendrier).
Sans dépendance numpy — listes Python pures pour la heatmap.
"""
from datetime import datetime, timedelta
import pandas as pd
import streamlit as st
import plotly.express as px
import plotly.graph_objects as go

from data import lisser_donnees, detect_plateau, suggest_next_session, compute_daily_activity
from supabase_io import update_exercise_name, save_user_settings


def _plateau_badge(dates, values, label: str) -> None:
    """Affiche un badge de tendance (progression / plateau / régression)."""
    result = detect_plateau(list(dates), list(values), window_days=21)
    if result["status"] == "progress":
        st.success(f"📈 {label} : en progression sur les 21 derniers jours.")
    elif result["status"] == "regression":
        st.warning(f"📉 {label} : en baisse sur les 21 derniers jours — envisage un deload.")
    elif result["status"] == "plateau":
        st.info(f"➖ {label} : stable sur les 21 derniers jours (plateau).")


# =========================================================================
# CALENDRIER D'ACTIVITÉ (style GitHub contributions) — sans numpy
# =========================================================================
def render_calendar_tab(df_global: pd.DataFrame) -> None:
    st.subheader("📅 Calendrier d'activité")
    if df_global.empty:
        st.info("Pas encore de données pour générer le calendrier.")
        return

    try:
        annees_dispo = sorted({d.year for d in df_global["date"].unique()}, reverse=True)
        annee_sel = st.selectbox("Année", annees_dispo, key="calendar_year")

        activity = df_global.groupby("date").size().to_dict()
        df_cal = compute_daily_activity(activity, annee_sel)

        total_series = int(df_cal["count"].sum())
        nb_jours_actifs = int((df_cal["count"] > 0).sum())
        st.caption(
            f"**{annee_sel} : {total_series} séries enregistrées "
            f"sur {nb_jours_actifs} jour(s) d'entraînement**"
        )

        ncols = int(df_cal["week_index"].max()) + 1

        # Matrices en listes Python pures — aucune dépendance numpy
        z          = [[None] * ncols for _ in range(7)]
        text_hover = [[""]   * ncols for _ in range(7)]

        for _, row in df_cal.iterrows():
            w   = int(row["weekday"])
            wk  = int(row["week_index"])
            cnt = int(row["count"])
            z[w][wk]          = cnt
            text_hover[w][wk] = f"{row['date'].strftime('%d %b %Y')}<br>{cnt} série(s)"

        month_positions = df_cal.groupby("month")["week_index"].min().to_dict()
        month_names = ["Jan","Fév","Mar","Avr","Mai","Jun","Jul","Aoû","Sep","Oct","Nov","Déc"]

        zmax_val = max(1, total_series)   # évite zmin == zmax quand tout est à 0

        fig = go.Figure(data=go.Heatmap(
            z=z,
            text=text_hover,
            hoverinfo="text",
            colorscale=[
                [0,    "#161b22"],
                [0.01, "#0e4429"],
                [0.35, "#006d32"],
                [0.65, "#26a641"],
                [1,    "#39d353"],
            ],
            showscale=False,
            xgap=3,
            ygap=3,
            zmin=0,
            zmax=zmax_val,
        ))
        
        # Optimisation des marges pour mobile
        fig.update_layout(
            yaxis=dict(
                tickmode="array",
                tickvals=list(range(7)),
                ticktext=["Lun","Mar","Mer","Jeu","Ven","Sam","Dim"],
                autorange="reversed",
            ),
            xaxis=dict(
                tickmode="array",
                tickvals=[month_positions[m] for m in sorted(month_positions)],
                ticktext=[month_names[m - 1] for m in sorted(month_positions)],
                side="top",
            ),
            height=220,
            margin=dict(l=30, r=10, t=30, b=10), # Marges réduites
            plot_bgcolor="rgba(0,0,0,0)",
            paper_bgcolor="rgba(0,0,0,0)",
        )
        st.plotly_chart(fig, use_container_width=True)
        st.caption("Intensité = nombre de séries loggées ce jour-là (planche + musculation).")

    except Exception as e:
        st.error(f"Erreur lors du rendu du calendrier : {e}")


# =========================================================================
# GRAPHIQUES
# =========================================================================
def render_graph_tab(df_global: pd.DataFrame, tous_les_exos: list, include_planche: bool) -> None:
    if df_global.empty:
        st.write("Pas de données pour les graphiques.")
        return

    col_preset, col_custom = st.columns([1, 2])
    with col_preset:
        preset = st.selectbox("Période", [
            "Tout l'historique", "7 derniers jours", "30 derniers jours",
            "Ce mois", "3 derniers mois", "Personnalisée",
        ])

    today       = datetime.now().date()
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

    df_period = df_global[
        (df_global["date"] >= start_date) & (df_global["date"] <= end_date)
    ]

    if df_period.empty:
        st.warning("Aucune donnée disponible pour cette période.")
        return

    # Planche — ffill
    if include_planche:
        df_planche = df_period[df_period["exercice"].str.lower() == "planche"]
        if not df_planche.empty:
            df_g_p  = df_planche.groupby(["date", "variante"])["effort_pondere"].max().reset_index()
            pivot_p = lisser_donnees(df_g_p, "date", "variante", "effort_pondere", fill_method="ffill")
            if not pivot_p.empty:
                df_melt_p = pivot_p.reset_index().melt(id_vars="date", var_name="Variante", value_name="Effort")
                fig_p = px.line(df_melt_p, x="date", y="Effort", color="Variante",
                                title="Évolution Planche — effort pondéré")
                fig_p.update_traces(connectgaps=True, hovertemplate="%{y:.0f} pts")
                
                # Optimisation légende et marges
                fig_p.update_layout(
                    hovermode="x unified", 
                    xaxis_title="", 
                    yaxis_title="Effort Pondéré",
                    legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="center", x=0.5),
                    margin=dict(l=10, r=10, t=40, b=10),
                    xaxis=dict(tickformat="%d/%m")
                )
                st.plotly_chart(fig_p, use_container_width=True)
                df_best = df_planche.groupby("date")["effort_pondere"].max().reset_index()
                _plateau_badge(df_best["date"], df_best["effort_pondere"], "Planche")

        # Musculation — volume (tonnage si charge renseignée)
    if tous_les_exos:
        select_exos = st.multiselect(
            "Sélectionner les exercices", tous_les_exos,
            default=tous_les_exos[:3] if len(tous_les_exos) >= 3 else tous_les_exos,
        )
        if select_exos:
            df_muscu = df_period[
                df_period["exercice"].str.lower().isin([e.lower().strip() for e in select_exos])
            ].copy()
            
            if not df_muscu.empty:
                if "charge" not in df_muscu.columns:
                    df_muscu["charge"] = 0.0
                
                # 🔒 SÉCURITÉ : On force la conversion en nombres pour s'assurer 
                # que 10 + 10 fasse bien 20, et non pas "1010"
                df_muscu["charge"] = pd.to_numeric(df_muscu["charge"], errors="coerce").fillna(0.0)
                df_muscu["performance"] = pd.to_numeric(df_muscu["performance"], errors="coerce").fillna(0.0)
                
                # Calcul du volume (Tonnage si charge, sinon Reps)
                df_muscu["volume"] = df_muscu.apply(
                    lambda r: r["performance"] * r["charge"]
                              if r["charge"] > 0 else r["performance"],
                    axis=1,
                )
                a_du_charge = (df_muscu["charge"] > 0).any()
                label_y     = "Tonnage (kg)" if a_du_charge else "Reps"

                # 📊 VRAIE SOMME par jour (sans aucun lissage)
                df_g_vol = df_muscu.groupby(["date", "exercice"])["volume"].sum().reset_index()
                
                # Affichage avec des points pour bien voir chaque séance
                fig_v = px.line(
                    df_g_vol, x="date", y="volume", color="exercice", markers=True,
                    title=f"Volume brut total par séance ({label_y.lower()})"
                )
                fig_v.update_traces(hovertemplate="%{y:.0f}")
                
                # Optimisation mobile (déjà en place)
                fig_v.update_layout(
                    hovermode="x unified", 
                    xaxis_title="", 
                    yaxis_title=label_y,
                    legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="center", x=0.5),
                    margin=dict(l=10, r=10, t=40, b=10),
                    xaxis=dict(tickformat="%d/%m")
                )
                st.plotly_chart(fig_v, use_container_width=True)

                for exo in select_exos:
                    sous_df = df_g_vol[df_g_vol["exercice"].str.lower() == exo.lower().strip()]
                    if not sous_df.empty:
                        _plateau_badge(sous_df["date"], sous_df["volume"], exo)

    # Volume par catégorie — zero fill
    df_g_cat  = df_period.groupby(["date", "categorie"]).size().reset_index(name="nb_series")
    pivot_cat = lisser_donnees(df_g_cat, "date", "categorie", "nb_series", fill_method="zero")
    if not pivot_cat.empty:
        df_melt_c = pivot_cat.reset_index().melt(id_vars="date", var_name="Catégorie", value_name="Séries")
        fig_c = px.line(df_melt_c, x="date", y="Séries", color="Catégorie",
                        title="Nombre de séries par catégorie")
        fig_c.update_traces(connectgaps=True, hovertemplate="%{y:.0f} Séries")
        
        # Optimisation légende et marges
        fig_c.update_layout(
            hovermode="x unified", 
            xaxis_title="", 
            yaxis_title="Volume (Séries)",
            legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="center", x=0.5),
            margin=dict(l=10, r=10, t=40, b=10),
            xaxis=dict(tickformat="%d/%m")
        )
        st.plotly_chart(fig_c, use_container_width=True)


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
        habitudes["Jours"] = habitudes["Jours"].astype(int).astype(str) + " j"
        fig_pie = px.pie(habitudes, values="Nb", names="Jours",
                         title="Répartition de tes formats de repos")
        # Optimisation du graphique en secteurs
        fig_pie.update_layout(
            legend=dict(orientation="h", yanchor="bottom", y=-0.2, xanchor="center", x=0.5),
            margin=dict(l=10, r=10, t=40, b=10)
        )
        st.plotly_chart(fig_pie, use_container_width=True)

    with cr2:
        fig_bar = px.bar(df_repos_stats, x="date_dt", y="jours_repos",
                         title="Chronologie des jours de repos accordés")
        fig_bar.update_layout(
            xaxis_title="", 
            yaxis_title="Jours de repos consécutifs",
            margin=dict(l=10, r=10, t=40, b=10),
            xaxis=dict(tickformat="%d/%m")
        )
        fig_bar.update_traces(
            marker_color="#1f77b4",
            hovertemplate="Reprise : %{x}<br>Repos : %{y} jours",
        )
        st.plotly_chart(fig_bar, use_container_width=True)

        st.write("#### 📜 Dernières tranches de récupération")
        df_log = df_repos_stats[["date", "jours_repos"]].copy()
        df_log.columns = ["Date de Reprise", "Jours de Repos"]
        df_log["Jours de Repos"] = df_log["Jours de Repos"].astype(int)
        st.dataframe(
            df_log.sort_values("Date de Reprise", ascending=False),
            use_container_width=True, hide_index=True,
        )


# =========================================================================
# PARAMÈTRES
# =========================================================================
def render_param_tab(df_global: pd.DataFrame, tous_les_exos: list, user_id: str) -> None:
    st.subheader("⚙️ Configuration Générale")

    st.checkbox("Inclure la Planche dans la saisie", key="include_planche")
    st.number_input("Taille de la moyenne glissante (séances)",
                    min_value=1, max_value=30, step=1, key="nb_days_avg")
    st.number_input("Poids de référence pour le calcul d'isométrie (kg)",
                    min_value=40, max_value=200, step=1, key="weight")

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
    st.caption(
        "Ces scores pondèrent la difficulté de chaque variante. "
        "Sauvegardés sur ton compte, ils persistent entre tes sessions."
    )
    # Remplacement des colonnes rigides par un flux naturel plus responsive
    updated_scores = {}
    for var, score in st.session_state.config_variantes.items():
        updated_scores[var] = st.number_input(
            var, min_value=1, max_value=20, value=int(score), step=1, key=f"cal_{var}"
        )
        
    if st.button("✅ Appliquer et sauvegarder la calibration", use_container_width=True):
        st.session_state.config_variantes = updated_scores
        ok = save_user_settings(user_id, updated_scores)
        st.cache_data.clear()
        if ok:
            st.success("Scores mis à jour et sauvegardés sur ton compte.")
        else:
            st.warning(
                "Scores appliqués pour cette session, mais la sauvegarde a échoué "
                "(table `user_settings` absente ? voir SETUP.md)."
            )
        st.rerun()

    st.write("---")
    st.subheader("✏️ Renommer un exercice")
    st.markdown("Corrige les fautes de frappe ou uniformise les noms dans tout ton historique.")
    if tous_les_exos:
        # Adaptation de l'affichage mobile pour le module de renommage
        exo_a_renommer = st.selectbox("Exercice à modifier", tous_les_exos)
        nouveau_nom    = st.text_input("Nouveau nom")
        
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
                    st.error(f"Erreur lors du renommage : {e}")
    else:
        st.caption("Aucun exercice personnalisé enregistré pour le moment.")


# =========================================================================
# POINT D'ENTRÉE UNIQUE
# =========================================================================
def render_stats_tabs(df_global: pd.DataFrame, tous_les_exos: list, user_id: str) -> None:
    tab_graph, tab_calendar, tab_records, tab_repos, tab_param = st.tabs([
        "📈 Graphiques", "📅 Calendrier", "🏆 Records (PRs)", "💤 Analyse du Repos", "⚙️ Paramètres",
    ])
    with tab_graph:
        render_graph_tab(df_global, tous_les_exos, st.session_state.include_planche)
    with tab_calendar:
        render_calendar_tab(df_global)
    with tab_records:
        render_records_tab(df_global)
    with tab_repos:
        render_repos_tab(df_global)
    with tab_param:
        render_param_tab(df_global, tous_les_exos, user_id)
