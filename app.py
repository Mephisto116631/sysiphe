"""
Sysiphe v15 — Point d'entrée principal.
"""
from datetime import datetime
import pandas as pd
import streamlit as st
from streamlit_calendar import calendar

from auth import get_pkce_store, check_oauth_callback, render_login_page, get_cookie_controller
from data import DEFAULT_VARIANTES, DEFAULT_FORMES
from supabase_io import (
    get_supabase_client, load_data, delete_perfs, 
    load_user_settings, load_app_theme, load_formes_config, 
    load_inactivity_days, load_enable_charges, save_enable_charges,
    load_weight, load_nb_days_avg, load_include_planche, load_graph_period
)
from ui_saisie import render_planche_block, render_exercise_block, render_kpi_panel, render_save_all_button
from ui_stats import render_stats_tabs, THEMES, inject_theme_css

APP_URL = "https://sysiphe-workout.streamlit.app"

st.set_page_config(page_title="Sysiphe v15 Cloud", layout="wide")

_DEFAULTS = {
    "user": None,
    "date_seance": datetime.now().date(),
    "weight": 97,
    "nb_days_avg": 5,
    "include_planche": True,
    "config_variantes": dict(DEFAULT_VARIANTES),
    "config_formes": dict(DEFAULT_FORMES),
    "confirm_delete_session": False,
    "app_theme": "Épuré",
    "inactivity_days": 4,
    "enable_charges": True, # <-- Ajout par défaut
}
for _k, _v in _DEFAULTS.items():
    if _k not in st.session_state:
        st.session_state[_k] = _v

supabase = get_supabase_client()
pkce_store = get_pkce_store()
check_oauth_callback(supabase, pkce_store)

if st.session_state.user is None:
    render_login_page(supabase, pkce_store, APP_URL)
    st.stop()

# Re-récupération DÉLIBÉRÉE : au premier appel ci-dessus, auth_mode n'était
# pas encore connu (avant login/reconnexion), donc le client obtenu était
# potentiellement celui du mauvais mode (anon par défaut). Maintenant que
# st.session_state.user et auth_mode sont définitivement fixés, on relit le
# bon client (mis en cache séparément par mode dans get_supabase_client).
supabase = get_supabase_client()

USER_ID = st.session_state.user.id

if "config_loaded" not in st.session_state:
    st.session_state.config_variantes = load_user_settings(USER_ID)
    st.session_state.config_formes = load_formes_config(USER_ID)
    st.session_state.app_theme = load_app_theme(USER_ID, default=st.session_state.app_theme)
    st.session_state.inactivity_days = load_inactivity_days(USER_ID, default=st.session_state.inactivity_days)
    st.session_state.enable_charges = load_enable_charges(USER_ID, default=st.session_state.enable_charges)
    st.session_state.weight = load_weight(USER_ID, default=st.session_state.weight)
    st.session_state.nb_days_avg = load_nb_days_avg(USER_ID, default=st.session_state.nb_days_avg)
    st.session_state.include_planche = load_include_planche(USER_ID, default=st.session_state.include_planche)
    st.session_state.graph_period = load_graph_period(USER_ID)
    st.session_state.config_loaded = True

inject_theme_css(st.session_state.app_theme)

with st.sidebar:
    st.caption(f"Connecté : {st.session_state.user.email}")
    if st.button("🚪 Se déconnecter", width='stretch'):
        try:
            c = get_cookie_controller()
            for cookie_name in ("sys_acc_token", "sys_ref_token", "sys_profile"):
                try:
                    c.remove(cookie_name)
                except KeyError:
                    pass  # cookie déjà absent, rien à faire
        except Exception:
            pass

        if st.session_state.get("auth_mode") != "profile":
            # Pas de vraie session Supabase Auth à clôturer en mode profil
            supabase.auth.sign_out()
        for k in ["user", "exos_du_jour", "last_seen_date", "oauth_intent", "config_loaded", "auth_mode",
                  "supabase_client_oauth", "supabase_client_profile"]:
            st.session_state.pop(k, None)
        st.cache_data.clear()
        st.rerun()
    st.markdown("---")
    
    # ---- NOUVEAU MENU PARAMÈTRES ----
    st.header("⚙️ Paramètres")
    new_enable_charges = st.toggle("Afficher les charges externes", value=st.session_state.enable_charges)
    if new_enable_charges != st.session_state.enable_charges:
        st.session_state.enable_charges = new_enable_charges
        save_enable_charges(USER_ID, new_enable_charges)
        st.rerun()
    st.markdown("---")
    # ---------------------------------

