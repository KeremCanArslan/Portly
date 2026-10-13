"""Toplu fiyat çekimi — TEK istekte N sembol (Yahoo v7/quote).

Neden var (4 Eyl, 10. tur ölçümü): `_fetch_many` "batch" adını taşıyordu ama
`yf.download` sembol BAŞINA bir `/v8/finance/chart/` isteği atıyor (ölçüldü:
10 sembol = 10 istek). 51 sembollük sinyal taraması = 51 Yahoo isteği →
Render'ın paylaşılan çıkış IP'sinde 429'un asıl kaynağı. v7/quote ucu aynı
işi TEK istekte yapıyor (54 sembol, 1,09 sn, eksiksiz).

Kilitlenen sözleşme:
 1. N sembol = TEK HTTP isteği (50'lik parçalar),
 2. dönen kayıt market_data sözleşmesine uyar (fiyat/değişim/ad/
    change_available),
 3. önceki kapanış yoksa `change_available=False` — sıfır basılmaz,
 4. uç düşerse (429/hata) eski `yf.download` yoluna düşülür, sessiz boş yok,
 5. yerel katalog adı Yahoo'nun kontrat adını (GC=F → "Gold Dec 26") EZMEZ.
"""

import pytest

from app.core import cache
from app.services import market_data_service as mds


@pytest.fixture(autouse=True)
def _clean(monkeypatch):
    cache._mem.clear()
    mds._name_cache.clear()
    yield
    cache._mem.clear()
    mds._name_cache.clear()


class _Resp:
    def __init__(self, payload, status=200):
        self._payload = payload
        self.status_code = status

    def json(self):
        return self._payload


def _quote(symbol, price, prev=None, change=None, name=None):
    q = {"symbol": symbol, "regularMarketPrice": price}
    if prev is not None:
        q["regularMarketPreviousClose"] = prev
    if change is not None:
        q["regularMarketChangePercent"] = change
    if name:
        q["longName"] = name
    return q


class _FakeSession:
    """v7/quote'u taklit eder; her çağrının sembollerini kaydeder."""

    def __init__(self, quotes, status=200):
        self.quotes = quotes
        self.status = status
        self.calls: list[list[str]] = []

    def get(self, url, params=None, timeout=None):
        asked = (params or {}).get("symbols", "").split(",")
        self.calls.append(asked)
        result = [self.quotes[s] for s in asked if s in self.quotes]
        return _Resp({"quoteResponse": {"result": result}}, self.status)


def test_n_symbols_single_request(monkeypatch):
    syms = ["AAPL", "MSFT", "THYAO.IS", "BTC-USD"]
    session = _FakeSession({
        s: _quote(s, 100.0, prev=99.0, change=1.0101, name=f"{s} A.Ş.")
        for s in syms
    })
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(
        mds, "_fetch_many_via_download",
        lambda s: pytest.fail(f"yedek yola düşülmemeliydi: {s}"))

    out = mds._fetch_many(syms)

    assert len(session.calls) == 1
    assert session.calls[0] == syms
    assert set(out) == set(syms)
    assert out["AAPL"]["current_price"] == 100.0
    assert out["AAPL"]["change_percent"] == 1.01
    assert out["AAPL"]["change_available"] is True
    assert out["AAPL"]["company_name"] == "AAPL A.Ş."


def test_chunks_at_50_symbols(monkeypatch):
    syms = [f"S{i}" for i in range(120)]
    session = _FakeSession({s: _quote(s, 10.0, prev=10.0) for s in syms})
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(mds, "_fetch_many_via_download", lambda s: {})

    out = mds._fetch_many(syms)

    assert [len(c) for c in session.calls] == [50, 50, 20]
    assert len(out) == 120


def test_missing_previous_close_marks_change_unavailable(monkeypatch):
    session = _FakeSession({"XU100.IS": _quote("XU100.IS", 10_500.0)})
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(mds, "_fetch_many_via_download", lambda s: {})

    out = mds._fetch_many(["XU100.IS"])

    assert out["XU100.IS"]["change_available"] is False
    assert out["XU100.IS"]["change_percent"] == 0.0


def test_falls_back_to_download_when_endpoint_fails(monkeypatch):
    session = _FakeSession({}, status=429)
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    called: list[list[str]] = []

    def _download(symbols):
        called.append(list(symbols))
        return {s: {"symbol": s, "company_name": s, "current_price": 5.0,
                    "change_percent": 0.0, "change_available": False}
                for s in symbols}

    monkeypatch.setattr(mds, "_fetch_many_via_download", _download)

    out = mds._fetch_many(["AAPL", "MSFT"])

    assert called == [["AAPL", "MSFT"]]
    assert set(out) == {"AAPL", "MSFT"}


def test_partial_batch_completes_missing_with_download(monkeypatch):
    session = _FakeSession({"AAPL": _quote("AAPL", 100.0, prev=99.0)})
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(
        mds, "_fetch_many_via_download",
        lambda symbols: {s: {"symbol": s, "company_name": s,
                             "current_price": 1.0, "change_percent": 0.0,
                             "change_available": False} for s in symbols})

    out = mds._fetch_many(["AAPL", "GARIP.XX"])

    assert out["AAPL"]["current_price"] == 100.0
    assert out["GARIP.XX"]["current_price"] == 1.0


