"""Yatırımcı günlüğü (not alma) — servis + HTTP uçtan uca.

Not kullanıcıya özel; bir hisseye bağlı (symbol) ya da serbest (symbol=None →
genel günlük) olabilir. Kilitlenen davranış:
- liste en yeni önce gelir (created_at DESC, id tie-break),
- symbol filtresi yalnız o hisseyi döner; filtresiz tüm notlar (genel dâhil),
- sembol normalize (strip+UPPER, boş→None),
- içerik iki-katman doğrulama: boş ""→422 (pydantic) · yalnız-boşluk "   "→400 (servis),
- sahiplik: başka kullanıcının notu güncellenemez/silinemez (404),
- kullanıcı izolasyonu (bir kullanıcının notu diğerine sızmaz),
- HTTP: auth zorunlu, POST→GET→PUT→DELETE akışı.

Çalıştırma:  cd backend && python -m pytest tests/test_notes.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.services import note_service as svc
from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app


# ── servis: oluştur / listele / güncelle / sil ────────────────────────────

def test_create_and_list_symbol_and_general(db, make_user):
    u = make_user()
    svc.create_note(db, u.id, "THY iyi gidiyor", symbol="THYAO")
    svc.create_note(db, u.id, "Bugün sabırlı olmalıyım")  # genel (symbol=None)
    all_notes = svc.list_notes(db, u.id)
    assert len(all_notes) == 2
    # symbol filtresi yalnız o hisseyi döner
    thyao = svc.list_notes(db, u.id, symbol="thyao")  # normalize ile bulur
    assert [n.content for n in thyao] == ["THY iyi gidiyor"]
    assert thyao[0].symbol == "THYAO"


def test_list_newest_first(db, make_user):
    u = make_user()
    a = svc.create_note(db, u.id, "ilk")
    b = svc.create_note(db, u.id, "ikinci")
    c = svc.create_note(db, u.id, "üçüncü")
    ids = [n.id for n in svc.list_notes(db, u.id)]
    assert ids == [c.id, b.id, a.id]  # en yeni önce


def test_symbol_normalized_and_blank_is_general(db, make_user):
    u = make_user()
    n1 = svc.create_note(db, u.id, "x", symbol=" aapl ")
    n2 = svc.create_note(db, u.id, "y", symbol="   ")  # boş → genel
    assert n1.symbol == "AAPL"
    assert n2.symbol is None


def test_empty_content_rejected(db, make_user):
    u = make_user()
    with pytest.raises(ValueError):
        svc.create_note(db, u.id, "   ")  # yalnız boşluk


def test_too_long_content_rejected(db, make_user):
    u = make_user()
    with pytest.raises(ValueError):
        svc.create_note(db, u.id, "a" * (svc.MAX_CONTENT_LEN + 1))


def test_update_content(db, make_user):
    u = make_user()
    n = svc.create_note(db, u.id, "eski")
    updated = svc.update_note(db, u.id, n.id, "yeni")
    assert updated is not None and updated.content == "yeni"


def test_update_other_user_returns_none(db, make_user):
    u1, u2 = make_user(), make_user()
    n = svc.create_note(db, u1.id, "u1 notu")
    assert svc.update_note(db, u2.id, n.id, "ele geçirme") is None  # sahiplik
    assert svc.list_notes(db, u1.id)[0].content == "u1 notu"       # değişmedi


def test_delete_and_ownership(db, make_user):
    u1, u2 = make_user(), make_user()
    n = svc.create_note(db, u1.id, "silinecek")
    assert svc.delete_note(db, u2.id, n.id) is False   # başkası silemez
    assert svc.delete_note(db, u1.id, n.id) is True     # sahibi siler
    assert svc.delete_note(db, u1.id, n.id) is False    # ikinci kez yok


def test_isolated_per_user(db, make_user):
    u1, u2 = make_user(), make_user()
    svc.create_note(db, u1.id, "u1")
    assert len(svc.list_notes(db, u1.id)) == 1
    assert svc.list_notes(db, u2.id) == []  # diğer kullanıcıya sızmaz


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


def _auth(client, email="note@mail.com"):
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": "testpass1"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_list_requires_auth(client):
    assert client.get("/api/v1/notes").status_code == 401


def test_create_get_update_delete_flow(client):
    hdr = _auth(client)

    # Başta boş.
    assert client.get("/api/v1/notes", headers=hdr).json() == []

    # Oluştur (hisseye bağlı).
    r = client.post("/api/v1/notes", headers=hdr,
                    json={"content": "THY hedef 400", "symbol": "thyao"})
    assert r.status_code == 200
    note = r.json()
    assert note["symbol"] == "THYAO" and note["content"] == "THY hedef 400"
    nid = note["id"]

    # Genel günlük girdisi (symbol yok).
    client.post("/api/v1/notes", headers=hdr, json={"content": "Disiplinli kal"})

    # Listele: ikisi de, en yeni önce.
    alln = client.get("/api/v1/notes", headers=hdr).json()
    assert len(alln) == 2 and alln[0]["content"] == "Disiplinli kal"

    # symbol filtresi.
    only = client.get("/api/v1/notes?symbol=THYAO", headers=hdr).json()
    assert len(only) == 1 and only[0]["id"] == nid

    # Güncelle.
    up = client.put(f"/api/v1/notes/{nid}", headers=hdr,
                    json={"content": "THY hedef 450"})
    assert up.status_code == 200 and up.json()["content"] == "THY hedef 450"

    # Sil.
    assert client.delete(f"/api/v1/notes/{nid}", headers=hdr).json() == {"deleted": True}
    assert len(client.get("/api/v1/notes", headers=hdr).json()) == 1


def test_empty_content_422(client):
    hdr = _auth(client, "note2@mail.com")
    # "" → pydantic min_length 422
    assert client.post("/api/v1/notes", headers=hdr,
                       json={"content": ""}).status_code == 422
    # "   " → pydantic geçer (min_length=1) ama servis strip→400
    assert client.post("/api/v1/notes", headers=hdr,
                       json={"content": "   "}).status_code == 400


def test_update_delete_nonexistent_404(client):
    hdr = _auth(client, "note3@mail.com")
    assert client.put("/api/v1/notes/999999", headers=hdr,
                      json={"content": "x"}).status_code == 404
    assert client.delete("/api/v1/notes/999999", headers=hdr).status_code == 404


def test_notes_isolated_per_user_http(client):
    h1 = _auth(client, "note-a@mail.com")
    h2 = _auth(client, "note-b@mail.com")
    r = client.post("/api/v1/notes", headers=h1, json={"content": "u1 gizli"})
    nid = r.json()["id"]
    # u2 u1'in notunu göremez / güncelleyemez / silemez.
    assert client.get("/api/v1/notes", headers=h2).json() == []
    assert client.put(f"/api/v1/notes/{nid}", headers=h2,
                      json={"content": "ele geçir"}).status_code == 404
    assert client.delete(f"/api/v1/notes/{nid}", headers=h2).status_code == 404
