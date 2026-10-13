"""Portföy screenshot yükleme sertleştirme — bayt-temelli görsel doğrulama.

content_type başlığı client'tan gelir ve sahtelenebilir; güvenlik kararı
baytların gerçekten decode olmasına dayanmalı (aksi halde sahte content_type'lı
zararlı/bozuk yük doğrudan AI vision'a gider). verify_image bunu kapatır;
endpoint geçersiz görseli 415 ile, boş/oversized'ı 400/413 ile reddeder.

parse-screenshot mutlu yolu LLM'e (ağ) gider → 200 testinde parse_screenshot
mock'lanır; doğrulama (verify_image) gerçek koşar.

Çalıştırma:  cd backend && pytest -q
"""

import pytest
from io import BytesIO
from PIL import Image
from fastapi.testclient import TestClient

from app.services import screenshot_import_service as ss
from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app

URL = "/api/v1/trading/parse-screenshot"


def _img(fmt: str = "PNG", size=(8, 8), color="red") -> bytes:
    buf = BytesIO()
    Image.new("RGB", size, color).save(buf, format=fmt)
    return buf.getvalue()


# ── verify_image: bayt-temelli doğrulama ──────────────────────────────────

@pytest.mark.parametrize("fmt", ["PNG", "JPEG", "WEBP"])
def test_verify_image_accepts_allowed_formats(fmt):
    assert ss.verify_image(_img(fmt)) == fmt


def test_verify_image_rejects_non_image():
    with pytest.raises(ValueError):
        ss.verify_image(b"this is definitely not an image")


def test_verify_image_rejects_disallowed_format():
    """GIF gerçek görsel ama izinli set dışında → reddedilir."""
    with pytest.raises(ValueError):
        ss.verify_image(_img("GIF"))


def test_verify_image_rejects_empty():
    with pytest.raises(ValueError):
        ss.verify_image(b"")


# ── HTTP endpoint: yetki + doğrulama reddi + mutlu yol ────────────────────

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
                    json={"email": "ss@mail.com", "password": "testpass1"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_upload_requires_auth(client):
    r = client.post(URL, files={"file": ("p.png", _img(), "image/png")})
    assert r.status_code == 401


def test_upload_rejects_spoofed_content_type(client):
    """content_type image/png ama baytlar görsel değil → 415 (Pillow gate)."""
    hdr = _auth(client)
    r = client.post(URL, headers=hdr,
                    files={"file": ("evil.png", b"#!/bin/sh\nrm -rf /", "image/png")})
    assert r.status_code == 415


def test_upload_rejects_empty_file(client):
    hdr = _auth(client)
    r = client.post(URL, headers=hdr,
                    files={"file": ("empty.png", b"", "image/png")})
    assert r.status_code == 400


def test_upload_accepts_valid_image(client, monkeypatch):
    """Gerçek PNG → verify_image geçer → parse_screenshot (mock) çağrılır → 200."""
    hdr = _auth(client)
    monkeypatch.setattr(
        "app.services.screenshot_import_service.parse_screenshot",
        lambda image_bytes, mime_type: {"positions": []})
    r = client.post(URL, headers=hdr,
                    files={"file": ("ok.png", _img(), "image/png")})
    assert r.status_code == 200
    assert r.json() == {"positions": []}
