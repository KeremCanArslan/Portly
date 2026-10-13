"""Stress test HTTP entegrasyon testleri.

`GET /api/v1/stress/scenarios` — AUTH GEREKTİRMEZ (statik senaryo listesi).
`GET /api/v1/stress/run/{user_id}` — auth + sahiplik (Monte Carlo, pahalı/ağ).

run happy-path yfinance geçmişine (get_stock_history; conftest mock'lamaz) bağlı
→ burada yalnız HTTP sözleşmesi: scenarios listesi + run auth/sahiplik kapısı.
Monte Carlo hesabının kendisi test_*_service seviyesinde sınanır.

Çalıştırma:  cd backend && python -m pytest tests/test_stress_api.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app
from app.models.user import User

STRESS = "/api/v1/stress"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


def _register(client, db, email="st@mail.com", password="testpass1"):
    r = client.post("/api/v1/auth/register",
                    json={"email": email, "password": password})
    assert r.status_code == 200, r.text
    token = r.json()["access_token"]
    uid = db.query(User).filter_by(email=email).one().id
    return {"Authorization": f"Bearer {token}"}, uid


def test_scenarios_public_non_empty(client):
    """scenarios auth GEREKTİRMEZ + boş olmayan senaryo listesi döner."""
    r = client.get(f"{STRESS}/scenarios")
    assert r.status_code == 200
    assert len(r.json()) > 0   # normal/subprime_2008/covid_2020/... senaryoları


def test_run_requires_auth(client):
    assert client.get(f"{STRESS}/run/1").status_code == 401


def test_run_other_user_forbidden(client, db):
    hdr, uid = _register(client, db)
    assert client.get(
        f"{STRESS}/run/{uid + 999}", headers=hdr).status_code == 403
