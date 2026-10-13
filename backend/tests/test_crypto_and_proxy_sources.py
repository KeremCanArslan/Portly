"""Kripto + Yahoo-chart yedek kaynakları ve toplu fiyat ucu.

Bağlam: Yahoo Render'ın paylaşılan IP'sini 429'luyor. USDTRY / ABD hissesi /
altın için yedek zinciri vardı; **kripto ve BIST için yoktu** → BTC-USD ve
THYAO.IS "veri alınamadı" dönüyordu, Sinyaller 6 aylık mum bulamadığı için
51/51 sembolde başarısızdı (canlıda ölçüldü).

Bu testler ağa ÇIKMAZ: HTTP katmanı sahte yanıtlarla değiştirilir.
"""

import pytest

from app.core import cache
from app.services import crypto_source_service as css
from app.services import market_data_service as mds
from app.services import yahoo_chart_service as ycs


# conftest'teki autouse fixture yedek kaynakları "veri yok"a sabitliyor (diğer
# testler ağa çıkmasın). Bu dosya TAM DA o kaynakları sınıyor → gerçek
# fonksiyonları import anında yakala ve her testte geri koy.
_REAL = {
    "css_quotes": css.get_quotes,
    "css_ohlcv": css.get_daily_ohlcv,
    "css_closes": css.get_daily_closes,
    "ycs_quotes": ycs.get_quotes,
    "ycs_ohlcv": ycs.get_daily_ohlcv,
    "ycs_closes": ycs.get_daily_closes,
}


@pytest.fixture(autouse=True)
def _real_sources(monkeypatch):
    monkeypatch.setattr(css, "get_quotes", _REAL["css_quotes"])
    monkeypatch.setattr(css, "get_daily_ohlcv", _REAL["css_ohlcv"])
    monkeypatch.setattr(css, "get_daily_closes", _REAL["css_closes"])
    monkeypatch.setattr(ycs, "get_quotes", _REAL["ycs_quotes"])
    monkeypatch.setattr(ycs, "get_daily_ohlcv", _REAL["ycs_ohlcv"])
    monkeypatch.setattr(ycs, "get_daily_closes", _REAL["ycs_closes"])
    yield


@pytest.fixture(autouse=True)
def _clean(monkeypatch):
    cache._mem.clear()
    from app.services import gold_rates_service
    monkeypatch.setattr(gold_rates_service, "spot_metal_usd", lambda symbols: {})
    from app.services import finnhub_service
    monkeypatch.setattr(finnhub_service, "available", False)
    yield
    cache._mem.clear()


# ── Kripto kaynağı ───────────────────────────────────────────────────────────
def _coinbase_rows(days: int = 5, last: float = 100.0):
    """Coinbase formatı: [time, low, high, open, close, volume], YENİDEN ESKİYE."""
    rows = []
    for i in range(days):
        close = last - i          # en yeni en yüksek
        ts = 1_700_000_000 - i * 86400
        rows.append([ts, close - 2, close + 2, close - 1, close, 10.0])
    return rows


def _use_coinbase(monkeypatch, rows):
    monkeypatch.setattr(css, "_coinbase_candles", lambda sym, client: rows)
    monkeypatch.setattr(css, "_binance_klines",
                        lambda sym, client, limit=200: None)


def test_crypto_quote_from_coinbase(monkeypatch):
    _use_coinbase(monkeypatch, _coinbase_rows(last=100.0))
    out = css.get_quotes(["BTC-USD"])
    assert out["BTC-USD"]["current_price"] == 100.0
    # Günlük değişim = dünkü kapanışa (99) göre → ~%1,01
    assert out["BTC-USD"]["change_percent"] == pytest.approx(1.01, abs=0.01)


def test_crypto_only_touches_crypto_symbols(monkeypatch):
    called = []

    def _spy(sym, client):
        called.append(sym)
        return _coinbase_rows()

    monkeypatch.setattr(css, "_coinbase_candles", _spy)
    monkeypatch.setattr(css, "_binance_klines",
                        lambda sym, client, limit=200: None)
    css.get_quotes(["BTC-USD", "THYAO.IS", "AAPL", "GC=F"])
    assert called == ["BTC-USD"]


