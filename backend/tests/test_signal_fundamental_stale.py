"""Temel oran cache'i: kayıt ≠ tazelik penceresi (stale-while-revalidate).

Bağlam — CANLI ÖLÇÜM (4 Eyl): soğuk `/signals` **20,7 sn** sürüyordu. Aynı anda
tek kripto sembolü 0,3 sn, tek ABD hissesi 2,8-5,3 sn ölçüldü → fark tamamen
temel oran çekimi. 44 hisse x ~3 sn / 6 işçi ~= 21 sn. Hepsinin BİRDEN soğuk
olmasının sebebi: bir tarama 44 sembolü aynı 20 saniyede yazıyor, 12 saat sonra
hepsi aynı 20 saniyede düşüyordu; bedeli Sinyaller'e ilk giren kullanıcı
ödüyordu (günde iki kez).

Sözleşme: kayıt `_FUND_KEEP_HOURS` durur · 12 saat yalnız TAZELİK eşiğidir ·
bayat oran ANINDA servis edilir + arka planda tazelenir · eşik sembole göre
dağıtılır (toplu düşüş yok) · ısıtma bayatı da yeniler.

Testler ağa ÇIKMAZ; arka plan thread'i yalnız kendi testinde gerçekten koşar.
"""

import threading
import time

import pytest

from app.core import cache
from app.models.portfolio import Portfolio
from app.services import signal_service as ss

_ORAN = {"pe_trailing": 10.0, "roe_pct": 20.0}


# conftest ısıtmayı global olarak stub'lıyor (ağ) → gerçeğini import anında al.
_ISITMA = ss.prewarm_fundamentals


@pytest.fixture(autouse=True)
def _temiz(monkeypatch):
    monkeypatch.setattr(ss, "prewarm_fundamentals", _ISITMA)
    cache._mem.clear()
    ss._signal_cache.clear()
    ss._fund_refresh_in_progress.clear()
    yield
    cache._mem.clear()
    ss._signal_cache.clear()
    ss._fund_refresh_in_progress.clear()


def _sayan(monkeypatch, sonuc=None):
    """`_compute_fundamentals` çağrılarını sayar (ağ yerine)."""
    cagrilan: list[str] = []
    monkeypatch.setattr(
        ss.fundamental_analysis_service, "_compute_fundamentals",
        lambda sym: cagrilan.append(sym) or dict(sonuc or _ORAN))
    return cagrilan


def _bayatlat(symbol: str, yas_sn: float | None = None) -> None:
    """Cache'teki kaydın zaman damgasını geriye alır."""
    key = ss._FUND_KEY + symbol
    data, _ts = cache._mem[key]
    yas = yas_sn if yas_sn is not None else ss._fund_fresh_seconds(symbol) + 60
    cache._mem[key] = (data, time.time() - yas)


