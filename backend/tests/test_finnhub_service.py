"""Finnhub temel-veri kaynağı birim testleri (HTTP MOCK'lu — ağ ÇAĞRILMAZ).

Sözleşme: /stock/metric + /profile2 + /quote + /recommendation → `_compute_
fundamentals` ile AYNI anahtarlar; ölçek (marketCap×1e6, borç/özkaynak×100,
yüzde alanlar olduğu gibi); kapsanmayan sembolde None.
"""

import pytest

from app.services import finnhub_service as fh


_METRIC = {"metric": {
    "peTTM": 65.4, "pbQuarterly": 50.1, "psTTM": 35.0,
    "netProfitMarginTTM": 55.8, "operatingMarginTTM": 62.0,
    "roeTTM": 115.0, "roaTTM": 65.0,
    "revenueGrowthTTMYoy": 114.0, "epsGrowthTTMYoy": 150.0,
    "totalDebt/totalEquityQuarterly": 0.5,
    "currentRatioQuarterly": 4.1, "quickRatioQuarterly": 3.5,
    "currentDividendYieldTTM": 0.03, "payoutRatioTTM": 1.5,
    "52WeekHigh": 320.0, "52WeekLow": 180.0, "beta": 1.7,
}}
_PROFILE = {"name": "NVIDIA Corp", "country": "US", "currency": "USD",
            "marketCapitalization": 3_200_000, "finnhubIndustry": "Semiconductors"}
_QUOTE = {"c": 204.65}
_REC = [{"strongBuy": 30, "buy": 10, "hold": 5, "sell": 1, "strongSell": 0,
         "period": "2026-06-01"}]
_PT = {"targetMean": 250.0}


def _router(mapping):
    def _get(path, params):
        return mapping.get(path)
    return _get


def _patch(monkeypatch, mapping):
    monkeypatch.setattr(fh, "available", True)
    monkeypatch.setattr(fh, "_get", _router(mapping))


def test_fundamentals_field_mapping(monkeypatch):
    _patch(monkeypatch, {
        "/stock/metric": _METRIC, "/stock/profile2": _PROFILE,
        "/quote": _QUOTE, "/stock/recommendation": _REC, "/stock/price-target": _PT,
    })
    f = fh.get_fundamentals("NVDA")
    assert f["data_source"] == "finnhub" and f["data_limited"] is False
    assert f["company_name"] == "NVIDIA Corp"
    assert f["market_cap"] == 3_200_000 * 1_000_000      # milyon → mutlak
    assert f["current_price"] == 204.65
    assert f["pe_trailing"] == 65.4
    assert f["roe_pct"] == 115.0                          # yüzde, olduğu gibi
    assert f["debt_to_equity"] == 50.0                    # 0.5 oran → ×100
    assert f["fifty_two_week_high"] == 320.0
    assert f["analyst_recommendation"] == "buy"           # 40 buy > 5 hold > 1 sell
    assert f["analyst_count"] == 46
    assert f["analyst_target"] == 250.0


def test_returns_none_when_symbol_uncovered(monkeypatch):
    """Ücretsiz tier kapsamayan sembol → boş metric + quote yok → None."""
    _patch(monkeypatch, {"/stock/metric": {"metric": {}}, "/quote": {}})
    assert fh.get_fundamentals("THYAO.IS") is None


def test_unavailable_without_key(monkeypatch):
    """Key yoksa available False → _get None → get_fundamentals None."""
    monkeypatch.setattr(fh, "available", False)
    assert fh.get_fundamentals("NVDA") is None


def test_financials_income_mapping(monkeypatch):
    _patch(monkeypatch, {"/stock/financials": {"financials": [
        {"period": "2024-12-31", "revenue": 1000, "netIncome": 250},
        {"period": "2023-12-31", "revenue": 800, "netIncome": 150},
    ]}})
    fin = fh.get_financials("NVDA")
    assert fin["has_data"] is True and fin["data_source"] == "finnhub"
    assert fin["history"][0]["period"] == "2024-12-31"
    assert fin["history"][0]["net_margin_pct"] == 25.0    # 250/1000
    assert fin["forecast"] is not None
    assert fin["forecast"]["revenue_growth_pct"] == 25.0  # 1000/800 - 1


def test_financials_none_when_empty(monkeypatch):
    _patch(monkeypatch, {"/stock/financials": {"financials": []}})
    assert fh.get_financials("THYAO.IS") is None
