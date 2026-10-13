"""News (haber) HTTP entegrasyon testleri.

`/api/v1/news/*` GİRİŞ İSTER (üç uç da LLM/RSS zincirini tetikliyor, kimliksiz
erişim LLM kotasını yakardı). Kilitlenen sözleşme: token'sız istek 401;
`/analyze` gövde doğrulaması (pydantic min_length → 422) + mutlu yol; `/latest`
response_model (`List[NewsResponse]`) şema uyumu (boş + dolu) ve `query`
parametresinin servise geçişi. LLM/RSS servisleri mock'lu — ağ ÇAĞRILMAZ.

Çalıştırma:  cd backend && python -m pytest tests/test_news_api.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app

NEWS = "/api/v1/news"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


@pytest.fixture
def hdr(client):
    """Haber uçları auth'lu → her istek Bearer token taşır."""
    r = client.post("/api/v1/auth/register",
                    json={"email": "news@mail.com", "password": "testpass1"})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_news_endpoints_require_auth(client):
    """Token'sız istek 401 — LLM kotası kimliksiz tüketilemez."""
    assert client.post(f"{NEWS}/analyze",
                       json={"title": "Fed faiz kararı"}).status_code == 401
    assert client.get(f"{NEWS}/latest").status_code == 401
    assert client.get(f"{NEWS}/for-symbols?q=AAPL").status_code == 401


# --- /analyze: gövde doğrulama + mutlu yol --------------------------------

def test_analyze_rejects_short_title(client, hdr):
    # title min_length=3 → pydantic 422 (servise hiç ulaşmaz)
    assert client.post(f"{NEWS}/analyze", headers=hdr,
                       json={"title": "ab"}).status_code == 422


def test_analyze_rejects_missing_title(client, hdr):
    assert client.post(f"{NEWS}/analyze", headers=hdr, json={}).status_code == 422


def test_analyze_ok(client, hdr, monkeypatch):
    monkeypatch.setattr(
        "app.services.news_analysis_service.analyze",
        lambda title, description: {"affected": ["THYAO"], "summary": "ok"})
    r = client.post(f"{NEWS}/analyze", headers=hdr,
                    json={"title": "TCMB faiz kararı", "description": "..."})
    assert r.status_code == 200
    assert r.json()["affected"] == ["THYAO"]


# --- /latest: response_model şema uyumu + query geçişi --------------------

def test_latest_empty_ok(client, hdr, monkeypatch):
    monkeypatch.setattr(
        "app.services.nlp_sentiment_service.get_financial_news",
        lambda **k: [])
    r = client.get(f"{NEWS}/latest", headers=hdr)
    assert r.status_code == 200
    assert r.json() == []


def test_latest_returns_shaped_items(client, hdr, monkeypatch):
    item = {
        "title": "THYAO rekor yolcu",
        "description": "açıklama",
        "url": "https://example.com/haber",
        "published_at": "2026-06-15T10:00:00",
        "sentiment_label": "Pozitif",
        "sentiment_score": 0.6,
        "affected_assets": [{"symbol": "THYAO", "name": "Türk Hava Yolları"}],
    }
    monkeypatch.setattr(
        "app.services.nlp_sentiment_service.get_financial_news",
        lambda **k: [item])
    r = client.get(f"{NEWS}/latest", headers=hdr)
    assert r.status_code == 200
    body = r.json()
    assert len(body) == 1
    assert body[0]["sentiment_label"] == "Pozitif"
    assert body[0]["affected_assets"][0]["symbol"] == "THYAO"


def test_latest_passes_query_to_service(client, hdr, monkeypatch):
    seen = {}

    def fake(query="stock market", force_refresh=False, **k):
        seen["query"] = query
        return []
    monkeypatch.setattr(
        "app.services.nlp_sentiment_service.get_financial_news", fake)
    assert client.get(f"{NEWS}/latest", headers=hdr,
                      params={"query": "THYAO"}).status_code == 200
    assert seen["query"] == "THYAO"


# --- /for-symbols: tekrarlı `q` paramı servise liste olarak geçer -----------

def test_for_symbols_passes_query_list(client, hdr, monkeypatch):
    seen = {}

    def fake(queries, force_refresh=False):
        seen["queries"] = queries
        return []
    monkeypatch.setattr(
        "app.services.nlp_sentiment_service.get_news_for_symbols", fake)
    r = client.get(f"{NEWS}/for-symbols", headers=hdr,
                   params=[("q", "THYAO"), ("q", "AKBNK")])
    assert r.status_code == 200
    assert seen["queries"] == ["THYAO", "AKBNK"]


# --- force bayrağı (cache bypass) servise geçer ---------------------------

def test_latest_passes_force_flag(client, hdr, monkeypatch):
    seen = {}

    def fake(query="stock market", force_refresh=False, **k):
        seen["force"] = force_refresh
        return []
    monkeypatch.setattr(
        "app.services.nlp_sentiment_service.get_financial_news", fake)
    assert client.get(f"{NEWS}/latest", headers=hdr,
                      params={"force": "true"}).status_code == 200
    assert seen["force"] is True


def test_for_symbols_passes_force_flag(client, hdr, monkeypatch):
    seen = {}

    def fake(queries, force_refresh=False):
        seen["force"] = force_refresh
        return []
    monkeypatch.setattr(
        "app.services.nlp_sentiment_service.get_news_for_symbols", fake)
    assert client.get(f"{NEWS}/for-symbols", headers=hdr,
                      params=[("q", "THYAO"), ("force", "true")]).status_code == 200
    assert seen["force"] is True


# --- /for-symbols: boş q + response_model şekil uyumu ---------------------

def test_for_symbols_empty_q_ok(client, hdr, monkeypatch):
    """q verilmezse (default []) servis boş listeyle çağrılır, 200 [] döner."""
    seen = {}

    def fake(queries, force_refresh=False):
        seen["queries"] = queries
        return []
    monkeypatch.setattr(
        "app.services.nlp_sentiment_service.get_news_for_symbols", fake)
    r = client.get(f"{NEWS}/for-symbols", headers=hdr)
    assert r.status_code == 200
    assert seen["queries"] == []
    assert r.json() == []


def test_for_symbols_returns_shaped_items(client, hdr, monkeypatch):
    """/latest gibi /for-symbols de NewsResponse şemasına uymalı (affected_assets dahil)."""
    item = {
        "title": "AKBNK net kâr açıkladı",
        "description": "açıklama",
        "url": "https://example.com/h",
        "published_at": "2026-06-15T10:00:00",
        "sentiment_label": "Pozitif",
        "sentiment_score": 0.7,
        "affected_assets": [{"symbol": "AKBNK", "name": "Akbank"}],
    }
    monkeypatch.setattr(
        "app.services.nlp_sentiment_service.get_news_for_symbols",
        lambda queries, force_refresh=False: [item])
    r = client.get(f"{NEWS}/for-symbols", headers=hdr, params=[("q", "AKBNK")])
    assert r.status_code == 200
    body = r.json()
    assert len(body) == 1
    assert body[0]["sentiment_label"] == "Pozitif"
    assert body[0]["affected_assets"][0]["symbol"] == "AKBNK"
