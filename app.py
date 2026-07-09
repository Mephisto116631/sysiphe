"""
Sysiphe v15 — Point d'entrée principal.
"""
from datetime import datetime
import pandas as pd
import streamlit as st
from streamlit_calendar import calendar

from auth import get_pkce_store, check_oauth_callback, render_login_page
from data import DEFAULT_VARIANTES, DEFAULT_FORMES
from supabase_io import get_supabase_client, load_data, delete_perfs, load_user_settings, load_app_theme, load_formes_config
from ui_saisie import render_planche_block, render_exercise_block, render_kpi_panel
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
    "app_theme": "Épuré"
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

USER_ID = st.session_state.user.id

if "config_loaded" not in st.session_state:
    st.session_state.config_variantes = load_user_settings(USER_ID)
    st.session_state.config_formes = load_formes_config(USER_ID)
    st.session_state.app_theme = load_app_theme(USER_ID, default=st.session_state.app_theme)
    st.session_state.config_loaded = True

inject_theme_css(st.session_state.app_theme)

with st.sidebar:
    st.caption(f"Connecté : {st.session_state.user.email}")
    if st.button("🚪 Se déconnecter", use_container_width=True):
        try:
            from streamlit_cookies_controller import CookieController
            c = CookieController()
            c.remove("sys_acc_token")
            c.remove("sys_ref_token")
        except ImportError:
            pass

        supabase.auth.sign_out()
        for k in ["user", "exos_du_jour", "last_seen_date", "oauth_intent", "config_loaded"]:
            st.session_state.pop(k, None)
        st.cache_data.clear()
        st.rerun()
    st.markdown("---")

if 'weight' in st.session_state and 'config_variantes' in st.session_state:
    df_global = load_data(USER_ID, float(st.session_state.weight), st.session_state.config_variantes)
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

    calendar_events = []
    if not df_global.empty:
        vol_par_jour = df_global.groupby("date")["performance"].sum()
        vmax = vol_par_jour.max() or 1
        hex_c = current_theme_colors["cal_event"].lstrip("#")
        r, g, b = int(hex_c[0:2], 16), int(hex_c[2:4], 16), int(hex_c[4:6], 16)
        for d, vol in vol_par_jour.items():
            intensite = 0.25 + 0.75 * (vol / vmax)  # 25% à 100% d'opacité
            calendar_events.append({
                "start": str(d),
                "display": "background",
                "backgroundColor": f"rgba({r},{g},{b},{intensite:.2f})",
            })

    calendar_options = {
        "headerToolbar": {"left": "prev", "center": "title", "right": "next"},
        "initialView": "dayGridMonth",
        "firstDay": 1,
        "height": 350,
        "selectable": True,
        "contentHeight": "auto",
    }

    # FIX DE LA BOUCLE : Ajout de callbacks=["dateClick"]
    cal_state = calendar(
        events=calendar_events,
        options=calendar_options,
        callbacks=["dateClick"],
        custom_css="""
        .fc-theme-standard td, .fc-theme-standard th { border: 1px solid #444; }
        .fc-daygrid-day-number { color: #888; text-decoration: none; }
        .fc-toolbar-title { font-size: 1.1em !important; }
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

    st.markdown(f"**Séance active : {st.session_state.date_seance.strftime('%d/%m/%Y')}**")
    st.markdown("---")

    if not st.session_state.confirm_delete_session:
        if st.button("🗑️ Supprimer cette séance", type="secondary", use_container_width=True):
            st.session_state.confirm_delete_session = True
            st.rerun()
    else:
        st.warning("⚠️ Confirmer la suppression ?")
        col_yes, col_no = st.columns(2)
        with col_yes:
            if st.button("Oui", type="primary", use_container_width=True):
                delete_perfs(USER_ID, str(st.session_state.date_seance))
                st.cache_data.clear()
                st.session_state.exos_du_jour = []
                st.session_state.confirm_delete_session = False
                st.toast("Séance supprimée", icon="🗑️")
                st.rerun()
        with col_no:
            if st.button("Non", use_container_width=True):
                st.session_state.confirm_delete_session = False
                st.rerun()

if "last_seen_date" not in st.session_state or st.session_state.last_seen_date != st.session_state.date_seance:
    st.session_state.last_seen_date = st.session_state.date_seance
    if not df_global.empty:
        df_today = df_global[df_global["date"] == st.session_state.date_seance]
        if not df_today.empty:
            st.session_state.exos_du_jour = df_today[df_today["exercice"].str.lower() != "planche"]["exercice"].unique().tolist()
        else:
            dates_passees = df_global[df_global["date"] < st.session_state.date_seance]["date"]
            if not dates_passees.empty:
                df_last = df_global[df_global["date"] == dates_passees.max()]
                st.session_state.exos_du_jour = df_last[df_last["exercice"].str.lower() != "planche"]["exercice"].unique().tolist()
            else:
                st.session_state.exos_du_jour = []
    else:
        st.session_state.exos_du_jour = []

col_saisie, col_kpi = st.columns([2, 1])

with col_saisie:
    if st.session_state.include_planche:
        render_planche_block(df_global, st.session_state.date_seance, USER_ID,
                             float(st.session_state.weight), st.session_state.config_variantes,
                             st.session_state.config_formes)

    for nom_exo in list(st.session_state.exos_du_jour):
        render_exercise_block(nom_exo, df_global, st.session_state.date_seance, USER_ID)

    with st.form(f"add_exo_form_{st.session_state.date_seance}", clear_on_submit=True):
        c_new, c_add = st.columns([4, 1])
        with c_new:
            nouvel_exo = st.text_input("Ajouter un exercice", placeholder="Nom de l'exercice (ex: Tractions, Squats...)",
                                       label_visibility="collapsed")
        with c_add:
            submitted = st.form_submit_button("➕ Ajouter", use_container_width=True)
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

st.markdown("---")
render_stats_tabs(df_global, tous_les_exos, USER_ID)
