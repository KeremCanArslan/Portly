import asyncio
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.api.v1 import (
    auth,
    behavior,
    chat,
    coach,
    market,
    news,
    portfolio as portfolio_api,
    stress,
    trading,
    alerts,
    chart,
    watchlist,
    notes,
    signals,
)
from app.core import cache
from app.core.config import settings
from app.core.activity import mark_activity, seconds_since_activity
from app.core.database import Base, engine  # noqa: F401 — Base.metadata Alembic için lazım
from app.core.json_response import SafeJSONResponse
from app.core.limiter import limiter
from app.services import (
    market_data_service,
    market_refresh_service,
    price_alert_service,
)
from app.models import refresh_token as _refresh_token_model  # noqa: F401 — register table
from app.models import price_alert as _price_alert_model  # noqa: F401 — register table
from app.models import dividend_cache as _dividend_cache_model  # noqa: F401 — register table
from app.models import chart_drawing as _chart_drawing_model  # noqa: F401 — register table
from app.models import watchlist as _watchlist_model  # noqa: F401 — register table
from app.models import note as _note_model  # noqa: F401 — register table

# Startup'ta arka planda prewarm edilecek popüler semboller (varsayılan watchlist).
_PREWARM_SYMBOLS = [
    "GC=F", "USDTRY=X", "EURTRY=X", "BTC-USD",
    "THYAO.IS", "ASELS.IS", "AAPL", "NVDA",
]

# main.py → app/main.py, backend/.env her zaman 1 seviye yukarıda
load_dotenv(dotenv_path=Path(__file__).resolve().parent.parent / ".env", override=True)

# Logger'ı middleware'lerden ÖNCE yapılandır ki ilk istekler de doğru formatlansın.
# loguru standart logging'den daha temiz; renkli ve yapılandırılmış çıktı sağlar.
logger.remove()
logger.add(
    sys.stdout,
    format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{extra[request_id]}</cyan> | <level>{message}</level>",
    level="INFO",
)
logger.configure(extra={"request_id": "-"})

# Şema artık Alembic ile yönetiliyor. Migration uygulamak için: `alembic upgrade head`.
# Geliştirme sırasında yeni migration üretmek için: `alembic revision --autogenerate -m "msg"`.

# Fiyat-alarmı worker'ı yalnız uygulama son _WORKER_ACTIVE_WINDOW sn içinde GERÇEKTEN
# kullanıldıysa (bkz. activity.mark_activity) DB'yi yoklar; boştaysa DB'ye DOKUNMAZ →
# Neon compute'u uyur, free-tier compute kotası 7/24 yoklama ile yanmaz. Boşta uyanış
# in-memory'dir (DB roundtrip yok), aktifken davranış aynı.
_WORKER_ACTIVE_WINDOW = 600  # sn (10 dk)

