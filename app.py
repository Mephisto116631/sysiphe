"""
Sysiphe — site web en CONSULTATION SEULE (st.navigation + st.Page).
Stats, Calendrier, Records, Repos et Infos ; la saisie et les réglages se
font dans l'app Android. Les écritures sont bloquées dans supabase_io.py.
"""
import streamlit as st

from auth import (get_pkce_store, check_oauth_callback, render_login_page,
                  get_cookie_controller, persist_session_tokens)
from supabase_io import _clear_profiles_cache
from data import DEFAULT_VARIANTES, DEFAULT_FORMES, DEFAULT_ELASTIQUES, DEFAULT_TENSIONS
from supabase_io import get_supabase_client, load_data, load_user_settings
from ui_stats import (
    render_graph_tab, render_calendar_tab,
    render_records_tab, render_repos_tab, render_param_tab,
)

CLOUD_URL = "https://sysiphe-voseesdgwwcstfepbdepkh.streamlit.app"
try:
    # URL publique de l'app (redirections d'auth). Surchargeable via
    # secrets.toml, par ex. en local ; Streamlit Cloud par défaut.
    APP_URL = st.secrets.get("APP_URL") or CLOUD_URL
except Exception:
    APP_URL = CLOUD_URL

st.set_page_config(page_title="Sysiphe", page_icon="🪨", layout="centered")

# ─── CSS responsive mobile ───────────────────────────────────────────────────
st.markdown("""
<style>
@media (max-width: 640px) {
    .main .block-container {
        padding-left: 0.6rem !important;
        padding-right: 0.6rem !important;
        padding-top: 0.5rem !important;
    }
    h1 { font-size: 1.45rem !important; margin-top: 0 !important; }
    h2 { font-size: 1.15rem !important; }
    h3 { font-size: 1.05rem !important; }
    .stButton > button { min-height: 2.75rem !important; font-size: 0.95rem !important; }
    [data-testid="stHorizontalBlock"] { flex-wrap: wrap !important; }
    [data-testid="stHorizontalBlock"] > [data-testid="stColumn"] {
        flex: 1 1 100% !important;
        min-width: 100% !important;
        width: 100% !important;
    }
}
@media (max-width: 480px) {
    [data-testid="stSegmentedControl"] button {
        padding: 0.25rem 0.35rem !important;
        font-size: 0.8rem !important;
    }
}
</style>
""", unsafe_allow_html=True)

# ─── Session state defaults ──────────────────────────────────────────────────
_DEFAULTS = {
    "user": None,
    "weight": 97,
    "nb_days_avg": 5,
    "include_planche": True,
    "config_variantes":  dict(DEFAULT_VARIANTES),
    "config_formes":     dict(DEFAULT_FORMES),
    "config_elastiques": dict(DEFAULT_ELASTIQUES),
    "config_tensions":   dict(DEFAULT_TENSIONS),
}
for _k, _v in _DEFAULTS.items():
    if _k not in st.session_state:
        st.session_state[_k] = _v

# ─── Auth ────────────────────────────────────────────────────────────────────
supabase = get_supabase_client()
pkce_store = get_pkce_store()
check_oauth_callback(supabase, pkce_store)
persist_session_tokens(supabase)  # jetons renouvelés → cookies à jour

if st.session_state.user is None:
    render_login_page(supabase, pkce_store, APP_URL)
    st.stop()

USER_ID = st.session_state.user.id

# Charger les paramètres persistés une seule fois par session
if "config_loaded" not in st.session_state:
    settings = load_user_settings(USER_ID)
    st.session_state.config_variantes  = settings["variantes_config"]
    st.session_state.config_formes     = settings["formes_config"]
    st.session_state.config_elastiques = settings["elastiques_config"]
    st.session_state.config_tensions   = settings["tensions_config"]
    st.session_state.weight            = settings["weight"]
    st.session_state.nb_days_avg       = settings["nb_days_avg"]
    st.session_state.include_planche   = settings["include_planche"]
    st.session_state.enable_charges    = settings["enable_charges"]  # champ lest (Réglages de l'app)
    st.session_state.config_loaded     = True

# ─── Sidebar globale (déconnexion / changement de profil) ────────────────────
with st.sidebar:
    st.caption(f"👤 {st.session_state.user.email}")
    st.info("👀 Consultation seule. Saisie et réglages : app Android Sysiphe.")
    # Libellé contextuel selon le mode d'auth
    is_profile_mode = st.session_state.get("auth_mode") == "profile"
    btn_label = "🔀 Changer de profil" if is_profile_mode else "🚪 Déconnexion"
    if st.button(btn_label, use_container_width=True):
        # Efface le cookie de profil pour empêcher la reconnexion automatique
        try:
            get_cookie_controller().remove("sys_profile")
        except Exception:
            pass
        # Marque le logout volontaire pour bloquer le fallback Supabase
        st.session_state["_manual_logout"] = True
        # Fermer la session : ce navigateur perd son rattachement aux profils,
        # le PIN sera redemandé (une nouvelle session anonyme sera créée).
        supabase.auth.sign_out()
        for c in ("sys_acc_token", "sys_ref_token"):
            try:
                get_cookie_controller().remove(c)
            except Exception:
                pass
        _clear_profiles_cache()
        for k in ["user", "oauth_intent", "config_loaded"]:
            st.session_state.pop(k, None)
        st.cache_data.clear()
        st.rerun()

# ─── Données globales (partagées par toutes les pages) ───────────────────────
df_global = load_data(
    USER_ID, float(st.session_state.weight),
    st.session_state.config_variantes, st.session_state.config_formes,
    st.session_state.config_elastiques, st.session_state.config_tensions,
)

tous_les_exos = []
if not df_global.empty:
    tous_les_exos = sorted(
        df_global[df_global["exercice"].str.lower() != "planche"]["exercice"].unique().tolist()
    )


# ═════════════════════════════════════════════════════════════════════════════
# PAGES
# ═════════════════════════════════════════════════════════════════════════════

def page_stats():
    st.title("📈 Statistiques")
    render_graph_tab(df_global, tous_les_exos, st.session_state.include_planche)


def page_calendar():
    st.title("📅 Calendrier")
    render_calendar_tab(df_global)


def page_records():
    st.title("🏆 Records")
    render_records_tab(df_global)


def page_repos():
    st.title("💤 Repos")
    render_repos_tab(df_global)


def page_infos():
    st.title("ℹ️ Infos")
    render_param_tab(df_global, tous_les_exos, USER_ID)


# ─── Navigation ──────────────────────────────────────────────────────────────
pg = st.navigation([
    st.Page(page_stats,    title="Stats",        icon="📈", default=True),
    st.Page(page_calendar, title="Calendrier",   icon="📅"),
    st.Page(page_records,  title="Records",      icon="🏆"),
    st.Page(page_repos,    title="Repos",        icon="💤"),
    st.Page(page_infos,    title="Infos",        icon="ℹ️"),
])
pg.run()
