"""Auth HTTP integration testleri — FastAPI TestClient ile uçtan uca kimlik akışı.

register → login → korumalı /me → refresh (rotation) → logout (blacklist) zinciri;
demo'nun EN kritik kullanıcı yolu (login bozulursa her şey biter). get_db,
conftest'in bellek-içi oturumuna override edilir; TestClient `with`SİZ kullanılır
→ lifespan/prewarm (yfinance ağ) HİÇ koşmaz. Rate limiter testte kapatılır
(register 5/dk limiti integration akışını bozmasın).

Çalıştırma:  cd backend && pytest -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app

AUTH = "/api/v1/auth"


@pytest.fixture
def client(db):
    """get_db → test oturumu; limiter kapalı; lifespan koşmaz (with yok)."""
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _register(client, email="api@mail.com", password="testpass1"):
    return client.post(
        f"{AUTH}/register", json={"email": email, "password": password})


# ── register ─────────────────────────────────────────────────────────────

def test_register_returns_token_and_user(client):
    """Kayıt → 200 + access/refresh token + kullanıcı bilgisi."""
    r = _register(client)
    assert r.status_code == 200
    body = r.json()
    assert body["access_token"] and body["refresh_token"]
    assert body["token_type"] == "bearer"
    assert body["user"]["email"] == "api@mail.com"
    # Pivot: sanal bakiye kalktı → user yanıtında balance alanı YOK
    assert "balance" not in body["user"]


def test_register_duplicate_rejected(client):
    """Aynı e-posta ikinci kez → 400."""
    _register(client)
    assert _register(client).status_code == 400


# ── login ────────────────────────────────────────────────────────────────

def test_login_success(client):
    _register(client, "u1@mail.com", "rightpass")
    r = client.post(
        f"{AUTH}/login", json={"email": "u1@mail.com", "password": "rightpass"})
    assert r.status_code == 200 and r.json()["access_token"]


def test_login_wrong_password_401(client):
    _register(client, "u2@mail.com", "rightpass")
    r = client.post(
        f"{AUTH}/login", json={"email": "u2@mail.com", "password": "wrongpass"})
    assert r.status_code == 401


def test_login_unknown_email_401(client):
    r = client.post(
        f"{AUTH}/login", json={"email": "ghost@mail.com", "password": "x12345"})
    assert r.status_code == 401


# ── /me (korumalı) ───────────────────────────────────────────────────────

def test_me_without_token_401(client):
    """Auth header yoksa 401 (kimlik yok — garbage-token ile tutarlı)."""
    assert client.get(f"{AUTH}/me").status_code == 401


def test_me_with_token(client):
    token = _register(client, "me@mail.com").json()["access_token"]
    r = client.get(f"{AUTH}/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200 and r.json()["email"] == "me@mail.com"


def test_me_garbage_token_401(client):
    """Geçersiz JWT → get_current_user 401 (header var, decode fail)."""
    r = client.get(
        f"{AUTH}/me", headers={"Authorization": "Bearer not.a.jwt"})
    assert r.status_code == 401


# ── refresh rotation ─────────────────────────────────────────────────────

def test_refresh_returns_new_access(client):
    refresh = _register(client, "rf@mail.com").json()["refresh_token"]
    r = client.post(f"{AUTH}/refresh", json={"refresh_token": refresh})
    assert r.status_code == 200 and r.json()["access_token"]


def test_refresh_single_use(client):
    """Rotation: aynı refresh token ikinci kez → 401."""
    refresh = _register(client, "rf2@mail.com").json()["refresh_token"]
    client.post(f"{AUTH}/refresh", json={"refresh_token": refresh})        # 1.
    r = client.post(f"{AUTH}/refresh", json={"refresh_token": refresh})    # 2.
    assert r.status_code == 401


# ── logout (blacklist + uçtan uca) ───────────────────────────────────────

def test_logout_blacklists_token(client):
    """logout sonrası aynı access token /me → 401 (blacklist)."""
    token = _register(client, "lo@mail.com").json()["access_token"]
    hdr = {"Authorization": f"Bearer {token}"}
    assert client.get(f"{AUTH}/me", headers=hdr).status_code == 200
    assert client.post(f"{AUTH}/logout", headers=hdr).status_code == 200
    assert client.get(f"{AUTH}/me", headers=hdr).status_code == 401


def test_full_auth_flow(client):
    """register → login → /me → refresh → logout uçtan uca yeşil."""
    assert _register(client, "flow@mail.com", "flowpass1").status_code == 200
    login = client.post(
        f"{AUTH}/login", json={"email": "flow@mail.com", "password": "flowpass1"})
    assert login.status_code == 200
    access, refresh = login.json()["access_token"], login.json()["refresh_token"]
    hdr = {"Authorization": f"Bearer {access}"}
    assert client.get(f"{AUTH}/me", headers=hdr).json()["email"] == "flow@mail.com"
    assert client.post(
        f"{AUTH}/refresh", json={"refresh_token": refresh}).status_code == 200
    assert client.post(f"{AUTH}/logout", headers=hdr).status_code == 200


# ── şifre değiştirme (oturum açıkken) ────────────────────────────────────
# Canlı geri bildirim: "şifreyi sonradan değiştirebilme yok sanırım".
# E-posta kodu yolu (forgot/reset) Brevo anahtarını bekliyor; bu yol
# oturum açık kullanıcı için ondan bağımsız çalışır.

def _login(client, email="api@mail.com", password="testpass1"):
    return client.post(f"{AUTH}/login",
                       json={"email": email, "password": password})


def test_change_password_then_login_with_new_one(client):
    """Doğru mevcut şifreyle değişir; yeni şifreyle giriş yapılır, eskisiyle olmaz."""
    token = _register(client).json()["access_token"]
    r = client.post(f"{AUTH}/change-password",
                    json={"current_password": "testpass1",
                          "new_password": "yenisifre9"},
                    headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 200
    # Bu cihaz dışarı düşmesin diye taze refresh token dönmeli
    assert r.json()["refresh_token"]

    assert _login(client, password="yenisifre9").status_code == 200
    assert _login(client, password="testpass1").status_code == 401


def test_change_password_wrong_current_rejected(client):
    """Mevcut şifre yanlışsa 400 — token çalınmışsa hesap ele geçirilemesin."""
    token = _register(client).json()["access_token"]
    r = client.post(f"{AUTH}/change-password",
                    json={"current_password": "yanlis123",
                          "new_password": "yenisifre9"},
                    headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 400
    assert _login(client, password="testpass1").status_code == 200


def test_change_password_requires_auth(client):
    """Token'sız istek 401/403 — herkese açık uç değil."""
    r = client.post(f"{AUTH}/change-password",
                    json={"current_password": "a", "new_password": "bbbbbb"})
    assert r.status_code in (401, 403)


def test_change_password_revokes_other_devices(client):
    """Eski refresh token'lar iptal: başka cihazdaki oturum düşsün."""
    body = _register(client).json()
    eski_refresh = body["refresh_token"]
    r = client.post(f"{AUTH}/change-password",
                    json={"current_password": "testpass1",
                          "new_password": "yenisifre9"},
                    headers={"Authorization": f"Bearer {body['access_token']}"})
    yeni_refresh = r.json()["refresh_token"]

    assert client.post(f"{AUTH}/refresh",
                       json={"refresh_token": eski_refresh}).status_code == 401
    assert client.post(f"{AUTH}/refresh",
                       json={"refresh_token": yeni_refresh}).status_code == 200
