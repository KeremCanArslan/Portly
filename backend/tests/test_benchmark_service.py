"""C5 — Benchmark servisi regresyon testleri.

İki kritik nokta:
 1. Makro sabitler (mevduat/TÜFE) — 29. turda 2026'ya çekildi. Sessiz drift'e
    karşı sentinel + sentetik getiri matematiği.
 2. Portföy getirisi USD pozisyonlarda KUR etkisini içermeli (₺ yatırımcısının
    gerçek getirisi) ve dönem verisi olmayan semboller DÜRÜSTÇE dışlanmalı (A4).

`_fetch_series` yfinance'e gider → mock'lanır; `_bench_cache` her testte temizlenir.

Çalıştırma:  cd backend && pytest -q
"""

import pytest

from app.services import benchmark_service
from app.models.portfolio import Portfolio


def _patch_series(monkeypatch, by_symbol):
    """Batch kapanış çekimini sym→(start, end) sözlüğüyle değiştirir (ağ yok).

    Mock noktası `get_daily_closes` (tek yf.download): benchmark artık sembol
    başına ayrı istek yapmıyor. Ham kapanış verilir, getiri/Sharpe'ı gerçek
    `_series_from_closes` hesaplar → test gerçek kod yolunu kapsar."""
    def fake(symbols, days):
        out = {}
        for sym in symbols:
            v = by_symbol.get(sym)
            if v is None:
                continue
            start, end = v
            out[sym] = {"2026-01-01": start, "2026-01-02": end}
        return out
    monkeypatch.setattr(
        "app.services.market_data_service.get_daily_closes", fake)
    benchmark_service._bench_cache.clear()


# ── Saf matematik + makro sabit sentinel ──────────────────────────────────

def test_synthetic_return_compounds():
    f = benchmark_service._synthetic_return
    assert f(49.0, 365) == pytest.approx(49.0)   # tam yıl = yıllık oran
    assert f(49.0, 0) == pytest.approx(0.0)       # sıfır gün = sıfır getiri
    assert 0 < f(49.0, 182) < 49.0                # yarım yıl < tam yıl


def test_macro_constants_are_intentional_sentinels():
    """29. turda güncellendi (TÜİK Nis'26 TÜFE + TCMB mevduat). Makro değişince
    BİLEREK güncelle — bu test sessiz drift'e karşı nöbetçi (kaynak: handoff 29)."""
    assert benchmark_service._ANNUAL_DEPOSIT_PCT == 49.0
    assert benchmark_service._ANNUAL_CPI_PCT == 32.5


# ── compute_benchmark entegrasyon (mock'lu seri) ──────────────────────────

def test_usd_portfolio_return_includes_fx(db, make_user, monkeypatch):
    """USD pozisyon getirisi kur hareketini içermeli: %10 fiyat × %10 kur ≈ %21."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=10, average_cost=100.0))
    db.commit()
    _patch_series(monkeypatch, {
        "AAPL": (100.0, 110.0),      # +%10 fiyat
        "USDTRY=X": (40.0, 44.0),    # +%10 kur
        "XU100.IS": (1000.0, 1100.0),
        "^GSPC": (5000.0, 5500.0),
        "GC=F": (2000.0, 2200.0),
    })

    res = benchmark_service.compute_benchmark(db, user.id, "3m")

    # (110×44)/(100×40) − 1 = 4840/4000 − 1 = %21
    assert res["portfolio"]["return_pct"] == pytest.approx(21.0)
    assert res["portfolio"]["symbols_included"] == 1
    assert res["portfolio"]["symbols_excluded"] == []


def test_bist_portfolio_return_no_fx(db, make_user, monkeypatch):
    """BIST pozisyonu getirisinde kur uygulanmaz (saf fiyat getirisi)."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=5, average_cost=100.0))
    db.commit()
    _patch_series(monkeypatch, {
        "THYAO.IS": (100.0, 120.0),  # +%20
        "USDTRY=X": (40.0, 60.0),    # kur fırlamış ama BIST'i etkilememeli
    })

    res = benchmark_service.compute_benchmark(db, user.id, "3m")

    assert res["portfolio"]["return_pct"] == pytest.approx(20.0)


def test_deposit_inflation_use_macro_constants(db, make_user, monkeypatch):
    """MEVDUAT/ENFLASYON benchmark'ları sabitlerin sentetik getirisini kullanır
    + 'approx' işaretli olur."""
    user = make_user()
    _patch_series(monkeypatch, {"USDTRY=X": (40.0, 44.0)})

    res = benchmark_service.compute_benchmark(db, user.id, "1y")  # 365 gün
    mevduat = res["benchmarks"]["MEVDUAT"]
    enflasyon = res["benchmarks"]["ENFLASYON"]

    assert mevduat["approx"] is True
    assert mevduat["return_pct"] == pytest.approx(49.0, abs=0.01)   # 1y = yıllık
    assert enflasyon["return_pct"] == pytest.approx(32.5, abs=0.01)


def test_benchmark_excludes_symbol_without_data(db, make_user, monkeypatch):
    """Dönem verisi olmayan pozisyon getiriye katılmaz, dürüstçe dışlanır (A4)."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=10, average_cost=100.0))
    db.add(Portfolio(user_id=user.id, symbol="FAKE", quantity=5, average_cost=50.0))
    db.commit()
    _patch_series(monkeypatch, {
        "AAPL": (100.0, 110.0), "USDTRY=X": (40.0, 44.0)})  # FAKE yok

    res = benchmark_service.compute_benchmark(db, user.id, "3m")

    assert "FAKE" in res["portfolio"]["symbols_excluded"]
    assert res["portfolio"]["symbols_included"] == 1