class TestBayatServis:
    def test_bayat_oran_aninda_servis_edilir(self, monkeypatch):
        cagrilan = _sayan(monkeypatch)
        assert ss._get_fundamentals_cached("AAPL")["pe_trailing"] == 10.0
        _bayatlat("AAPL")

        planlanan: list[str] = []
        monkeypatch.setattr(ss, "_schedule_fund_refresh", planlanan.append)
        # Bayat kayıt: istek yolu BEKLEMEZ, eldeki oranla döner.
        assert ss._get_fundamentals_cached("AAPL")["pe_trailing"] == 10.0
        assert cagrilan == ["AAPL"]          # senkron ikinci çekim YOK
        assert planlanan == ["AAPL"]         # tazeleme arka plana verildi

    def test_taze_oran_arka_plani_tetiklemez(self, monkeypatch):
        _sayan(monkeypatch)
        ss._get_fundamentals_cached("AAPL")
        planlanan: list[str] = []
        monkeypatch.setattr(ss, "_schedule_fund_refresh", planlanan.append)
        ss._get_fundamentals_cached("AAPL")
        assert planlanan == []

    def test_kayit_yoksa_bloklayan_cekim(self, monkeypatch):
        cagrilan = _sayan(monkeypatch)
        assert ss._get_fundamentals_cached("MSFT")["roe_pct"] == 20.0
        assert cagrilan == ["MSFT"]          # ilk kurulum: senkron hak edilir

    def test_oran_yok_kaydi_da_bayatlayinca_tazelenir(self, monkeypatch):
        """BIST'te oran gelmiyor → None cache'leniyor. Kayıt 7 gün durduğu için
        bu 'oran yok' sonucu bayatlayınca yeniden denenmezse sembol günlerce
        temelsiz kalırdı."""
        _sayan(monkeypatch, sonuc={"data_limited": True})
        assert ss._get_fundamentals_cached("THYAO.IS") is None
        _bayatlat("THYAO.IS")

        planlanan: list[str] = []
        monkeypatch.setattr(ss, "_schedule_fund_refresh", planlanan.append)
        assert ss._get_fundamentals_cached("THYAO.IS") is None
        assert planlanan == ["THYAO.IS"]

    def test_kayit_tazelik_penceresi_kadar_degil_daha_uzun_yasar(self, monkeypatch):
        """Kaydın TTL'i 12 saat OLMAMALI: 12 saat tazelik eşiği, kayıt 7 gün
        durur. (Eski kod TTL=12s yazıyordu → kayıt silinince istek yolu
        bloklayan çekime düşüyordu.)"""
        _sayan(monkeypatch)
        yazilan: list[int] = []
        gercek_set = cache.set
        monkeypatch.setattr(
            cache, "set",
            lambda k, v, ttl: yazilan.append(ttl) or gercek_set(k, v, ttl))
        ss._get_fundamentals_cached("AAPL")
        assert yazilan == [ss._FUND_KEEP_HOURS * 3600]
        assert ss._FUND_KEEP_HOURS * 3600 > ss._FUND_FRESH_HOURS * 3600


class TestTazelikDagilimi:
    def test_esik_sembole_gore_dagilir(self):
        """Birlikte yazılan kayıtlar birlikte bayatlamamalı."""
        esikler = {s: ss._fund_fresh_seconds(s)
                   for s in ("AAPL", "MSFT", "NVDA", "THYAO.IS", "KO", "PEP")}
        assert len(set(esikler.values())) == len(esikler)   # hepsi farklı
        taban = ss._FUND_FRESH_HOURS * 3600
        for s, e in esikler.items():
            # Eşik tabanı AŞMAMALI: eski sürümün yazdığı kayıtlar Redis'te 12
            # saatlik TTL taşıyor, daha geç bayatlarsa tazelenmeden ölürler.
            assert taban * (1 - ss._FUND_JITTER) <= e <= taban

    def test_esik_deterministik(self):
        """Aynı sembol her süreçte aynı eşiği görmeli (rastgele DEĞİL)."""
        assert ss._fund_fresh_seconds("AAPL") == ss._fund_fresh_seconds("AAPL")


class TestArkaPlanTuru:
    def test_ayni_sembol_icin_tek_tur(self, monkeypatch):
        """51 sembollük tarama aynı bayat sembolü birden çok işçiden görebilir;
        her görüş yeni bir çekim başlatmamalı."""
        basladi = threading.Event()
        devam = threading.Event()
        cagrilan: list[str] = []

        def _yavas(symbol):
            cagrilan.append(symbol)
            basladi.set()
            devam.wait(timeout=5)
            return None

        monkeypatch.setattr(ss, "_fetch_and_store_fundamentals", _yavas)
        ss._schedule_fund_refresh("AAPL")
        assert basladi.wait(timeout=5)
        ss._schedule_fund_refresh("AAPL")      # tur sürerken ikinci istek
        ss._schedule_fund_refresh("AAPL")
        devam.set()
        for _ in range(100):                   # thread'in bitmesini bekle
            if not ss._fund_refresh_in_progress:
                break
            time.sleep(0.02)
        assert cagrilan == ["AAPL"]
        assert ss._fund_refresh_in_progress == set()

    def test_eszamanli_tur_sayisi_sinirli(self, monkeypatch):
        """Bir tarama 44 bayat sembol görebilir; 44 thread Finnhub'ı 429'lardı."""
        devam = threading.Event()
        cagrilan: list[str] = []

        def _yavas(symbol):
            cagrilan.append(symbol)
            devam.wait(timeout=5)
            return None

        monkeypatch.setattr(ss, "_fetch_and_store_fundamentals", _yavas)
        for sym in ("A", "B", "C", "D", "E"):
            ss._schedule_fund_refresh(sym)
        for _ in range(100):
            if len(cagrilan) >= ss._FUND_REFRESH_MAX_INFLIGHT:
                break
            time.sleep(0.02)
        assert len(cagrilan) == ss._FUND_REFRESH_MAX_INFLIGHT
        devam.set()
        for _ in range(100):
            if not ss._fund_refresh_in_progress:
                break
            time.sleep(0.02)
        assert ss._fund_refresh_in_progress == set()


