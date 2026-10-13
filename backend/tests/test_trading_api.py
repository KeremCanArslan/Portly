"""Trading HTTP entegrasyon testleri — FastAPI TestClient ile uçtan uca kayıt yolu.

Servis-seviyesi kayıt semantiği test_order_service_fx'te kilitli. Burada
kilitlenen HTTP KATMANI (pivot sonrası: emir motoru yok, kayıt defteri):
- auth zorunlu (token yok → 401),
- **sahiplik kontrolü**: body/path user_id token'la eşleşmezse 403 (başka
  kullanıcı adına kayıt/sorgu yok),
- alış/satış kaydı → işlem geçmişi → CSV dışa aktarım uçtan uca,
- servis 400'leri (fazla sat) HTTP'ye doğru yansıyor mu.

get_db conftest'in bellek-içi oturumuna override edilir; TestClient `with`SİZ →
lifespan/prewarm (ağ) koşmaz. Fiyat/FX `market` fixture'ıyla mock'lu (ağ yok).
Rate limiter kapatılır.

Çalıştırma:  cd backend && python -m pytest tests/test_trading_api.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app
from app.models.user import User

TRADING = "/api/v1/trading"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _register(client, db, email="tr@mail.com", password="testpass1"):
    """Kayıt ol → (auth header, user_id). user_id şemadan bağımsız olarak
    DB'den okunur (test oturumu app ile aynı session)."""
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    uid = db.query(User).filter_by(email=email).one().id
    return {"Authorization": f"Bearer {token}"}, uid


def _buy(client, hdr, uid, symbol, qty):
    return client.post(f"{TRADING}/order", headers=hdr, json={
        "user_id": uid, "symbol": symbol,
        "quantity": qty, "transaction_type": "BUY"})


# ── /order — al/sat + auth + sahiplik ─────────────────────────────────────

def test_order_requires_auth(client):
    r = client.post(f"{TRADING}/order", json={
        "user_id": 1, "symbol": "AAPL",
        "quantity": 1, "transaction_type": "BUY"})
    assert r.status_code == 401


def test_order_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    # token uid'ye ait ama body başkasının id'sini söylüyor → 403
    r = client.post(f"{TRADING}/order", headers=hdr, json={
        "user_id": uid + 999, "symbol": "AAPL",
        "quantity": 1, "transaction_type": "BUY"})
    assert r.status_code == 403


def test_buy_order_succeeds_and_persists(client, db, market):
    market.set_usdtry(40.0)
    market.set_price("AAPL", 200.0)
    hdr, uid = _register(client, db)

    r = _buy(client, hdr, uid, "AAPL", 2)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["transaction_type"] == "BUY"
    assert body["quantity"] == pytest.approx(2.0)
    assert body["price"] == pytest.approx(200.0)   # native (USD)

    # İşlem geçmişinde görünür.
    tx = client.get(f"{TRADING}/transactions/{uid}", headers=hdr)
    assert tx.status_code == 200
    assert any(t["symbol"] == body["symbol"] for t in tx.json())


def test_buy_any_size_accepted(client, db, market):
    """Kayıt defteri: sanal bakiye yok → büyük alım kaydı da kabul edilir."""
    market.set_usdtry(40.0)
    market.set_price("AAPL", 200.0)
    hdr, uid = _register(client, db)
    r = _buy(client, hdr, uid, "AAPL", 100)
    assert r.status_code == 200, r.text


def test_sell_more_than_held_400(client, db, market):
    market.set_price("AAPL", 100.0)
    hdr, uid = _register(client, db)
    _buy(client, hdr, uid, "AAPL", 1)
    r = client.post(f"{TRADING}/order", headers=hdr, json={
        "user_id": uid, "symbol": "AAPL",
        "quantity": 5, "transaction_type": "SELL"})
    assert r.status_code == 400


# ── /transactions — geçmiş + sayfalama + sahiplik ─────────────────────────

def test_transactions_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{TRADING}/transactions/{uid + 999}", headers=hdr).status_code == 403


def test_transactions_pagination(client, db, market):
    market.set_price("AAPL", 100.0)
    hdr, uid = _register(client, db)
    for _ in range(3):
        _buy(client, hdr, uid, "AAPL", 1)

    page1 = client.get(
        f"{TRADING}/transactions/{uid}?limit=2&offset=0", headers=hdr)
    page2 = client.get(
        f"{TRADING}/transactions/{uid}?limit=2&offset=2", headers=hdr)
    assert len(page1.json()) == 2     # en yeni 2
    assert len(page2.json()) == 1     # kalan 1


def test_transactions_csv_export(client, db, market):
    market.set_usdtry(40.0)
    market.set_price("AAPL", 200.0)
    hdr, uid = _register(client, db)
    _buy(client, hdr, uid, "AAPL", 1)

    r = client.get(f"{TRADING}/transactions/{uid}/csv", headers=hdr)
    assert r.status_code == 200
    assert "text/csv" in r.headers["content-type"]
    assert "attachment" in r.headers.get("content-disposition", "")
    text = r.content.decode("utf-8-sig")
    assert "Sembol" in text and "AAPL" in text   # başlık + işlem satırı


# ── /manual-position — sahiplik + kayıt ──────────────────────────────────

def test_manual_position_other_user_forbidden(client, db, market):
    hdr, uid = _register(client, db)
    r = client.post(f"{TRADING}/manual-position", headers=hdr, json={
        "user_id": uid + 999, "symbol": "AAPL",
        "quantity": 2, "avg_cost": 150.0})
    assert r.status_code == 403


def test_manual_position_creates_holding(client, db, market):
    hdr, uid = _register(client, db)
    r = client.post(f"{TRADING}/manual-position", headers=hdr, json={
        "user_id": uid, "symbol": "AAPL", "quantity": 2, "avg_cost": 150.0})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["transaction_type"] == "BUY"
    assert body["price"] == pytest.approx(150.0)


# ── kaldırılan sanal-emir uçları gerçekten yok ────────────────────────────

def test_removed_trading_endpoints_gone(client, db, market):
    """Pivot: limit-order / pending-orders / demo uçları söküldü → 404/405."""
    hdr, uid = _register(client, db)
    assert client.post(f"{TRADING}/limit-order", headers=hdr,
                       json={}).status_code in (404, 405)
    assert client.get(f"{TRADING}/pending-orders/{uid}",
                      headers=hdr).status_code in (404, 405)
    assert client.post(f"{TRADING}/demo/{uid}",
                       headers=hdr).status_code in (404, 405)
