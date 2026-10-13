"""BIST yedek veri kaynağı (İş Yatırım günlük serisi).

Bağlam: BIST'in TEK dayanağı Yahoo'ydu — Cloudflare Worker vekili de tek nokta.
Yahoo o yolu da kısarsa BIST fiyatı/sinyali/grafiği komple düşüyordu; kripto,
fon ve ABD hissesinin yedeği vardı, BIST'in yoktu.

Testler ağa ÇIKMAZ: HTTP katmanı sahte yanıtla değiştirilir.

Sınırı sabitlenen asıl kural: bu kaynakta GÜN İÇİ fiyat yok. Seans açıkken
`get_quotes` boş dönmeli — dünkü kapanışı "şu anki fiyat" diye basmak dürüst
boş-durum kuralını ihlal eder.
"""

from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from app.core import cache
from app.services import bist_source_service as bss
from app.services import market_data_service as mds

_TR = ZoneInfo("Europe/Istanbul")
# 3 Eylül 2026 Perşembe — seans içi 13:00, seans dışı 19:00.
_ACIK = datetime(2026, 9, 3, 13, 0, tzinfo=_TR)
_KAPALI = datetime(2026, 9, 3, 19, 0, tzinfo=_TR)

_REAL = {
    "get_quotes": bss.get_quotes,
    "get_daily_ohlcv": bss.get_daily_ohlcv,
    "get_daily_closes": bss.get_daily_closes,
    "get_history_rows": bss.get_history_rows,
}


@pytest.fixture(autouse=True)
def _yahoo_dusuk(monkeypatch):
    """Bu dosyanın senaryosu "Yahoo TAMAMEN düştü" → yfinance ve chart ucunun
    HER yolu boş dönmeli (conftest chart'ın yalnız üç fonksiyonunu susturuyor,
    `get_history_rows` açık kalıyordu ve testler gerçekten ağa çıkıyordu)."""
    from app.services import yahoo_chart_service as ycs
    monkeypatch.setattr(ycs, "get_history_rows",
                        lambda symbol, period, interval: [])
    # Kapanış serisinin yeni birincil kaynağı spark; "Yahoo tamamen düştü"
    # senaryosunda o da boş dönmeli (yoksa test gerçekten ağa çıkıyor).
    monkeypatch.setattr(ycs, "get_daily_closes_batch",
                        lambda symbols, rng="400d": {})
    monkeypatch.setattr(mds, "_download_closes", lambda symbols: {})
    monkeypatch.setattr(mds, "_download_ohlcv", lambda symbols, period: {})
    yield


@pytest.fixture(autouse=True)
def _real_source(monkeypatch):
    # conftest yedek kaynakları "veri yok"a sabitliyor; bu dosya TAM DA onu sınıyor.
    for name, fn in _REAL.items():
        monkeypatch.setattr(bss, name, fn)
    cache._mem.clear()
    yield
    cache._mem.clear()


def _rows(days: int = 5, last: float = 100.0):
    """`_fetch_rows` çıktısı: ESKİDEN YENİYE, iso tarihli."""
    return [{"date": f"2026-08-{20 + i:02d}",
             "high": last - (days - 1 - i) + 2,
             "low": last - (days - 1 - i) - 2,
             "close": last - (days - 1 - i),
             "volume": 1_000_000.0 + i}
            for i in range(days)]


def _use(monkeypatch, rows):
    monkeypatch.setattr(bss, "_fetch_rows", lambda sym, days, client: rows)
    monkeypatch.setattr(bss, "_fresh", lambda rows, now=None: True)


# ── Seans kuralı (dürüst boş-durum) ──────────────────────────────────────────
def test_seans_acikken_fiyat_verilmez(monkeypatch):
    _use(monkeypatch, _rows())
    assert bss.get_quotes(["THYAO.IS"], now=_ACIK) == {}


def test_seans_kapaliyken_son_kapanis_fiyat_olur(monkeypatch):
    _use(monkeypatch, _rows(last=100.0))  # son iki kapanış 99 → 100
    q = bss.get_quotes(["THYAO.IS"], now=_KAPALI)["THYAO.IS"]
    assert q["current_price"] == 100.0
    assert q["change_percent"] == pytest.approx(1.01, abs=0.01)


def test_bayat_seri_fiyat_olarak_kullanilmaz(monkeypatch):
    eski = [{**r, "date": r["date"].replace("2026-08", "2026-06")}
            for r in _rows()]
    monkeypatch.setattr(bss, "_fetch_rows", lambda sym, days, client: eski)
    # `_fresh` gerçek hâliyle: Haziran serisi Eylül'de fiyat sayılamaz.
    assert bss.get_quotes(["THYAO.IS"], now=_KAPALI) == {}


def test_tek_barla_degisim_uydurulmaz(monkeypatch):
    _use(monkeypatch, _rows(days=1))
    assert bss.get_quotes(["THYAO.IS"], now=_KAPALI) == {}


def test_seans_penceresi():
    assert bss.session_open(datetime(2026, 9, 3, 10, 0, tzinfo=_TR)) is True
    assert bss.session_open(datetime(2026, 9, 3, 9, 59, tzinfo=_TR)) is False
    assert bss.session_open(datetime(2026, 9, 3, 18, 10, tzinfo=_TR)) is False
    assert bss.session_open(datetime(2026, 9, 4, 13, 0, tzinfo=_TR)) is True   # Cuma
    assert bss.session_open(datetime(2026, 9, 5, 13, 0, tzinfo=_TR)) is False  # Cmt


