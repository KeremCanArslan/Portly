"""Batch geçmiş veri (kapanış + OHLCV) — istek sayısı ve 429 dayanıklılığı.

Neden var: benchmark/sinyal yolları SEMBOL BAŞINA ayrı `yf.Ticker().history()`
çağırıyordu. 40 pozisyonluk portföyde tek sayfa açılışı 100+ Yahoo isteği →
Yahoo Render IP'sini 429'luyor ("Too Many Requests"), getiriler "+0,00%",
sinyal listesi boş kalıyordu. İki garanti:

 1. N sembol = TEK indirme çağrısı.
 2. İndirme başarısızsa (429) SESSİZCE BOŞ dönmez — elde son bilinen seri
    varsa onu servis eder (biraz eski ama doğru veri > sahte sıfır).
"""

import pytest

from app.core import cache
from app.services import market_data_service as mds


@pytest.fixture(autouse=True)
def _clean_cache():
    cache._mem.clear()
    yield
    cache._mem.clear()


@pytest.fixture(autouse=True)
def _spark_kapali(monkeypatch):
    """Kapanış serisinin BİRİNCİL kaynağı artık `/v8/finance/spark`
    (yahoo_chart_service.get_daily_closes_batch). Bu dosya YEDEK yolu
    (`_download_closes`) ölçüyor → spark kapatılır, yoksa testler ağa çıkar.
    spark'ın kendi kapsamı: tests/test_spark_closes.py."""
    monkeypatch.setattr(
        "app.services.yahoo_chart_service.get_daily_closes_batch",
        lambda symbols, rng="400d": {})


def _bars(*closes):
    """Bugünden geriye günlük kapanışlar — get_daily_closes takvim gününe göre
    dilimlediği için sabit 2026-01 tarihleri pencerenin dışına düşerdi."""
    from datetime import datetime, timedelta
    today = datetime.now().date()
    n = len(closes)
    return {(today - timedelta(days=n - 1 - i)).isoformat(): float(c)
            for i, c in enumerate(closes)}


# ── Kapanış serisi ────────────────────────────────────────────────────────

def test_closes_fetch_is_a_single_batch_call(monkeypatch):
    calls = []

    def fake(symbols):
        calls.append(list(symbols))
        return {s: _bars(100, 110) for s in symbols}

    monkeypatch.setattr(mds, "_download_closes", fake)
    out = mds.get_daily_closes(["AAPL", "MSFT", "THYAO.IS", "GC=F"], 90)

    assert len(calls) == 1, "sembol başına ayrı istek atılıyor"
    assert sorted(calls[0]) == ["AAPL", "GC=F", "MSFT", "THYAO.IS"]
    assert len(out) == 4


def test_closes_serve_stale_when_download_fails(monkeypatch):
    """429 senaryosu: önce dolu cache, sonra indirme boş dönüyor."""
    monkeypatch.setattr(mds, "_download_closes",
                        lambda symbols: {"AAPL": _bars(100, 120)})
    first = mds.get_daily_closes(["AAPL"], 90)
    assert first["AAPL"]

    # Cache'i bayatlat + indirmeyi 429 gibi boş döndür
    key = mds._closes_key("AAPL")
    data, _ = cache.get(key)
    cache._mem[key] = (data, 0.0)          # çok eski timestamp
    monkeypatch.setattr(mds, "_download_closes", lambda symbols: {})

    out = mds.get_daily_closes(["AAPL"], 90)
    assert out["AAPL"] == first["AAPL"], "429'da eski seri servis edilmeli"


def test_closes_omit_symbol_with_no_data_at_all(monkeypatch):
    """Hiç veri yoksa uydurma yok — sembol dönüşte yer almaz, çağıran
    dürüstçe 'hesaplanamadı' der."""
    monkeypatch.setattr(mds, "_download_closes", lambda symbols: {})
    assert mds.get_daily_closes(["NOPE"], 90) == {}


def test_closes_use_fresh_cache_without_network(monkeypatch):
    monkeypatch.setattr(mds, "_download_closes",
                        lambda symbols: {"AAPL": _bars(100, 110)})
    mds.get_daily_closes(["AAPL"], 90)

    def _boom(symbols):
        raise AssertionError("taze cache varken ağa çıkıldı")

    monkeypatch.setattr(mds, "_download_closes", _boom)
    assert sorted(mds.get_daily_closes(["AAPL"], 90)["AAPL"].values()) == [100.0, 110.0]


# ── OHLCV (teknik analiz / sinyaller) ─────────────────────────────────────