if 'weight' in st.session_state and 'config_variantes' in st.session_state:
    df_global = load_data(supabase, USER_ID, float(st.session_state.weight), st.session_state.config_variantes,
                          st.session_state.config_formes)
    with st.sidebar:
        with st.expander("🔍 Debug Stats (Base de données)"):
            st.write(f"**Lignes chargées :** {len(df_global)}")
            if not df_global.empty:
                st.write(f"**Dernière date :** {df_global['date'].max()}")
else:
    df_global = pd.DataFrame()

tous_les_exos = sorted(df_global[df_global["exercice"].str.lower() != "planche"]["exercice"].unique().tolist()) if not df_global.empty else []

st.title("🪨 Sysiphe v15 (Cloud)")

current_theme_colors = THEMES[st.session_state.app_theme]

with st.sidebar:
    st.header("📅 Calendrier")

    # Heatmap verte façon GitHub (4 paliers d'intensité), indépendante du
    # thème choisi — sert de repère visuel constant pour le volume/jour.
    GREEN_SCALE = ["#9BE9A8", "#40C463", "#30A14E", "#216E39"]

    calendar_events = []
    if not df_global.empty:
        vol_par_jour = df_global.groupby("date")["performance"].sum()
        vmax = vol_par_jour.max() or 1
        for d, vol in vol_par_jour.items():
            ratio = vol / vmax
            if ratio <= 0.25:
                couleur = GREEN_SCALE[0]
            elif ratio <= 0.5:
                couleur = GREEN_SCALE[1]
            elif ratio <= 0.75:
                couleur = GREEN_SCALE[2]
            else:
                couleur = GREEN_SCALE[3]
            calendar_events.append({
                "start": str(d),
                "display": "background",
                "backgroundColor": couleur,
            })

    calendar_options = {
        "headerToolbar": {"left": "prev", "center": "title", "right": "next"},
        "initialView": "dayGridMonth",
        "firstDay": 1,
        "height": 350,
        "selectable": True,
        "contentHeight": "auto",
    }

    cal_state = calendar(
        events=calendar_events,
        options=calendar_options,
        callbacks=["dateClick"],
        custom_css=f"""
        .fc {{
            font-family: {current_theme_colors['font']};
            --fc-border-color: {current_theme_colors['card_border']};
        }}
        .fc-theme-standard td, .fc-theme-standard th {{
            border: 1px solid {current_theme_colors['card_border']};
        }}
        .fc-daygrid-day {{
            transition: background 0.15s ease;
        }}
        .fc-daygrid-day:hover {{
            background: {current_theme_colors['accent_soft']};
        }}
        .fc-daygrid-day-frame {{
            border-radius: 6px;
            overflow: hidden;
        }}
        .fc-daygrid-day-number {{
            color: {current_theme_colors['text_main']};
            opacity: 0.85;
            text-decoration: none;
            font-weight: 500;
            font-size: 0.85em;
        }}
        .fc-day-today {{
            background: {current_theme_colors['accent_soft']} !important;
        }}
        .fc-day-today .fc-daygrid-day-number {{
            color: {current_theme_colors['accent']};
            font-weight: 700;
        }}
        .fc-toolbar-title {{
            font-size: 1.05em !important;
            color: {current_theme_colors['text_main']};
            font-weight: 600;
        }}
        .fc-prev-button, .fc-next-button {{
            background: {current_theme_colors['accent_soft']} !important;
            border: 1px solid {current_theme_colors['accent']} !important;
            color: {current_theme_colors['accent']} !important;
        }}
        .fc-prev-button:hover, .fc-next-button:hover {{
            background: {current_theme_colors['accent']} !important;
            color: #fff !important;
        }}
        .fc-col-header-cell {{
            color: {current_theme_colors['text_main']};
            opacity: 0.6;
            font-size: 0.75em;
            text-transform: uppercase;
        }}
        """,
        key="main_calendar"
    )

    if cal_state and isinstance(cal_state, dict) and "dateClick" in cal_state:
        clicked_date_str = cal_state["dateClick"]["date"]
        date_obj = datetime.strptime(clicked_date_str[:10], "%Y-%m-%d").date()

        if date_obj != st.session_state.date_seance:
            st.session_state.date_seance = date_obj
            st.session_state.confirm_delete_session = False
            st.rerun()

    st.markdown(
        "<div style='display:flex;align-items:center;gap:4px;font-size:0.75rem;"
        f"opacity:0.7;margin-top:4px;color:{current_theme_colors['text_main']};'>"
        "Léger"
        + "".join(f"<div style='width:14px;height:14px;border-radius:3px;"
                  f"background:{c};'></div>" for c in GREEN_SCALE)
        + "Intense</div>",
        unsafe_allow_html=True,
    )

    st.markdown(f"**Séance active : {st.session_state.date_seance.strftime('%d/%m/%Y')}**")
    st.markdown("---")

    if not st.session_state.confirm_delete_session:
        if st.button("🗑️ Supprimer cette séance", type="secondary", width='stretch'):
            st.session_state.confirm_delete_session = True
            st.rerun()
    else:
        st.warning("⚠️ Confirmer la suppression ?")
        col_yes, col_no = st.columns(2)
        with col_yes:
            if st.button("Oui", type="primary", width='stretch'):
                delete_perfs(USER_ID, str(st.session_state.date_seance))
                st.cache_data.clear()
                st.session_state.exos_du_jour = []
                st.session_state.confirm_delete_session = False
                st.toast("Séance supprimée", icon="🗑️")
                st.rerun()
        with col_no:
            if st.button("Non", width='stretch'):
                st.session_state.confirm_delete_session = False
                st.rerun()

    st.markdown("---")
    render_stats_tabs(df_global, tous_les_exos, USER_ID)

