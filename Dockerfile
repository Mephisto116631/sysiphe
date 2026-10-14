# Sysiphe — image pour l'auto-hébergement (NAS).
# Streamlit Cloud ignore ce fichier et continue d'utiliser requirements.txt.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

# Les secrets (Supabase, APP_URL) sont montés au lancement :
# /app/.streamlit/secrets.toml — jamais inclus dans l'image.
RUN useradd --create-home --uid 1000 sysiphe && chown -R sysiphe /app
USER sysiphe

EXPOSE 8501
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8501/_stcore/health')"

CMD ["streamlit", "run", "app.py", \
     "--server.address=0.0.0.0", "--server.port=8501", \
     "--server.headless=true", "--browser.gatherUsageStats=false"]
