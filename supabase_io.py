"""
Sysiphe — Couche d'accès aux données (Supabase + cache Streamlit).
Toute fonction ici suppose un contexte Streamlit actif (st.cache_data, st.secrets).
"""
import streamlit as st
import pandas as pd
from supabase import create_client

from data import calculer_effort, DEFAULT_VARIANTES, DEFAULT_FORMES


def get_supabase_client():
    if "supabase" not in st.session_state:
        st.session_state.supabase = create_client(
            st.secrets["SUPABASE_URL"], st.secrets["SUPABASE_KEY"]
        )
    return st.session_state.supabase


@st.cache_data(ttl=60)
def load_data(_supabase, uid: str, current_weight: float, variantes_config: dict, formes_config: dict = None) -> pd.DataFrame:
    """
    Charge toutes les perfs de l'utilisateur. current_weight, variantes_config
    et formes_config font partie de la clé de cache pour forcer un recalcul
    rétroactif de effort_pondere si l'un des trois change.
    Le client _supabase est injecté pour éviter les appels au session_state dans le cache.
    """
    
    # Correction : utilisation de uid et limite à 10 000 lignes
    response = _supabase.table("perfs").select("*").eq("user_id", uid).limit(10000).execute()
    
    # Sécurité si aucune donnée n'est renvoyée
    if not response.data:
        return pd.DataFrame()

    df = pd.DataFrame(response.data)
    df["date"] = pd.to_datetime(df["date"]).dt.date

    for col in ["serie", "forme", "effort_pondere", "unite", "charge"]:
        if col not in df.columns:
            df[col] = None

    df["serie"] = df["serie"].fillna(1).astype(int)
    df["charge"] = pd.to_numeric(df["charge"], errors="coerce").fillna(0.0)
    df["exercice"] = df["exercice"].astype(str).str.strip()

    def _clean(col, default):
        return (df[col].astype(str).str.strip()
                .replace({"": default, "nan": default, "None": default}))

    df["forme"] = _clean("forme", "Normal")
    df["unite"] = _clean("unite", "Sec")
    df["elastique"] = _clean("elastique", "Aucun")
    df["tension"] = _clean("tension", "N/A")
    df["variante"] = (df["variante"].astype(str).str.strip()
                      .replace({"Advanced Tuck": "Adv_Tuck", "Half Lay": "Half_Lay",
                                "": "Tuck", "nan": "Tuck", "None": "Tuck"}))

    df.loc[df["categorie"].str.lower().str.strip()
             .isin(["force iso", "force isometrique", "statique"]), "categorie"] = "Force Iso"
    df.loc[df["categorie"].str.lower().str.strip()
             .isin(["force", "musculation", ""]), "categorie"] = "Musculation"
    df["categorie"] = df["categorie"].fillna("Musculation")

    df["effort_pondere"] = df.apply(
        lambda r: calculer_effort(
            r["variante"], r["elastique"], r["tension"], r["forme"],
            r["performance"], current_weight, variantes_config, formes_config
        ) if r["exercice"].lower() == "planche" else 0,
        axis=1
    )
    return df


def insert_perfs(rows: list) -> None:
    if rows:
        get_supabase_client().table("perfs").insert(rows).execute()


def delete_perfs(uid: str, date_str: str, exercice: str = None) -> None:
    q = get_supabase_client().table("perfs").delete().eq("user_id", uid).eq("date", date_str)
    if exercice is not None:
        q = q.eq("exercice", exercice)
    q.execute()


def update_exercise_name(uid: str, old_name: str, new_name: str) -> None:
    get_supabase_client().table("perfs").update({"exercice": new_name}) \
        .eq("user_id", uid).eq("exercice", old_name).execute()


