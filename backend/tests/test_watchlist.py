"""İzleme listesi (watchlist) kalıcılığı — servis + HTTP uçtan uca.

İzleme listesi kullanıcıya özel, SIRALI sembol listesi olarak saklanır (sembol
başına tek satır + position). Burada kilitlenen davranış:
- okuma position sırasına göre gelir (eklenme sırası korunur),
- add idempotent (aynı sembol iki kez eklenemez) + sembol normalize (strip+UPPER),
- remove yoksa no-op,
- replace listeyi tümüyle değiştirir → reorder + tekrar/boş eleme + tavana kırpma,
- kullanıcı izolasyonu (bir kullanıcının listesi diğerine sızmaz),
- HTTP: auth zorunlu, POST→GET→DELETE akışı, PUT reorder, tavan aşımı 413.

Çalıştırma:  cd backend && python -m pytest tests/test_watchlist.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.services import watchlist_service as svc
from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app


# ── servis: okuma / ekleme / silme / değiştirme ───────────────────────────

def test_empty_watchlist_is_empty_list(db, make_user):
    u = make_user()
    assert svc.get_watchlist(db, u.id) == []


def test_add_appends_in_order(db, make_user):
    u = make_user()
    svc.add_symbol(db, u.id, "AAPL")
    svc.add_symbol(db, u.id, "THYAO")
    svc.add_symbol(db, u.id, "BTC-USD")
    assert svc.get_watchlist(db, u.id) == ["AAPL", "THYAO", "BTC-USD"]


def test_add_is_idempotent(db, make_user):
    """Aynı sembol iki kez eklenmez (PK tekilliği), sıra bozulmaz."""
    u = make_user()
    svc.add_symbol(db, u.id, "AAPL")
    svc.add_symbol(db, u.id, "THYAO")
    svc.add_symbol(db, u.id, "AAPL")  # tekrar
    assert svc.get_watchlist(db, u.id) == ["AAPL", "THYAO"]


def test_add_normalizes_symbol(db, make_user):
    """' aapl ' ile eklenir, 'AAPL' olarak okunur; tekrar normalize tekildir."""
    u = make_user()
    svc.add_symbol(db, u.id, " aapl ")
    svc.add_symbol(db, u.id, "AAPL")
    assert svc.get_watchlist(db, u.id) == ["AAPL"]


def test_add_ignores_empty(db, make_user):
    u = make_user()
    svc.add_symbol(db, u.id, "   ")
    assert svc.get_watchlist(db, u.id) == []


def test_remove_symbol(db, make_user):
    u = make_user()
    svc.add_symbol(db, u.id, "AAPL")
    svc.add_symbol(db, u.id, "THYAO")
    assert svc.remove_symbol(db, u.id, "aapl") == ["THYAO"]  # normalize ile siler
    assert svc.remove_symbol(db, u.id, "YOK") == ["THYAO"]   # yoksa no-op


def test_replace_reorders_and_dedupes(db, make_user):
    u = make_user()
    svc.add_symbol(db, u.id, "AAPL")
    svc.add_symbol(db, u.id, "THYAO")
    # reorder + tekrar + boş + küçük harf karışık
    out = svc.replace_watchlist(db, u.id, ["thyao", "AAPL", "THYAO", "", "msft"])
    assert out == ["THYAO", "AAPL", "MSFT"]


def test_replace_with_empty_clears(db, make_user):
    u = make_user()
    svc.add_symbol(db, u.id, "AAPL")
    assert svc.replace_watchlist(db, u.id, []) == []


def test_max_symbols_guard(db, make_user):
    """Tavan dolunca add sessiz no-op (liste büyümez)."""
    u = make_user()
    full = [f"SYM{i}" for i in range(svc.MAX_SYMBOLS)]
    svc.replace_watchlist(db, u.id, full)
    assert len(svc.get_watchlist(db, u.id)) == svc.MAX_SYMBOLS
    svc.add_symbol(db, u.id, "EXTRA")
    assert len(svc.get_watchlist(db, u.id)) == svc.MAX_SYMBOLS
    assert "EXTRA" not in svc.get_watchlist(db, u.id)


def test_isolated_per_user(db, make_user):
    u1, u2 = make_user(), make_user()
    svc.add_symbol(db, u1.id, "AAPL")
    assert svc.get_watchlist(db, u1.id) == ["AAPL"]
    assert svc.get_watchlist(db, u2.id) == []  # diğer kullanıcıya sızmaz


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


def _auth(client, email="wl@mail.com"):
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": "testpass1"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_get_requires_auth(client):
    assert client.get("/api/v1/watchlist").status_code == 401


def test_add_get_delete_flow(client):
    hdr = _auth(client)

    # Başta boş.
    r0 = client.get("/api/v1/watchlist", headers=hdr)
    assert r0.status_code == 200 and r0.json()["symbols"] == []

    # POST ekle (normalize + idempotent).
    assert client.post("/api/v1/watchlist/aapl", headers=hdr).json()["symbols"] == ["AAPL"]
    assert client.post("/api/v1/watchlist/THYAO", headers=hdr).json()["symbols"] == ["AAPL", "THYAO"]
    assert client.post("/api/v1/watchlist/AAPL", headers=hdr).json()["symbols"] == ["AAPL", "THYAO"]

    # GET geri okur.
    assert client.get("/api/v1/watchlist", headers=hdr).json()["symbols"] == ["AAPL", "THYAO"]

    # DELETE çıkarır.
    assert client.delete("/api/v1/watchlist/AAPL", headers=hdr).json()["symbols"] == ["THYAO"]


def test_put_replace_reorder(client):
    hdr = _auth(client, "wl2@mail.com")
    client.post("/api/v1/watchlist/AAPL", headers=hdr)
    client.post("/api/v1/watchlist/THYAO", headers=hdr)
    r = client.put("/api/v1/watchlist", headers=hdr,
                   json={"symbols": ["THYAO", "MSFT", "AAPL"]})
    assert r.status_code == 200
    assert r.json()["symbols"] == ["THYAO", "MSFT", "AAPL"]


def test_put_too_long_413(client):
    hdr = _auth(client, "wl3@mail.com")
    big = [f"SYM{i}" for i in range(svc.MAX_SYMBOLS + 1)]
    r = client.put("/api/v1/watchlist", headers=hdr, json={"symbols": big})
    assert r.status_code == 413


def test_watchlist_isolated_per_user_http(client):
    h1 = _auth(client, "wl-a@mail.com")
    h2 = _auth(client, "wl-b@mail.com")
    client.post("/api/v1/watchlist/AAPL", headers=h1)
    assert client.get("/api/v1/watchlist", headers=h2).json()["symbols"] == []
    assert client.get("/api/v1/watchlist", headers=h1).json()["symbols"] == ["AAPL"]