def _ohlcv(n=3):
    return {
        "date": [f"2026-01-{i + 1:02d}" for i in range(n)],
        "open": [10.0] * n, "high": [11.0] * n,
        "low": [9.0] * n, "close": [10.5] * n, "volume": [1000.0] * n,
    }


def test_ohlcv_fetch_is_a_single_batch_call(monkeypatch):
    calls = []

    def fake(symbols, period):
        calls.append(list(symbols))
        return {s: _ohlcv() for s in symbols}

    monkeypatch.setattr(mds, "_download_ohlcv", fake)
    out = mds.get_daily_ohlcv(["AAPL", "MSFT", "ASELS.IS"], "6mo")

    assert len(calls) == 1
    assert len(out) == 3


def test_ohlcv_serves_stale_when_download_fails(monkeypatch):
    monkeypatch.setattr(mds, "_download_ohlcv",
                        lambda symbols, period: {"AAPL": _ohlcv()})
    mds.get_daily_ohlcv(["AAPL"], "6mo")

    key = mds._ohlcv_key("AAPL", "6mo")
    data, _ = cache.get(key)
    cache._mem[key] = (data, 0.0)
    monkeypatch.setattr(mds, "_download_ohlcv", lambda symbols, period: {})

    out = mds.get_daily_ohlcv(["AAPL"], "6mo")
    assert out["AAPL"]["close"] == [10.5, 10.5, 10.5]


def test_indicators_read_from_shared_cache(monkeypatch):
    """Sinyal taraması sembolleri tek batch ile ısıtır; _compute_indicators
    ağa ÇIKMAMALI (yoksa 40 sembol = 40 istek → 429)."""
    from app.services import technical_analysis_service as tas

    n = 60
    bars = {
        "date": [f"2026-{(i // 28) + 1:02d}-{(i % 28) + 1:02d}" for i in range(n)],
        "open": [100.0 + i for i in range(n)],
        "high": [101.0 + i for i in range(n)],
        "low": [99.0 + i for i in range(n)],
        "close": [100.0 + i for i in range(n)],
        "volume": [1000.0] * n,
    }
    monkeypatch.setattr(mds, "_download_ohlcv",
                        lambda symbols, period: {"AAPL": bars})
    mds.get_daily_ohlcv(["AAPL"], "6mo")     # ön-ısıtma

    def _boom(symbols, period):
        raise AssertionError("ön-ısıtmadan sonra tekrar ağa çıkıldı")

    monkeypatch.setattr(mds, "_download_ohlcv", _boom)
    ind = tas._compute_indicators("AAPL")
    assert ind["current_price"] == pytest.approx(159.0)


def test_indicators_raise_when_no_data(monkeypatch):
    monkeypatch.setattr(mds, "_download_ohlcv", lambda symbols, period: {})
    from app.services import technical_analysis_service as tas
    with pytest.raises(ValueError):
        tas._compute_indicators("NOPE")


def test_all_benchmark_periods_share_one_download(monkeypatch):
    """1A/3A/6A/1Y sekmeleri arasında gezinmek YENİ indirme tetiklememeli:
    tek uzun pencere çekilir, kısa dönemler ondan dilimlenir. Eskiden her
    dönem ayrı anahtardı → tek kullanıcı 4 batch attırıyordu."""
    from datetime import datetime, timedelta

    today = datetime.now().date()
    long_series = {(today - timedelta(days=i)).isoformat(): 100.0 + i
                   for i in range(300)}
    calls = []

    def fake(symbols):
        calls.append(list(symbols))
        return {s: long_series for s in symbols}

    monkeypatch.setattr(mds, "_download_closes", fake)

    got = {d: mds.get_daily_closes(["AAPL"], d) for d in (30, 90, 180, 365)}

    assert len(calls) == 1, f"dönem başına ayrı indirme yapıldı: {len(calls)}"
    # Her dönem gerçekten kendi penceresini almalı (hepsi aynı uzunlukta değil)
    sizes = {d: len(v["AAPL"]) for d, v in got.items()}
    assert sizes[30] < sizes[90] < sizes[180] < sizes[365], sizes


def test_slice_keeps_only_requested_window():
    from datetime import datetime, timedelta

    today = datetime.now().date()
    series = {(today - timedelta(days=i)).isoformat(): float(i)
              for i in range(200)}
    out = mds._slice_closes(series, 30)
    assert len(out) <= 36          # 30 gün + 5 tampon
    assert max(out.keys()) == today.isoformat()


