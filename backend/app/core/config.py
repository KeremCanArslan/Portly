import os
import secrets
import sys
from pathlib import Path
from dotenv import load_dotenv
from loguru import logger

# config.py → app/core/config.py, backend/.env her zaman 2 seviye yukarıda
_backend_env = Path(__file__).resolve().parents[2] / ".env"
load_dotenv(dotenv_path=_backend_env, override=True)

_INSECURE_DEFAULT_HINT = "varsayilan_gizli_anahtar_degistir"


def _resolve_secret_key() -> str:
    """
    SECRET_KEY .env'den okunur. Env'de yoksa veya bilinen zayıf değerse:
      - PORTLY_ENV=production ise sürecin başlamasını engelle.
      - Aksi halde rastgele bir geçici anahtar üret ve uyar.
    """
    env_key = os.getenv("SECRET_KEY", "").strip()
    is_prod = os.getenv("PORTLY_ENV", "development").lower() == "production"

    if env_key and env_key != _INSECURE_DEFAULT_HINT:
        return env_key

    if is_prod:
        sys.exit(
            "FATAL: SECRET_KEY production ortamında ayarlanmalı. "
            "`python -c \"import secrets;print(secrets.token_urlsafe(64))\"` ile üretebilirsin."
        )

    fallback = secrets.token_urlsafe(64)
    logger.warning(
        "SECRET_KEY .env'de yok ya da güvensiz. Geçici anahtar üretildi — "
        "her yeniden başlatmada token'lar geçersiz olacak. Production'a çıkmadan önce sabitleyin."
    )
    return fallback


class Settings:
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./portly.db")
    SECRET_KEY: str = _resolve_secret_key()
    NEWS_API_KEY: str = os.getenv("NEWS_API_KEY", "")
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", "")
    # Groq modeli env'den değiştirilebilir (deploy beklemeden). Boşsa kod
    # içindeki aday listesi sırayla denenir — bkz. llm_service._GROQ_MODELS.
    GROQ_MODEL: str = os.getenv("GROQ_MODEL", "")
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    # Finnhub — hisse temel verisi (F/K, ROE, marj, bilanço). yfinance `.info`
    # (Yahoo quoteSummary) Render datacenter IP'sinde BLOKLU → temel analiz/
    # bilanço boş geliyordu. Finnhub API-key'li (IP-bağımsız) güvenilir kaynak;
    # boşsa servis devre dışı, yfinance'e düşülür. Ücretsiz tier: ABD hisseleri.
    FINNHUB_API_KEY: str = os.getenv("FINNHUB_API_KEY", "")
    SMTP_HOST: str = os.getenv("SMTP_HOST", "smtp.gmail.com")
    SMTP_PORT: int = int(os.getenv("SMTP_PORT", "587"))
    SMTP_USER: str = os.getenv("SMTP_USER", "")
    SMTP_PASSWORD: str = os.getenv("SMTP_PASSWORD", "")
    SMTP_FROM_NAME: str = os.getenv("SMTP_FROM_NAME", "Portly")
    # Brevo (transactional email — HTTPS/443). Render giden SMTP portlarını
    # (25/465/587) bloklar → "Network is unreachable". Cloud'da mail göndermenin
    # tek yolu HTTP API. BREVO_API_KEY tanımlıysa email_service Brevo'yu kullanır;
    # boşsa lokal geliştirme için Gmail SMTP'ye düşer.
    BREVO_API_KEY: str = os.getenv("BREVO_API_KEY", "")
    # Brevo'da doğrulanmış gönderici adresi; verilmezse SMTP_USER'a düşer.
    BREVO_SENDER_EMAIL: str = os.getenv("BREVO_SENDER_EMAIL", os.getenv("SMTP_USER", ""))
    REDIS_URL: str = os.getenv("REDIS_URL", "")

    # Yahoo Finance çıkış-IP çözümü (ücretsiz): Cloudflare Worker reverse
    # proxy'sinin kökü, örn. https://portly-yahoo.<hesap>.workers.dev
    # Boşsa Yahoo'ya DOĞRUDAN gidilir (mevcut davranış). Kurulum:
    # infra/cloudflare-worker/README.md
    YAHOO_PROXY_BASE: str = os.getenv("YAHOO_PROXY_BASE", "").rstrip("/")

    # TEFAS (yatırım fonu birim pay değeri) için aynı kaçış yolu. TEFAS'ın
    # Render'ın IP'sini kısıtlayıp kısıtlamadığı ÖLÇÜLMEDİ; kısıtlarsa bu
    # değişkeni tanımlamak yeterli (Worker zaten TEFAS'ı da vekilliyor,
    # kod değişikliği gerekmez). Boşsa TEFAS'a DOĞRUDAN gidilir.
    TEFAS_PROXY_BASE: str = os.getenv("TEFAS_PROXY_BASE", "").rstrip("/")


settings = Settings()
