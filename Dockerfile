# Backend için. Root context — `docker build -t portly-backend .` ile derlenir.
# Render bu Dockerfile'ı otomatik bulur (render.yaml ile bağlanır).
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# yfinance/curl_cffi/cryptography/psycopg için sistem bağımlılıkları.
# Slim imajda gcc + libpq-dev gerekli; sonradan apt cache silinir.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt ./
RUN pip install -r requirements.txt

COPY backend/ ./

# Render $PORT env-var atar (genelde 10000). Fallback 8000.
ENV PORT=8000
EXPOSE 8000

# Migration → server. Cold start'ta DB şeması garanti güncel olur.
# sh -c ile $PORT genişler.
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
