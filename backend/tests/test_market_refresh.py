"""Arka plan piyasa yenileyicisi — Yahoo istek hızını trafikten ayırır.

Sözleşme: bir yenileme turu, sembol sayısından BAĞIMSIZ olarak sabit sayıda
batch atar (fiyat + kapanış + OHLCV = 3). Biri düşerse diğerleri devam eder.
"""

import pytest

from app.models.portfolio import Portfolio
from app.models.watchlist import WatchlistItem
from app.services import market_refresh_service as mrs


# ── İzlenen sembol kümesi ─────────────────────────────────────────────────

def test_tracked_symbols_covers_portfolio_watchlist_and_benchmarks(
        db, make_user):
    user = make_user()
    db.add_all([
        Portfolio(user_id=user.id, symbol="ASELS.IS", quantity=1,
                  average_cost=1),
        WatchlistItem(user_id=user.id, symbol="NVDA"),
    ])
    db.commit()

    syms = mrs.tracked_symbols(db)

    assert "ASELS.IS" in syms          # pozisyon
    assert "NVDA" in syms              # izleme listesi
    for b in ("XU100.IS", "^GSPC", "USDTRY=X", "GC=F"):
        assert b in syms, f"benchmark sembolü eksik: {b}"
    assert len(syms) == len(set(syms)), "tekrar eden sembol var"


def test_tracked_symbols_canonicalises(db, make_user):
    """Çıplak BIST kodu kanonikleştirilmeli — yoksa cache anahtarı fiyat
    yolununkiyle tutmaz ve yenileme boşa gider."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="THYAO", quantity=1,
                     average_cost=1))
    db.commit()

    syms = mrs.tracked_symbols(db)
    assert "THYAO.IS" in syms
    assert "THYAO" not in syms


# ── Tur davranışı ─────────────────────────────────────────────────────────

def _patch_sources(monkeypatch, *, quotes=None, closes=None, ohlcv=None):
    calls = {"quote": 0, "closes": 0, "ohlcv": 0}

    def mk(name, fail):
        def _f(symbols, *a, **k):
            calls[name] += 1
            if fail:
                raise RuntimeError(f"{name} düştü")
            return {s: {} for s in symbols}
        return _f

    monkeypatch.setattr(mrs.market_data_service, "prewarm_symbols",
                        mk("quote", quotes == "fail"))
    monkeypatch.setattr(mrs.market_data_service, "refresh_daily_closes",
                        mk("closes", closes == "fail"))
    monkeypatch.setattr(mrs.market_data_service, "refresh_daily_ohlcv",
                        mk("ohlcv", ohlcv == "fail"))
    return calls


def test_refresh_is_constant_number_of_batches(monkeypatch):
    """40 sembol de olsa 3 sembol de olsa tur başına 3 batch."""
    calls = _patch_sources(monkeypatch)
    many = [f"SYM{i}" for i in range(40)]

    res = mrs.refresh(many)

    assert calls == {"quote": 1, "closes": 1, "ohlcv": 1}
    assert res.symbols == 40
    assert res.ok


def test_partial_failure_does_not_abort_other_sets(monkeypatch):
    """Kapanış çekimi 429 yerse fiyat ve OHLCV yine tazelenmeli."""
    calls = _patch_sources(monkeypatch, closes="fail")

    res = mrs.refresh(["AAPL", "NVDA"])

    assert calls["quote"] == 1 and calls["ohlcv"] == 1
    assert res.closes == 0
    assert any("closes" in e for e in res.errors)


def test_all_failures_reported_not_raised(monkeypatch):
    _patch_sources(monkeypatch, quotes="fail", closes="fail", ohlcv="fail")
    res = mrs.refresh(["AAPL"])
    assert len(res.errors) == 3
    assert not res.ok


def test_empty_symbol_list_is_a_noop(monkeypatch):
    calls = _patch_sources(monkeypatch)
    res = mrs.refresh([])
    assert calls == {"quote": 0, "closes": 0, "ohlcv": 0}
    assert res.symbols == 0


def test_round_warms_sector_cache(monkeypatch):
    """Sağlık skorunun girdisi olan sektör çözümü de arka plan turunda ısınır
    (soğuk /health canlıda 7,5 sn ölçülmüştü; kullanıcı isteği çözüm yapmasın)."""
    _patch_sources(monkeypatch)
    seen = []
    monkeypatch.setattr(mrs.portfolio_service, "prewarm_sectors",
                        lambda symbols, *a, **k: seen.append(list(symbols)) or len(symbols))

    res = mrs.refresh(["AAPL", "THYAO.IS"])

    assert seen == [["AAPL", "THYAO.IS"]]
    assert res.sectors == 2


def test_sector_warm_failure_does_not_abort_round(monkeypatch):
    """Sektör kaynağı düşerse fiyat/kapanış/OHLCV tazelemesi sürmeli."""
    calls = _patch_sources(monkeypatch)

    def _boom(symbols, *a, **k):
        raise RuntimeError("Finnhub 403")

    monkeypatch.setattr(mrs.portfolio_service, "prewarm_sectors", _boom)

    res = mrs.refresh(["AAPL"])

    assert calls == {"quote": 1, "closes": 1, "ohlcv": 1}
    assert any("sektör" in e for e in res.errors)
