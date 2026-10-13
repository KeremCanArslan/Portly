"""Hisse-dışı (kripto/forex/emtia) 'varlık sınıfına uygun' temel analiz.

Sözleşme: _classify son ekten doğru sınıfı verir; analyze() hisse-dışı sembolde
macro yoluna sapar → {asset_class, overview, analysis.scores[3 etiketli]} döner ve
hisse-özel `fundamentals` ÜRETİLMEZ. yfinance + LLM mock'lu (ağ ÇAĞRILMAZ).

Çalıştırma:  cd backend && python -m pytest tests/test_fundamental_macro.py -q
"""

import json
import pytest

from app.services import fundamental_analysis_service as fa


@pytest.mark.parametrize("symbol,expected", [
    ("BTC-USD", "crypto"),
    ("eth-usd", "crypto"),
    ("USDTRY=X", "forex"),
    ("GC=F", "commodity"),
    ("CL=F", "commodity"),
    ("AAPL", "stock"),
    ("THYAO.IS", "stock"),
])
def test_classify(symbol, expected):
    assert fa._classify(symbol) == expected


_FAKE_OV = {
    "display_name": "Bitcoin USD",
    "currency": "USD",
    "currency_prefix": "$",
    "current_price": 64200.0,
    "week52_high": 73000.0,
    "week52_low": 38000.0,
    "perf_1m_pct": 5.0,
    "perf_6m_pct": 20.0,
    "perf_1y_pct": 48.0,
    "market_cap": 1.2e12,
    "circulating_supply": 19_700_000,
    "volume": 3.0e10,
}

_FAKE_LLM = json.dumps({
    "recommendation": "TUT",
    "overall_score": 66,
    "primary_score": 72,
    "momentum_score": 55,
    "stability_score": 80,
    "key_strengths": ["ETF girişleri", "ağ etkinliği artıyor"],
    "key_weaknesses": ["regülasyon belirsizliği"],
    "summary": "Kurumsal benimsenme sürüyor; oynaklık yüksek.",
})


def _patch_macro(monkeypatch, llm_out=_FAKE_LLM):
    monkeypatch.setattr(fa, "_overview", lambda sym, cls: dict(_FAKE_OV))
    monkeypatch.setattr(fa.llm_service, "available", True)
    monkeypatch.setattr(fa.llm_service, "complete", lambda *a, **k: llm_out)
    fa._cache.clear()


def test_macro_analysis_schema(monkeypatch):
    """Kripto sembolü → asset_class+overview+3 etiketli skor; hisse alanı YOK."""
    _patch_macro(monkeypatch)

    res = fa.analyze("BTC-USD")

    assert res["asset_class"] == "crypto"
    assert "fundamentals" not in res          # hisse-özel blok üretilmez
    assert res["overview"]["current_price"] == 64200.0
    a = res["analysis"]
    assert a["recommendation"] == "TUT"
    labels = [s["label"] for s in a["scores"]]
    assert labels == ["Benimsenme", "Momentum", "Dayanıklılık"]
    assert [s["score"] for s in a["scores"]] == [72, 55, 80]


def test_macro_labels_per_class(monkeypatch):
    """Forex→Makro/İstikrar, emtia→Arz-Talep etiketleri (3. eksen yüksek=iyi)."""
    _patch_macro(monkeypatch)
    fx = fa.analyze("USDTRY=X")
    assert [s["label"] for s in fx["analysis"]["scores"]] == \
        ["Makro Görünüm", "Momentum", "İstikrar"]

    fa._cache.clear()
    gold = fa.analyze("GC=F")
    assert [s["label"] for s in gold["analysis"]["scores"]] == \
        ["Arz-Talep", "Momentum", "İstikrar"]


def test_macro_llm_failure_falls_back(monkeypatch):
    """LLM bozuk JSON → patlamaz, nötr (TUT/50) varsayılan + şema korunur."""
    _patch_macro(monkeypatch, llm_out="bozuk-json-değil")

    res = fa.analyze("ETH-USD")

    assert res["asset_class"] == "crypto"
    assert res["analysis"]["recommendation"] == "TUT"
    assert len(res["analysis"]["scores"]) == 3


class _FakeFast:
    """fast_info stub (chart-endpoint tabanlı — Render'da .info bloklu olsa da çalışır)."""
    last_price = 298.0
    year_high = 317.0
    year_low = 196.0
    market_cap = 4.3e12
    currency = "USD"


def _fake_ticker_factory(info_value):
    import pandas as pd

    class _FakeTicker:
        def __init__(self, symbol, session=None):
            self.symbol = symbol

        @property
        def info(self):
            return info_value

        @property
        def fast_info(self):
            return _FakeFast()

        def history(self, **k):
            return pd.DataFrame()

    return _FakeTicker


