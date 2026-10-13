"""Dönem performansı (hafta/ay) — ana ekran hero'su.

Kritik noktalar:
 1. USD pozisyonun getirisi KUR hareketini içermeli (₺ yatırımcısının gerçek
    getirisi) — dönem başı o günkü kur, bugün güncel kur.
 2. Borsa kapalı günler: tam tarih eşleşmesi aranmamalı, ÖNCEKİ en yakın
    işlem günü kullanılmalı — yoksa hafta sonuna denk gelen pencere tüm
    pozisyonları boşuna dışlardı.
 3. Dönem verisi olmayan pozisyon SESSİZCE SIFIR sayılmaz, dışlanıp raporlanır.
 4. Ek piyasa isteği YOK: veri paylaşılan kapanış cache'inden okunur.
"""

from datetime import datetime, timedelta

import pytest

from app.models.portfolio import Portfolio
from app.services import portfolio_performance_service as pps


def _day(offset: int) -> str:
    return (datetime.now().date() - timedelta(days=offset)).isoformat()


@pytest.fixture
def closes(monkeypatch):
    """get_daily_closes'u sahteler; {sym: {gün: kapanış}} verilir."""
    store: dict[str, dict[str, float]] = {}
    calls = []

    def fake(symbols, days):
        calls.append(sorted(symbols))
        return {s: store[s] for s in symbols if s in store}

    monkeypatch.setattr(pps.market_data_service, "get_daily_closes", fake)
    store["_calls"] = calls  # test erişebilsin
    return store


def _set(closes, sym, **by_offset):
    closes[sym] = {_day(int(k[1:])): v for k, v in by_offset.items()}


# ── Temel hesap ───────────────────────────────────────────────────────────

def test_try_position_weekly_return(db, make_user, market, closes, monkeypatch):
    user = make_user()
    market.set_price("THYAO.IS", 110.0)
    db.add(Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=10,
                     average_cost=50.0))
    db.commit()
    _set(closes, "THYAO.IS", d7=100.0)          # 7 gün önce 100 → şimdi 110

    out = pps.compute_performance(db, user.id)

    assert out["periods"]["1w"]["pnl_percent"] == pytest.approx(10.0)
    assert out["periods"]["1w"]["pnl_try"] == pytest.approx(100.0)  # 1100-1000


def test_usd_position_return_includes_fx(db, make_user, market, closes,
                                         monkeypatch):
    """Fiyat +%10, kur +%10 → ₺ getirisi ≈ %21 (yalnız %10 DEĞİL)."""
    user = make_user()
    market.set_price("AAPL", 110.0)
    market.set_usdtry(44.0)                       # bugünkü kur
    db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=10,
                     average_cost=1.0))
    db.commit()
    _set(closes, "AAPL", d7=100.0)
    _set(closes, "USDTRY=X", d7=40.0)             # dönem başı kur

    out = pps.compute_performance(db, user.id)

    assert out["periods"]["1w"]["pnl_percent"] == pytest.approx(21.0, abs=0.1)


def test_closed_market_uses_previous_trading_day(db, make_user, market, closes):
    """Hedef gün borsada kapalıysa ÖNCEKİ işlem günü kullanılmalı."""
    user = make_user()
    market.set_price("THYAO.IS", 120.0)
    db.add(Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=1,
                     average_cost=1.0))
    db.commit()
    # 7. günde bar YOK; 9. günde var → 9. gün kullanılmalı
    _set(closes, "THYAO.IS", d9=100.0, d3=115.0)

    out = pps.compute_performance(db, user.id)
    assert out["periods"]["1w"]["pnl_percent"] == pytest.approx(20.0)


def test_uses_nearest_day_not_oldest(db, make_user, market, closes):
    """Hedeften ÖNCEKİ en YAKIN gün seçilmeli (en eski değil)."""
    user = make_user()
    market.set_price("THYAO.IS", 100.0)
    db.add(Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=1,
                     average_cost=1.0))
    db.commit()
    _set(closes, "THYAO.IS", d30=10.0, d8=50.0, d2=90.0)

    out = pps.compute_performance(db, user.id)
    # 1 hafta → 8. gün (50) kullanılmalı; 30 günlük → 30. gün (10)
    assert out["periods"]["1w"]["pnl_percent"] == pytest.approx(100.0)
    assert out["periods"]["1m"]["pnl_percent"] == pytest.approx(900.0)


# ── Dürüstlük ─────────────────────────────────────────────────────────────

def test_symbol_without_history_is_excluded_not_zeroed(db, make_user, market,
                                                       closes):
    """Yeni/verisiz sembol sessizce 'sıfır getiri' sayılırsa portföy getirisi
    sistematik olarak sulanırdı."""
    user = make_user()
    market.set_price("THYAO.IS", 110.0)
    market.set_price("YENI.IS", 500.0)
    db.add_all([
        Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=10,
                  average_cost=1.0),
        Portfolio(user_id=user.id, symbol="YENI.IS", quantity=1,
                  average_cost=1.0),
    ])
    db.commit()
    _set(closes, "THYAO.IS", d7=100.0)            # YENI.IS serisi YOK

    out = pps.compute_performance(db, user.id)
    w = out["periods"]["1w"]

    assert w["symbols_excluded"] == ["YENI.IS"]
    assert w["symbols_included"] == 1
    assert w["pnl_percent"] == pytest.approx(10.0)   # yalnız THYAO'dan


def test_no_history_at_all_returns_null_not_zero(db, make_user, market, closes):
    """Hiç veri yoksa '%0 değişim' YALAN olur → null döner, UI '—' gösterir."""
    user = make_user()
    market.set_price("THYAO.IS", 110.0)
    db.add(Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=1,
                     average_cost=1.0))
    db.commit()

    out = pps.compute_performance(db, user.id)
    assert out["periods"]["1w"]["pnl_percent"] is None
    assert out["periods"]["1w"]["pnl_try"] is None


def test_empty_portfolio(db, make_user, closes):
    out = pps.compute_performance(db, make_user().id)
    assert out["has_holdings"] is False
    assert out["periods"] == {}


# ── Maliyet ───────────────────────────────────────────────────────────────

def test_single_shared_closes_call_for_all_windows(db, make_user, market,
                                                   closes):
    """Hafta ve ay AYNI seriden okunmalı — pencere başına ayrı çekim değil."""
    user = make_user()
    market.set_price("THYAO.IS", 110.0)
    db.add(Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=1,
                     average_cost=1.0))
    db.commit()
    _set(closes, "THYAO.IS", d30=90.0, d7=100.0)

    pps.compute_performance(db, user.id)

    assert len(closes["_calls"]) == 1, "pencere başına ayrı kapanış çekimi"