def test_local_catalog_name_wins_over_contract_name(monkeypatch):
    """Yahoo GC=F için "Gold Dec 26" döndürüyor; bilinen ad varsa o kalmalı."""
    mds._name_cache["GC=F"] = "Altın (ons)"
    session = _FakeSession(
        {"GC=F": _quote("GC=F", 4500.0, prev=4520.0, name="Gold Dec 26")})
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(mds, "_fetch_many_via_download", lambda s: {})

    out = mds._fetch_many(["GC=F"])

    assert out["GC=F"]["company_name"] == "Altın (ons)"


def test_funds_are_excluded_from_quote_batch(monkeypatch):
    """TEFAS fonu Yahoo'da yok → batch'e girmemeli (kendi kaynağına gider)."""
    session = _FakeSession({"AAPL": _quote("AAPL", 100.0, prev=99.0)})
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(mds, "_fetch_many_via_download", lambda s: {})

    mds._fetch_many(["AAPL", "AFT.FON"])

    assert session.calls == [["AAPL"]]


# ── Vekil (Cloudflare Worker) yolu ────────────────────────────────────────
# Yahoo, Render'in paylasilan cikis IP'sini 429'luyor. Istek sayisi 51 → 1
# indi ama o tek istek de ayni cezali IP'den gidiyor → YAHOO_PROXY_BASE
# tanimliysa once vekil denenmeli, olmazsa dogrudan Yahoo (davranis en kotu
# ihtimalle bugunku hale doner).

class _UrlTrackingSession:
    def __init__(self, ok_url_contains: str | None, quotes):
        self.ok = ok_url_contains
        self.quotes = quotes
        self.urls: list[str] = []

    def get(self, url, params=None, timeout=None):
        self.urls.append(url)
        if self.ok is not None and self.ok not in url:
            return _Resp({}, 403)
        asked = (params or {}).get("symbols", "").split(",")
        return _Resp({"quoteResponse": {
            "result": [self.quotes[s] for s in asked if s in self.quotes]}})


def test_proxy_is_tried_first_when_configured(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "YAHOO_PROXY_BASE", "https://vekil.example")
    monkeypatch.setattr(mds, "_quote_url_pref", None)
    session = _UrlTrackingSession(None, {"AAPL": _quote("AAPL", 10.0, prev=9.0)})
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(mds, "_fetch_many_via_download", lambda s: {})

    mds._fetch_many(["AAPL"])

    assert session.urls[0].startswith("https://vekil.example")


def test_falls_back_to_direct_yahoo_when_proxy_rejects(monkeypatch):
    """Vekil yolu izin listesinde degilse/cerez dusmusse 403 doner —
    dogrudan Yahoo denenmeli, sonuc yine gelmeli."""
    from app.core.config import settings

    monkeypatch.setattr(settings, "YAHOO_PROXY_BASE", "https://vekil.example")
    monkeypatch.setattr(mds, "_quote_url_pref", None)
    session = _UrlTrackingSession(
        "query2.finance.yahoo.com", {"AAPL": _quote("AAPL", 10.0, prev=9.0)})
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(mds, "_fetch_many_via_download", lambda s: {})

    out = mds._fetch_many(["AAPL"])

    assert len(session.urls) == 2                      # once vekil, sonra Yahoo
    assert "query2.finance.yahoo.com" in session.urls[1]
    assert out["AAPL"]["current_price"] == 10.0


def test_direct_yahoo_used_when_no_proxy_configured(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "YAHOO_PROXY_BASE", "")
    monkeypatch.setattr(mds, "_quote_url_pref", None)
    session = _UrlTrackingSession(None, {"AAPL": _quote("AAPL", 10.0, prev=9.0)})
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(mds, "_fetch_many_via_download", lambda s: {})

    mds._fetch_many(["AAPL"])

    assert session.urls == [mds._QUOTE_DIRECT]


def test_encoded_symbols_get_turkish_names(monkeypatch):
    """Toplu uc GC=F icin "Gold Dec 26" (kontrat adi) donuyor; kullaniciya ve
    AI Koc'a giden ad Turkce olmali (6. turdaki "ham sembol" duzeltmesi)."""
    session = _FakeSession({
        "GC=F": _quote("GC=F", 4500.0, prev=4480.0, name="Gold Dec 26"),
        "USDTRY=X": _quote("USDTRY=X", 41.2, prev=41.0, name="USD/TRY"),
    })
    monkeypatch.setattr(mds, "_yf_session", lambda: session)
    monkeypatch.setattr(mds, "_fetch_many_via_download", lambda s: {})

    out = mds._fetch_many(["GC=F", "USDTRY=X"])

    assert out["GC=F"]["company_name"] == "Altın (ons)"
    assert out["USDTRY=X"]["company_name"] == "Dolar/TL"