class TestKaynakHatasi:
    def test_gecici_hata_iyi_kaydin_ustune_yazmaz(self, monkeypatch):
        """Finnhub 429 / .info bloğu geçicidir; eldeki gerçek oranı silip
        hisseyi saatlerce "temel oran yok" bırakmamalı."""
        _sayan(monkeypatch)
        assert ss._get_fundamentals_cached("AAPL")["pe_trailing"] == 10.0
        _bayatlat("AAPL")

        monkeypatch.setattr(ss.fundamental_analysis_service,
                            "_compute_fundamentals",
                            lambda sym: {"data_limited": True})
        assert ss._fetch_and_store_fundamentals("AAPL")["pe_trailing"] == 10.0
        # Kayıt hâlâ BAYAT (yeni damga yok) → sonraki tur yeniden dener.
        assert ss._fund_is_stale(cache._mem[ss._FUND_KEY + "AAPL"][1], "AAPL")
        assert ss._get_fundamentals_cached("AAPL")["pe_trailing"] == 10.0

    def test_hic_kayit_yokken_oran_yok_cachelenir(self, monkeypatch):
        """Negatif cache korunur: BIST hisseleri her taramada yeniden
        denenmemeli."""
        cagrilan = []
        monkeypatch.setattr(
            ss.fundamental_analysis_service, "_compute_fundamentals",
            lambda sym: cagrilan.append(sym) or {"data_limited": True})
        assert ss._get_fundamentals_cached("KARSN.IS") is None
        assert ss._get_fundamentals_cached("KARSN.IS") is None
        assert cagrilan == ["KARSN.IS"]


class TestIsitma:
    def test_isitma_bayati_da_yeniler(self, monkeypatch):
        """Kayıt artık silinmediği için 'eksik mi' diye bakan ısıtma hiçbir
        şeyi yenilemezdi."""
        cagrilan = _sayan(monkeypatch)
        assert ss.prewarm_fundamentals(["AAPL"]) == 1
        assert ss.prewarm_fundamentals(["AAPL"]) == 0      # taze → bedava
        _bayatlat("AAPL")
        assert ss.prewarm_fundamentals(["AAPL"]) == 1      # bayat → yenilenir
        assert cagrilan == ["AAPL", "AAPL"]

    def test_isitma_arka_plan_thread_i_acmaz(self, monkeypatch):
        """Isıtma zaten arka plan işçisinde koşuyor → senkron çekmeli, üstüne
        bir de thread açmamalı."""
        _sayan(monkeypatch)
        ss.prewarm_fundamentals(["AAPL"])
        _bayatlat("AAPL")
        planlanan: list[str] = []
        monkeypatch.setattr(ss, "_schedule_fund_refresh", planlanan.append)
        ss.prewarm_fundamentals(["AAPL"])
        assert planlanan == []


