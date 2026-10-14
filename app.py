"""
Sysiphe v17 — Point d'entrée principal.
Architecture modulaire : auth.py / data.py / supabase_io.py / ui_saisie.py / ui_stats.py / ui_helpers.py
v17 : Responsive mobile (layout centré, CSS media queries, KPI en expander)
"""
from datetime import datetime, timedelta
import streamlit as st

from auth import get_pkce_store, check_oauth_callback, render_login_page
from data import DEFAULT_VARIANTES
from supabase_io import get_supabase_client, load_data, delete_perfs, load_user_settings
from ui_saisie import render_planche_block, render_exercise_block, render_kpi_panel, render_save_all_button
from ui_stats import render_stats_tabs

CLOUD_URL = "https://sysiphe-voseesdgwwcstfepbdepkh.streamlit.app"
# URL publique de l'instance (redirection OAuth). Sur le NAS : APP_URL dans secrets.toml.
APP_URL = st.secrets.get("APP_URL", CLOUD_URL)

st.set_page_config(page_title="Sysiphe v18", layout="centered")

# ─── CSS responsive mobile ──────────────────────────────────────────────────
st.markdown("""
<style>
/* ═══ Responsive mobile — Sysiphe v17 ═══ */
@media (max-width: 640px) {
    /* Padding compact */
    .main .block-container {
        padding-left: 0.6rem !important;
        padding-right: 0.6rem !important;
        padding-top: 0.5rem !important;
    }
    /* Titres */
    h1 { font-size: 1.45rem !important; margin-top: 0 !important; }
    h2 { font-size: 1.15rem !important; }
    h3 { font-size: 1.05rem !important; }
    /* Cibles tactiles plus grandes */
    .stButton > button { min-height: 2.75rem !important; font-size: 0.95rem !important; }
    /* Empiler toutes les colonnes horizontales */
    [data-testid="stHorizontalBlock"] { flex-wrap: wrap !important; }
    [data-testid="stHorizontalBlock"] > [data-testid="stColumn"] {
        flex: 1 1 100% !important;
        min-width: 100% !important;
        width: 100% !important;
    }
}
/* Segmented controls : labels plus courts sur petits écrans */
@media (max-width: 480px) {
    [data-testid="stSegmentedControl"] button {
        padding: 0.25rem 0.35rem !important;
        font-size: 0.8rem !important;
    }
}
/* ════════════════════════════════════════ */
</style>
""", unsafe_allow_html=True)