def test_crypto_falls_back_to_binance(monkeypatch):
    """Coinbase vermezse USDT paritesine düşer (yaklaşık ama boş ekrandan iyi)."""
    monkeypatch.setattr(css, "_coinbase_candles", lambda sym, client: None)
    # Binance: [openTime(ms), open, high, low, close, volume, ...] ESKİDEN YENİYE
    rows = [[1_699_913_600_000, "9", "11", "8", "10", "5"],
            [1_700_000_000_000, "10", "12", "9", "11", "6"]]
    monkeypatch.setattr(css, "_binance_klines",
                        lambda sym, client, limit=200: rows)
    out = css.get_quotes(["ETH-USD"])
    assert out["ETH-USD"]["current_price"] == 11.0
    assert css.last_source() == "binance"


def test_crypto_ohlcv_shape_matches_contract(monkeypatch):
    _use_coinbase(monkeypatch, _coinbase_rows(days=10))
    bars = css.get_daily_ohlcv(["BTC-USD"], days=6)
    got = bars["BTC-USD"]
    assert set(got) == {"date", "open", "high", "low", "close", "volume"}
    assert len(got["close"]) == 6
    # Tarihler artan sırada (eskiden yeniye) — teknik göstergeler buna dayanır.
    assert got["date"] == sorted(got["date"])


# ── market_data_service entegrasyonu ─────────────────────────────────────────
def test_price_path_recovers_crypto_when_yahoo_is_rate_limited(monkeypatch):
    monkeypatch.setattr(mds, "_fetch_many", lambda symbols: {})
    monkeypatch.setattr(css, "get_quotes", lambda symbols: {
        s: {"symbol": s, "company_name": s,
            "current_price": 42.0, "change_percent": -1.0}
        for s in symbols if s.endswith("-USD")})
    monkeypatch.setattr(ycs, "get_quotes", lambda symbols: {})

    out = mds.get_stock_prices(["BTC-USD"])
    assert out["BTC-USD"]["current_price"] == 42.0


def test_ohlcv_path_recovers_crypto_for_signals(monkeypatch):
    """Sinyal motorunun 6 aylık mum yolu: Yahoo boş → kripto yedeği doldurur."""
    monkeypatch.setattr(mds, "_download_ohlcv", lambda symbols, period: {})
    monkeypatch.setattr(ycs, "get_daily_ohlcv", lambda symbols, period="6mo": {})
    monkeypatch.setattr(css, "get_daily_ohlcv", lambda symbols, days=200: {
        "ETH-USD": {"date": ["2026-01-01"], "open": [1.0], "high": [2.0],
                    "low": [0.5], "close": [1.5], "volume": [3.0]}})

    out = mds.get_daily_ohlcv(["ETH-USD"], period="6mo")
    assert out["ETH-USD"]["close"] == [1.5]


def test_bist_recovers_via_yahoo_chart_path(monkeypatch):
    """BIST'in ücretsiz alternatifi yok → son halka Yahoo'nun açık chart ucu
    (kurulmuşsa Cloudflare Worker vekili üzerinden)."""
    monkeypatch.setattr(mds, "_fetch_many", lambda symbols: {})
    monkeypatch.setattr(css, "get_quotes", lambda symbols: {})
    monkeypatch.setattr(ycs, "get_quotes", lambda symbols: {
        "THYAO.IS": {"symbol": "THYAO.IS", "company_name": "THYAO.IS",
                     "current_price": 310.5, "change_percent": 0.8}})

    out = mds.get_stock_prices(["THYAO.IS"])
    assert out["THYAO.IS"]["current_price"] == 310.5


# ── Yahoo chart istemcisi ────────────────────────────────────────────────────
def test_chart_client_drops_null_bars():
    """KALICI KURAL: NaN/None mum çizilmez, satır ATILIR."""
    payload = {
        "timestamp": [1_700_000_000, 1_700_086_400],
        "indicators": {"quote": [{
            "open": [10.0, None], "high": [11.0, None],
            "low": [9.0, None], "close": [10.5, None],
            "volume": [100, None]}]},
    }
    bars = ycs._bars(payload)
    assert len(bars) == 1
    assert bars[0]["close"] == 10.5


