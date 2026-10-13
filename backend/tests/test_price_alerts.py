"""Fiyat alarmı tetik mantığı + uygulama-içi teslimat (okunmamış sayacı).

Alarm tetik koşulu (ABOVE/BELOW) demoda görünür bir özellik; yanlışsa kullanıcı
yanlış seviyede uyarılır. E-posta teslimatı (SMTP) demoda yapılandırılmadığından
asıl teslimat kanalı uygulama-içi rozet (count_unseen_triggered) → onu da kilitleriz.

check_and_fire_alerts KENDİ SessionLocal'ını açar → test session'ına yönlendirilir
(close no-op'lanır, fixture sahibi kapatır). get_stock_data conftest `market`
fixture'ında price_alert_service ad alanında da patch'lenir (ağ yok).

Çalıştırma:  cd backend && pytest -q
"""

import pytest
from datetime import datetime, timezone
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.services import price_alert_service as svc
from app.models.price_alert import PriceAlert
from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app


# ── create_alert: doğrulama ───────────────────────────────────────────────

def test_create_alert_defaults(db, make_user):
    user = make_user()
    a = svc.create_alert(db, user.id, "aapl", 150.0, "ABOVE")
    assert a.symbol == "AAPL"               # upper'a normalize
    assert a.active is True
    assert a.acknowledged is False
    assert a.triggered_at is None


def test_create_alert_rejects_bad_threshold(db, make_user):
    user = make_user()
    with pytest.raises(HTTPException) as ei:
        svc.create_alert(db, user.id, "AAPL", 0, "ABOVE")
    assert ei.value.status_code == 400


def test_create_alert_rejects_bad_direction(db, make_user):
    user = make_user()
    with pytest.raises(HTTPException) as ei:
        svc.create_alert(db, user.id, "AAPL", 100.0, "SIDEWAYS")
    assert ei.value.status_code == 400


def test_delete_other_users_alert_forbidden(db, make_user):
    u1, u2 = make_user(), make_user()
    a = svc.create_alert(db, u1.id, "AAPL", 100.0, "ABOVE")
    with pytest.raises(HTTPException) as ei:
        svc.delete_alert(db, a.id, u2.id)
    assert ei.value.status_code == 403


# ── check_and_fire_alerts: tetik koşulu ───────────────────────────────────

def _redirect_session(db, monkeypatch):
    """Worker'ın açtığı SessionLocal'ı test session'ına yönlendir."""
    monkeypatch.setattr(db, "close", lambda: None)
    monkeypatch.setattr("app.services.price_alert_service.SessionLocal", lambda: db)


def test_above_triggers_and_deactivates(db, market, make_user, monkeypatch):
    """Cari (150) ≥ eşik (150, sınır dahil) → tetiklenir, pasifleşir, fiyat yazılır."""
    market.set_price("AAPL", 150.0)
    user = make_user()
    svc.create_alert(db, user.id, "AAPL", 150.0, "ABOVE", notify_email=False)
    _redirect_session(db, monkeypatch)

    fired = svc.check_and_fire_alerts()

    assert fired == 1
    db.expire_all()
    a = db.query(PriceAlert).filter_by(user_id=user.id).one()
    assert a.active is False
    assert a.triggered_price == pytest.approx(150.0)
    assert a.triggered_at is not None


def test_below_triggers(db, market, make_user, monkeypatch):
    """Cari (80) ≤ eşik (100) → BELOW tetiklenir."""
    market.set_price("AAPL", 80.0)
    user = make_user()
    svc.create_alert(db, user.id, "AAPL", 100.0, "BELOW", notify_email=False)
    _redirect_session(db, monkeypatch)

    assert svc.check_and_fire_alerts() == 1


def test_above_not_triggered_when_below_threshold(db, market, make_user, monkeypatch):
    """Cari (90) < eşik (100) → ABOVE tetiklenmez; alarm aktif kalır."""
    market.set_price("AAPL", 90.0)
    user = make_user()
    svc.create_alert(db, user.id, "AAPL", 100.0, "ABOVE", notify_email=False)
    _redirect_session(db, monkeypatch)

    assert svc.check_and_fire_alerts() == 0
    db.expire_all()
    assert db.query(PriceAlert).filter_by(user_id=user.id).one().active is True


def test_already_triggered_not_refired(db, market, make_user, monkeypatch):
    """Tetiklenip pasifleşen alarm ikinci turda yeniden tetiklenmez (idempotent)."""
    market.set_price("AAPL", 150.0)
    user = make_user()
    svc.create_alert(db, user.id, "AAPL", 150.0, "ABOVE", notify_email=False)
    _redirect_session(db, monkeypatch)

    assert svc.check_and_fire_alerts() == 1
    assert svc.check_and_fire_alerts() == 0      # aktif değil → atlanır


