"""Güvenlik sertleştirmesi — dışarıdan gerçek kullanıcı gelince eklendi.

Kilitlenen davranışlar:
 1. Yeni/değiştirilen şifre politikası (uzunluk · yaygın şifre · e-posta ile
    aynılık · tek karakter tekrarı). MEVCUT kullanıcılar girişte kilitlenmez.
 2. Tarayıcı sertleştirme başlıkları her yanıtta.
 3. Prod'da /docs + /openapi.json kapalı (uç listesi herkese açık kalmasın).
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app
from app.services import auth_service

AUTH = "/api/v1/auth"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


# ── şifre politikası ─────────────────────────────────────────────────────

@pytest.mark.parametrize("password,reason", [
    ("kisa12", "8 karakterden kısa"),
    ("12345678", "sızıntı listelerinin tepesinde"),
    ("password", "en yaygın şifre"),
    ("aaaaaaaa", "tek karakterin tekrarı"),
])
def test_weak_passwords_rejected_on_register(client, password, reason):
    r = client.post(f"{AUTH}/register",
                    json={"email": "yeni@mail.com", "password": password})
    # Uzunluk Pydantic'te (422), politika serviste (400) yakalanır
    assert r.status_code in (400, 422), reason


def test_password_cannot_be_the_email(client):
    r = client.post(f"{AUTH}/register",
                    json={"email": "keremcan@mail.com",
                          "password": "keremcan"})
    assert r.status_code == 400
    assert "e-posta" in r.json()["detail"].lower()


def test_reasonable_password_accepted(client):
    r = client.post(f"{AUTH}/register",
                    json={"email": "iyi@mail.com", "password": "cetrefil42"})
    assert r.status_code == 200


def test_change_password_also_validated(client):
    token = client.post(f"{AUTH}/register",
                        json={"email": "d@mail.com",
                              "password": "cetrefil42"}).json()["access_token"]
    r = client.post(f"{AUTH}/change-password",
                    json={"current_password": "cetrefil42",
                          "new_password": "password"},
                    headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 400


def test_existing_weak_password_still_logs_in(client, db):
    """Politika GEÇMİŞE dönük uygulanmaz — eski kullanıcı kilitlenmemeli."""
    from app.models.user import User
    db.add(User(email="eski@mail.com",
                hashed_password=auth_service.get_password_hash("123456")))
    db.commit()
    r = client.post(f"{AUTH}/login",
                    json={"email": "eski@mail.com", "password": "123456"})
    assert r.status_code == 200


# ── başlıklar ve dokümanın kapalılığı ────────────────────────────────────

def test_security_headers_present(client):
    h = client.get("/health").headers
    assert h["X-Content-Type-Options"] == "nosniff"
    assert h["X-Frame-Options"] == "DENY"
    assert h["Referrer-Policy"] == "strict-origin-when-cross-origin"


def test_docs_closed_in_production(monkeypatch):
    """Prod'da /docs, /redoc ve /openapi.json kapalı olmalı."""
    import importlib
    import app.main as main_module

    monkeypatch.setenv("PORTLY_ENV", "production")
    monkeypatch.setenv("SECRET_KEY", "test-anahtar-yeterince-uzun-olsun-123")
    reloaded = importlib.reload(main_module)
    try:
        assert reloaded.app.docs_url is None
        assert reloaded.app.openapi_url is None
        assert reloaded.app.redoc_url is None
    finally:
        monkeypatch.delenv("PORTLY_ENV")
        importlib.reload(main_module)


# ── hesap silme (KVKK silme hakkı) ───────────────────────────────────────

def _kayit(client, email="silinecek@mail.com", password="cetrefil42"):
    r = client.post(f"{AUTH}/register", json={"email": email,
                                              "password": password})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_delete_account_requires_correct_password(client):
    """Token yetmez: geri dönüşü olmayan işlem için şifre şart."""
    hdr = _kayit(client)
    r = client.post(f"{AUTH}/delete-account",
                    json={"password": "yanlis123"}, headers=hdr)
    assert r.status_code == 400
    # Hesap duruyor
    assert client.post(f"{AUTH}/login",
                       json={"email": "silinecek@mail.com",
                             "password": "cetrefil42"}).status_code == 200


def test_delete_account_removes_user_and_all_rows(client, db):
    """Kullanıcı + portföy + işlem + izleme + token: hiçbiri kalmamalı."""
    from app.models.portfolio import Portfolio
    from app.models.transaction import Transaction
    from app.models.user import User
    from app.models.watchlist import WatchlistItem

    hdr = _kayit(client)
    uid = db.query(User).filter_by(email="silinecek@mail.com").one().id
    db.add_all([
        Portfolio(user_id=uid, symbol="THYAO.IS", quantity=10,
                  average_cost=300.0),
        Transaction(user_id=uid, symbol="THYAO.IS", transaction_type="BUY",
                    quantity=10, price=300.0),
        WatchlistItem(user_id=uid, symbol="AAPL"),
    ])
    db.commit()

    r = client.post(f"{AUTH}/delete-account",
                    json={"password": "cetrefil42"}, headers=hdr)
    assert r.status_code == 200, r.text

    assert db.query(User).filter_by(id=uid).first() is None
    assert db.query(Portfolio).filter_by(user_id=uid).count() == 0
    assert db.query(Transaction).filter_by(user_id=uid).count() == 0
    assert db.query(WatchlistItem).filter_by(user_id=uid).count() == 0


def test_deleted_account_cannot_log_in_again(client):
    hdr = _kayit(client)
    client.post(f"{AUTH}/delete-account",
                json={"password": "cetrefil42"}, headers=hdr)
    r = client.post(f"{AUTH}/login", json={"email": "silinecek@mail.com",
                                           "password": "cetrefil42"})
    assert r.status_code == 401


def test_delete_account_requires_auth(client):
    r = client.post(f"{AUTH}/delete-account", json={"password": "x"})
    assert r.status_code in (401, 403)
