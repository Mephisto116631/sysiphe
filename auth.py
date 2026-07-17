"""
Sysiphe — Authentification (Email/Password + Google OAuth via PKCE + Cookies)
+ Mode Profils : sélection rapide sans mot de passe pour un usage familial,
avec la connexion sécurisée (Google/email) conservée en option de secours.
"""
import time
import uuid
from types import SimpleNamespace
import streamlit as st
from streamlit_cookies_controller import CookieController

# --- MODE PROFILS ---------------------------------------------------------
# Pas d'authentification réelle : n'importe qui avec le lien peut voir ET
# modifier les données de n'importe quel profil listé ici. Chaque profil a
# un UUID FIXE (pas lié à un vrai compte Supabase Auth) utilisé comme user_id
# dans les tables perfs/user_settings. Renomme les clés ci-dessous avec les
# vrais prénoms ; garde les UUID tels quels (ou génère les tiens avec
# `python3 -c "import uuid; print(uuid.uuid4())"`).
PROFILES = {
    "Medhi": "9250e548-1d5a-48d1-98c0-5c97089a77d8",   # ton compte historique
    "Profil 2": "7c1a2ca2-9b9d-43d9-af21-3f84578fe53e",  # <- renomme-moi
    "Profil 3": "a03fb31f-f0d0-4871-a903-a4a1f3924531",  # <- renomme-moi
}
# ---------------------------------------------------------------------------

def get_cookie_controller():
    """Isole le gestionnaire de cookies par session utilisateur."""
    if "cookie_controller" not in st.session_state:
        st.session_state.cookie_controller = CookieController(key="sysiphe_cookies")
    return st.session_state.cookie_controller

def get_pkce_store() -> dict:
    @st.cache_resource
    def _store():
        return {}
    store = _store()
    _clean_pkce_store(store)
    return store


def _clean_pkce_store(store: dict, max_age: int = 600) -> None:
    """Supprime les intent_id expirés (>10 min) pour éviter une fuite mémoire."""
    now = time.time()
    expired = [k for k, (_, ts) in store.items() if now - ts > max_age]
    for k in expired:
        del store[k]


def check_oauth_callback(supabase, pkce_store: dict) -> None:
    """Traite le retour OAuth Google ou la reconnexion automatique via Cookie."""
    controller = get_cookie_controller()
    
    # --- GESTION DE L'ASYNCHRONISME DES COOKIES VS OAUTH ---
    # Sur mobile, revenir sur l'onglet après avoir quitté l'app (ex: pour
    # filmer) tue souvent la connexion WebSocket de Streamlit : au retour,
    # la page recharge à froid et le composant JS des cookies peut mettre
    # plus de temps à s'initialiser qu'un simple chargement desktop. On
    # attend donc un peu plus longtemps qu'à l'origine avant de vérifier
    # les cookies.
    is_oauth_return = "code" in st.query_params

    if is_oauth_return:
        st.session_state.cookies_initialized = True
    elif "cookies_initialized" not in st.session_state:
        time.sleep(0.6)
        st.session_state.cookies_initialized = True
        st.rerun()
    # -------------------------------------------------------

    # 1. Si on est déjà connecté en mémoire de session, on ne fait rien
    if st.session_state.get("user") is not None:
        return

    # 1bis. RECONNEXION SILENCIEUSE — MODE PROFIL (pas de vrai token à
    # rafraîchir, juste un cookie qui rappelle quel profil était choisi)
    try:
        saved_profile_uid = controller.get("sys_profile")
    except KeyError:
        saved_profile_uid = None
    if saved_profile_uid:
        nom_profil = next((n for n, u in PROFILES.items() if u == saved_profile_uid), None)
        if nom_profil:
            st.session_state.user = SimpleNamespace(id=saved_profile_uid, email=f"{nom_profil} (profil partagé)")
            st.session_state.auth_mode = "profile"
            return

    # 2. TENTATIVE DE RECONNEXION SILENCIEUSE (Cookies)
    try:
        saved_token = controller.get("sys_acc_token")
        saved_refresh = controller.get("sys_ref_token")
    except KeyError:
        saved_token, saved_refresh = None, None

    if saved_token and saved_refresh:
        try:
            # Restauration de la session Supabase depuis les cookies
            res = supabase.auth.set_session(saved_token, saved_refresh)
            if res.user:
                st.session_state.user = res.user
                st.session_state.auth_mode = "oauth"
                return
        except Exception:
            # Si le token est expiré ou corrompu, on nettoie les cookies
            for cookie_name in ("sys_acc_token", "sys_ref_token"):
                try:
                    controller.remove(cookie_name)
                except KeyError:
                    pass

    # 3. TRAITEMENT DU RETOUR OAUTH (GOOGLE)
    if not is_oauth_return:
        return
        
    try:
        code = st.query_params["code"]
        intent_id = st.query_params.get("intent_id")
        
        # Restauration du verifier PKCE (utilisation de .get au lieu de .pop)
        if intent_id and intent_id in pkce_store:
            verifier, _ = pkce_store.get(intent_id)
            supabase.auth._storage.set_item("supabase.auth.token-code-verifier", verifier)
            
        res = supabase.auth.exchange_code_for_session({"auth_code": code})
        
        if res.user:
            st.session_state.user = res.user
            st.session_state.auth_mode = "oauth"
            # SAUVEGARDE EN COOKIE (valable 30 jours)
            controller.set("sys_acc_token", res.session.access_token, max_age=2592000)
            controller.set("sys_ref_token", res.session.refresh_token, max_age=2592000)
            
            # Nettoyage manuel du store PKCE maintenant que le code est validé
            if intent_id in pkce_store:
                del pkce_store[intent_id]
                
        # IMPORTANT : On vide l'URL et on redémarre l'appli pour effacer le paramètre 'code'
        st.query_params.clear()
        st.rerun()
        
    except Exception as e:
        # En cas d'erreur (ex: refresh manuel sur un vieux code), on purge l'URL et on relance
        st.query_params.clear()
        st.error(f"Erreur de validation OAuth : {e}")
        time.sleep(2)
        st.rerun()


