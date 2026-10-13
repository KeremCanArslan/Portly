"""`/health` — deploy ve ÖLÇÜM koşullarının okunabilir olması.

Neden var: 8. turda "push ettim, herhalde çıkmıştır" ile deploy doğrulanamadı
(→ `commit` alanı eklendi), 9. turda ise ölçümler deploy'dan hemen sonra
alındığı için saçıldı (0,92 → 5,54 sn) ve "soğuk muydu?" sorusu tahmine kaldı.
Bu uç artık ölçüm ÖNCESİ okunacak üç koşulu da veriyor.

Kritik davranış: `/health` çağırmak aktivite SAYILMAZ (core/activity.py) —
yoksa ölçümü doğrulamak için atılan istek ölçümün koşulunu bozardı.
"""

from fastapi.testclient import TestClient

from app.core import activity
from app.main import app

client = TestClient(app)


def test_health_reports_deploy_and_measurement_context():
    body = client.get("/health").json()
    assert body["status"] == "healthy"
    assert body["commit"]                     # yerelde "local"
    assert body["cache"] in ("redis", "memory")
    assert isinstance(body["uptime_s"], int) and body["uptime_s"] >= 0
    assert isinstance(body["idle_s"], int) and body["idle_s"] >= 0


def test_health_ping_does_not_count_as_activity():
    """UptimeRobot ping'i (ve ölçüm öncesi kontrol) arka plan yenileyicinin
    30 dk'lık aktif penceresini AÇMAMALI."""
    activity._last_activity_monotonic = 0.0
    idle_before = activity.seconds_since_activity()

    client.get("/health")
    client.head("/health")

    assert activity.seconds_since_activity() >= idle_before


def test_idle_never_exceeds_process_age():
    """Hiç /api isteği gelmemişken idle_s monotonic saatin HAM değerini
    (makine uptime'ı — canlıda 11.465.986 sn görüldü) basmamalı."""
    activity._last_activity_monotonic = 0.0

    body = client.get("/health").json()

    assert body["idle_s"] <= body["uptime_s"]


def test_health_reports_yahoo_proxy_usage(monkeypatch):
    """Vekil kurulduktan sonra "acaba kullanılıyor mu" sorusu tahmine
    kalmasın: env tanımlı mı + son başarılı quote çağrısı hangi uçtan."""
    from app.services import market_data_service as mds

    monkeypatch.setattr(mds, "_quote_url_pref", mds._QUOTE_DIRECT)
    assert client.get("/health").json()["quote_source"] == "direct"

    monkeypatch.setattr(
        mds, "_quote_url_pref", "https://vekil.example/v7/finance/quote")
    body = client.get("/health").json()
    assert body["quote_source"] == "proxy"
    assert isinstance(body["yahoo_proxy"], bool)
