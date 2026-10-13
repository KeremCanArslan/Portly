"""Coach (AI koç) HTTP entegrasyon testleri.

`/api/v1/coach/*` auth'lu. Kilitlenen sözleşme: auth kapısı (401), `/advice`
sahiplik (token≠path → 403), gövde doğrulama (`build-portfolio`), ve router'ın
hata eşlemesi — servis `ValueError` → 404, diğer `Exception` → 500. LLM/analiz
servisleri mock'lu (ağ ÇAĞRILMAZ); odak HTTP sözleşmesi + güvenlik.

Çalıştırma:  cd backend && python -m pytest tests/test_coach_api.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app
from app.models.user import User

COACH = "/api/v1/coach"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _register(client, db, email="co@mail.com", password="testpass1"):
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    uid = db.query(User).filter_by(email=email).one().id
    return {"Authorization": f"Bearer {token}"}, uid


# --- /advice/{user_id}: auth + sahiplik + mutlu yol -----------------------

def test_advice_requires_auth(client):
    assert client.get(f"{COACH}/advice/1").status_code == 401


def test_advice_other_user_forbidden(client, db):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{COACH}/advice/{uid + 999}", headers=hdr).status_code == 403


def test_advice_ok(client, db, monkeypatch):
    hdr, uid = _register(client, db)
    monkeypatch.setattr(
        "app.services.ai_coach_service.generate_portfolio_advice",
        lambda **k: {"advice": "Çeşitlendir."})
    r = client.get(f"{COACH}/advice/{uid}", headers=hdr)
    assert r.status_code == 200
    assert r.json()["advice"] == "Çeşitlendir."


# --- /fundamental/{symbol}: auth + 200 + hata eşlemesi (404/500) ----------

def test_fundamental_requires_auth(client):
    assert client.get(f"{COACH}/fundamental/AAPL").status_code == 401


def test_fundamental_ok(client, db, monkeypatch):
    hdr, _ = _register(client, db)
    monkeypatch.setattr("app.services.fundamental_analysis_service.analyze",
                        lambda symbol, force_refresh=False: {"pe": 25.0})
    r = client.get(f"{COACH}/fundamental/AAPL", headers=hdr)
    assert r.status_code == 200
    assert r.json()["pe"] == 25.0


def test_fundamental_value_error_404(client, db, monkeypatch):
    hdr, _ = _register(client, db)

    def boom(symbol, force_refresh=False):
        raise ValueError("sembol yok")
    monkeypatch.setattr("app.services.fundamental_analysis_service.analyze", boom)
    assert client.get(f"{COACH}/fundamental/ZZZZ",
                      headers=hdr).status_code == 404


def test_fundamental_generic_error_500(client, db, monkeypatch):
    hdr, _ = _register(client, db)

    def boom(symbol, force_refresh=False):
        raise RuntimeError("LLM down")
    monkeypatch.setattr("app.services.fundamental_analysis_service.analyze", boom)
    assert client.get(f"{COACH}/fundamental/AAPL",
                      headers=hdr).status_code == 500


# --- /financials/{symbol}: auth + 200 + 500 -------------------------------

def test_financials_requires_auth(client):
    assert client.get(f"{COACH}/financials/AAPL").status_code == 401


def test_financials_ok(client, db, monkeypatch):
    hdr, _ = _register(client, db)
    monkeypatch.setattr(
        "app.services.fundamental_analysis_service.get_financials",
        lambda symbol: {"revenue": [1, 2, 3]})
    r = client.get(f"{COACH}/financials/AAPL", headers=hdr)
    assert r.status_code == 200
    assert r.json()["revenue"] == [1, 2, 3]


def test_financials_generic_error_500(client, db, monkeypatch):
    hdr, _ = _register(client, db)

    def boom(symbol):
        raise RuntimeError("bilanço yok")
    monkeypatch.setattr(
        "app.services.fundamental_analysis_service.get_financials", boom)
    assert client.get(f"{COACH}/financials/AAPL",
                      headers=hdr).status_code == 500


# --- /predict/{symbol}: auth + 200 + 404 ----------------------------------

def test_predict_requires_auth(client):
    assert client.get(f"{COACH}/predict/AAPL").status_code == 401


def test_predict_ok(client, db, monkeypatch):
    hdr, _ = _register(client, db)
    monkeypatch.setattr("app.services.technical_analysis_service.predict",
                        lambda symbol, force_refresh=False: {"direction": "up"})
    r = client.get(f"{COACH}/predict/AAPL", headers=hdr)
    assert r.status_code == 200
    assert r.json()["direction"] == "up"


def test_predict_value_error_404(client, db, monkeypatch):
    hdr, _ = _register(client, db)

    def boom(symbol, force_refresh=False):
        raise ValueError("veri yok")
    monkeypatch.setattr("app.services.technical_analysis_service.predict", boom)
    assert client.get(f"{COACH}/predict/ZZZZ",
                      headers=hdr).status_code == 404


# --- /build-portfolio: auth + gövde doğrulama + 200 + 500 -----------------

def test_build_portfolio_requires_auth(client):
    assert client.post(f"{COACH}/build-portfolio", json={
        "risk_profile": "dengeli", "horizon": "medium", "amount": 10000
    }).status_code == 401


def test_build_portfolio_validation_422(client, db):
    hdr, _ = _register(client, db)
    # amount > 0 zorunlu
    assert client.post(f"{COACH}/build-portfolio", headers=hdr, json={
        "risk_profile": "dengeli", "horizon": "medium", "amount": 0
    }).status_code == 422
    # risk_profile min_length=3
    assert client.post(f"{COACH}/build-portfolio", headers=hdr, json={
        "risk_profile": "x", "horizon": "medium", "amount": 10000
    }).status_code == 422


def test_build_portfolio_ok(client, db, monkeypatch):
    hdr, _ = _register(client, db)
    monkeypatch.setattr("app.services.ai_portfolio_service.build_portfolio",
                        lambda **k: {"allocations": [], "backtest": {}})
    r = client.post(f"{COACH}/build-portfolio", headers=hdr, json={
        "risk_profile": "dengeli", "horizon": "medium", "amount": 10000})
    assert r.status_code == 200
    assert "allocations" in r.json()


def test_build_portfolio_generic_error_500(client, db, monkeypatch):
    hdr, _ = _register(client, db)

    def boom(**k):
        raise RuntimeError("AI down")
    monkeypatch.setattr("app.services.ai_portfolio_service.build_portfolio", boom)
    assert client.post(f"{COACH}/build-portfolio", headers=hdr, json={
        "risk_profile": "dengeli", "horizon": "medium", "amount": 10000
    }).status_code == 500
