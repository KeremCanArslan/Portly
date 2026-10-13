"""Market (piyasa araçları) HTTP entegrasyon testleri.

`/api/v1/market/*` uçları **auth'suz/public** — burada kilitlenen sözleşme:
girdi doğrulama kapıları (what-if/dca/quiz 400'leri, ağsız + deterministik) +
servis-destekli uçların 200 + 500 yolları (ağ-ağır servisler mock'lu, yfinance
ÇAĞRILMAZ). Servislerin kendi hesap mantığı ayrı birim testlerinde (what_if vb.).

Çalıştırma:  cd backend && python -m pytest tests/test_market_api.py -q
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app

MKT = "/api/v1/market"


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


# --- what-if: girdi doğrulama (ağsız, mock gerekmez) ----------------------

def test_what_if_rejects_nonpositive_amount(client):
    assert client.get(f"{MKT}/what-if",
                      params={"symbol": "AAPL", "amount": 0}).status_code == 400


def test_what_if_rejects_out_of_range_years(client):
    assert client.get(f"{MKT}/what-if", params={
        "symbol": "AAPL", "amount": 1000, "years_back": 31}).status_code == 400
    assert client.get(f"{MKT}/what-if", params={
        "symbol": "AAPL", "amount": 1000, "years_back": 0}).status_code == 400


def test_what_if_ok(client, monkeypatch):
    monkeypatch.setattr("app.services.what_if_service.calculate",
                        lambda *a, **k: {"final_value": 4200.0})
    r = client.get(f"{MKT}/what-if",
                   params={"symbol": "AAPL", "amount": 1000, "years_back": 2})
    assert r.status_code == 200
    assert r.json()["final_value"] == 4200.0


# --- dca: girdi doğrulama + mutlu yol -------------------------------------

def test_dca_rejects_nonpositive_amount(client):
    assert client.get(f"{MKT}/dca", params={
        "symbol": "AAPL", "monthly_amount": 0}).status_code == 400


def test_dca_rejects_out_of_range_years(client):
    assert client.get(f"{MKT}/dca", params={
        "symbol": "AAPL", "monthly_amount": 500, "years_back": 31}).status_code == 400


def test_dca_ok(client, monkeypatch):
    monkeypatch.setattr("app.services.what_if_service.calculate_dca",
                        lambda *a, **k: {"total_invested": 18000.0})
    r = client.get(f"{MKT}/dca", params={
        "symbol": "AAPL", "monthly_amount": 500, "years_back": 3})
    assert r.status_code == 200
    assert r.json()["total_invested"] == 18000.0


# --- quiz: vade doğrulama + 200 + servis hatası 500 -----------------------

def test_quiz_rejects_bad_horizon(client):
    assert client.get(f"{MKT}/quiz",
                      params={"horizon": "forever"}).status_code == 400


def test_quiz_ok(client, monkeypatch):
    monkeypatch.setattr("app.services.ta_quiz_service.generate_question",
                        lambda **k: {"asset_class": "stock", "candles": []})
    r = client.get(f"{MKT}/quiz", params={"horizon": "medium"})
    assert r.status_code == 200
    assert r.json()["asset_class"] == "stock"


def test_quiz_service_error_500(client, monkeypatch):
    def boom(**k):
        raise RuntimeError("model down")
    monkeypatch.setattr("app.services.ta_quiz_service.generate_question", boom)
    assert client.get(f"{MKT}/quiz",
                      params={"horizon": "short"}).status_code == 500


# --- servis-destekli basit uçlar (mock'lu 200) ----------------------------

def test_fear_greed_ok(client, monkeypatch):
    monkeypatch.setattr("app.services.fear_greed_service.get_fear_greed_index",
                        lambda **k: {"score": 55, "label": "Nötr"})
    r = client.get(f"{MKT}/fear-greed")
    assert r.status_code == 200
    assert r.json()["score"] == 55


def test_fear_greed_nan_does_not_500(client, monkeypatch):
    """Regresyon: yfinance NaN son-kapanış döndürünce sonuca NaN sızıyordu →
    Starlette JSONResponse `allow_nan=False` → 500 → frontend 'veri alınamadı'.
    Gerçek hesaplama koşar (helper'lar NaN döndürür), endpoint 200 + finite olmalı."""
    import math
    from app.services import fear_greed_service as fg
    nan = float("nan")
    monkeypatch.setattr(fg, "_vix_score", lambda: (50.0, nan))
    monkeypatch.setattr(fg, "_momentum_score", lambda: (100.0, nan))
    monkeypatch.setattr(fg, "_sentiment_score", lambda: (54.5, nan))
    fg._cache.clear()
    r = client.get(f"{MKT}/fear-greed", params={"force": "true"})
    assert r.status_code == 200
    body = r.json()
    comp = body["components"]
    assert math.isfinite(body["score"])
    assert math.isfinite(comp["volatility"]["vix_value"])
    assert math.isfinite(comp["momentum"]["sp500_5d_pct"])
    assert math.isfinite(comp["sentiment"]["news_avg"])


def test_global_safe_json_sanitizes_nan(client, monkeypatch):
    """Global SafeJSONResponse: servis ham NaN dönse bile uç 500 değil 200 +
    NaN→null. (yfinance NaN'ı tek başına TÜM ucu çökertmesin garantisi — gold
    servisinin kendi sanitizer'ı yok, bu uçtan uca global ağı doğrular.)"""
    monkeypatch.setattr("app.services.gold_rates_service.get_bank_gold_rates",
                        lambda: [{"bank": "X", "buy": float("nan"), "sell": 2.0}])
    r = client.get(f"{MKT}/gold-rates")
    assert r.status_code == 200
    assert r.json()[0]["buy"] is None
    assert r.json()[0]["sell"] == 2.0


def test_history_skips_nan_ohlc_rows(monkeypatch):
    """Regresyon: yfinance günlük seride NaN OHLC satırı (bugünün yarım barı)
    döndürünce JSON'a NaN sızıp uç 500'lüyordu ('Grafik verisi alınamadı').
    NaN satır ATLANMALI, kalanlar finite olmalı."""
    import numpy as np
    import pandas as pd
    from app.services import market_data_service as mds

    idx = pd.to_datetime(["2026-06-17", "2026-06-18", "2026-06-19"])
    df = pd.DataFrame({
        "Open": [10.0, 11.0, np.nan],
        "High": [10.5, 11.5, np.nan],
        "Low": [9.5, 10.5, np.nan],
        "Close": [10.2, 11.2, np.nan],
        "Volume": [1000, 1100, 0],
    }, index=idx)

    class _FakeTicker:
        def __init__(self, *a, **k):
            pass

        def history(self, **k):
            return df

    monkeypatch.setattr(mds.yf, "Ticker", _FakeTicker)
    monkeypatch.setattr(mds, "_cache_get", lambda k: None)
    monkeypatch.setattr(mds, "_cache_set", lambda *a, **k: None)

    r = mds.get_stock_history("NVDA", period="1mo", interval="1d")
    assert r["data_points"] == 2                      # NaN satır atlandı
    for row in r["data"]:
        for k in ("open", "high", "low", "close"):
            assert row[k] == row[k]                    # NaN değil


def test_gold_rates_ok(client, monkeypatch):
    monkeypatch.setattr("app.services.gold_rates_service.get_bank_gold_rates",
                        lambda: [{"bank": "X", "buy": 1.0, "sell": 2.0}])
    r = client.get(f"{MKT}/gold-rates")
    assert r.status_code == 200
    assert isinstance(r.json(), list)


def test_macro_calendar_ok(client, monkeypatch):
    monkeypatch.setattr("app.services.macro_calendar_service.get_upcoming_events",
                        lambda **k: [])
    assert client.get(f"{MKT}/macro-calendar").status_code == 200


def test_search_ok(client, monkeypatch):
    monkeypatch.setattr("app.services.market_data_service.search_symbols",
                        lambda **k: [{"symbol": "THYAO.IS", "name": "Türk Hava Yolları"}])
    r = client.get(f"{MKT}/search", params={"q": "thy"})
    assert r.status_code == 200
    assert r.json()[0]["symbol"] == "THYAO.IS"


def test_price_ok(client, monkeypatch):
    # get_price(symbol, background_tasks) → get_stock_data(symbol, background_tasks):
    # fake *args ile background_tasks'i yutar (ağ yok).
    monkeypatch.setattr("app.services.market_data_service.get_stock_data",
                        lambda symbol, *a, **k: {"symbol": symbol, "current_price": 100.0})
    r = client.get(f"{MKT}/price/AAPL")
    assert r.status_code == 200
    assert r.json()["current_price"] == 100.0


def test_history_ok(client, monkeypatch):
    monkeypatch.setattr("app.services.market_data_service.get_stock_history",
                        lambda **k: [{"timestamp": 1, "close": 100.0}])
    r = client.get(f"{MKT}/history/AAPL", params={"period": "1mo"})
    assert r.status_code == 200
    assert isinstance(r.json(), list)


# --- toplu fiyat ucu (/market/prices) — istemcinin açılış yolu -------------

def test_batch_prices_endpoint_returns_quotes_and_missing(client, monkeypatch):
    """İzleme listesi açılışta sembol başına ayrı `/price/{sym}` çağırıyordu
    (8 sembol = 8 HTTP). Tek uç: sıra korunur, veri gelmeyen sembol `missing`."""
    from app.services import market_data_service as mds
    monkeypatch.setattr(mds, "get_stock_prices_named", lambda symbols: {
        "quotes": [{"symbol": s, "company_name": s, "current_price": 1.0,
                    "change_percent": 0.0} for s in symbols if s != "YOK"],
        "missing": [s for s in symbols if s == "YOK"]})

    r = client.get(f"{MKT}/prices", params={"symbols": "AAPL,YOK"})
    assert r.status_code == 200
    body = r.json()
    assert [q["symbol"] for q in body["quotes"]] == ["AAPL"]
    assert body["missing"] == ["YOK"]


def test_batch_prices_endpoint_empty_input_is_not_an_error(client):
    r = client.get(f"{MKT}/prices", params={"symbols": ""})
    assert r.status_code == 200
    assert r.json() == {"quotes": [], "missing": []}
