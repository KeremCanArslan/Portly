"""AI Teknik Tahmin: hedef/stop tutarlılığı ve risk/getiri.

Canlıda (16 Kas 2026) AAPL'de "YÜKSELİŞ" tahmininin hedefi günün yükseğiydi:
hedef cari fiyata stop'tan çok daha yakın, yani risk/getiri 1'in altındaydı ve
ekran bunu göstermiyordu. LLM'in verdiği seviyeler yönle çelişirse (yükselişte
hedef fiyatın altında) gösterilmez; risk/getiri hesaplanıp döner. LLM yanıtı
alınamazsa uydurma "NÖTR %50, hedef = fiyat" yerine boş tahmin döner ve
cache'lenmez. yfinance + LLM mock'lu (ağ çağrılmaz).

Çalıştırma:  cd backend && python -m pytest tests/test_technical_levels.py -q
"""

import json

import pytest

from app.services import technical_analysis_service as tas

_IND = {"current_price": 100.0, "atr": 2.0, "resistance_1m": 100.5,
        "resistance_3m": 110.0, "support_1m": 95.0, "support_3m": 90.0}


def _run(monkeypatch, llm_out):
    calls = []
    monkeypatch.setattr(tas, "_compute_indicators", lambda s: dict(_IND))
    monkeypatch.setattr(tas.llm_service, "available", True)
    monkeypatch.setattr(tas.llm_service, "complete",
                        lambda *a, **k: calls.append(1) or llm_out)
    tas._cache.clear()
    return tas.predict("AAPL")["prediction"], calls


def test_risk_reward_hesaplanir(monkeypatch):
    pred, _ = _run(monkeypatch, json.dumps(
        {"direction": "BULLISH", "confidence": 70,
         "target_price": 110.0, "stop_loss": 96.0}))
    assert pred["target_price"] == 110.0
    assert pred["stop_loss"] == 96.0
    assert pred["risk_reward"] == pytest.approx(2.5)   # 10 / 4


@pytest.mark.parametrize("direction, target, stop", [
    ("BULLISH", 99.0, 96.0),     # yükselişte hedef fiyatın altında
    ("BEARISH", 105.0, 104.0),   # düşüşte hedef fiyatın üstünde
])
def test_yonle_celisen_hedef_gosterilmez(monkeypatch, direction, target, stop):
    pred, _ = _run(monkeypatch, json.dumps(
        {"direction": direction, "confidence": 60,
         "target_price": target, "stop_loss": stop}))
    assert pred["target_price"] is None
    assert pred["risk_reward"] is None


def test_llm_hatasi_uydurma_tahmin_vermez_cache_lenmez(monkeypatch):
    pred, calls = _run(monkeypatch, "bozuk-json")
    assert pred["direction"] is None
    assert pred["confidence"] is None
    assert pred["target_price"] is None and pred["stop_loss"] is None
    tas.predict("AAPL")
    assert len(calls) == 2
