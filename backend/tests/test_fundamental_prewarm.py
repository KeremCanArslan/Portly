"""Temel oran cache'inin arka planda ısıtılması.

Bağlam: ilk sinyal taraması ~32 sn sürüyordu; ölçümde bunun büyük kısmı
sembol sembol temel oran çekmekti (cache sıcakken aynı tarama 0,5 sn). Bedeli
Sinyaller sekmesine ilk giren kullanıcı ödüyordu. Isıtma arka plan işçisine
alındı; kurallar: yalnız EKSİKLER, yalnız HİSSE, tur başına üst sınır.

Testler ağa ÇIKMAZ.
"""

import pytest

from app.core import cache
from app.services import fundamental_analysis_service as fa
from app.services import market_refresh_service as mrs
from app.services import signal_service as ss

_F = {"pe_ratio": 10.0, "sector": "Test"}


@pytest.fixture(autouse=True)
def _temiz(monkeypatch):
    cache._mem.clear()
    monkeypatch.setattr(ss, "prewarm_fundamentals", _REAL)
    yield
    cache._mem.clear()


_REAL = ss.prewarm_fundamentals   # conftest stub'ını aşmak için (import anı)


def _sayan(monkeypatch):
    cagrilan: list[str] = []
    monkeypatch.setattr(fa, "_compute_fundamentals",
                        lambda sym: cagrilan.append(sym) or dict(_F))
    return cagrilan


def test_yalniz_hisse_isitilir(monkeypatch):
    cagrilan = _sayan(monkeypatch)
    ss.prewarm_fundamentals(["AAPL", "THYAO.IS", "BTC-USD", "GC=F",
                             "USDTRY=X", "TLY.FON"])
    assert cagrilan == ["AAPL", "THYAO.IS"]


def test_cachedeki_sembol_tekrar_cekilmez(monkeypatch):
    cagrilan = _sayan(monkeypatch)
    assert ss.prewarm_fundamentals(["AAPL"]) == 1
    assert ss.prewarm_fundamentals(["AAPL"]) == 0      # ikinci tur bedava
    assert cagrilan == ["AAPL"]


def test_tur_basina_ust_sinir(monkeypatch):
    cagrilan = _sayan(monkeypatch)
    semboller = [f"SYM{i}" for i in range(20)]
    assert ss.prewarm_fundamentals(semboller, limit=3) == 3
    assert len(cagrilan) == 3


def test_oran_yoksa_sonuc_da_cachelenir(monkeypatch):
    """`data_limited` (oran çıkmadı) sonucu da yazılır — yoksa BIST hisseleri
    her turda yeniden denenirdi."""
    cagrilan = []
    monkeypatch.setattr(fa, "_compute_fundamentals",
                        lambda sym: cagrilan.append(sym) or {"data_limited": True})
    ss.prewarm_fundamentals(["KARSN.IS"])
    ss.prewarm_fundamentals(["KARSN.IS"])
    assert cagrilan == ["KARSN.IS"]


def test_patlayan_sembol_turu_dusurmez(monkeypatch):
    def _patla(sym):
        if sym == "AAPL":
            raise RuntimeError("kaynak düştü")
        return dict(_F)
    monkeypatch.setattr(fa, "_compute_fundamentals", _patla)
    # AAPL patlar ama None cache'lenir; MSFT ısınır → tur devam eder.
    assert ss.prewarm_fundamentals(["AAPL", "MSFT"]) >= 1


def test_isci_turunda_isitma_isi_var(monkeypatch):
    _sayan(monkeypatch)
    monkeypatch.setattr(mrs.market_data_service, "prewarm_symbols",
                        lambda symbols: None)
    monkeypatch.setattr(mrs.market_data_service, "refresh_daily_closes",
                        lambda symbols: {})
    monkeypatch.setattr(mrs.market_data_service, "refresh_daily_ohlcv",
                        lambda symbols, period: {})
    monkeypatch.setattr(mrs.signal_service, "prewarm_fundamentals", _REAL)
    res = mrs.refresh(["AAPL", "BTC-USD"])
    assert res.warmed == 1
    assert not res.errors