def test_chart_quote_marks_single_bar_change_as_unknown(monkeypatch):
    """Tek bar = dünkü kapanış YOK → değişim 0 DEĞİL, BİLİNMİYOR.

    Aynı tuzağa BIST'te bir kez düşülmüştü (`period=2d` gece tek bar döndürüp
    "Bugün %0" gösteriyordu). Sıfır basmak "hiç oynamadı" demektir."""
    monkeypatch.setattr(ycs, "_collect", lambda symbols, rng, interval="1d": {
        "TEK": [{"date": "2026-09-02", "open": 1.0, "high": 1.0,
                 "low": 1.0, "close": 10.5, "volume": 1}],
        "IKI": [{"date": "2026-09-01", "open": 1.0, "high": 1.0,
                 "low": 1.0, "close": 10.0, "volume": 1},
                {"date": "2026-09-02", "open": 1.0, "high": 1.0,
                 "low": 1.0, "close": 10.5, "volume": 1}],
    })

    out = ycs.get_quotes(["TEK", "IKI"])

    assert out["TEK"]["change_available"] is False
    assert out["IKI"]["change_available"] is True
    assert out["IKI"]["change_percent"] == 5.0


def test_chart_client_circuit_breaker(monkeypatch):
    """429 görülünce modül kendini kapatır — cezayı uzatmamak için."""
    monkeypatch.setattr(ycs, "_blocked_until", 0.0)
    assert ycs.available()
    ycs._mark_rate_limited()
    try:
        assert not ycs.available()
        assert ycs._collect(["AAPL"], rng="5d") == {}
    finally:
        ycs._blocked_until = 0.0


def test_proxy_base_used_when_configured(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "YAHOO_PROXY_BASE",
                        "https://portly-yahoo.example.workers.dev")
    assert ycs.via_proxy()
    assert ycs.base_url().endswith("workers.dev")
    monkeypatch.setattr(settings, "YAHOO_PROXY_BASE", "")
    assert not ycs.via_proxy()
    assert "query1.finance.yahoo.com" in ycs.base_url()


# ── Toplu fiyat ucu (istemci açılış yolu) ────────────────────────────────────
def test_batch_prices_endpoint_keeps_order_and_reports_missing(monkeypatch):
    monkeypatch.setattr(mds, "_fetch_many", lambda symbols: {
        "AAPL": {"symbol": "AAPL", "company_name": "AAPL",
                 "current_price": 200.0, "change_percent": 1.0}})
    monkeypatch.setattr(css, "get_quotes", lambda symbols: {})
    monkeypatch.setattr(ycs, "get_quotes", lambda symbols: {})
    monkeypatch.setattr(mds, "_schedule_name_resolution", lambda symbols: None)

    res = mds.get_stock_prices_named(["AAPL", "THYAO.IS"])
    assert [q["symbol"] for q in res["quotes"]] == ["AAPL"]
    # Veri gelmeyen sembol DÜRÜSTÇE bildirilir (0 fiyat uydurulmaz).
    assert res["missing"] == ["THYAO.IS"]


def test_batch_prices_uses_known_name_without_network(monkeypatch):
    """Ad çözümü batch yolda AĞA ÇIKMAZ: BIST kataloğu yerelde karşılar."""
    monkeypatch.setattr(mds, "_fetch_many", lambda symbols: {
        "THYAO.IS": {"symbol": "THYAO.IS", "company_name": "THYAO.IS",
                     "current_price": 310.0, "change_percent": 0.5}})
    monkeypatch.setattr(css, "get_quotes", lambda symbols: {})
    monkeypatch.setattr(ycs, "get_quotes", lambda symbols: {})
    monkeypatch.setattr(mds, "_schedule_name_resolution", lambda symbols: None)

    res = mds.get_stock_prices_named(["THYAO.IS"])
    assert res["quotes"][0]["company_name"] == "Türk Hava Yolları"


