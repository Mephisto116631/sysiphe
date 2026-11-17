"""
Tests unitaires pour data.py — fonctions pures, aucune dépendance Streamlit/Supabase.
Exécution : pytest test_data.py -v
"""
import pytest
from datetime import datetime, timedelta
import pandas as pd

from data import (
    calculer_effort, parse_reps, lisser_donnees,
    detect_plateau, compute_period_comparison, build_ics_event,
    suggest_next_session, compute_daily_activity, DEFAULT_VARIANTES,
)


# --- calculer_effort ---------------------------------------------------
def test_calculer_effort_valeurs_basiques():
    eff = calculer_effort("Full", "Aucun", "N/A", "Normal", "60", 97)
    assert eff > 0
    assert isinstance(eff, int)

def test_calculer_effort_deterministe():
    a = calculer_effort("Full", "Aucun", "N/A", "Normal", "60", 97)
    b = calculer_effort("Full", "Aucun", "N/A", "Normal", "60", 97)
    assert a == b

def test_calculer_effort_temps_vide():
    assert calculer_effort("Full", "Aucun", "N/A", "Normal", "", 97) == 0

def test_calculer_effort_variante_inconnue():
    assert calculer_effort("Inexistante", "Aucun", "N/A", "Normal", "60", 97) == 0

def test_calculer_effort_temps_invalide():
    assert calculer_effort("Full", "Aucun", "N/A", "Normal", "abc", 97) == 0

def test_calculer_effort_config_custom():
    custom = {**DEFAULT_VARIANTES, "Full": 20}
    eff_default = calculer_effort("Full", "Aucun", "N/A", "Normal", "60", 97)
    eff_custom = calculer_effort("Full", "Aucun", "N/A", "Normal", "60", 97, variantes_config=custom)
    assert eff_custom > eff_default

def test_calculer_effort_elastique_plus_lourd_donne_moins_effort():
    eff_sans = calculer_effort("Full", "Aucun", "N/A", "Normal", "60", 97)
    eff_avec = calculer_effort("Full", "Vert", "Normal", "Normal", "60", 97)
    assert eff_avec < eff_sans


# --- parse_reps ----------------------------------------------------------
def test_parse_reps_simple():
    assert parse_reps("12 10 8") == [12.0, 10.0, 8.0]

def test_parse_reps_vide():
    assert parse_reps("") == []

def test_parse_reps_decimal():
    assert parse_reps("12.5 10") == [12.5, 10.0]

def test_parse_reps_negatif_leve_erreur():
    with pytest.raises(ValueError):
        parse_reps("12 -5 8")

def test_parse_reps_non_numerique_leve_erreur():
    with pytest.raises(ValueError):
        parse_reps("12 abc 8")


# --- lisser_donnees --------------------------------------------------------
def test_lisser_donnees_vide():
    df = pd.DataFrame()
    assert lisser_donnees(df, "date", "exercice", "performance").empty

def test_lisser_donnees_ffill_ne_fabrique_pas_de_valeurs():
    df = pd.DataFrame({
        "date": ["2026-01-01", "2026-01-10"],
        "exercice": ["Dips", "Dips"],
        "performance": [10, 20],
    })
    pivot = lisser_donnees(df, "date", "exercice", "performance", fill_method="ffill")
    val_milieu = pivot.loc["2026-01-05", "Dips"]
    assert val_milieu == 10

def test_lisser_donnees_zero_fill():
    df = pd.DataFrame({
        "date": ["2026-01-01", "2026-01-03"],
        "exercice": ["Dips", "Dips"],
        "performance": [10, 20],
    })
    pivot = lisser_donnees(df, "date", "exercice", "performance", fill_method="zero")
    assert pivot.loc["2026-01-02", "Dips"] == 0


# --- detect_plateau ---------------------------------------------------------
def test_detect_plateau_donnees_insuffisantes():
    result = detect_plateau([], [])
    assert result["status"] == "insufficient_data"

def test_detect_plateau_progression():
    base = datetime(2026, 1, 1)
    dates = [base + timedelta(days=i) for i in range(10)]
    values = [10 + i * 2 for i in range(10)]
    result = detect_plateau(dates, values, window_days=21)
    assert result["status"] == "progress"