# ── Yalnız BIST sembolü ──────────────────────────────────────────────────────
def test_bist_disi_sembol_istenmez(monkeypatch):
    cagrilan = []
    monkeypatch.setattr(bss, "_fetch_rows",
                        lambda sym, days, client: cagrilan.append(sym) or _rows())
    bss.get_daily_closes(["AAPL", "BTC-USD", "GC=F", "TLY.FON"])
    assert cagrilan == []
    assert bss.is_bist("THYAO.IS") and not bss.is_bist("AAPL")


# ── Seri sözleşmeleri ────────────────────────────────────────────────────────
def test_ohlcv_sekli_ve_open_kabulu(monkeypatch):
    _use(monkeypatch, _rows(days=5))
    bars = bss.get_daily_ohlcv(["THYAO.IS"], days=3)["THYAO.IS"]
    assert len(bars["date"]) == 3
    assert bars["date"] == sorted(bars["date"])          # eskiden yeniye
    # Kaynak açılış fiyatı vermiyor → open=close (uydurma değil, kabul).
    assert bars["open"] == bars["close"]
    assert all(h >= c >= low for h, c, low
               in zip(bars["high"], bars["close"], bars["low"]))


def test_kapanis_serisi_iso_gunlu(monkeypatch):
    _use(monkeypatch, _rows(days=4))
    ser = bss.get_daily_closes(["THYAO.IS"])["THYAO.IS"]
    assert len(ser) == 4
    assert all(len(day) == 10 and day[4] == "-" for day in ser)


def test_history_satirlari(monkeypatch):
    _use(monkeypatch, _rows(days=3))
    rows = bss.get_history_rows("THYAO.IS", 3)
    assert len(rows) == 3
    assert {"date", "timestamp", "open", "high", "low", "close",
            "volume"} <= set(rows[0])


def test_bozuk_satir_seriyi_dusurmez(monkeypatch):
    payload = {"ok": True, "value": [
        {"HGDG_TARIH": "02-09-2026", "HGDG_KAPANIS": 291.5,
         "HGDG_MIN": 291.25, "HGDG_MAX": 301.0, "HGDG_HACIM": 1.0},
        {"HGDG_TARIH": "bozuk", "HGDG_KAPANIS": 1.0},
        {"HGDG_TARIH": "01-09-2026", "HGDG_KAPANIS": 0.0},   # fiyatsız → atlanır
        {"HGDG_TARIH": "31-08-2026", "HGDG_KAPANIS": 302.25,
         "HGDG_MIN": 302.0, "HGDG_MAX": 306.5, "HGDG_HACIM": 2.0},
    ]}

    class _Resp:
        status_code = 200

        def json(self):
            return payload

    class _Client:
        def get(self, *a, **k):
            return _Resp()

    rows = bss._fetch_rows("THYAO.IS", 10, _Client())
    assert [r["date"] for r in rows] == ["2026-08-31", "2026-09-02"]


def test_ok_false_bos_doner():
    class _Resp:
        status_code = 200

        def json(self):
            return {"ok": False, "errorCode": "SYS0000"}

    class _Client:
        def get(self, *a, **k):
            return _Resp()

    assert bss._fetch_rows("THYAO.IS", 10, _Client()) == []


# ── market_data_service'e bağlanma ───────────────────────────────────────────
def test_yahoo_dusunce_kapanis_serisi_bistten_gelir(monkeypatch):
    _use(monkeypatch, _rows(days=6))
    out = mds.refresh_daily_closes(["THYAO.IS"])
    assert "THYAO.IS" in out and len(out["THYAO.IS"]) == 6


def test_yahoo_dusunce_ohlcv_bistten_gelir(monkeypatch):
    _use(monkeypatch, _rows(days=6))
    out = mds.refresh_daily_ohlcv(["THYAO.IS"], period="1mo")
    assert len(out["THYAO.IS"]["close"]) == 6


def test_yahoo_dusunce_grafik_bistten_gelir(monkeypatch):
    _use(monkeypatch, _rows(days=6))
    rows = mds._history_from_fallbacks("THYAO.IS", "1mo", "1d")
    assert len(rows) == 6


def test_intraday_grafikte_uydurma_mum_basilmaz(monkeypatch):
    _use(monkeypatch, _rows(days=6))
    assert mds._history_from_fallbacks("THYAO.IS", "1mo", "1h") == []


def test_yahoo_dusunce_kapali_seansta_fiyat_bistten_gelir(monkeypatch):
    _use(monkeypatch, _rows(days=6, last=100.0))
    monkeypatch.setattr(bss, "session_open", lambda now=None: False)
    out = mds._fallback_quotes(["THYAO.IS"])
    assert out["THYAO.IS"]["current_price"] == 100.0


def test_yahoo_dusunce_acik_seansta_fiyat_uydurulmaz(monkeypatch):
    _use(monkeypatch, _rows(days=6))
    monkeypatch.setattr(bss, "session_open", lambda now=None: True)
    assert mds._fallback_quotes(["THYAO.IS"]) == {}
