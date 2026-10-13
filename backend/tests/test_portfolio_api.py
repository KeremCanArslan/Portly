"""Portfolio HTTP entegrasyon testleri — FastAPI TestClient ile.

Portföy değerleme/benchmark/temettü servis-mantığı zaten test_portfolio_valuation
/ test_benchmark_service / test_dividend_collect'te kilitli. Burada kilitlenen
HTTP KATMANI:
- **sahiplik kontrolü** (`_ensure_self`): her uçta token≠path user_id → 403
  (başka kullanıcının portföy/temettü/benchmark verisine erişim yok),
- auth zorunlu (token yok → 401),
- boş portföy + holding'li portföy GET uçtan uca (değerleme `market` mock'uyla).

Pahalı/ağ-bağımlı uçlar (benchmark: 10+ sembol yfinance) yalnız auth+sahiplik
kapısından sınanır — happy-path servis testinde. get_db test oturumuna override;
TestClient `with`SİZ (lifespan/ağ yok); fiyat/FX `market` ile mock; limiter kapalı.

Çalıştırma:  cd backend && python -m pytest tests/test_portfolio_api.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app
from app.models.user import User
from app.schemas.trade_schema import TradeRequest
from app.services import order_service

PF = "/api/v1/portfolio"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _register(client, db, email="pf@mail.com", password="testpass1"):
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    uid = db.query(User).filter_by(email=email).one().id
    return {"Authorization": f"Bearer {token}"}, uid


# ── GET /{uid} portföy ────────────────────────────────────────────────────

def test_portfolio_requires_auth(client):
    assert client.get(f"{PF}/1").status_code == 401


def test_portfolio_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(f"{PF}/{uid + 999}", headers=hdr).status_code == 403


def test_empty_portfolio_returns_empty_list(client, db, market):
    hdr, uid = _register(client, db)
    r = client.get(f"{PF}/{uid}", headers=hdr)
    assert r.status_code == 200 and r.json() == []


def test_portfolio_reflects_holding(client, db, market):
    market.set_price("AAPL", 150.0)
    hdr, uid = _register(client, db)
    order_service.execute_trade(db, TradeRequest(
        user_id=uid, symbol="AAPL", quantity=3, transaction_type="BUY"))

    r = client.get(f"{PF}/{uid}", headers=hdr)
    assert r.status_code == 200
    symbols = [item["symbol"] for item in r.json()]
    assert "AAPL" in symbols


# ── /{uid}/sectors ────────────────────────────────────────────────────────

def test_sectors_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{PF}/{uid + 999}/sectors", headers=hdr).status_code == 403


def test_sectors_empty_ok(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(f"{PF}/{uid}/sectors", headers=hdr).status_code == 200


# ── /{uid}/health ─────────────────────────────────────────────────────────

def test_health_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{PF}/{uid + 999}/health", headers=hdr).status_code == 403


def test_health_empty_ok(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(f"{PF}/{uid}/health", headers=hdr).status_code == 200


# ── /{uid}/dividends + collect + preview ──────────────────────────────────

def test_dividends_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{PF}/{uid + 999}/dividends", headers=hdr).status_code == 403


def test_dividends_empty_ok(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(f"{PF}/{uid}/dividends", headers=hdr).status_code == 200


def test_dividends_collect_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.post(
        f"{PF}/{uid + 999}/dividends/collect", headers=hdr).status_code == 403


def test_dividends_collect_empty_ok(client, db, market):
    """Boş portföyde tahsil → 200, mutasyon yok (idempotent sıfır)."""
    hdr, uid = _register(client, db)
    assert client.post(
        f"{PF}/{uid}/dividends/collect", headers=hdr).status_code == 200


def test_dividends_preview_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{PF}/{uid + 999}/dividends/preview", headers=hdr).status_code == 403


# ── /{uid}/benchmark (pahalı/ağ → yalnız auth + sahiplik kapısı) ───────────

def test_benchmark_requires_auth(client):
    assert client.get(f"{PF}/1/benchmark").status_code == 401


def test_benchmark_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{PF}/{uid + 999}/benchmark", headers=hdr).status_code == 403


# ── DELETE /{uid}/positions/{symbol} ──────────────────────────────────────
# Yanlış girilmiş pozisyonu kaldırma. Satış DEĞİL: satışta lot düşer ve işlem
# kaydı geçmişte kalır; burada sembol "hiç eklenmemiş" hâline döner.

def test_delete_position_requires_auth(client):
    assert client.delete(f"{PF}/1/positions/AAPL").status_code == 401


def test_delete_position_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.delete(
        f"{PF}/{uid + 999}/positions/AAPL", headers=hdr).status_code == 403


def test_delete_position_missing_returns_404(client, db, market):
    hdr, uid = _register(client, db)
    assert client.delete(
        f"{PF}/{uid}/positions/AAPL", headers=hdr).status_code == 404


def test_delete_position_removes_holding_and_transactions(client, db, market):
    from app.models.transaction import Transaction

    market.set_price("AAPL", 150.0)
    hdr, uid = _register(client, db)
    order_service.execute_trade(db, TradeRequest(
        user_id=uid, symbol="AAPL", quantity=3, transaction_type="BUY"))
    order_service.execute_trade(db, TradeRequest(
        user_id=uid, symbol="AAPL", quantity=2, transaction_type="BUY"))

    r = client.delete(f"{PF}/{uid}/positions/AAPL", headers=hdr)
    assert r.status_code == 200, r.text
    assert r.json()["symbol"] == "AAPL"
    assert r.json()["deleted_transactions"] == 2

    assert client.get(f"{PF}/{uid}", headers=hdr).json() == []
    assert db.query(Transaction).filter_by(
        user_id=uid, symbol="AAPL").count() == 0


def test_delete_position_leaves_other_symbols_alone(client, db, market):
    from app.models.transaction import Transaction

    market.set_price("AAPL", 150.0)
    market.set_price("MSFT", 300.0)
    hdr, uid = _register(client, db)
    for sym in ("AAPL", "MSFT"):
        order_service.execute_trade(db, TradeRequest(
            user_id=uid, symbol=sym, quantity=1, transaction_type="BUY"))

    assert client.delete(
        f"{PF}/{uid}/positions/AAPL", headers=hdr).status_code == 200

    symbols = [i["symbol"] for i in client.get(f"{PF}/{uid}", headers=hdr).json()]
    assert symbols == ["MSFT"]
    assert db.query(Transaction).filter_by(
        user_id=uid, symbol="MSFT").count() == 1


def test_delete_position_does_not_touch_other_users(client, db, market):
    """Sahiplik filtresi WHERE'de: aynı sembol başka kullanıcıda duruyorsa
    silinmemeli (toplu delete'te en kolay kaçırılan yer)."""
    from app.models.transaction import Transaction

    market.set_price("AAPL", 150.0)
    hdr_a, uid_a = _register(client, db, email="a@mail.com")
    hdr_b, uid_b = _register(client, db, email="b@mail.com")
    for uid in (uid_a, uid_b):
        order_service.execute_trade(db, TradeRequest(
            user_id=uid, symbol="AAPL", quantity=1, transaction_type="BUY"))

    assert client.delete(
        f"{PF}/{uid_a}/positions/AAPL", headers=hdr_a).status_code == 200

    assert [i["symbol"] for i in
            client.get(f"{PF}/{uid_b}", headers=hdr_b).json()] == ["AAPL"]
    assert db.query(Transaction).filter_by(
        user_id=uid_b, symbol="AAPL").count() == 1


def test_delete_position_accepts_bare_bist_code(client, db, market):
    """Kullanıcı `.IS`'siz yazsa/eski kayıt ham biçimdeyse de eşleşmeli."""
    market.set_price("THYAO.IS", 300.0)
    hdr, uid = _register(client, db)
    order_service.execute_trade(db, TradeRequest(
        user_id=uid, symbol="THYAO.IS", quantity=5, transaction_type="BUY"))

    r = client.delete(f"{PF}/{uid}/positions/THYAO", headers=hdr)
    assert r.status_code == 200, r.text
    assert client.get(f"{PF}/{uid}", headers=hdr).json() == []