# ── Negatif cache: alınamayan sembol her istekte yeniden denenmesin ──────────
def test_unavailable_symbol_is_not_refetched_on_every_request(monkeypatch):
    """Canlı ölçüm: 429 sürerken /portfolio 4,2 sn, /performance 10,6 sn
    sürüyordu — çünkü hiçbir kaynaktan gelmeyen sembol HER istekte baştan
    deneniyordu. Artık kısa süre hatırlanır."""
    calls = []

    def _fetch(symbols):
        calls.append(tuple(symbols))
        return {}

    monkeypatch.setattr(mds, "_fetch_many", _fetch)
    monkeypatch.setattr(css, "get_quotes", lambda symbols: {})
    monkeypatch.setattr(ycs, "get_quotes", lambda symbols: {})

    assert mds.get_stock_prices(["ZZZZ.IS"]) == {}
    assert mds.get_stock_prices(["ZZZZ.IS"]) == {}
    assert len(calls) == 1  # ikinci istek ağa çıkmadı


def test_background_refresh_ignores_negative_cache(monkeypatch):
    """Arka plan işçisi denemeye DEVAM etmeli — kaynak açılınca veri geri gelsin."""
    mds._mark_failed("c", ["ZZZZ.IS"])
    calls = []

    def _download(symbols):
        calls.append(tuple(symbols))
        return {"ZZZZ.IS": {"2026-01-02": 10.0}}

    monkeypatch.setattr(mds, "_download_closes", _download)
    out = mds.refresh_daily_closes(["ZZZZ.IS"])
    assert calls and out["ZZZZ.IS"]["2026-01-02"] == 10.0


# ── Grafik ucu da yedeğe düşer ───────────────────────────────────────────────
def test_chart_endpoint_falls_back_to_daily_bars(monkeypatch):
    """Canlıda 429 sürerken /market/history HER sembolde 400 dönüyordu.
    Günlük aralıkta yedek zinciri devreye girer."""
    import yfinance as yf

    class _Boom:
        def __init__(self, *a, **k):
            pass

        def history(self, *a, **k):
            raise RuntimeError("Too Many Requests. Rate limited.")

    monkeypatch.setattr(yf, "Ticker", _Boom)
    monkeypatch.setattr(ycs, "get_history_rows",
                        lambda symbol, rng, interval: [])
    monkeypatch.setattr(css, "get_daily_ohlcv", lambda symbols, days=200: {
        "BTC-USD": {"date": ["2026-08-31", "2026-09-01"],
                    "open": [1.0, 2.0], "high": [3.0, 4.0],
                    "low": [0.5, 1.5], "close": [2.5, 3.5],
                    "volume": [10.0, 20.0]}})

    out = mds.get_stock_history("BTC-USD", period="6mo", interval="1d")
    assert out["data_points"] == 2
    assert out["data"][-1]["close"] == 3.5


def test_chart_endpoint_intraday_never_uses_daily_bars(monkeypatch):
    """Kripto borsa yedeği YALNIZ günlük mum verir → 5m/1h grafiğine günlük
    mum basılmaz (uydurma veri yok); chart ucu da vermezse hata döner."""
    import pytest as _pytest
    import yfinance as yf
    from fastapi import HTTPException

    class _Boom:
        def __init__(self, *a, **k):
            pass

        def history(self, *a, **k):
            raise RuntimeError("Too Many Requests. Rate limited.")

    monkeypatch.setattr(yf, "Ticker", _Boom)
    monkeypatch.setattr(ycs, "get_history_rows",
                        lambda symbol, rng, interval: [])
    called = []
    monkeypatch.setattr(css, "get_daily_ohlcv",
                        lambda symbols, days=200: called.append(symbols) or {})
    with _pytest.raises(HTTPException):
        mds.get_stock_history("BTC-USD", period="1d", interval="5m")
    assert called == []  # günlük yedeğe HİÇ gidilmedi