def render_login_page(supabase, pkce_store: dict, app_url: str) -> None:
    """Affiche l'écran de connexion : sélection de profil en premier plan,
    connexion sécurisée (Google/email) repliée en secours."""
    controller = get_cookie_controller()
    st.title("🪨 Sysiphe")
    st.markdown("Choisis ton profil pour continuer.")

    _, col_auth, _ = st.columns([1, 2, 1])
    with col_auth:
        for nom, uid_profil in PROFILES.items():
            if st.button(f"👤 {nom}", key=f"profile_btn_{uid_profil}", width='stretch'):
                st.session_state.user = SimpleNamespace(id=uid_profil, email=f"{nom} (profil partagé)")
                st.session_state.auth_mode = "profile"
                controller.set("sys_profile", uid_profil, max_age=2592000)
                st.rerun()

        st.markdown("<div style='text-align:center;margin:20px 0;opacity:0.6;'>— ou —</div>",
                    unsafe_allow_html=True)

        with st.expander("🔒 Connexion sécurisée (Google / email)"):
            if "oauth_intent" not in st.session_state:
                st.session_state.oauth_intent = str(uuid.uuid4())
            intent_id = st.session_state.oauth_intent
            redirect_url = f"{app_url}/?intent_id={intent_id}"

            res = supabase.auth.sign_in_with_oauth({
                "provider": "google",
                "options": {"redirect_to": redirect_url},
            })
            verifier = supabase.auth._storage.get_item("supabase.auth.token-code-verifier")
            if verifier:
                pkce_store[intent_id] = (verifier, time.time())

            st.link_button("🔵 Se connecter avec Google", url=res.url,
                            type="primary", width='stretch')
            st.markdown("<div style='text-align:center;margin:15px 0;'>— OU —</div>",
                        unsafe_allow_html=True)

            choix = st.radio("Connexion classique :", ["Se connecter", "Créer un compte"], horizontal=True)
            email = st.text_input("Adresse Email")
            password = st.text_input("Mot de passe", type="password")

            if st.button("Valider", width='stretch'):
                try:
                    if choix == "Créer un compte":
                        supabase.auth.sign_up({"email": email, "password": password})
                        st.success("✅ Compte créé ! Tu peux maintenant te connecter.")
                    else:
                        resp = supabase.auth.sign_in_with_password({"email": email, "password": password})
                        st.session_state.user = resp.user
                        st.session_state.auth_mode = "oauth"
                        # SAUVEGARDE EN COOKIE (valable 30 jours)
                        controller.set("sys_acc_token", resp.session.access_token, max_age=2592000)
                        controller.set("sys_ref_token", resp.session.refresh_token, max_age=2592000)
                        st.rerun()
                except Exception as e:
                    st.error(f"❌ Erreur : {e}")
