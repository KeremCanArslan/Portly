"""Chat (AI sohbet) HTTP entegrasyon testleri.

`/api/v1/chat/*` auth'lu. Kilitlenen sözleşme: auth (401) + sahiplik (token≠path/
payload → 403) + mesaj doğrulama (boş/whitespace/çok-uzun) iki katmanda (pydantic
422 vs `_validate_message` 400) + SSE stream'in token/done eventleri + geçmiş
oku/sil (gerçek `chat_service` + DB). LLM stream'i mock'lu (ağ ÇAĞRILMAZ).

Çalıştırma:  cd backend && python -m pytest tests/test_chat_api.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app
from app.models.chat import ChatMessage
from app.models.user import User

CHAT = "/api/v1/chat"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _register(client, db, email="ch@mail.com", password="testpass1"):
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    uid = db.query(User).filter_by(email=email).one().id
    return {"Authorization": f"Bearer {token}"}, uid


@pytest.fixture
def fake_stream(monkeypatch):
    """LLM stream'ini deterministik iki token'la değiştir (ağ yok, DB yazmaz)."""
    def _stream(db, user_id, user_message):
        yield "Merhaba"
        yield " dünya"
    monkeypatch.setattr(
        "app.services.chat_service.stream_chat_response", _stream)


# --- POST /send: auth + sahiplik + doğrulama + stream ---------------------

def test_post_send_requires_auth(client):
    assert client.post(f"{CHAT}/send",
                       json={"user_id": 1, "message": "selam"}).status_code == 401


def test_post_send_other_user_forbidden(client, db):
    hdr, uid = _register(client, db)
    assert client.post(f"{CHAT}/send", headers=hdr, json={
        "user_id": uid + 999, "message": "selam"}).status_code == 403


def test_post_send_empty_message_422(client, db):
    # message min_length=1 → boş string pydantic 422 (router'a ulaşmaz)
    hdr, uid = _register(client, db)
    assert client.post(f"{CHAT}/send", headers=hdr, json={
        "user_id": uid, "message": ""}).status_code == 422


def test_post_send_whitespace_message_400(client, db):
    # " " pydantic'i geçer (len≥1), _validate_message strip → boş → 400
    hdr, uid = _register(client, db)
    assert client.post(f"{CHAT}/send", headers=hdr, json={
        "user_id": uid, "message": "   "}).status_code == 400


def test_post_send_streams_tokens(client, db, fake_stream):
    hdr, uid = _register(client, db)
    r = client.post(f"{CHAT}/send", headers=hdr,
                    json={"user_id": uid, "message": "portföyüm nasıl?"})
    assert r.status_code == 200
    # SSE gövdesi token + done eventlerini içerir
    assert "Merhaba" in r.text
    assert "done" in r.text


# --- GET /send: query varyantı (auth + sahiplik + 400 yolları) ------------

def test_get_send_requires_auth(client):
    assert client.get(f"{CHAT}/send", params={
        "user_id": 1, "message": "selam"}).status_code == 401


def test_get_send_other_user_forbidden(client, db):
    hdr, uid = _register(client, db)
    assert client.get(f"{CHAT}/send", headers=hdr, params={
        "user_id": uid + 999, "message": "selam"}).status_code == 403


def test_get_send_whitespace_400(client, db):
    hdr, uid = _register(client, db)
    assert client.get(f"{CHAT}/send", headers=hdr, params={
        "user_id": uid, "message": "   "}).status_code == 400


def test_get_send_too_long_400(client, db):
    # Query param'da pydantic max_length yok → _validate_message uzunluk kapısı 400
    hdr, uid = _register(client, db)
    assert client.get(f"{CHAT}/send", headers=hdr, params={
        "user_id": uid, "message": "x" * 2001}).status_code == 400


def test_get_send_streams_tokens(client, db, fake_stream):
    hdr, uid = _register(client, db)
    r = client.get(f"{CHAT}/send", headers=hdr,
                   params={"user_id": uid, "message": "merhaba"})
    assert r.status_code == 200
    # SSE data'sı json.dumps ile non-ASCII'yi escape'ler (ü→ü); ASCII
    # token + done eventi ile stream'in tam aktığını doğrula.
    assert "Merhaba" in r.text
    assert "done" in r.text


# --- GET /history/{user_id}: auth + sahiplik + boş/dolu -------------------

def test_history_requires_auth(client):
    assert client.get(f"{CHAT}/history/1").status_code == 401


def test_history_other_user_forbidden(client, db):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{CHAT}/history/{uid + 999}", headers=hdr).status_code == 403


def test_history_empty_ok(client, db):
    hdr, uid = _register(client, db)
    r = client.get(f"{CHAT}/history/{uid}", headers=hdr)
    assert r.status_code == 200
    assert r.json() == []


def test_history_returns_messages(client, db):
    hdr, uid = _register(client, db)
    db.add_all([
        ChatMessage(user_id=uid, role="user", content="soru"),
        ChatMessage(user_id=uid, role="assistant", content="cevap"),
    ])
    db.commit()
    r = client.get(f"{CHAT}/history/{uid}", headers=hdr)
    assert r.status_code == 200
    body = r.json()
    assert len(body) == 2
    assert {m["content"] for m in body} == {"soru", "cevap"}


# --- DELETE /history/{user_id}: auth + sahiplik + siler ------------------

def test_clear_history_requires_auth(client):
    assert client.delete(f"{CHAT}/history/1").status_code == 401


def test_clear_history_other_user_forbidden(client, db):
    hdr, uid = _register(client, db)
    assert client.delete(
        f"{CHAT}/history/{uid + 999}", headers=hdr).status_code == 403


def test_clear_history_deletes_and_reports_count(client, db):
    hdr, uid = _register(client, db)
    db.add_all([
        ChatMessage(user_id=uid, role="user", content="a"),
        ChatMessage(user_id=uid, role="assistant", content="b"),
    ])
    db.commit()
    r = client.delete(f"{CHAT}/history/{uid}", headers=hdr)
    assert r.status_code == 200
    assert r.json() == {"success": True, "deleted_count": 2}
    # silindikten sonra geçmiş boş
    assert client.get(f"{CHAT}/history/{uid}", headers=hdr).json() == []