def test_email_sent_when_notify_enabled(db, market, make_user, monkeypatch):
    """notify_email=True → tetiklenince _send_alert_email çağrılır (SMTP mock'lu)."""
    market.set_price("AAPL", 150.0)
    user = make_user()
    svc.create_alert(db, user.id, "AAPL", 150.0, "ABOVE", notify_email=True)
    _redirect_session(db, monkeypatch)

    calls = []
    monkeypatch.setattr(
        "app.services.price_alert_service._send_alert_email",
        lambda **kw: calls.append(kw) or True)

    svc.check_and_fire_alerts()
    assert len(calls) == 1
    assert calls[0]["to_email"] == user.email
    assert calls[0]["symbol"] == "AAPL"


def test_email_not_sent_when_notify_disabled(db, market, make_user, monkeypatch):
    market.set_price("AAPL", 150.0)
    user = make_user()
    svc.create_alert(db, user.id, "AAPL", 150.0, "ABOVE", notify_email=False)
    _redirect_session(db, monkeypatch)

    calls = []
    monkeypatch.setattr(
        "app.services.price_alert_service._send_alert_email",
        lambda **kw: calls.append(kw) or True)

    svc.check_and_fire_alerts()
    assert calls == []


# ── uygulama-içi teslimat: okunmamış sayacı + görüldü işaretle ────────────

def test_unseen_count_lifecycle(db, market, make_user, monkeypatch):
    """Aktif alarm sayılmaz → tetik sonrası 1 → mark_seen sonrası 0."""
    market.set_price("AAPL", 150.0)
    user = make_user()
    svc.create_alert(db, user.id, "AAPL", 150.0, "ABOVE", notify_email=False)

    # Henüz tetiklenmemiş (aktif) alarm okunmamış sayılmaz.
    assert svc.count_unseen_triggered(db, user.id) == 0

    _redirect_session(db, monkeypatch)
    svc.check_and_fire_alerts()
    assert svc.count_unseen_triggered(db, user.id) == 1

    assert svc.mark_alerts_seen(db, user.id) == 1
    assert svc.count_unseen_triggered(db, user.id) == 0


def test_unseen_count_isolated_per_user(db, market, make_user, monkeypatch):
    """Bir kullanıcının tetiklenen alarmı diğerinin sayacına sızmaz."""
    market.set_price("AAPL", 150.0)
    u1, u2 = make_user(), make_user()
    svc.create_alert(db, u1.id, "AAPL", 150.0, "ABOVE", notify_email=False)
    _redirect_session(db, monkeypatch)
    svc.check_and_fire_alerts()

    assert svc.count_unseen_triggered(db, u1.id) == 1
    assert svc.count_unseen_triggered(db, u2.id) == 0


# ── HTTP entegrasyon: uçtan uca rozet akışı ───────────────────────────────

@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _auth(client):
    r = client.post("/api/v1/auth/register",
                    json={"email": "al@mail.com", "password": "testpass1"})
    token = r.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_unseen_count_requires_auth(client):
    assert client.get("/api/v1/alerts/unseen-count").status_code == 401


def test_http_unseen_count_and_mark_seen_flow(client, db):
    """create → 0 okunmamış → (DB'de tetiklendi simüle) → 1 → mark-seen → 0."""
    hdr = _auth(client)
    created = client.post("/api/v1/alerts", headers=hdr, json={
        "symbol": "AAPL", "threshold_price": 150.0, "direction": "ABOVE",
        "notify_email": False,
    })
    assert created.status_code == 200
    alert_id = created.json()["id"]

    # Yeni (aktif) alarm okunmamış değil.
    assert client.get("/api/v1/alerts/unseen-count", headers=hdr).json()["count"] == 0

    # Worker'ı çağırmadan tetik durumunu DB'de simüle et (ağ yok).
    a = db.query(PriceAlert).filter_by(id=alert_id).one()
    a.active = False
    a.triggered_at = datetime.now(timezone.utc)
    a.triggered_price = 152.0
    db.commit()

    assert client.get("/api/v1/alerts/unseen-count", headers=hdr).json()["count"] == 1

    marked = client.post("/api/v1/alerts/mark-seen", headers=hdr)
    assert marked.status_code == 200 and marked.json()["marked"] == 1
    assert client.get("/api/v1/alerts/unseen-count", headers=hdr).json()["count"] == 0
