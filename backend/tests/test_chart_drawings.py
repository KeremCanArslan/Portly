"""Grafik çizim kalıcılığı — servis upsert/okuma/silme + HTTP uçtan uca.

Çizimler kullanıcıya özel ve sembol başına tek JSON blob olarak saklanır
(timestamp-bazlı; bkz. app.models.chart_drawing). Burada kilitlenen davranış:
- upsert (sembol başına TEK satır, ikinci kayıt birinciyi ezer),
- sembol normalizasyonu (strip + UPPER) → "aapl" ile "AAPL" aynı satır,
- kullanıcı izolasyonu (bir kullanıcının çizimi diğerine sızmaz),
- HTTP: auth zorunlu, PUT→GET→DELETE akışı, boş sembol {} döner, boyut sınırı 413.

Çalıştırma:  cd backend && pytest -q
"""

import pytest
from fastapi.testclient import TestClient

from app.services import chart_drawing_service as svc
from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app


# Örnek timestamp-bazlı payload (frontend'in yazacağı şekle yakın).
_SAMPLE = {
    "v": 1,
    "hlines": [150.0, 175.5],
    "trends": [{"ta": 1700000000, "pa": 100.0, "tb": 1700600000, "pb": 120.0}],
    "hrays": [{"t": 1700000000, "p": 99.0}],
    "vlines": [1700300000],
    "notes": [{"t": 1700300000, "p": 110.0, "text": "kırılım"}],
}


# ── servis: upsert / okuma / silme ────────────────────────────────────────

def test_save_and_get_roundtrip(db, make_user):
    u = make_user()
    svc.save_drawings(db, u.id, "AAPL", _SAMPLE)
    assert svc.get_drawings(db, u.id, "AAPL") == _SAMPLE


def test_get_missing_returns_none(db, make_user):
    u = make_user()
    assert svc.get_drawings(db, u.id, "AAPL") is None


def test_save_is_upsert_single_row(db, make_user):
    """İkinci kayıt birinciyi ezer (sembol başına tek satır)."""
    from app.models.chart_drawing import ChartDrawing
    u = make_user()
    svc.save_drawings(db, u.id, "AAPL", {"v": 1, "hlines": [1.0]})
    svc.save_drawings(db, u.id, "AAPL", {"v": 1, "hlines": [2.0, 3.0]})
    assert svc.get_drawings(db, u.id, "AAPL") == {"v": 1, "hlines": [2.0, 3.0]}
    assert db.query(ChartDrawing).filter_by(user_id=u.id).count() == 1


def test_symbol_normalized_to_upper(db, make_user):
    """'aapl' ile yazıp 'AAPL' ile (ve tersi) okuyabilmeli."""
    u = make_user()
    svc.save_drawings(db, u.id, " aapl ", _SAMPLE)
    assert svc.get_drawings(db, u.id, "AAPL") == _SAMPLE
    assert svc.get_drawings(db, u.id, "aapl") == _SAMPLE


def test_delete_returns_true_then_false(db, make_user):
    u = make_user()
    svc.save_drawings(db, u.id, "AAPL", _SAMPLE)
    assert svc.delete_drawings(db, u.id, "AAPL") is True
    assert svc.get_drawings(db, u.id, "AAPL") is None
    assert svc.delete_drawings(db, u.id, "AAPL") is False  # zaten yok


def test_isolated_per_user(db, make_user):
    u1, u2 = make_user(), make_user()
    svc.save_drawings(db, u1.id, "AAPL", _SAMPLE)
    assert svc.get_drawings(db, u1.id, "AAPL") == _SAMPLE
    assert svc.get_drawings(db, u2.id, "AAPL") is None  # diğer kullanıcıya sızmaz


# ── HTTP entegrasyon ──────────────────────────────────────────────────────

@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _auth(client, email="cd@mail.com"):
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": "testpass1"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_get_requires_auth(client):
    assert client.get("/api/v1/chart/drawings/AAPL").status_code == 401


def test_put_get_delete_flow(client):
    hdr = _auth(client)

    # Kayıt yokken boş {} döner.
    r0 = client.get("/api/v1/chart/drawings/AAPL", headers=hdr)
    assert r0.status_code == 200 and r0.json()["payload"] == {}

    # PUT upsert.
    put = client.put("/api/v1/chart/drawings/aapl", headers=hdr,
                     json={"payload": _SAMPLE})
    assert put.status_code == 200
    assert put.json()["symbol"] == "AAPL"        # normalize
    assert put.json()["payload"] == _SAMPLE

    # GET geri okur.
    got = client.get("/api/v1/chart/drawings/AAPL", headers=hdr)
    assert got.json()["payload"] == _SAMPLE

    # DELETE temizler → tekrar boş.
    dele = client.delete("/api/v1/chart/drawings/AAPL", headers=hdr)
    assert dele.status_code == 200 and dele.json()["deleted"] is True
    assert client.get("/api/v1/chart/drawings/AAPL", headers=hdr).json()["payload"] == {}


def test_payload_too_large_413(client):
    hdr = _auth(client)
    big = {"blob": "x" * (256 * 1024 + 16)}
    r = client.put("/api/v1/chart/drawings/AAPL", headers=hdr,
                   json={"payload": big})
    assert r.status_code == 413


def test_drawings_isolated_per_user_http(client):
    h1 = _auth(client, "cd1@mail.com")
    h2 = _auth(client, "cd2@mail.com")
    client.put("/api/v1/chart/drawings/AAPL", headers=h1,
               json={"payload": _SAMPLE})
    # İkinci kullanıcı aynı sembolde kendi (boş) setini görür.
    assert client.get("/api/v1/chart/drawings/AAPL", headers=h2).json()["payload"] == {}
    assert client.get("/api/v1/chart/drawings/AAPL", headers=h1).json()["payload"] == _SAMPLE
