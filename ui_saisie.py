"""
Sysiphe — Interface de saisie (Planche + Exercices) et panneau KPI du jour.
"""
from datetime import datetime, timedelta
import pandas as pd
import streamlit as st

from data import CONFIG, DEFAULT_FORMES, calculer_effort, parse_reps, compute_period_comparison, build_ics_event, suggest_next_session
from supabase_io import insert_perfs, delete_perfs
from ui_helpers import is_debounced


def _intensity_color(ratio: float) -> str:
    """Vert -> Orange -> Rouge selon un ratio 0..1+ (ex: effort/record, score/max_score)."""
    ratio = max(0.0, min(1.0, ratio))
    if ratio < 0.5:
        # Vert -> Orange sur [0, 0.5]
        t = ratio / 0.5
        r, g, b = (int(34 + t * (245 - 34)), int(197 + t * (158 - 197)), int(94 + t * (11 - 94)))
    else:
        # Orange -> Rouge sur [0.5, 1]
        t = (ratio - 0.5) / 0.5
        r, g, b = (int(245 + t * (239 - 245)), int(158 + t * (68 - 158)), int(11 + t * (68 - 11)))
    return f"rgb({r},{g},{b})"


def _build_default_planche(df_global: pd.DataFrame, date_active) -> dict:
    """Calcule les valeurs de préremplissage pour le bloc Planche."""
    defaults = {
        "var": "Full", "elas": "Aucun", "tens": "N/A",
        "forms": {i: "Normal" for i in range(1, 6)},
        "times": {i: "" for i in range(1, 6)},
    }
    if df_global.empty:
        return defaults

    df_active = df_global[(df_global["date"] == date_active) &
                          (df_global["exercice"].str.lower() == "planche")]
    if not df_active.empty:
        last = df_active.iloc[0]
        defaults["var"], defaults["elas"], defaults["tens"] = last["variante"], last["elastique"], last["tension"]
        for _, r in df_active.iterrows():
            s = int(r["serie"])
            defaults["forms"][s] = r["forme"] if pd.notna(r["forme"]) else "Normal"
            if pd.notna(r["performance"]):
                p = float(r["performance"])
                defaults["times"][s] = str(int(p) if p.is_integer() else p)
        return defaults

    df_past = df_global[(df_global["date"] < date_active) &
                        (df_global["exercice"].str.lower() == "planche")]
    if not df_past.empty:
        last_date = df_past["date"].max()
        df_last = df_past[df_past["date"] == last_date]
        last = df_last.iloc[0]
        defaults["var"], defaults["elas"], defaults["tens"] = last["variante"], last["elastique"], last["tension"]
        for _, r in df_last.iterrows():
            s = int(r["serie"])
            defaults["forms"][s] = r["forme"] if pd.notna(r["forme"]) else "Normal"
    return defaults