# Piyasa verisi arka plan yenilemesi. AMAÇ: Yahoo'ya giden istek hızını
# kullanıcı trafiğinden BAĞIMSIZ ve öngörülebilir kılmak. Eskiden her
# portföy/benchmark/sinyal isteği Yahoo'ya çıkabiliyordu → hacim büyüyünce
# Yahoo Render IP'sini 429'luyor ve uygulama tamamen verisiz kalıyordu.
# Tur başına 3 istek (fiyat + kapanış + OHLCV), sembol sayısından bağımsız.
_MARKET_REFRESH_INTERVAL = 300  # sn (5 dk)
# Yenileme, uygulama son bu süre içinde kullanıldıysa çalışır. Alarm
# worker'ından uzun: kullanıcı geri döndüğünde cache HÂLÂ sıcak olsun,
# ama kimse yokken Yahoo/Neon kotası yanmasın.
_REFRESH_ACTIVE_WINDOW = 1800  # sn (30 dk)
# Süreç başlangıcı — /health'in uptime_s alanı için (deploy/uyanış
# ısıtması sürerken alınan ölçüm gürültülüdür).
_STARTED_MONOTONIC = time.monotonic()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Varsayılan watchlist + KULLANICILARIN TUTTUĞU pozisyonları arka planda
    # ısıt; startup'ı bloke etme. Tutulan sembollerin de prewarm'ı, portföy
    # ekranının soğuk (server restart sonrası) ilk açılışında 10sn'lik bekleme
    # yerine ısınmış cache'e düşmesini sağlar.
    def _prewarm_held_symbols() -> None:
        from app.core.database import SessionLocal
        from app.models.portfolio import Portfolio
        from app.services.symbol_alias import canonical
        from app.services import order_service, dividend_service
        db = SessionLocal()
        try:
            syms = {canonical(row[0])
                    for row in db.query(Portfolio.symbol).distinct()}
            if syms:
                # Fiyat + bölünme serisi birlikte ısıt → ilk portföy açılışı
                # (fiyat batch'i + split mutabakatı) soğuk değil.
                market_data_service.prewarm_symbols(list(syms))
                order_service.prewarm_splits(list(syms))
                # Temettü serisini de ısıt → temettü ekranının ilk açılışı
                # (kalıcı DB cache boşken bile) soğuk yfinance beklemesin.
                dividend_service.prewarm_dividends(list(syms))
                # Sinyal cache'i de süreç-içi (15 dk) → deploy/restart sonrası
                # ilk Sinyaller açılışı canlıda 3,9 sn ölçüldü (aynı tarama
                # hemen ardından 0,25 sn). Isıtma arka planda; kullanıcı
                # beklemez, paylaşılan cache'ler zaten sıcak.
                from app.services import signal_service
                warmed = signal_service.prewarm_signals(list(syms))
                if warmed:
                    logger.info(f"Sinyal ısıtma: {warmed} sembol")
        except Exception as exc:
            logger.warning(f"Held-symbol prewarm atlandı: {exc}")
        finally:
            db.close()

    async def _prewarm():
        await asyncio.to_thread(market_data_service.prewarm_symbols, _PREWARM_SYMBOLS)
        await asyncio.to_thread(_prewarm_held_symbols)

    async def _price_alert_loop():
        # Fiyat alarmları için worker (45 sn aralıkla) — yalnız uygulama aktif
        # kullanılıyorken DB'yi yoklar (boştayken Neon uyusun, kota yanmasın).
        while True:
            try:
                await asyncio.sleep(45)
                if seconds_since_activity() >= _WORKER_ACTIVE_WINDOW:
                    continue  # boşta — DB'yi yoklama, Neon uyusun
                fired = await asyncio.to_thread(
                    price_alert_service.check_and_fire_alerts
                )
                if fired:
                    logger.info(f"Price alert worker: {fired} alarm tetiklendi")
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.warning(f"Price alert worker hata: {exc}")

    async def _market_refresh_loop():
        # Tek merkezden, sabit aralıkla, sabit sayıda batch. Kullanıcı
        # istekleri artık Yahoo'yu beklemez; cache'ten okur.
        while True:
            try:
                await asyncio.sleep(_MARKET_REFRESH_INTERVAL)
                if seconds_since_activity() >= _REFRESH_ACTIVE_WINDOW:
                    continue  # kimse kullanmıyor — kota yakma
                res = await asyncio.to_thread(market_refresh_service.refresh_all)
                if res.errors:
                    logger.warning(
                        f"Piyasa yenileme kısmi ({res.symbols} sembol): "
                        f"{'; '.join(res.errors)}")
                else:
                    logger.info(
                        f"Piyasa yenilendi: {res.symbols} sembol "
                        f"(fiyat {res.quotes} · kapanış {res.closes} · "
                        f"ohlcv {res.ohlcv} · temel ısıtma {res.warmed}"
                        + (f" · yeni fon {res.new_funds}" if res.new_funds else "")
                        + ")")
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.warning(f"Piyasa yenileme worker hata: {exc}")

    prewarm_task = asyncio.create_task(_prewarm())
    alert_task = asyncio.create_task(_price_alert_loop())
    refresh_task = asyncio.create_task(_market_refresh_loop())
    try:
        yield
    finally:
        for t in (prewarm_task, alert_task, refresh_task):
            t.cancel()


# Prod'da interaktif API dokümanı KAPALI. Uygulamayı artık dışarıdan gerçek
# kullanıcılar kullanıyor; /docs + /openapi.json tüm uç listesini, gövde
# şemalarını ve örnek istekleri isteyen herkese veriyordu. Geliştirmede açık
# kalır (orada işe yarıyor).
_IS_PROD = os.getenv("PORTLY_ENV", "development").lower() == "production"

