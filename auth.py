"""
Sysiphe — Authentification (Email/Password + Google OAuth via PKCE + Cookies).
"""
import time
import uuid
import streamlit as st
from streamlit_cookies_controller import CookieController

# Initialisation du gestionnaire de cookies
controller = CookieController()

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
    
    # 1. Si on est déjà connecté en mémoire de session, on ne fait rien
    if st.session_state.get("user") is not None:
        return

    # 2. TENTATIVE DE RECONNEXION SILENCIEUSE (Cookies)
    saved_token = controller.get("sys_acc_token")
    saved_refresh = controller.get("sys_ref_token")

    if saved_token and saved_refresh:
        try:
            # Restauration de la session Supabase depuis les cookies
            res = supabase.auth.set_session(saved_token, saved_refresh)
            if res.user:
                st.session_state.user = res.user
                return
        except Exception:
            # Si le token est expiré ou corrompu, on nettoie les cookies
            controller.remove("sys_acc_token")
            controller.remove("sys_ref_token")

    # 3. TRAITEMENT DU RETOUR OAUTH (GOOGLE)
    if "code" not in st.query_params:
        return
        
    try:
        code = st.query_params["code"]
        intent_id = st.query_params.get("intent_id")
        if intent_id and intent_id in pkce_store:
            verifier, _ = pkce_store.pop(intent_id)
            supabase.auth._storage.set_item("supabase.auth.token-code-verifier", verifier)
            
        res = supabase.auth.exchange_code_for_session({"auth_code": code})
        if res.user:
            st.session_state.user = res.user
            # SAUVEGARDE EN COOKIE (valable 30 jours)
            controller.set("sys_acc_token", res.session.access_token, max_age=2592000)
            controller.set("sys_ref_token", res.session.refresh_token, max_age=2592000)
            
        st.query_params.clear()
    except Exception as e:
        st.error(f"Erreur de validation OAuth : {e}")


def render_login_page(supabase, pkce_store: dict, app_url: str) -> None:
    """Affiche l'écran de connexion."""
    st.title("🔐 Accès Sécurisé Sysiphe")
    st.markdown("Connecte-toi pour accéder à ton tableau de bord personnel.")

    _, col_auth, _ = st.columns([1, 2, 1])
    with col_auth:
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
                    # SAUVEGARDE EN COOKIE (valable 30 jours)
                    controller.set("sys_acc_token", resp.session.access_token, max_age=2592000)
                    controller.set("sys_ref_token", resp.session.refresh_token, max_age=2592000)
                    st.rerun()
            except Exception as e:
                st.error(f"❌ Erreur : {e}")
