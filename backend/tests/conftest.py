"""Test fixture'ları — izole bellek-içi DB + deterministik fiyat/FX mock'u.

Para-yolu testleri yfinance'e (ağ) ya da Postgres'e ASLA bağlanmamalı:
- `db`     : test başına temiz, bellek-içi SQLite oturumu (gerçek şema, StaticPool).
- `market` : fiyat + USDTRY kuru mock'u; `order_service` ve `fx_service`'in
             `get_stock_data` referanslarını tek sahte fonksiyona bağlar, fx
             cache'ini sıfırlar → kur ve fiyat testte tam kontrol edilir.
- `make_user`: verilen bakiyeyle kullanıcı üretir.
"""

import uuid

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base

# Tüm modelleri import et → Base.metadata'ya kaydolsunlar. User.chat_messages
# gibi string-ilişkiler mapper-configure anında çözülür; eksik model = hata.
import app.models.user  # noqa: F401
import app.models.portfolio  # noqa: F401
import app.models.transaction  # noqa: F401
import app.models.chat  # noqa: F401
import app.models.refresh_token  # noqa: F401
import app.models.price_alert  # noqa: F401
import app.models.dividend_cache  # noqa: F401
import app.models.chart_drawing  # noqa: F401
import app.models.watchlist  # noqa: F401
import app.models.note  # noqa: F401

from app.models.user import User
from app.services import market_data_service as _mds

# Bayat seriyi arka planda tazeleyen fonksiyonun GERÇEK hâli. Aşağıdaki autouse
# fixture onu no-op'luyor (testte daemon thread açılmasın); davranışını sınayan
# test bu fixture ile gerçeğine ulaşır.
_REAL_SERIES_REFRESH = _mds._schedule_series_refresh


@pytest.fixture
def real_series_refresh():
    return _REAL_SERIES_REFRESH


@pytest.fixture(autouse=True)
def _no_network_fallbacks(monkeypatch):
    """Yeni yedek kaynaklar (kripto borsa API'leri + TEFAS fon ucu + Yahoo
    chart + BIST günlük serisi) testte AĞA ÇIKMASIN. Bunlar üretimde Yahoo 429'ladığında devreye giren son halkalar;
    testte varsayılan olarak "veri yok" davranırlar. Kendi davranışını sınayan
    testler monkeypatch ile bunları geri açar."""
    from app.services import (bist_source_service, crypto_source_service,
                              fund_source_service, fx_service,
                              market_data_service, yahoo_chart_service)
    for mod in (bist_source_service, crypto_source_service,
                fund_source_service, yahoo_chart_service):
        monkeypatch.setattr(mod, "get_quotes", lambda symbols, *a, **k: {})
        monkeypatch.setattr(mod, "get_daily_closes",
                            lambda symbols, *a, **k: {})
        monkeypatch.setattr(mod, "get_daily_ohlcv",
                            lambda symbols, *a, **k: {})
    monkeypatch.setattr(fund_source_service, "get_history_rows",
                        lambda symbol, days: [])
    monkeypatch.setattr(bist_source_service, "get_history_rows",
                        lambda symbol, days: [])
    # Fon kataloğunun canlı tazelemesi de ağdır (arka plan işçisi günde bir
    # çağırıyor) → testte kapalı; kendi testi monkeypatch ile açar.
    monkeypatch.setattr(fund_source_service, "fetch_catalog", lambda: {})
    # Bayat seri (kapanış/OHLCV) artık arka planda TEK batch ile tazeleniyor;
    # testte daemon thread açılmasın (monkeypatch'li indirme fonksiyonu teardown
    # sonrası gerçek ağa çıkabilirdi). Davranışını sınayan test bunu kendi
    # kaydedicisiyle geri açar.
    monkeypatch.setattr(market_data_service, "_schedule_series_refresh",
                        lambda kind, symbols, period="": None)
    # GEÇMİŞ kur sorgusu da ağdır (frankfurter tarih ucu; maliyetin ₺
    # karşılığı alış günündeki kurla işaretleniyor). Testte varsayılan
    # "geçmiş kur bilinmiyor" → canlı (mock) kura düşülür; kendi testi
    # monkeypatch ile gerçek bir seri verir.
    monkeypatch.setattr(fx_service, "usdtry_rate_on", lambda day: None)

    # Temel oran ısıtması da ağdır (arka plan işçisi eksik sembolleri çeker).
    from app.services import signal_service
    monkeypatch.setattr(signal_service, "prewarm_fundamentals",
                        lambda symbols, *a, **k: 0)
    yield


@pytest.fixture(autouse=True)
def _reset_info_breaker():
    """yfinance `.info` devre kesicisi süreç-geneli → testler arasında sızmasın."""
    from app.services import fundamental_analysis_service as fa
    fa._info_fails = 0
    fa._info_blocked_until = 0.0
    yield


