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

from supabase_io import (load_profiles, create_profile, claim_profile,
                         touch_profile_login, _clear_profiles_cache)

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


_TOKEN_COOKIES = ("sys_acc_token", "sys_ref_token")
_ONE_YEAR = 31536000


def persist_session_tokens(supabase) -> None:
    """Garde les jetons de la session Supabase (anonyme ou Google) dans les
    cookies d'un an. Appelé à chaque exécution : les jetons sont renouvelés
    par le client et l'ancien jeton de rafraîchissement devient invalide."""
    controller = get_cookie_controller()
    try:
        session = supabase.auth.get_session()
    except Exception:
        session = None
    if not session:
        return
    try:
        if controller.get("sys_acc_token") != session.access_token:
            controller.set("sys_acc_token", session.access_token, max_age=_ONE_YEAR)
            controller.set("sys_ref_token", session.refresh_token, max_age=_ONE_YEAR)
    except Exception:
        pass


def ensure_session(supabase) -> None:
    """Garantit une session Supabase pour ce navigateur, sans rien demander :
    reprise depuis les cookies, sinon session anonyme (créée une seule fois,
    puis gardée un an). Le PIN rattache ensuite cette session à un profil."""
    try:
        if supabase.auth.get_session():
            return
    except Exception:
        pass
    controller = get_cookie_controller()
    try:
        acc, ref = (controller.get(c) for c in _TOKEN_COOKIES)
    except KeyError:
        acc = ref = None
    if acc and ref:
        try:
            supabase.auth.set_session(acc, ref)
            persist_session_tokens(supabase)
            return
        except Exception:
            for c in _TOKEN_COOKIES:
                try:
                    controller.remove(c)
                except KeyError:
                    pass
    try:
        supabase.auth.sign_in_anonymously()
        persist_session_tokens(supabase)
    except Exception:
        pass  # réseau indisponible : la page de connexion affichera l'erreur


def _session_user(supabase):
    try:
        session = supabase.auth.get_session()
        return session.user if session else None
    except Exception:
        return None


def _login_profile(controller, profil: dict) -> None:
    touch_profile_login(profil["id"])
    controller.set("sys_profile", profil["id"], max_age=_ONE_YEAR)
    st.session_state.user = SimpleNamespace(
        id=profil["id"], email=f"{profil['name']} (profil partagé)")
    st.session_state.auth_mode = "profile"


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
        time.sleep(1.5)
        st.session_state.cookies_initialized = True
        st.rerun()
    # -------------------------------------------------------

    # 0. Session Supabase de ce navigateur (anonyme ou Google), sans latence
    #    après la première fois : jetons repris des cookies.
    if not is_oauth_return:
        ensure_session(supabase)

    # 1. Si on est déjà connecté en mémoire de session, on ne fait rien
    if st.session_state.get("user") is not None:
        return

    # 1bis. RECONNEXION SILENCIEUSE — MODE PROFIL
    # a) Via cookie (fonctionne si Chrome est resté en vie)
    try:
        saved_profile_uid = controller.get("sys_profile")
    except KeyError:
        saved_profile_uid = None
    if saved_profile_uid:
        profiles = load_profiles()
        profil = next((p for p in profiles if p["id"] == saved_profile_uid), None)
        if profil and profil.get("is_member"):
            _login_profile(controller, profil)
            return
        if profil and profil.get("has_pin") and "_pending_profile" not in st.session_state:
            # Navigateur pas encore rattaché (mise à jour de sécurité) :
            # PIN demandé une dernière fois.
            st.session_state["_pending_profile"] = profil

    # b) Fallback Supabase : si le cookie est absent (cookie de session perdu
    #    quand Android tue Chrome), reconnecte au profil le plus récent.
    #    — Pas de PIN : connexion immédiate et transparente
    #    — Avec PIN   : pré-sélectionne le profil pour aller direct au PIN
    #    Ignoré si l'utilisateur vient de se déconnecter volontairement.
    if not st.session_state.get("_manual_logout") and not is_oauth_return:
        fallback = load_profiles()
        if fallback:
            top = fallback[0]
            if top.get("is_member") or (
                    not top.get("has_pin") and claim_profile(top["id"]) == "ok"):
                _login_profile(controller, top)
                return
            else:
                # PIN requis : skip la liste, ouvre directement l'écran PIN
                if "_pending_profile" not in st.session_state:
                    st.session_state["_pending_profile"] = top

    # 2. SESSION GOOGLE / E-MAIL DÉJÀ OUVERTE (jetons repris des cookies)
    #    Une session anonyme n'ouvre rien : il faut choisir un profil + PIN.
    user = _session_user(supabase)
    if user is not None and not getattr(user, "is_anonymous", False):
        st.session_state.user = user
        st.session_state.auth_mode = "oauth"
        return

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
            controller.set("sys_acc_token", res.session.access_token, max_age=31536000)  # 1 an
            controller.set("sys_ref_token", res.session.refresh_token, max_age=31536000)  # 1 an
            
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
        profiles = load_profiles()

        # ── Étape PIN ────────────────────────────────────────────────────────
        pending = st.session_state.get("_pending_profile")
        if pending:
            st.info(f"🔐 PIN pour **{pending['name']}**")
            pin_input = st.text_input("Code PIN", type="password", max_chars=6,
                                      key="pin_input", placeholder="••••")
            c_ok, c_back = st.columns(2)
            with c_ok:
                if st.button("Valider", key="btn_pin_ok", width='stretch', type="primary"):
                    # Vérifié par le serveur, qui rattache ce navigateur au profil
                    statut = claim_profile(pending["id"], pin_input)
                    if statut == "ok":
                        st.session_state.pop("_pending_profile", None)
                        _login_profile(controller, pending)
                        st.rerun()
                    elif statut == "locked":
                        st.error("Trop d'essais : réessaie dans 15 minutes.")
                    elif statut == "bad_pin":
                        st.error("PIN incorrect.")
                    else:
                        st.error("Connexion impossible, réessaie dans un instant.")
            with c_back:
                if st.button("Retour", key="btn_pin_back", width='stretch'):
                    st.session_state.pop("_pending_profile", None)
                    st.rerun()
            st.stop()
        # ─────────────────────────────────────────────────────────────────────

        for p in profiles:
            if st.button(f"👤 {p['name']}", key=f"profile_btn_{p['id']}", width='stretch'):
                if p.get("is_member"):
                    # Navigateur déjà rattaché : pas de PIN
                    _login_profile(controller, p)
                    st.rerun()
                elif p.get("has_pin"):
                    st.session_state["_pending_profile"] = p
                    st.rerun()
                elif claim_profile(p["id"]) == "ok":
                    _login_profile(controller, p)
                    st.rerun()
                else:
                    st.error("Connexion impossible, réessaie dans un instant.")

        with st.expander("➕ Nouveau profil"):
            new_name = st.text_input("Prénom / pseudo", key="new_profile_name", placeholder="ex: Sarah")
            if st.button("Créer le profil", key="btn_create_profile", width='stretch'):
                name = new_name.strip()
                if not name:
                    st.warning("Saisis un prénom ou pseudo.")
                else:
                    profil = create_profile(name)  # rattaché à ce navigateur
                    if profil:
                        _login_profile(controller, profil)
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
                        controller.set("sys_acc_token", resp.session.access_token, max_age=31536000)  # 1 an
                        controller.set("sys_ref_token", resp.session.refresh_token, max_age=31536000)  # 1 an
                        st.rerun()
                except Exception as e:
                    st.error(f"❌ Erreur : {e}")