def test_detect_plateau_stagnation():
    base = datetime(2026, 1, 1)
    dates = [base + timedelta(days=i) for i in range(10)]
    values = [50 for _ in range(10)]
    result = detect_plateau(dates, values, window_days=21)
    assert result["status"] == "plateau"

def test_detect_plateau_regression():
    base = datetime(2026, 1, 1)
    dates = [base + timedelta(days=i) for i in range(10)]
    values = [50 - i * 3 for i in range(10)]
    result = detect_plateau(dates, values, window_days=21)
    assert result["status"] == "regression"


# --- compute_period_comparison ----------------------------------------------
def test_compute_period_comparison_division_par_zero_evitee():
    df = pd.DataFrame({
        "date": pd.to_datetime(["2026-06-01", "2026-06-08", "2026-06-15"]),
        "volume": [100, 0, 150],
    })
    result = compute_period_comparison(
        df, "date", "volume",
        current_start=pd.Timestamp("2026-06-15"), current_end=pd.Timestamp("2026-06-21"),
        previous_start=pd.Timestamp("2026-06-08"), previous_end=pd.Timestamp("2026-06-14"),
    )
    assert result["current_total"] == 150
    assert result["previous_total"] == 0
    assert result["delta_pct"] is None

def test_compute_period_comparison_delta_positif():
    df = pd.DataFrame({
        "date": pd.to_datetime(["2026-06-01", "2026-06-08"]),
        "volume": [100, 150],
    })
    result = compute_period_comparison(
        df, "date", "volume",
        current_start=pd.Timestamp("2026-06-08"), current_end=pd.Timestamp("2026-06-08"),
        previous_start=pd.Timestamp("2026-06-01"), previous_end=pd.Timestamp("2026-06-01"),
    )
    assert result["delta_pct"] == 50.0


# --- suggest_next_session ---------------------------------------------------
def test_suggest_next_session_pattern_2_jours():
    dates = ["2026-06-01", "2026-06-04", "2026-06-07", "2026-06-10"]
    result = suggest_next_session(dates)
    assert result["mode_repos"] == 2
    assert result["next_session"] is not None

def test_suggest_next_session_donnees_insuffisantes():
    result = suggest_next_session(["2026-06-01"])
    assert result["mode_repos"] is None
    assert result["next_session"] is None


# --- build_ics_event ---------------------------------------------------------
def test_build_ics_event_contient_les_champs_essentiels():
    ics = build_ics_event(datetime(2026, 6, 25, 18, 0), "Séance Sysiphe", "Planche + Dips")
    assert "BEGIN:VCALENDAR" in ics
    assert "SUMMARY:Séance Sysiphe" in ics
    assert "DTSTART:20260625T180000" in ics
    assert "END:VCALENDAR" in ics


# --- compute_daily_activity ---------------------------------------------------
def test_compute_daily_activity_jours_sans_seance_sont_zero():
    activity = {"2026-01-01": 5, "2026-01-03": 2}
    df = compute_daily_activity(activity, 2026)
    assert df.loc[df["date"] == pd.Timestamp("2026-01-01"), "count"].iloc[0] == 5
    assert df.loc[df["date"] == pd.Timestamp("2026-01-02"), "count"].iloc[0] == 0
    assert df.loc[df["date"] == pd.Timestamp("2026-01-03"), "count"].iloc[0] == 2

def test_compute_daily_activity_couvre_annee_complete():
    df_normale = compute_daily_activity({}, 2026)
    df_bissextile = compute_daily_activity({}, 2024)
    assert len(df_normale) == 365
    assert len(df_bissextile) == 366

def test_compute_daily_activity_weekday_lundi_zero():
    # Le 5 janvier 2026 est un lundi
    df = compute_daily_activity({}, 2026)
    assert df.loc[df["date"] == pd.Timestamp("2026-01-05"), "weekday"].iloc[0] == 0

def test_compute_daily_activity_accepte_objets_date():
    from datetime import date as date_type
    activity = {date_type(2026, 3, 15): 7}
    df = compute_daily_activity(activity, 2026)
    assert df.loc[df["date"] == pd.Timestamp("2026-03-15"), "count"].iloc[0] == 7