@pytest.fixture(autouse=True)
def _reset_auth_blacklist():
    """Oturum durumunu (blacklist + sıfırlama kodu) her test öncesi/sonrası sıfırla.

    Blacklist artık paylaşımlı cache'te (`app.core.cache`, testte süreç-içi
    sözlük) ve süreç-genelidir; testler arası temizlenmezse
    `test_logout_blacklists_token`'ın iptal ettiği token, sonraki testte taze
    SQLite (kullanıcı hep id=1) + saniye-çözünürlüklü JWT yüzünden birebir
    aynı üretilip /me'yi 401'e düşürebilir (flaky test_full_auth_flow).
    Sıfırlamak bu sızıntıyı kapatır.
    """
    from app.core import cache
    from app.services import auth_service
    def _clear():
        cache.delete_prefix(auth_service._BLACKLIST_PREFIX)
        cache.delete_prefix(auth_service._RESET_PREFIX)
    _clear()
    yield
    _clear()


@pytest.fixture
def db():
    """Test başına izole, bellek-içi SQLite oturumu.

    StaticPool + tek paylaşılan bağlantı: ":memory:" normalde her bağlantıda
    YENİ boş DB açar; StaticPool aynı bağlantıyı koruyarak şemanın test boyu
    yaşamasını sağlar.
    """
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSessionLocal = sessionmaker(
        bind=engine, autoflush=False, autocommit=False)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


@pytest.fixture
def make_user(db):
    """Kullanıcı üreten fabrika.

    `balance` parametresi pivotla anlamsızlaştı (sanal nakit kalktı) ama
    onlarca eski test hâlâ `make_user(50_000)` çağırıyor → kabul edilir,
    YOK SAYILIR. Testler ayıklandıkça parametre de kaldırılabilir."""
    def _make(balance: float | None = None, email: str | None = None) -> User:
        u = User(
            email=email or f"t-{uuid.uuid4().hex[:8]}@mail.com",
            hashed_password="x",
        )
        db.add(u)
        db.commit()
        db.refresh(u)
        return u
    return _make


@pytest.fixture
def market(monkeypatch):
    """Fiyat + USDTRY mock'u (ağ yok).

    `order_service` modülü `get_stock_data`'yı kendi ad alanına import ettiği
    için (from ... import get_stock_data) hem order_service hem
    market_data_service üzerindeki referansı patch'leriz; fx_service kuru
    market_data_service.get_stock_data("USDTRY=X") ile okur.
    """
    from app.services import fx_service

    prices = {"USDTRY=X": 40.0}

    def fake_get_stock_data(symbol, *args, **kwargs):
        s = (symbol or "").upper()
        if "TRY=X" in s:                       # USDTRY=X, EURTRY=X ...
            return {"current_price": prices.get("USDTRY=X", 40.0)}
        return {"current_price": prices.get(s, 100.0)}

    def fake_get_stock_prices(symbols, *args, **kwargs):
        # Batch sürüm (portfolio_service): YALNIZ açıkça set edilmiş sembolleri
        # döndürür → set edilmemiş sembol "quote yok" sayılır, böylece
        # avg_cost fallback yolu (_price_from_quotes) test edilebilir.
        out = {}
        for sym in symbols or []:
            su = (sym or "").upper()
            if su in prices:
                out[su] = {"current_price": prices[su]}
        return out

    monkeypatch.setattr(
        "app.services.order_service.get_stock_data", fake_get_stock_data)
    monkeypatch.setattr(
        "app.services.market_data_service.get_stock_data", fake_get_stock_data)
    monkeypatch.setattr(
        "app.services.price_alert_service.get_stock_data", fake_get_stock_data)
    monkeypatch.setattr(
        "app.services.portfolio_service.get_stock_prices", fake_get_stock_prices)
    # get_user_portfolio her okumada split mutabakatı çağırır (yfinance .splits
    # = ağ). Testte no-op; mutabakatın kendi testi ayrı yazılır.
    monkeypatch.setattr(
        "app.services.order_service.reconcile_splits", lambda db, user_id: 0)
    fx_service._cache.clear()

    class _Market:
        def set_price(self, symbol: str, price: float) -> None:
            prices[symbol.upper()] = price

        def set_usdtry(self, rate: float) -> None:
            prices["USDTRY=X"] = rate
            fx_service._cache.clear()          # bir sonraki okuma yeni kuru alsın

    yield _Market()
    fx_service._cache.clear()


@pytest.fixture(autouse=True)
def _reset_news_caches():
    """Haber cache'leri süreç-geneli → testler arası sızmasın.

    Sorgu-başına HAM cache (3 Eylül, 5. tur) eklendikten sonra bir testin
    çektiği sorgu, sonraki testte `_fetch_google_raw`'ı HİÇ çağırmadan cache'ten
    dönüyordu (çekim sayısı sayan testler yanlış sonuç veriyordu)."""
    from app.services import nlp_sentiment_service as nls

    def _clear():
        nls._raw_cache.clear()
        nls._query_cache.clear()
        nls._multi_cache.clear()
        nls._multi_refreshing.clear()
        nls._news_cache["data"] = None
        nls._news_cache["timestamp"] = None

    _clear()
    yield
    _clear()
