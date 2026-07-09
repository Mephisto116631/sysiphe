"""
Sysiphe — Fonctions métier pures (sans dépendance Streamlit/Supabase).
Toutes les fonctions ici sont testables unitairement (voir test_data.py).
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta, timezone

# =========================================================================
# CONFIGURATION DE BASE
# =========================================================================
CONFIG = {
    "elastiques": {"Aucun": 0, "Rouge/Violet": 35, "Jaune+Bleu": 40, "Jaune": 25, "Bleu": 15, "Vert": 45},
    "tensions":   {"N/A": 0.70, "Ecarté": 0.85, "Normal": 0.70, "Serré": 0.60},
}

# Formes désormais calibrables par l'utilisateur (voir user_settings.formes_config).
# Ordre = difficulté croissante (score le plus bas → le plus haut).
DEFAULT_FORMES = {"High": 34, "Normal": 47.6, "Bas": 66.64, "Dead": 93.296}

DEFAULT_VARIANTES = {
    "Full": 10, "Straddle": 9, "Half_Lay": 9,
    "Diamond": 5, "Maltese": 11, "Tuck": 2, "Adv_Tuck": 3,
}


# =========================================================================
# CALCUL D'EFFORT PLANCHE
# =========================================================================
def calculer_effort(variante: str, elastique: str, tension: str, forme: str,
                     temps, weight: float, variantes_config: dict = None,
                     formes_config: dict = None) -> int:
    """
    Calcule l'effort pondéré d'un hold de planche isométrique.

    Fonction pure : variantes_config, formes_config et weight sont passés
    explicitement, jamais lus depuis st.session_state (testabilité + évite
    les bugs de cache).
    """
    variantes_config = variantes_config or DEFAULT_VARIANTES
    formes_config = formes_config or DEFAULT_FORMES
    try:
        force_e = CONFIG["elastiques"].get(elastique, 0)
        ratio_t = CONFIG["tensions"].get(tension, 0.70)
        score_v = variantes_config.get(variante, 0)
        score_f = formes_config.get(forme, 0)
        if score_v == 0 or score_f == 0 or not temps:
            return 0
        kg_traction = force_e * ratio_t
        poids_eff = weight - kg_traction
        facteur_e = (poids_eff / 100) ** 2
        facteur_m = (score_v * score_f) ** 1.2
        return int(round((float(temps) * facteur_e * facteur_m) / 100))
    except (ValueError, TypeError, ZeroDivisionError):
        return 0


# =========================================================================
# PARSING DES SAISIES
# =========================================================================
def parse_reps(raw: str) -> list:
    """
    Parse une chaîne de reps espacées ("12 10 8") en liste de floats.
    Lève ValueError si une valeur est non numérique ou négative.
    """
    values = []
    for token in raw.strip().split():
        val = float(token)
        if val < 0:
            raise ValueError(f"Valeur négative non autorisée : {val}")
        values.append(val)
    return values


# =========================================================================
# LISSAGE / RÉÉCHANTILLONNAGE
# =========================================================================
def lisser_donnees(df: pd.DataFrame, index_col: str, columns_col: str,
                    values_col: str, fill_method: str = "interpolate") -> pd.DataFrame:
    """
    Rééchantillonne sur un index date continu.

    fill_method:
      - 'interpolate' : remplissage linéaire (courbes de tendance lisses)
      - 'ffill'       : dernier record connu (évite de fabriquer des valeurs
                         fictives entre deux séances espacées)
      - 'zero'        : remplace les trous par 0 (volumes journaliers)
    """
    if df.empty:
        return pd.DataFrame()
    df = df.copy()
    df[index_col] = pd.to_datetime(df[index_col])
    pivot = df.pivot_table(index=index_col, columns=columns_col, values=values_col, aggfunc="max")
    if len(pivot) > 1:
        idx = pd.date_range(pivot.index.min(), pivot.index.max(), name=index_col)
        pivot = pivot.reindex(idx)
        if fill_method == "zero":
            pivot = pivot.fillna(0)
        elif fill_method == "ffill":
            pivot = pivot.ffill()
        else:
            pivot = pivot.interpolate(method="linear", limit_direction="both")
    return pivot


# =========================================================================
# DÉTECTION DE PLATEAU / PROGRESSION
# =========================================================================
def detect_plateau(dates: list, values: list, window_days: int = 21,
                    relative_threshold: float = 0.05) -> dict:
    """
    Analyse la tendance des `window_days` derniers jours via régression linéaire.

    Retourne {"status": "progress"|"plateau"|"regression"|"insufficient_data",
              "slope": float, "relative_slope": float, "n_points": int}
    """
    if not dates or not values or len(dates) != len(values):
        return {"status": "insufficient_data", "slope": 0.0, "relative_slope": 0.0, "n_points": 0}

    df = pd.DataFrame({"date": pd.to_datetime(list(dates)), "value": list(values)}).sort_values("date")
    cutoff = df["date"].max() - timedelta(days=window_days)
    df_window = df[df["date"] >= cutoff]

    if len(df_window) < 3:
        return {"status": "insufficient_data", "slope": 0.0, "relative_slope": 0.0, "n_points": len(df_window)}

    x = df_window["date"].map(pd.Timestamp.toordinal).to_numpy(dtype=float)
    y = df_window["value"].to_numpy(dtype=float)
    x = x - x.min()  # stabilité numérique

    slope, _ = np.polyfit(x, y, 1)
    mean_val = y.mean() if y.mean() != 0 else 1.0
    relative_slope = (slope * window_days) / mean_val

    if relative_slope > relative_threshold:
        status = "progress"
    elif relative_slope < -relative_threshold:
        status = "regression"
    else:
        status = "plateau"

    return {"status": status, "slope": float(slope),
            "relative_slope": float(relative_slope), "n_points": len(df_window)}


# =========================================================================
# COMPARAISON DE PÉRIODES
# =========================================================================
def compute_period_comparison(df: pd.DataFrame, date_col: str, value_col: str,
                               current_start, current_end,
                               previous_start, previous_end) -> dict:
    """
    Compare la somme de `value_col` entre deux fenêtres de dates.
    Retourne {"current_total", "previous_total", "delta_pct"} (delta_pct=None si previous_total==0).
    """
    if df.empty:
        return {"current_total": 0.0, "previous_total": 0.0, "delta_pct": None}

    cur_mask = (df[date_col] >= current_start) & (df[date_col] <= current_end)
    prev_mask = (df[date_col] >= previous_start) & (df[date_col] <= previous_end)

    current_total = float(df.loc[cur_mask, value_col].sum())
    previous_total = float(df.loc[prev_mask, value_col].sum())

    if previous_total == 0:
        delta_pct = None
    else:
        delta_pct = round((current_total - previous_total) / previous_total * 100, 1)

    return {"current_total": current_total, "previous_total": previous_total, "delta_pct": delta_pct}


# =========================================================================
# SUGGESTION DE PROCHAINE SÉANCE
# =========================================================================
def suggest_next_session(dates: list) -> dict:
    """
    À partir d'une liste de dates de séances passées, détermine le repos habituel
    (mode des jours de repos) et suggère la prochaine date de séance optimale.

    Retourne {"mode_repos": int|None, "next_session": date|None, "days_until": int|None}
    """
    if not dates or len(dates) < 2:
        return {"mode_repos": None, "next_session": None, "days_until": None}

    df = pd.DataFrame({"date": pd.to_datetime(sorted(dates))})
    df["jours_repos"] = df["date"].diff().dt.days - 1
    df_repos = df.dropna()
    if df_repos.empty:
        return {"mode_repos": None, "next_session": None, "days_until": None}

    mode_repos = int(df_repos["jours_repos"].mode()[0])
    last_date = df["date"].max()
    next_session = (last_date + timedelta(days=mode_repos + 1)).date()
    days_until = (next_session - datetime.now().date()).days

    return {"mode_repos": mode_repos, "next_session": next_session, "days_until": days_until}


# =========================================================================
# CALENDRIER D'ACTIVITÉ (style "GitHub contributions")
# =========================================================================
def compute_daily_activity(activity_by_date: dict, year: int) -> pd.DataFrame:
    """
    Construit un calendrier complet (1er janvier -> 31 décembre) pour `year`,
    avec un compteur d'activité par jour (0 si pas de séance ce jour-là).

    activity_by_date: dict {date (str | datetime.date | pd.Timestamp) -> count}

    Retourne un DataFrame avec colonnes : date, count, weekday (0=Lundi..6=Dimanche),
    week_index (0-based, semaines de 7 jours depuis le 1er janvier), month (1-12).
    """
    normalized = {}
    for k, v in activity_by_date.items():
        if isinstance(k, str):
            k = pd.to_datetime(k).date()
        elif isinstance(k, pd.Timestamp):
            k = k.date()
        normalized[k] = v

    start = pd.Timestamp(year=year, month=1, day=1)
    end = pd.Timestamp(year=year, month=12, day=31)
    full_range = pd.date_range(start, end, freq="D")

    df = pd.DataFrame({"date": full_range})
    df["count"] = df["date"].dt.date.map(normalized).fillna(0).astype(int)
    df["weekday"] = df["date"].dt.weekday  # 0=Lundi ... 6=Dimanche
    df["week_index"] = (df["date"] - start).dt.days // 7
    df["month"] = df["date"].dt.month
    return df


# =========================================================================
# EXPORT ICS (RAPPEL CALENDRIER)
# =========================================================================
def build_ics_event(start_dt: datetime, title: str, description: str = "",
                     duration_minutes: int = 60, alarm_minutes_before: int = 60) -> str:
    """
    Construit un fichier .ics minimal (RFC 5545) pour un rappel de séance,
    sans dépendance externe.
    """
    end_dt = start_dt + timedelta(minutes=duration_minutes)
    fmt = "%Y%m%dT%H%M%S"
    uid = f"sysiphe-{start_dt.strftime('%Y%m%d%H%M%S')}@sysiphe.local"
    now_stamp = datetime.now(timezone.utc).strftime(fmt) + "Z"

    return (
        "BEGIN:VCALENDAR\r\n"
        "VERSION:2.0\r\n"
        "PRODID:-//Sysiphe//Reminder//FR\r\n"
        "BEGIN:VEVENT\r\n"
        f"UID:{uid}\r\n"
        f"DTSTAMP:{now_stamp}\r\n"
        f"DTSTART:{start_dt.strftime(fmt)}\r\n"
        f"DTEND:{end_dt.strftime(fmt)}\r\n"
        f"SUMMARY:{title}\r\n"
        f"DESCRIPTION:{description}\r\n"
        "BEGIN:VALARM\r\n"
        "ACTION:DISPLAY\r\n"
        f"TRIGGER:-PT{alarm_minutes_before}M\r\n"
        f"DESCRIPTION:{title}\r\n"
        "END:VALARM\r\n"
        "END:VEVENT\r\n"
        "END:VCALENDAR\r\n"
    )
