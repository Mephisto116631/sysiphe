"""
Sysiphe — Couche d'accès aux données (Supabase + cache Streamlit).
Toute fonction ici suppose un contexte Streamlit actif (st.cache_data, st.secrets).
"""
import streamlit as st
import pandas as pd
from supabase import create_client

from data import calculer_effort, DEFAULT_VARIANTES


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

    df.loc[df["categorie"].str.lower().str.strip()
             .isin(["force iso", "force isometrique", "statique"]), "categorie"] = "Force Iso"
    df.loc[df["categorie"].str.lower().str.strip()
             .isin(["force", "musculation", ""]), "categorie"] = "Musculation"
    df["categorie"].fillna("Musculation", inplace=True)

    df["effort_pondere"] = df.apply(
        lambda r: calculer_effort(
            r["variante"], r["elastique"], r["tension"], r["forme"],
            r["performance"], current_weight, variantes_config
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