# --- Initialisation session state (valeurs par défaut avant chargement DB) ---
_DEFAULTS = {
    "user": None,
    "date_seance": datetime.now().date(),
    "weight": 97,
    "nb_days_avg": 5,
    "include_planche": True,
    "config_variantes": dict(DEFAULT_VARIANTES),
    "confirm_delete_session": False,
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

# Charger tous les paramètres persistés une seule fois par session
if "config_loaded" not in st.session_state:
    settings = load_user_settings(USER_ID)
    st.session_state.config_variantes  = settings["variantes_config"]
    st.session_state.weight            = settings["weight"]
    st.session_state.nb_days_avg       = settings["nb_days_avg"]
    st.session_state.include_planche   = settings["include_planche"]
    st.session_state.config_loaded     = True

with st.sidebar:
    st.caption(f"Connecté : {st.session_state.user.email}")
    if st.button("🚪 Se déconnecter", use_container_width=True):
        supabase.auth.sign_out()
        for k in ["user", "exos_du_jour", "last_seen_date", "oauth_intent", "config_loaded"]:
            st.session_state.pop(k, None)
        st.cache_data.clear()
        st.rerun()
    st.markdown("---")

df_global = load_data(USER_ID, float(st.session_state.weight), st.session_state.config_variantes)

tous_les_exos = []
if not df_global.empty:
    tous_les_exos = sorted(df_global[df_global["exercice"].str.lower() != "planche"]["exercice"].unique().tolist())

st.title("🪨 Sysiphe v18")

with st.sidebar:
    st.header("📅 Navigation")
    date_active = st.date_input("Choisir une date", st.session_state.date_seance, key="date_picker")
    if date_active != st.session_state.date_seance:
        st.session_state.date_seance = date_active
        st.session_state.confirm_delete_session = False
        st.rerun()

    if not df_global.empty:
        st.write("")
        jours_entraines = sorted([
            d.day for d in df_global["date"].unique()
            if d.month == date_active.month and d.year == date_active.year
        ])
        if jours_entraines:
            st.markdown(
                f"**🎯 Ce mois :** <span style='background:#2e7d32;color:white;padding:4px 12px;"
                f"border-radius:12px;font-size:16px;font-weight:bold;'>{len(jours_entraines)} séance(s)</span>",
                unsafe_allow_html=True,
            )
        else:
            st.caption("ℹ️ Aucune séance ce mois.")

    st.markdown("---")

    # --- Suppression de séance avec confirmation à deux étapes ---
    if not st.session_state.confirm_delete_session:
        if st.button("🗑️ Supprimer cette séance", type="secondary", use_container_width=True):
            st.session_state.confirm_delete_session = True
            st.rerun()
    else:
        st.warning(f"⚠️ Confirmer la suppression de la séance du {date_active.strftime('%d/%m/%Y')} ?")
        col_yes, col_no = st.columns(2)
        with col_yes:
            if st.button("Oui, supprimer", type="primary", use_container_width=True):
                delete_perfs(USER_ID, str(date_active))
                st.cache_data.clear()
                st.session_state.exos_du_jour = []
                st.session_state.confirm_delete_session = False
                st.toast(f"Séance du {date_active.strftime('%d/%m/%Y')} supprimée", icon="🗑️")
                st.session_state.date_seance = datetime.now().date()
                st.rerun()
        with col_no:
            if st.button("Annuler", use_container_width=True):
                st.session_state.confirm_delete_session = False
                st.rerun()

# --- Navigation date rapide (mobile-first) ---
_c_prev, _c_mid, _c_next = st.columns([1, 2, 1])
with _c_prev:
    if st.button("◀ Hier", use_container_width=True):
        st.session_state.date_seance = date_active - timedelta(days=1)
        st.session_state.confirm_delete_session = False
        st.rerun()
with _c_mid:
    _today = datetime.now().date()
    _lbl = f"📅 {date_active.strftime('%d/%m')}" + (" ↩ Auj." if date_active != _today else "")
    if st.button(_lbl, use_container_width=True, disabled=(date_active == _today)):
        st.session_state.date_seance = _today
        st.session_state.confirm_delete_session = False
        st.rerun()
with _c_next:
    if st.button("Demain ▶", use_container_width=True):
        st.session_state.date_seance = date_active + timedelta(days=1)
        st.session_state.confirm_delete_session = False
        st.rerun()

# --- Préfill des exercices du jour selon historique ---
if "last_seen_date" not in st.session_state or st.session_state.last_seen_date != date_active:
    st.session_state.last_seen_date = date_active
    if not df_global.empty:
        df_today = df_global[df_global["date"] == date_active]
        if not df_today.empty:
            st.session_state.exos_du_jour = (
                df_today[df_today["exercice"].str.lower() != "planche"]["exercice"].unique().tolist()
            )
        else:
            dates_passees = df_global[df_global["date"] < date_active]["date"]
            if not dates_passees.empty:
                df_last = df_global[df_global["date"] == dates_passees.max()]
                st.session_state.exos_du_jour = (
                    df_last[df_last["exercice"].str.lower() != "planche"]["exercice"].unique().tolist()
                )
            else:
                st.session_state.exos_du_jour = []
    else:
        st.session_state.exos_du_jour = []

# =========================================================================
# INTERFACE PRINCIPALE — layout colonne unique (mobile-first)
# =========================================================================

# --- Panneau KPI du jour (rétractable) ---
with st.expander("📊 Stats du jour & prochaine séance", expanded=True):
    render_kpi_panel(df_global, date_active)

st.write("")

# --- Saisie pleine largeur ---
if st.session_state.include_planche:
    render_planche_block(df_global, date_active, USER_ID,
                         float(st.session_state.weight), st.session_state.config_variantes)

for nom_exo in list(st.session_state.exos_du_jour):
    render_exercise_block(nom_exo, df_global, date_active, USER_ID)

render_save_all_button(USER_ID, date_active, st.session_state.exos_du_jour)

# --- Ajout d'exercice ---
col_sel, col_add = st.columns([3, 1])
with col_sel:
    new_sel = st.selectbox("Exercices Habituels", ["--- Sélectionner ---"] + tous_les_exos)
    new_txt = st.text_input("...ou taper un nouvel exercice")
with col_add:
    if st.button("➕ Ajouter", use_container_width=True):
        exo_ok = new_txt.strip() or (new_sel if new_sel != "--- Sélectionner ---" else None)
        if exo_ok and exo_ok not in st.session_state.exos_du_jour:
            st.session_state.exos_du_jour.append(exo_ok)
            st.rerun()

st.write("---")
render_stats_tabs(df_global, tous_les_exos, USER_ID)