def render_planche_block(df_global: pd.DataFrame, date_active, user_id: str, weight: float,
                         variantes_config: dict, formes_config: dict = None) -> None:
    formes_config = formes_config or DEFAULT_FORMES
    record_planche = 0
    titre = "🤸 PLANCHE"
    if not df_global.empty:
        df_hist = df_global[(df_global["exercice"].str.lower() == "planche") & (df_global["effort_pondere"] > 0)]
        if not df_hist.empty:
            record_planche = int(df_hist["effort_pondere"].max())
            titre = f"🤸 PLANCHE (Record : {record_planche} pts)"

    defaults = _build_default_planche(df_global, date_active)

    with st.expander(titre, expanded=True):
        var_keys = list(variantes_config.keys())
        idx_v = var_keys.index(defaults["var"]) if defaults["var"] in var_keys else 0
        idx_e = list(CONFIG["elastiques"].keys()).index(defaults["elas"]) if defaults["elas"] in CONFIG["elastiques"] else 0
        idx_t = list(CONFIG["tensions"].keys()).index(defaults["tens"]) if defaults["tens"] in CONFIG["tensions"] else 0

        c1, c2, c3 = st.columns(3)
        elas_keys = list(CONFIG["elastiques"].keys())
        tens_keys = list(CONFIG["tensions"].keys())
        # Ordre chronologique = difficulté croissante (score le plus bas → le plus haut)
        forme_keys = [k for k, _ in sorted(formes_config.items(), key=lambda kv: kv[1])]

        # segmented_control renvoie None si on clique sur l'option déjà
        # sélectionnée (comportement togglé natif) : on mémorise donc la
        # dernière valeur confirmée en session_state pour ne jamais perdre
        # la sélection en cours.
        def _persisted_choice(label, options, state_key, default_val, widget_key):
            if state_key not in st.session_state:
                st.session_state[state_key] = default_val
            choice = st.segmented_control(label, options, default=st.session_state[state_key], key=widget_key)
            if choice is not None:
                st.session_state[state_key] = choice
            return st.session_state[state_key]

        with c1:
            var_g = _persisted_choice("Variante", var_keys, f"var_state_{date_active}",
                                       var_keys[idx_v], f"var_g_{date_active}")
        with c2:
            elas_g = _persisted_choice("Élastique", elas_keys, f"elas_state_{date_active}",
                                        elas_keys[idx_e], f"elas_g_{date_active}")
        with c3:
            tens_g = _persisted_choice("Tension", tens_keys, f"tens_state_{date_active}",
                                        tens_keys[idx_t], f"tens_g_{date_active}")

        st.write("---")
        formes_temp, temps_temp, efforts_jour = {}, {}, []
        min_score, max_score = min(formes_config.values()), max(formes_config.values())
        for s in range(1, 6):
            c1, c2, c3 = st.columns([1, 2, 1])
            with c1: t = st.text_input(f"S{s}(s)", value=defaults["times"].get(s, ""), key=f"p_t_{s}_{date_active}")
            with c2:
                f = _persisted_choice(f"F{s}", forme_keys,
                                       f"forme_state_{s}_{date_active}",
                                       defaults["forms"].get(s, "Normal"), f"p_f_{s}_{date_active}")
                # Colore le bouton actif du dropdown Forme selon sa difficulté relative
                ratio_f = ((formes_config.get(f, min_score) - min_score) / (max_score - min_score)
                          if max_score > min_score else 0.5)
                color_f = _intensity_color(ratio_f)
                st.markdown(
                    f"<style>.st-key-p_f_{s}_{date_active} "
                    f"button[data-testid='stBaseButton-segmented_controlActive']"
                    f"{{background:{color_f} !important; border-color:{color_f} !important;}}</style>",
                    unsafe_allow_html=True,
                )
            with c3:
                eff = calculer_effort(var_g, elas_g, tens_g, f, t, weight, variantes_config, formes_config) if t else 0
                ratio_e = (eff / record_planche) if record_planche else 0
                color_e = _intensity_color(ratio_e) if eff > 0 else "inherit"
                st.markdown(
                    f"<div style='text-align:center;'>"
                    f"<div style='font-size:0.8rem;opacity:0.7;'>Effort</div>"
                    f"<div style='font-size:1.6rem;font-weight:700;color:{color_e};'>{eff:.0f}</div>"
                    f"</div>",
                    unsafe_allow_html=True,
                )
            temps_temp[s], formes_temp[s] = t, f
            if t and eff > 0:
                efforts_jour.append(eff)

        if efforts_jour:
            best_today = max(efforts_jour)
            if best_today > record_planche:
                st.success(f"🏆 Nouveau Record ! **{best_today} pts** (ancien : {record_planche} pts)")
            else:
                pct = round(best_today / record_planche * 100) if record_planche else 0
                st.info(f"🎯 Meilleur effort aujourd'hui : **{best_today} pts** ({pct}% du record)")

        if st.button("💾 Enregistrer la Planche", type="primary", use_container_width=True):
            if is_debounced(f"save_planche_{date_active}"):
                st.toast("⏳ Déjà enregistré à l'instant — patiente quelques secondes.")
            else:
                delete_perfs(user_id, str(date_active), "Planche")
                lignes = []
                for s in range(1, 6):
                    t, f = temps_temp[s], formes_temp[s]
                    if t:
                        try:
                            eff = calculer_effort(var_g, elas_g, tens_g, f, t, weight, variantes_config, formes_config)
                            lignes.append({
                                "user_id": user_id, "date": str(date_active),
                                "exercice": "Planche", "serie": s, "performance": float(t),
                                "variante": var_g, "elastique": elas_g, "tension": tens_g,
                                "forme": f, "effort_pondere": eff, "charge": 0,
                                "categorie": "Force Iso", "unite": "Sec",
                            })
                        except ValueError:
                            st.warning(f"Série {s} ignorée : valeur non numérique.")
                if lignes:
                    insert_perfs(lignes)
                    st.cache_data.clear()
                    st.success("Planche enregistrée !")
                    st.rerun()


