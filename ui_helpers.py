"""
Sysiphe — Petits utilitaires d'interface.
"""
import time
import streamlit as st


def is_debounced(action_key: str, window_seconds: float = 2.0) -> bool:
    """
    Retourne True si une action identique a été déclenchée il y a moins de
    `window_seconds` secondes. Protège contre les doubles clics qui
    dupliqueraient une insertion Supabase. Met à jour le timestamp à chaque appel.
    """
    store = st.session_state.setdefault("_debounce_ts", {})
    now = time.time()
    last = store.get(action_key, 0)
    if now - last < window_seconds:
        return True
    store[action_key] = now
    return False