if "last_seen_date" not in st.session_state or st.session_state.last_seen_date != st.session_state.date_seance:
    st.session_state.last_seen_date = st.session_state.date_seance
    if not df_global.empty:
        df_today = df_global[df_global["date"] == st.session_state.date_seance]
        exos_today = (df_today[df_today["exercice"].str.lower() != "planche"]["exercice"].unique().tolist()
                      if not df_today.empty else [])

        # On garde en plus tout exercice pratiqué au cours des N DERNIÈRES
        # SÉANCES passées (dates distinctes avec données, pas une fenêtre
        # calendaire) — utile si l'entraînement n'est pas quotidien. On fusionne
        # avec exos_today au lieu de choisir l'un OU l'autre : sinon, dès qu'on
        # a déjà loggé quelque chose aujourd'hui (ex: la Planche), les exercices
        # des séances précédentes disparaissaient complètement.
        dates_passees = sorted(
            df_global[df_global["date"] < st.session_state.date_seance]["date"].unique(),
            reverse=True,
        )
        dates_retenues = dates_passees[: st.session_state.inactivity_days]
        df_recent = df_global[df_global["date"].isin(dates_retenues)]
        exos_recent = df_recent[df_recent["exercice"].str.lower() != "planche"]["exercice"].unique().tolist()

        st.session_state.exos_du_jour = list(dict.fromkeys(exos_today + exos_recent))
    else:
        st.session_state.exos_du_jour = []

# Bouton "Tout sauvegarder" collant en haut de la page : reste visible en
# permanence pendant le scroll (position: sticky, cf. inject_theme_css).
with st.container(key="save_all_sticky"):
    render_save_all_button(USER_ID, st.session_state.date_seance, st.session_state.exos_du_jour)

col_saisie, col_kpi = st.columns([2, 1])

with col_saisie:
    if st.session_state.get("include_planche", True):
        render_planche_block(df_global, st.session_state.date_seance, USER_ID,
                             float(st.session_state.weight), st.session_state.config_variantes,
                             st.session_state.config_formes)

    for nom_exo in list(st.session_state.exos_du_jour):
        render_exercise_block(nom_exo, df_global, st.session_state.date_seance, USER_ID)

    # Suggestions d'anciens exercices (déjà faits par le passé, mais pas
    # dans la fenêtre des dernières séances donc pas affichés ci-dessus).
    exos_suggeres = sorted(
        e for e in tous_les_exos
        if not any(e.lower() == deja.lower() for deja in st.session_state.exos_du_jour)
    )
    if exos_suggeres:
        c_sugg, c_add_sugg = st.columns([4, 1])
        with c_sugg:
            choix_ancien = st.selectbox(
                "Reprendre un ancien exercice", exos_suggeres,
                index=None, placeholder="Exercices déjà pratiqués mais pas affichés...",
                label_visibility="collapsed", key=f"sugg_exo_{st.session_state.date_seance}",
            )
        with c_add_sugg:
            if st.button("↩️ Reprendre", width='stretch', disabled=choix_ancien is None):
                st.session_state.exos_du_jour.append(choix_ancien)
                st.rerun()

    with st.form(f"add_exo_form_{st.session_state.date_seance}", clear_on_submit=True):
        c_new, c_add = st.columns([4, 1])
        with c_new:
            nouvel_exo = st.text_input("Ajouter un exercice", placeholder="Nom de l'exercice (ex: Tractions, Squats...)",
                                       label_visibility="collapsed")
        with c_add:
            submitted = st.form_submit_button("➕ Ajouter", width='stretch')
        if submitted:
            nom_propre = nouvel_exo.strip()
            if not nom_propre:
                st.warning("Le nom de l'exercice ne peut pas être vide.")
            elif any(e.lower() == nom_propre.lower() for e in st.session_state.exos_du_jour):
                st.warning(f"'{nom_propre}' est déjà dans la séance du jour.")
            else:
                st.session_state.exos_du_jour.append(nom_propre)
                st.rerun()

with col_kpi:
    render_kpi_panel(df_global, st.session_state.date_seance)