def test_chart_endpoint_intraday_uses_proxy_rows(monkeypatch):
    """Grafiklerin çoğu intraday (1mo→1h): vekil yolu bunları da karşılar."""
    import yfinance as yf

    class _Boom:
        def __init__(self, *a, **k):
            pass

        def history(self, *a, **k):
            raise RuntimeError("Too Many Requests. Rate limited.")

    monkeypatch.setattr(yf, "Ticker", _Boom)
    monkeypatch.setattr(ycs, "get_history_rows", lambda symbol, rng, interval: [
        {"date": "2026-09-01 10:00", "timestamp": 1788336000, "open": 1.0,
         "high": 2.0, "low": 0.5, "close": 1.5, "volume": 3}])

    out = mds.get_stock_history("THYAO.IS", period="1mo", interval="1h")
    assert out["data_points"] == 1
    assert out["interval"] == "1h"


def test_hourly_aggregation_builds_4h_candles():
    """2h/4h Yahoo'da native yok → 1h barlardan toplanır (open=ilk, close=son,
    high=maks, low=min, hacim=toplam)."""
    base = 1_788_336_000 - (1_788_336_000 % 14400)
    bars = [{"ts": base + i * 3600, "open": 10.0 + i, "high": 20.0 + i,
             "low": 5.0 - i, "close": 15.0 + i, "volume": 100.0}
            for i in range(4)]
    out = ycs._aggregate_hours(bars, 4)
    assert len(out) == 1
    assert out[0]["open"] == 10.0 and out[0]["close"] == 18.0
    assert out[0]["high"] == 23.0 and out[0]["low"] == 2.0
    assert out[0]["volume"] == 400.0


# ── "Sembol yok" ile "kaynak düştü" ayrımı ───────────────────────────────────
def test_unknown_symbol_returns_404_not_rate_limit_message(monkeypatch):
    """yfinance HER hatada 'Too Many Requests' diyor → olmayan sembolde de
    kullanıcı 'çok fazla istek' görüyordu (canlıda doğrulandı: uydurma
    ZZZZTEST.IS ile portföydeki LTL.IS aynı mesajı veriyordu)."""
    import pytest as _pytest
    from fastapi import HTTPException

    monkeypatch.setattr(mds, "_fetch_stock_data", lambda s: (_ for _ in ()).throw(
        RuntimeError("Too Many Requests. Rate limited.")))
    monkeypatch.setattr(mds, "_fallback_quotes", lambda symbols: {})
    monkeypatch.setattr(ycs, "probe", lambda symbol: "unknown")

    with _pytest.raises(HTTPException) as err:
        mds.get_stock_data("ZZZZTEST.IS")
    assert err.value.status_code == 404
    assert "bulunamadı" in err.value.detail


def test_source_down_returns_503_with_retry_wording(monkeypatch):
    import pytest as _pytest
    from fastapi import HTTPException

    monkeypatch.setattr(mds, "_fetch_stock_data", lambda s: (_ for _ in ()).throw(
        RuntimeError("Too Many Requests. Rate limited.")))
    monkeypatch.setattr(mds, "_fallback_quotes", lambda symbols: {})
    monkeypatch.setattr(ycs, "probe", lambda symbol: "unavailable")

    with _pytest.raises(HTTPException) as err:
        mds.get_stock_data("THYAO.IS")
    assert err.value.status_code == 503
    assert "ulaşılamıyor" in err.value.detail


def test_probe_reads_chart_error_as_unknown(monkeypatch):
    """Yahoo chart ucu olmayan sembolde error alanı döndürür."""
    class _Resp:
        status_code = 200

        @staticmethod
        def json():
            return {"chart": {"result": None,
                              "error": {"code": "Not Found",
                                        "description": "No data found"}}}

    class _Client:
        def __init__(self, *a, **k):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def get(self, *a, **k):
            return _Resp()

    import httpx
    monkeypatch.setattr(httpx, "Client", _Client)
    monkeypatch.setattr(ycs, "_blocked_until", 0.0)
    assert ycs.probe("ZZZZTEST.IS") == "unknown"
