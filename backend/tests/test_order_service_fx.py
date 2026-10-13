"""C2 — İşlem kaydı (kayıt defteri) regresyon testleri.

Pivot sonrası execute_trade sanal emir motoru DEĞİL, kayıt defteri:
BUY pozisyonu piyasa fiyatından ekler/ortalar, SELL azaltır/siler;
sanal nakit YOK. avg_cost ve transaction.price NATIVE kalır (gösterim/
temettü fx_service ile ₺'ye çevirir) — bu testler o sözleşmenin nöbetçisi.

Çalıştırma:  cd backend && pytest -q
"""

import pytest
from fastapi import HTTPException

from app.schemas.trade_schema import TradeRequest, ManualPositionRequest
from app.services import order_service
from app.models.portfolio import Portfolio
from app.models.transaction import Transaction


def _buy(db, user, symbol, qty):
    return order_service.execute_trade(db, TradeRequest(
        user_id=user.id, symbol=symbol, quantity=qty, transaction_type="BUY"))


def _sell(db, user, symbol, qty):
    return order_service.execute_trade(db, TradeRequest(
        user_id=user.id, symbol=symbol, quantity=qty, transaction_type="SELL"))


def _position(db, user, symbol):
    return db.query(Portfolio).filter_by(
        user_id=user.id, symbol=symbol).one()


# ── BUY kaydı ────────────────────────────────────────────────────────────

def test_buy_records_native_cost_and_position(db, market, make_user):
    """BUY kaydı pozisyonu piyasa fiyatından açar; avg_cost NATIVE (USD)."""
    market.set_usdtry(40.0)
    market.set_price("AAPL", 200.0)
    user = make_user()

    tx = _buy(db, user, "AAPL", 1)

    pos = _position(db, user, "AAPL")
    assert pos.average_cost == pytest.approx(200.0)   # avg_cost NATIVE (USD)
    assert pos.quantity == pytest.approx(1.0)
    assert tx.transaction_type == "BUY"
    assert tx.price == pytest.approx(200.0)           # kayıt fiyatı da native


def test_buy_bist_records_try_price(db, market, make_user):
    """BIST (₺) kaydında fiyat ₺; kur uygulanmaz."""
    market.set_usdtry(40.0)
    market.set_price("THYAO.IS", 100.0)
    user = make_user()

    _buy(db, user, "THYAO.IS", 10)

    assert _position(db, user, "THYAO.IS").average_cost == pytest.approx(100.0)


def test_weighted_average_cost_is_native(db, market, make_user):
    """İki farklı fiyattan alım → avg_cost native ağırlıklı ortalama (kur DEĞİL)."""
    market.set_usdtry(40.0)
    user = make_user()

    market.set_price("AAPL", 100.0)
    _buy(db, user, "AAPL", 1)
    market.set_price("AAPL", 200.0)
    _buy(db, user, "AAPL", 1)

    pos = _position(db, user, "AAPL")
    assert pos.average_cost == pytest.approx(150.0)   # (100+200)/2, native
    assert pos.quantity == pytest.approx(2.0)


# ── SELL kaydı ───────────────────────────────────────────────────────────

def test_sell_reduces_position_and_records(db, market, make_user):
    """SELL kaydı pozisyonu azaltır ve SELL işlemi düşer."""
    market.set_price("AAPL", 200.0)
    user = make_user()

    _buy(db, user, "AAPL", 2)
    market.set_price("AAPL", 250.0)
    _sell(db, user, "AAPL", 1)

    assert _position(db, user, "AAPL").quantity == pytest.approx(1.0)
    sells = db.query(Transaction).filter_by(
        user_id=user.id, transaction_type="SELL").all()
    assert len(sells) == 1
    assert sells[0].price == pytest.approx(250.0)


def test_sell_more_than_held_rejected(db, market, make_user):
    """Elde olandan fazlasını satmak 400 dönmeli."""
    market.set_price("AAPL", 100.0)
    user = make_user()
    _buy(db, user, "AAPL", 1)

    with pytest.raises(HTTPException) as ei:
        _sell(db, user, "AAPL", 5)
    assert ei.value.status_code == 400


def test_sell_all_removes_position(db, market, make_user):
    """Tüm adet satılınca pozisyon kaydı silinmeli (float epsilon toleransı)."""
    market.set_price("AAPL", 100.0)
    user = make_user()
    _buy(db, user, "AAPL", 2)
    _sell(db, user, "AAPL", 2)

    assert db.query(Portfolio).filter_by(
        user_id=user.id, symbol="AAPL").first() is None


# ── Manuel pozisyon içe aktarma ──────────────────────────────────────────

def test_manual_import_creates_position_and_buy_record(db, market, make_user):
    """Manuel içe aktarma pozisyonu girilen maliyetle açar + BUY kaydı düşer."""
    user = make_user()

    order_service.import_manual_position(db, ManualPositionRequest(
        user_id=user.id, symbol="AAPL", quantity=2, avg_cost=150.0))

    pos = _position(db, user, "AAPL")
    assert pos.quantity == pytest.approx(2.0)
    assert pos.average_cost == pytest.approx(150.0)
    buys = db.query(Transaction).filter_by(
        user_id=user.id, transaction_type="BUY").all()
    assert len(buys) == 1
    assert buys[0].price == pytest.approx(150.0)


def test_manual_import_merges_weighted_average(db, market, make_user):
    """Var olan pozisyona içe aktarma → ağırlıklı ortalama maliyet."""
    user = make_user()

    order_service.import_manual_position(db, ManualPositionRequest(
        user_id=user.id, symbol="AAPL", quantity=1, avg_cost=100.0))
    order_service.import_manual_position(db, ManualPositionRequest(
        user_id=user.id, symbol="AAPL", quantity=1, avg_cost=200.0))

    pos = _position(db, user, "AAPL")
    assert pos.quantity == pytest.approx(2.0)
    assert pos.average_cost == pytest.approx(150.0)