app = FastAPI(
    title="Portly API",
    description="Portföy Takibi, Haber ve AI Destekli Alım-Satım Sinyalleri Platformu",
    version="1.0.0",
    lifespan=lifespan,
    # Tüm uçlarda NaN/inf → null (yfinance NaN'ı tek başına 500 atıyordu).
    default_response_class=SafeJSONResponse,
    docs_url=None if _IS_PROD else "/docs",
    redoc_url=None if _IS_PROD else "/redoc",
    openapi_url=None if _IS_PROD else "/openapi.json",
)

# Rate limiter - main app state'ine ekle ki @limiter.limit() decoratorları çalışsın.
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS - Flutter web/mobil uygulamasının backend'e erişebilmesi için gerekli.
# .env dosyasından izin verilen origin'leri oku; production'da * kullanma!
_DEFAULT_ORIGINS = (
    "http://localhost,http://127.0.0.1,http://localhost:3000,http://127.0.0.1:3000"
)


def resolve_cors_settings(
    origins_env: str | None = None,
    regex_env: str | None = None,
    is_production: bool | None = None,
) -> dict:
    """CORS ayarını env'den çöz (saf fonksiyon — test edilebilsin diye ayrı).

    - `*` → kimlik bilgisi taşınamaz (CORS spec: credentials + wildcard yasak).
    - `origin_regex`: sabit listeye sığmayan adresler (ör. `flutter run -d
      chrome` her çalıştırmada rastgele port seçer). Prod'da boş bırakılır.
    - Prod'da `*` kaldıysa uyarı bayrağı döner: herhangi bir site API'yi
      kendi sayfasından çağırabilir, ücretsiz katman kotasını o tüketir.
    """
    raw = origins_env if origins_env is not None else os.getenv(
        "ALLOWED_ORIGINS", _DEFAULT_ORIGINS
    )
    origins = [o.strip() for o in (raw or "").split(",") if o.strip()]
    wildcard = "*" in origins
    if wildcard:
        origins = ["*"]
    regex = (
        regex_env if regex_env is not None else os.getenv("ALLOWED_ORIGIN_REGEX", "")
    ).strip() or None
    prod = (
        is_production
        if is_production is not None
        else os.getenv("PORTLY_ENV", "development").lower() == "production"
    )
    return {
        "allow_origins": origins,
        "allow_origin_regex": regex,
        "allow_credentials": not wildcard,
        "insecure_in_production": bool(prod and wildcard),
    }