# ── Bayat seri kullanıcıyı BEKLETMEZ (4 Eyl 2026, 9. tur) ─────────────────
# Ölçüm: canlıda soğuk /signals 10,0 sn, hemen ardından tam tarama 0,41 sn.
# Sebep: bu iki cache "stale-if-error"du — 15 dakikayı geçen kayıt istek
# yolunda BLOKLAYAN batch çekim tetikliyordu, eski kayıt yalnız çekim
# patlarsa servis ediliyordu. Arka plan yenileyici 30 dk boştan sonra durduğu
# için faturayı her sessizlik sonrası ilk kullanıcı ödüyordu.

def _stale(key):
    """Cache kaydını bayatlat (kayıt DURUR, yalnız tazelik damgası eskir)."""
    data, _ = cache.get(key)
    cache._mem[key] = (data, 0.0)


def test_stale_closes_are_served_without_blocking(monkeypatch):
    monkeypatch.setattr(mds, "_download_closes",
                        lambda symbols: {"AAPL": _bars(100, 110)})
    mds.get_daily_closes(["AAPL"], 90)
    _stale(mds._closes_key("AAPL"))

    scheduled = []
    monkeypatch.setattr(mds, "_schedule_series_refresh",
                        lambda kind, symbols, period="": scheduled.append((kind, list(symbols))))

    def _boom(symbols):
        raise AssertionError("bayat kayıt varken istek yolunda ağa çıkıldı")

    monkeypatch.setattr(mds, "_download_closes", _boom)
    out = mds.get_daily_closes(["AAPL"], 90)

    assert out["AAPL"], "bayat ama GERÇEK seri anında servis edilmeli"
    assert scheduled == [("c", ["AAPL"])], "tazeleme arka plana verilmeli"


def test_stale_ohlcv_is_served_without_blocking(monkeypatch):
    monkeypatch.setattr(mds, "_download_ohlcv",
                        lambda symbols, period: {"AAPL": _ohlcv()})
    mds.get_daily_ohlcv(["AAPL"], "6mo")
    _stale(mds._ohlcv_key("AAPL", "6mo"))

    scheduled = []
    monkeypatch.setattr(mds, "_schedule_series_refresh",
                        lambda kind, symbols, period="": scheduled.append((kind, list(symbols), period)))

    def _boom(symbols, period):
        raise AssertionError("bayat kayıt varken istek yolunda ağa çıkıldı")

    monkeypatch.setattr(mds, "_download_ohlcv", _boom)
    out = mds.get_daily_ohlcv(["AAPL"], "6mo")

    assert out["AAPL"]["close"] == [10.5, 10.5, 10.5]
    assert scheduled == [("o", ["AAPL"], "6mo")]


def test_symbol_with_no_record_still_blocks(monkeypatch):
    """Hiç kayıt yoksa bloklayan çekim HAK EDİLİR (ilk kurulum) — yoksa
    kullanıcı boş ekran görürdü."""
    calls = []
    monkeypatch.setattr(mds, "_download_ohlcv",
                        lambda symbols, period: calls.append(list(symbols)) or {s: _ohlcv() for s in symbols})
    out = mds.get_daily_ohlcv(["MSFT"], "6mo")
    assert calls == [["MSFT"]]
    assert out["MSFT"]


def test_background_refresh_is_batched_and_rate_limited(monkeypatch, real_series_refresh):
    """Bayat semboller TEK batch turuna girer ve tur biter bitmez ikincisi
    açılmaz (soğuma penceresi) — kaynak sürekli düşerken her istek yeni
    thread açsaydı 429'un üstüne bir de thread yığını gelirdi."""
    batches = []
    monkeypatch.setattr(mds, "_download_closes",
                        lambda symbols: batches.append(list(symbols)) or {})
    # Thread'i senkron çalıştır: tur bu çağrıda başlayıp biter.
    monkeypatch.setattr(mds.threading, "Thread",
                        lambda target, daemon=None: type(
                            "T", (), {"start": lambda self: target()})())
    mds._series_refresh_in_progress.clear()
    mds._series_refresh_last.clear()

    real_series_refresh("c", ["AAPL", "MSFT"])
    assert batches == [["AAPL", "MSFT"]], "sembol başına ayrı tur açılmamalı"

    real_series_refresh("c", ["AAPL"])
    assert batches == [["AAPL", "MSFT"]], "soğuma penceresinde ikinci tur yok"

    mds._series_refresh_last.clear()  # pencere doldu
    real_series_refresh("c", ["AAPL"])
    assert len(batches) == 2, "pencere dolunca yeniden denenmeli"
