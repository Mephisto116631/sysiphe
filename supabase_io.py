"""
Sysiphe — Couche d'accès aux données (Supabase + cache Streamlit).
Toute fonction ici suppose un contexte Streamlit actif (st.cache_data, st.secrets).
"""
import streamlit as st
import pandas as pd
from supabase import create_client

from data import calculer_effort, DEFAULT_VARIANTES

_SETTINGS_DEFAULTS = {
    "variantes_config": None,   # None → sera remplacé par DEFAULT_VARIANTES
    "weight": 97,
    "nb_days_avg": 5,
    "include_planche": True,
}


def get_supabase_client():
    if "supabase" not in st.session_state:
        st.session_state.supabase = create_client(
            st.secrets["SUPABASE_URL"], st.secrets["SUPABASE_KEY"]
        )
    return st.session_state.supabase


@st.cache_data(ttl=60)
def load_data(uid: str, current_weight: float, variantes_config: dict) -> pd.DataFrame:
    """
    Charge toutes les perfs de l'utilisateur. current_weight et variantes_config
    font partie de la clé de cache pour forcer un recalcul si l'un des deux change.
    """
    supabase = get_supabase_client()
    reponse = supabase.table("perfs").select("*").eq("user_id", uid).execute()
    if not reponse.data:
        return pd.DataFrame()

    df = pd.DataFrame(reponse.data)
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

    mask_iso = df["categorie"].str.lower().str.strip().isin(["force iso", "force isometrique", "statique"])
    df.loc[mask_iso, "categorie"] = "Force Iso"
    mask_muscu = df["categorie"].str.lower().str.strip().isin(["force", "musculation", ""])
    df.loc[mask_muscu, "categorie"] = "Musculation"
    df["categorie"] = df["categorie"].fillna("Musculation")

    df["effort_pondere"] = df.apply(
        lambda r: calculer_effort(
            r["variante"], r["elastique"], r["tension"], r["forme"],
            r["performance"], current_weight, variantes_config
        ) if r["exercice"].lower() == "planche" else 0,
        axis=1
    )
    return df


def insert_perfs(rows: list) -> bool:
    """Insère les lignes en base. Retourne True si OK, False si erreur."""
    if not rows:
        return False
    try:
        get_supabase_client().table("perfs").insert(rows).execute()
        return True
    except Exception as e:
        import streamlit as st
        st.error(f"❌ Erreur lors de la sauvegarde : {e}")
        return False


def delete_perfs(uid: str, date_str: str, exercice: str = None) -> bool:
    """Supprime des perfs. Retourne True si OK, False si erreur."""
    try:
        q = get_supabase_client().table("perfs").delete().eq("user_id", uid).eq("date", date_str)
        if exercice is not None:
            q = q.eq("exercice", exercice)
        q.execute()
        return True
    except Exception as e:
        import streamlit as st
        st.error(f"❌ Erreur lors de la suppression : {e}")
        return False


# =========================================================================
# GESTION DES PROFILS (table profiles)
# =========================================================================
@st.cache_data(ttl=30)
def load_profiles() -> list[dict]:
    """Retourne la liste des profils [{id, name}] triée par created_at."""
    try:
        res = get_supabase_client().table("profiles").select("id, name").order("created_at").execute()
        return res.data or []
    except Exception:
        return []


def create_profile(name: str) -> dict | None:
    """Crée un nouveau profil. Retourne {id, name} ou None si erreur."""
    try:
        res = get_supabase_client().table("profiles").insert({"name": name.strip()}).execute()
        if res.data:
            load_profiles.clear()
            return res.data[0]
    except Exception as e:
        import streamlit as st
        st.error(f"❌ Erreur création profil : {e}")
    return None


def rename_profile(profile_id: str, new_name: str) -> bool:
    """Renomme un profil. Retourne True si OK."""
    try:
        get_supabase_client().table("profiles").update({"name": new_name.strip()}).eq("id", profile_id).execute()
        load_profiles.clear()
        return True
    except Exception as e:
        import streamlit as st
        st.error(f"❌ Erreur renommage : {e}")
        return False


def delete_profile(profile_id: str) -> bool:
    """Supprime un profil (et laisse ses perfs orphelines). Retourne True si OK."""
    try:
        get_supabase_client().table("profiles").delete().eq("id", profile_id).execute()
        load_profiles.clear()
        return True
    except Exception:
        return False


def update_exercise_name(uid: str, old_name: str, new_name: str) -> None:
    get_supabase_client().table("perfs").update({"exercice": new_name}) \
        .eq("user_id", uid).eq("exercice", old_name).execute()


# =========================================================================
# PERSISTANCE DES PARAMÈTRES UTILISATEUR (table user_settings)
# =========================================================================
def load_user_settings(uid: str) -> dict:
    """
    Charge tous les paramètres depuis Supabase.
    Retourne les valeurs par défaut si l'utilisateur n'a encore rien sauvegardé.
    Dégradation gracieuse si la table est absente.
    """
    try:
        res = get_supabase_client().table("user_settings") \
            .select("variantes_config, weight, nb_days_avg, include_planche") \
            .eq("user_id", uid).execute()
        if res.data:
            row = res.data[0]
            return {
                "variantes_config": {
                    **DEFAULT_VARIANTES,
                    **(row.get("variantes_config") or {}),
                },
                "weight":          int(row["weight"])          if row.get("weight")          is not None else 97,
                "nb_days_avg":     int(row["nb_days_avg"])     if row.get("nb_days_avg")     is not None else 5,
                "include_planche": bool(row["include_planche"]) if row.get("include_planche") is not None else True,
            }
    except Exception:
        pass
    return {
        "variantes_config": dict(DEFAULT_VARIANTES),
        "weight":           97,
        "nb_days_avg":      5,
        "include_planche":  True,
    }


def save_user_settings(
    uid: str,
    variantes_config: dict,
    weight: float | None = None,
    nb_days_avg: int | None = None,
    include_planche: bool | None = None,
) -> bool:
    """
    Upsert de tous les paramètres utilisateur.
    Les arguments optionnels ne sont inclus que s'ils sont fournis (non None).
    Retourne False si la sauvegarde échoue (mode dégradé gracieux).
    """
    try:
        payload: dict = {"user_id": uid, "variantes_config": variantes_config}
        if weight is not None:
            payload["weight"] = float(weight)
        if nb_days_avg is not None:
            payload["nb_days_avg"] = int(nb_days_avg)
        if include_planche is not None:
            payload["include_planche"] = bool(include_planche)
        get_supabase_client().table("user_settings").upsert(payload).execute()
        return True
    except Exception:
        return False