class TestTaramaTekOkuma:
    def test_ohlcv_isci_basina_tekrar_okunmaz(self, db, make_user, monkeypatch):
        """Isıtma zaten tüm sembollerin serisini getiriyor; işçiler aynı seriyi
        cache'ten yeniden okumamalı (51 sembolde ~150 Redis gidiş-dönüşü)."""
        user = make_user()
        db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=1,
                         average_cost=100.0))
        db.add(Portfolio(user_id=user.id, symbol="MSFT", quantity=1,
                         average_cost=100.0))
        db.commit()

        seri = {"AAPL": {"close": [1.0]}, "MSFT": {"close": [2.0]}}
        cagri: list[list[str]] = []

        def _ohlcv(symbols, period="6mo"):
            cagri.append(list(symbols))
            return seri

        from app.services import market_data_service
        monkeypatch.setattr(market_data_service, "get_daily_ohlcv", _ohlcv)

        gelen: dict[str, dict] = {}

        def _ind(symbol, bars=None):
            gelen[symbol] = bars
            return {"current_price": 10.0}

        monkeypatch.setattr(ss.technical_analysis_service,
                            "_compute_indicators", _ind)
        monkeypatch.setattr(ss, "_get_fundamentals_cached", lambda s: None)

        out = ss.get_signals_for_user(db, user.id)
        assert len(out["signals"]) == 2
        assert len(cagri) == 1                       # TEK okuma turu
        assert gelen["AAPL"] == seri["AAPL"]         # seri işçiye taşındı
        assert gelen["MSFT"] == seri["MSFT"]

    def test_isitmada_gelmeyen_sembol_kendi_yolunu_dener(self, db, make_user,
                                                        monkeypatch):
        """Batch'ten dönmeyen sembol bars=None alır → eski davranış (kendi
        çekimi + negatif cache), sinyali sessizce kaybolmaz."""
        user = make_user()
        db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=1,
                         average_cost=100.0))
        db.commit()

        from app.services import market_data_service
        monkeypatch.setattr(market_data_service, "get_daily_ohlcv",
                            lambda symbols, period="6mo": {})

        gelen: dict[str, dict | None] = {}

        def _ind(symbol, bars=None):
            gelen[symbol] = bars
            return {"current_price": 10.0}

        monkeypatch.setattr(ss.technical_analysis_service,
                            "_compute_indicators", _ind)
        monkeypatch.setattr(ss, "_get_fundamentals_cached", lambda s: None)

        ss.get_signals_for_user(db, user.id)
        assert gelen == {"AAPL": None}


# ── Sinyal cache'i ısıtması (4 Eyl 2026, 9. tur) ──────────────────────────
# Canlı: taze süreçte /signals 3,9 sn, hemen ardından 0,25 sn. `_signal_cache`
# süreç-içi olduğu için bedeli deploy sonrası ilk kullanıcı ödüyordu.

def test_prewarm_signals_skips_cached_and_batches_ohlcv(monkeypatch):
    from app.services import signal_service as ss, market_data_service as mds
    ss._signal_cache.clear()
    ss._signal_cache["AAPL"] = ({"symbol": "AAPL"}, __import__("datetime").datetime.now())
    batches = []
    monkeypatch.setattr(mds, "get_daily_ohlcv",
                        lambda symbols, period: batches.append(list(symbols)) or {})
    computed = []
    monkeypatch.setattr(ss, "get_signal",
                        lambda symbol, force_refresh=False, bars=None:
                            computed.append(symbol) or {"symbol": symbol})

    warmed = ss.prewarm_signals(["AAPL", "MSFT", "THYAO.IS"])

    assert batches == [["MSFT", "THYAO.IS"]], "OHLCV tek batch + cache'teki atlanmalı"
    assert computed == ["MSFT", "THYAO.IS"]
    assert warmed == 2
    ss._signal_cache.clear()


def test_prewarm_signals_is_free_when_all_cached(monkeypatch):
    from app.services import signal_service as ss, market_data_service as mds
    ss._signal_cache.clear()
    now = __import__("datetime").datetime.now()
    for sym in ("AAPL", "MSFT"):
        ss._signal_cache[sym] = ({"symbol": sym}, now)

    def _boom(*a, **k):
        raise AssertionError("hepsi cache'teyken ağa/hesaba gidildi")

    monkeypatch.setattr(mds, "get_daily_ohlcv", _boom)
    assert ss.prewarm_signals(["AAPL", "MSFT"]) == 0
    ss._signal_cache.clear()