_cors = resolve_cors_settings()
if _cors["insecure_in_production"]:
    logger.warning(
        "CORS production'da '*' — ALLOWED_ORIGINS'i frontend adresine kilitleyin "
        "(ör. https://portly-frontend.onrender.com)."
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors["allow_origins"],
    allow_origin_regex=_cors["allow_origin_regex"],
    allow_credentials=_cors["allow_credentials"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    """Tarayıcı tarafı sertleştirme başlıkları.

    API JSON döndürüyor ama yanıtları bir tarayıcı okuyor: `nosniff` olmadan
    tarayıcı içeriği HTML sanıp çalıştırabilir, `DENY` olmadan API yanıtı bir
    iframe'e gömülebilir. HSTS Render'da zaten TLS var — tarayıcıya "bu alan
    adına bir daha http ile gitme" der (token'ı düz metin taşıyan ilk isteği
    engeller). Referrer kısıtı, adres satırındaki yolun üçüncü taraflara
    sızmasını önler.
    """
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault(
        "Permissions-Policy", "geolocation=(), microphone=(), camera=()")
    if _IS_PROD:
        response.headers.setdefault(
            "Strict-Transport-Security", "max-age=31536000; includeSubDomains")
    return response


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    # Her HTTP isteğine kısa bir UUID atar; log satırları bu ID ile gruplanabilir.
    # Bu yöntem, birden fazla eş zamanlı istek olduğunda hangi log hangi isteğe ait
    # diye karışmamasını sağlar (basit distributed tracing).
    request_id = str(uuid.uuid4())[:8]
    start = time.time()

    # Gerçek uygulama kullanımını işaretle → arka plan worker'ı uyanık kalsın.
    # /health (UptimeRobot ping'i) ve / sayılmaz; yoksa app hiç kullanılmasa da
    # worker sürekli DB yoklayıp Neon'un uyumasını engellerdi (compute kotası).
    if request.url.path.startswith("/api/"):
        mark_activity()

    with logger.contextualize(request_id=request_id):
        logger.info(f"→ {request.method} {request.url.path}")
        response = await call_next(request)
        elapsed = (time.time() - start) * 1000
        status_emoji = "✓" if response.status_code < 400 else "✗"
        logger.info(f"← {status_emoji} {response.status_code} ({elapsed:.0f}ms)")

    response.headers["X-Request-ID"] = request_id
    return response


# API rotalarını kaydet - hepsine /api/v1 prefix'i eklenir
app.include_router(auth.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(market.router, prefix="/api/v1/market", tags=["market"])
app.include_router(trading.router, prefix="/api/v1/trading", tags=["trading"])
app.include_router(portfolio_api.router, prefix="/api/v1/portfolio", tags=["portfolio"])
app.include_router(news.router, prefix="/api/v1/news", tags=["news"])
app.include_router(coach.router, prefix="/api/v1/coach", tags=["coach"])
app.include_router(behavior.router, prefix="/api/v1/behavior", tags=["behavior"])
app.include_router(stress.router, prefix="/api/v1/stress", tags=["stress"])
app.include_router(chat.router, prefix="/api/v1/chat", tags=["chat"])
app.include_router(alerts.router, prefix="/api/v1/alerts", tags=["alerts"])
app.include_router(chart.router, prefix="/api/v1/chart", tags=["chart"])
app.include_router(watchlist.router, prefix="/api/v1/watchlist", tags=["watchlist"])
app.include_router(notes.router, prefix="/api/v1/notes", tags=["notes"])
app.include_router(signals.router, prefix="/api/v1/signals", tags=["signals"])


@app.get("/")
def read_root():
    return {"message": "Portly API çalışıyor"}


# health check - deployment ortamında "çalışıyor mu?" diye kontrol için
# HEAD'i de kabul ediyoruz: UptimeRobot free plan HEAD atıyor, GET istemiyor.
@app.api_route("/health", methods=["GET", "HEAD"])
def health_check():
    # Sürüm damgası: canlıdaki kodun HANGİ commit olduğu curl ile görülebilsin.
    # Deploy doğrulaması bugüne kadar tahmine dayanıyordu ("push ettim, herhalde
    # çıkmıştır") — Render her deploy'da RENDER_GIT_COMMIT'i kendisi verir.
    commit = os.getenv("RENDER_GIT_COMMIT", "")[:7]
    # Ölçüm koşulları da burada: performans ölçümü "soğuk mu sıcak mı" sorusu
    # bugüne kadar TAHMİNE dayanıyordu (9. tur: deploy'dan hemen sonraki
    # ardışık ölçümler 0,92 → 5,54 sn saçıldı). Artık ölçümden ÖNCE okunur:
    #   idle_s   — son /api isteğinden bu yana (bu uç aktivite saymaz, bkz.
    #              core/activity.py → /health ping'i pencereyi açmaz);
    #              ≥1800 ise arka plan yenileyici durmuş = gerçek soğuk senaryo.
    #   uptime_s — süreç yaşı; küçükse deploy/uyanış ısıtması sürüyordur.
    #   cache    — "redis" ise cache restart'a dayanır, "memory" ise her
    #              uyanışta sıfırlanır (ücretsiz katman 15 dk'da uyur).
    uptime_s = int(time.monotonic() - _STARTED_MONOTONIC)
    return {
        "status": "healthy",
        "commit": commit or "local",
        "cache": "redis" if cache.is_redis() else "memory",
        # Yahoo vekili (Cloudflare Worker) devrede mi ve toplu fiyat ucu
        # GERÇEKTEN oradan mı geçiyor? `yahoo_proxy` env'i, `quote_source` son
        # BAŞARILI çağrının ucunu söyler ("proxy" / "direct" / henüz yok).
        # Vekil kurulunca "acaba kullanılıyor mu" sorusu tahmine kalmasın.
        "yahoo_proxy": bool(settings.YAHOO_PROXY_BASE),
        "quote_source": market_data_service.quote_source(),
        "uptime_s": uptime_s,
        # Süreç açılışında "hiç istek gelmedi" hâli monotonic saatin HAM
        # değeri olarak görünüyordu (11.465.986 sn = makine uptime'ı).
        # Anlamlı üst sınır süreç yaşıdır: bundan eskisi zaten ölçülemez.
        "idle_s": min(int(seconds_since_activity()), uptime_s),
    }