# =========================================================================
# PERSISTANCE DE LA CALIBRATION (table user_settings — voir SETUP.md)
# =========================================================================
def load_user_settings(uid: str) -> dict:
    """
    Charge la calibration des variantes depuis Supabase.
    Retourne DEFAULT_VARIANTES si la table n'existe pas encore ou si
    l'utilisateur n'a jamais sauvegardé de calibration (dégradation gracieuse).
    """
    try:
        res = get_supabase_client().table("user_settings") \
            .select("variantes_config").eq("user_id", uid).execute()
        if res.data and res.data[0].get("variantes_config"):
            return {**DEFAULT_VARIANTES, **res.data[0]["variantes_config"]}
    except Exception:
        pass
    return dict(DEFAULT_VARIANTES)


def save_user_settings(uid: str, variantes_config: dict) -> bool:
    """Sauvegarde (upsert) la calibration. Retourne False si échec (table absente, etc.)."""
    try:
        get_supabase_client().table("user_settings").upsert({
            "user_id": uid,
            "variantes_config": variantes_config,
        }).execute()
        return True
    except Exception:
        return False


def load_app_theme(uid: str, default: str = "Épuré") -> str:
    """Charge le thème visuel sauvegardé par l'utilisateur. Retourne `default`
    si jamais sauvegardé ou si la colonne/table n'existe pas encore."""
    try:
        res = get_supabase_client().table("user_settings") \
            .select("app_theme").eq("user_id", uid).execute()
        if res.data and res.data[0].get("app_theme"):
            return res.data[0]["app_theme"]
    except Exception:
        pass
    return default


def save_app_theme(uid: str, theme_name: str) -> bool:
    """Sauvegarde (upsert) le thème visuel choisi. Retourne False si échec."""
    try:
        get_supabase_client().table("user_settings").upsert({
            "user_id": uid,
            "app_theme": theme_name,
        }).execute()
        return True
    except Exception:
        return False


def load_formes_config(uid: str) -> dict:
    """Charge la calibration des formes (indices de difficulté) depuis Supabase.
    Retourne DEFAULT_FORMES si jamais sauvegardée (dégradation gracieuse)."""
    try:
        res = get_supabase_client().table("user_settings") \
            .select("formes_config").eq("user_id", uid).execute()
        if res.data and res.data[0].get("formes_config"):
            return {**DEFAULT_FORMES, **res.data[0]["formes_config"]}
    except Exception:
        pass
    return dict(DEFAULT_FORMES)


def save_formes_config(uid: str, formes_config: dict) -> bool:
    """Sauvegarde (upsert) la calibration des formes. Retourne False si échec."""
    try:
        get_supabase_client().table("user_settings").upsert({
            "user_id": uid,
            "formes_config": formes_config,
        }).execute()
        return True
    except Exception:
        return False


def load_inactivity_days(uid: str, default: int = 2) -> int:
    """Nombre de jours d'inactivité avant qu'un exercice disparaisse de la
    page d'accueil. Retourne `default` si jamais sauvegardé."""
    try:
        res = get_supabase_client().table("user_settings") \
            .select("inactivity_days").eq("user_id", uid).execute()
        if res.data and res.data[0].get("inactivity_days") is not None:
            return int(res.data[0]["inactivity_days"])
    except Exception:
        pass
    return default


def save_inactivity_days(uid: str, days: int) -> bool:
    try:
        get_supabase_client().table("user_settings").upsert({
            "user_id": uid,
            "inactivity_days": int(days),
        }).execute()
        return True
    except Exception:
        return False


def load_enable_charges(uid: str, default: bool = True) -> bool:
    """Charge la préférence d'affichage des charges externes."""
    try:
        res = get_supabase_client().table("user_settings") \
            .select("enable_charges").eq("user_id", uid).execute()
        if res.data and res.data[0].get("enable_charges") is not None:
            return bool(res.data[0]["enable_charges"])
    except Exception:
        pass
    return default


def save_enable_charges(uid: str, enable: bool) -> bool:
    """Sauvegarde la préférence d'affichage des charges externes."""
    try:
        get_supabase_client().table("user_settings").upsert({
            "user_id": uid,
            "enable_charges": bool(enable),
        }).execute()
        return True
    except Exception:
        return False