def test_blocked_info_falls_back_not_404(monkeypatch):
    """Regresyon: yfinance .info (quoteSummary) Render IP'sinde BOŞ dönünce
    eskiden ValueError→404→'AI temel analiz yüklenemedi' oluyordu. Artık
    fast_info'ya düşüp data_limited + fiyat/52H ile 200 dönmeli (oranlar None)."""
    monkeypatch.setattr(fa.yf, "Ticker", _fake_ticker_factory({}))  # .info BLOKLU
    monkeypatch.setattr(fa.llm_service, "available", True)
    monkeypatch.setattr(fa.llm_service, "complete", lambda *a, **k: json.dumps({
        "valuation": "Adil", "valuation_score": 60, "growth_score": 55,
        "health_score": 70, "overall_score": 62, "recommendation": "TUT",
        "fair_value_estimate": 310, "summary": "x",
        "key_strengths": ["a"], "key_weaknesses": ["b"],
        "competitive_position": "c",
    }))
    fa._cache.clear()

    res = fa.analyze("AAPL", force_refresh=True)  # ValueError ATMAMALI

    assert res["asset_class"] == "stock"
    f = res["fundamentals"]
    assert f["data_limited"] is True
    assert f["current_price"] == 298.0
    assert f["fifty_two_week_high"] == 317.0
    assert f["pe_trailing"] is None      # oran verisi yok (bloklu)
    assert res["analysis"]["recommendation"] == "TUT"


def test_blocked_info_uses_finnhub_not_degraded(monkeypatch):
    """yfinance `.info` bloklu AMA Finnhub mevcut → degrade DEĞİL, gerçek
    oranlar (data_limited=False) dönmeli (Finnhub fallback'i devrede)."""
    monkeypatch.setattr(fa.yf, "Ticker", _fake_ticker_factory({}))  # .info bloklu
    finnhub_full = {
        "data_limited": False, "data_source": "finnhub",
        "company_name": "NVIDIA Corp", "current_price": 204.65,
        "pe_trailing": 65.4, "roe_pct": 115.0, "sector": "Semiconductors",
    }
    monkeypatch.setattr(fa.finnhub_service, "get_fundamentals",
                        lambda s: finnhub_full)
    monkeypatch.setattr(fa.llm_service, "available", True)
    monkeypatch.setattr(fa.llm_service, "complete", lambda *a, **k: json.dumps({
        "recommendation": "AL", "overall_score": 80, "valuation_score": 70,
        "growth_score": 90, "health_score": 75, "summary": "x",
    }))
    fa._cache.clear()

    res = fa.analyze("NVDA", force_refresh=True)
    f = res["fundamentals"]
    assert f["data_limited"] is False            # degrade DEĞİL
    assert f["data_source"] == "finnhub"
    assert f["pe_trailing"] == 65.4 and f["roe_pct"] == 115.0


def test_compute_fundamentals_nan_llm_no_crash(monkeypatch):
    """Savunma: LLM JSON-mode'da NaN token dönebilir (json.loads → float nan).
    _json_safe temizlemezse Starlette allow_nan=False → 500. Sonuç JSON-safe olmalı."""
    import math
    monkeypatch.setattr(fa.yf, "Ticker", _fake_ticker_factory({}))
    monkeypatch.setattr(fa.llm_service, "available", True)
    # json.loads NaN'ı kabul eder → parsed['fair_value_estimate'] = nan
    monkeypatch.setattr(fa.llm_service, "complete",
                        lambda *a, **k: '{"recommendation":"TUT","overall_score":50,"fair_value_estimate":NaN,"summary":"x"}')
    fa._cache.clear()

    res = fa.analyze("AAPL", force_refresh=True)

    fv = res["analysis"]["fair_value_estimate"]
    assert fv is None or math.isfinite(fv)   # NaN sızmamalı


# ── `.info` devre kesici ────────────────────────────────────────────────────
# Canlı ölçüm: 51 sembollük sinyal taraması SOĞUK 24 sn sürüyordu; temel oran
# cache'i sıcakken aynı tarama 0,5 sn. Fark tamamen buradan: yfinance `.info`
# Render IP'sinde bloklu, her sembolde İKİ kez deneniyor ve aralarında 0,6 sn
# uyunuyordu.
def test_info_ustuste_bos_donerse_atlanir(monkeypatch):
    calls = []

    def _counting_factory(symbol, session=None):
        calls.append(symbol)
        return _fake_ticker_factory({})(symbol, session)

    monkeypatch.setattr(fa.yf, "Ticker", _counting_factory)
    monkeypatch.setattr(fa.finnhub_service, "get_fundamentals", lambda s: None)
    monkeypatch.setattr(fa, "_fast_price", lambda s: (100.0, None))
    monkeypatch.setattr(fa.time, "sleep", lambda s: None)

    for _ in range(fa._INFO_FAIL_THRESHOLD):
        fa._compute_fundamentals("AAPL")
    denemeler = len(calls)
    assert denemeler > 0

    fa._compute_fundamentals("MSFT")          # eşik doldu → hiç denenmemeli
    assert len(calls) == denemeler
    assert not fa._info_available()


def test_info_calisirsa_devre_kesici_kapanmaz(monkeypatch):
    """Lokal geliştirmede `.info` çalışıyor → davranış değişmemeli."""
    monkeypatch.setattr(fa.yf, "Ticker",
                        _fake_ticker_factory({"regularMarketPrice": 100.0}))
    monkeypatch.setattr(fa.time, "sleep", lambda s: None)
    for _ in range(fa._INFO_FAIL_THRESHOLD + 2):
        fa._compute_fundamentals("AAPL")
    assert fa._info_available()