def render_exercise_block(nom_exo: str, df_global: pd.DataFrame, date_active, user_id: str) -> None:
    df_hist = (df_global[df_global["exercice"].str.lower() == nom_exo.lower().strip()]
              if not df_global.empty else pd.DataFrame())
    pr_absolu = int(df_hist["performance"].max()) if not df_hist.empty else 0
    vol_series = (df_hist.groupby("date")["performance"].sum().sort_index(ascending=False)
                 if not df_hist.empty else pd.Series(dtype=float))
    vol_moyen = vol_series.head(int(st.session_state.nb_days_avg)).mean() if not vol_series.empty else 0

    titre = (f"💪 {nom_exo.upper()} (PR série : {pr_absolu} | Moy. vol. : {vol_moyen:.0f})"
            if not df_hist.empty else f"💪 {nom_exo.upper()} (Nouvel Exercice)")

    with st.expander(titre, expanded=True):
        p_today, cat_init, charge_init = [], "Musculation", 0.0
        if not df_global.empty:
            df_today = df_global[(df_global["date"] == date_active) &
                                 (df_global["exercice"].str.lower() == nom_exo.lower().strip())]
            if not df_today.empty:
                p_today = df_today["performance"].tolist()
                cat_init = df_today.iloc[0]["categorie"]
                charge_init = float(df_today.iloc[0].get("charge", 0) or 0)

        val_init = " ".join([str(int(p) if float(p).is_integer() else p) for p in p_today if pd.notna(p)])

        c_input, c_m1, c_m2, c_btn = st.columns([2.5, 1, 1, 0.5])
        with c_input:
            raw_input = st.text_input("Séries", value=val_init, key=f"perf_{nom_exo}_{date_active}",
                                      placeholder="ex: 12 10 8", label_visibility="collapsed")
            cat_exo = st.text_input("Catégorie", value=cat_init, key=f"cat_{nom_exo}_{date_active}",
                                    label_visibility="collapsed")
        charge_kg = st.number_input(
            "Charge externe (kg) — laisser à 0 pour un exercice au poids du corps",
            min_value=0.0, max_value=300.0, step=0.5, value=charge_init,
            key=f"charge_{nom_exo}_{date_active}",
        )

        total_reps, nb_series, max_serie, liste_reps = 0, 0, 0, []
        if raw_input:
            try:
                liste_reps = parse_reps(raw_input)
                total_reps = int(sum(liste_reps))
                nb_series = len(liste_reps)
                max_serie = int(max(liste_reps))
            except ValueError as e:
                st.warning(f"Valeur invalide : {e}")

        with c_m1:
            label_total = "Tonnage (kg)" if charge_kg > 0 else "Total Reps"
            valeur_total = f"{total_reps * charge_kg:.0f}" if charge_kg > 0 else total_reps
            delta_pct = None
            if vol_moyen > 0 and total_reps > 0:
                pct = (total_reps / vol_moyen - 1) * 100
                delta_pct = f"{pct:+.0f}% vs moy."
            st.metric(label_total, valeur_total, delta=delta_pct)
        with c_m2:
            st.metric("Séries", nb_series)
        with c_btn:
            st.write("")
            if st.button("🗑️", key=f"rem_{nom_exo}_{date_active}", use_container_width=True):
                st.session_state.exos_du_jour.remove(nom_exo)
                delete_perfs(user_id, str(date_active), nom_exo)
                st.cache_data.clear()
                st.rerun()

        if max_serie > 0 and pr_absolu > 0 and max_serie > pr_absolu:
            st.success(f"🏆 Nouveau PR en série ! **{max_serie} reps** (ancien : {pr_absolu})")

        if st.button(f"Enregistrer {nom_exo}", key=f"save_{nom_exo}_{date_active}"):
            action_key = f"save_exo_{nom_exo}_{date_active}"
            if is_debounced(action_key):
                st.toast("⏳ Déjà enregistré à l'instant — patiente quelques secondes.")
            elif liste_reps:
                delete_perfs(user_id, str(date_active), nom_exo)
                lignes = [
                    {
                        "user_id": user_id, "date": str(date_active),
                        "exercice": nom_exo, "serie": i + 1, "performance": float(v),
                        "variante": None, "elastique": None, "tension": None, "forme": None,
                        "effort_pondere": 0, "charge": charge_kg,
                        "categorie": cat_exo, "unite": "Reps",
                    }
                    for i, v in enumerate(liste_reps)
                ]
                insert_perfs(lignes)
                st.cache_data.clear()
                st.success(f"{nom_exo} sauvegardé !")
                st.rerun()


