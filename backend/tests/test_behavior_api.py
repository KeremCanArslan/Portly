"""Behavior (davranışsal finans) HTTP entegrasyon testleri.

`GET /api/v1/behavior/profile/{user_id}` — Disposition/Overconfidence/Loss
Aversion önyargılarını işlem geçmişinden ölçer. Burada HTTP katmanı kilitlenir:
auth zorunlu, sahiplik (token≠path → 403), boş ve işlem-dolu geçmişte 200.
Fiyat okuması (açık pozisyon) `market` ile mock'lu (ağ yok).

Çalıştırma:  cd backend && python -m pytest tests/test_behavior_api.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app
from app.models.user import User
from app.schemas.trade_schema import TradeRequest
from app.services import order_service

BEH = "/api/v1/behavior"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _register(client, db, email="bh@mail.com", password="testpass1"):
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    uid = db.query(User).filter_by(email=email).one().id
    return {"Authorization": f"Bearer {token}"}, uid


def test_profile_requires_auth(client):
    assert client.get(f"{BEH}/profile/1").status_code == 401


def test_profile_other_user_forbidden(client, db):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{BEH}/profile/{uid + 999}", headers=hdr).status_code == 403


def test_profile_empty_history_ok(client, db, market):
    """İşlem yokken de analiz 200 dönmeli (boş-durum çökmesin)."""
    hdr, uid = _register(client, db)
    assert client.get(f"{BEH}/profile/{uid}", headers=hdr).status_code == 200


def test_profile_with_trades_ok(client, db, market):
    market.set_price("AAPL", 100.0)
    hdr, uid = _register(client, db)
    # al + kısmi sat → kapanan & açık pozisyon (önyargı ölçümüne girdi)
    order_service.execute_trade(db, TradeRequest(
        user_id=uid, symbol="AAPL", quantity=2, transaction_type="BUY"))
    order_service.execute_trade(db, TradeRequest(
        user_id=uid, symbol="AAPL", quantity=1, transaction_type="SELL"))
    assert client.get(f"{BEH}/profile/{uid}", headers=hdr).status_code == 200