def render_kpi_panel(df_global: pd.DataFrame, date_active) -> None:
    """Panneau de droite : stats du jour, comparaison de période, prochaine séance, rappel ICS."""
    st.markdown("### 📊 Aujourd'hui")
    if df_global.empty:
        st.info("Pas encore de données.")
        return

    df_today = df_global[df_global["date"] == date_active]
    if not df_today.empty:
        df_reps = df_today[df_today["unite"] == "Reps"]
        nb_exos = df_today[df_today["exercice"].str.lower() != "planche"]["exercice"].nunique()
        vol_tot = int(df_reps["performance"].sum()) if not df_reps.empty else 0
        best_eff = int(df_today["effort_pondere"].max())
        st.metric("Exercices", nb_exos)
        st.metric("Volume total (reps)", vol_tot)
        if best_eff > 0:
            st.metric("Meilleur effort planche", f"{best_eff} pts")
    else:
        st.info("Aucune saisie pour cette date.")

    # --- Comparaison semaine courante vs semaine précédente ---
    st.markdown("---")
    st.markdown("##### 📅 Cette semaine vs précédente")
    today = datetime.now().date()
    start_week = today - timedelta(days=today.weekday())
    end_week = start_week + timedelta(days=6)
    start_prev = start_week - timedelta(days=7)
    end_prev = start_week - timedelta(days=1)

    df_reps_global = df_global[df_global["unite"] == "Reps"].copy()
    if not df_reps_global.empty:
        df_reps_global["date_dt"] = pd.to_datetime(df_reps_global["date"])
        comp = compute_period_comparison(
            df_reps_global, "date_dt", "performance",
            pd.Timestamp(start_week), pd.Timestamp(end_week),
            pd.Timestamp(start_prev), pd.Timestamp(end_prev),
        )
        delta_label = f"{comp['delta_pct']:+.0f}%" if comp["delta_pct"] is not None else None
        st.metric("Volume (reps)", f"{comp['current_total']:.0f}", delta=delta_label)
    else:
        st.caption("Pas encore de séries de musculation enregistrées.")

    # --- Suggestion de prochaine séance + rappel ICS ---
    st.markdown("---")
    suggestion = suggest_next_session(df_global["date"].unique().tolist())
    if suggestion["next_session"] is not None:
        jours_restants = suggestion["days_until"]
        next_dt = datetime.combine(suggestion["next_session"], datetime.min.time()).replace(hour=18)
        if jours_restants <= 0:
            st.success("💪 Prochaine séance : **Aujourd'hui !**")
        elif jours_restants == 1:
            st.info("🔜 Prochaine séance optimale : **Demain**")
        else:
            st.info(f"🔜 Prochaine séance : **{next_dt.strftime('%A %d/%m')}** ({jours_restants}j)")
        st.caption(f"Basé sur {suggestion['mode_repos']} jour(s) de repos habituel")

        ics_content = build_ics_event(
            next_dt, "Séance Sysiphe 🪨",
            f"Rappel généré automatiquement — repos habituel : {suggestion['mode_repos']} jour(s)."
        )
        st.download_button(
            "📅 Rappel calendrier (.ics)", data=ics_content,
            file_name="sysiphe_prochaine_seance.ics", mime="text/calendar",
            use_container_width=True,
        )
