"""Toplu fiyat vekilden GERÇEKTEN geçiyor mu (çerez taşıma).

7 Eyl'de canlı ölçüldü: `/v7/finance/quote` Cloudflare Worker üzerinden **401**
dönüyordu, doğrudan Yahoo'da 200. Sebep Worker değil (izin listesi doğru,
`Cookie` başlığını iletiyor): yfinance'in çerez kavanozu çerezi `.yahoo.com`
alan adına saklıyor, istek `…workers.dev`e gidince çerezi TAKMIYOR → Yahoo
kimliksiz istek görüp reddediyor. Backend de sessizce doğrudan Yahoo'ya
düşüyordu; yani vekilin varlık sebebi (Render'ın cezalı IP'sini devreden
çıkarmak) bu uçta hiç işlemiyordu.

Burada kilitlenen: vekile giden istekte çerez BAŞLIKTA ve crumb PARAMETREDE
taşınır; doğrudan Yahoo yolunda eski davranış (yfinance kendi halleder) korunur.
"""

import pytest

from app.services import market_data_service as m


class _Cookie:
    name = "A3"
    value = "d=AQABtest"


class _Inner:
    """requests.Session yerine geçer (vekil yolu bunu kullanır)."""

    def __init__(self, recorder):
        self.recorder = recorder

    def get(self, url, params=None, headers=None, timeout=None):
        self.recorder.append({"url": url, "params": params or {},
                              "headers": headers or {}, "yol": "elle"})
        return _Resp()


class _Resp:
    status_code = 200

    def json(self):
        return {"quoteResponse": {"result": []}}


class _FakeYfData:
    """YfData yerine geçer."""

    def __init__(self, recorder, cookie=_Cookie()):
        self.recorder = recorder
        self._cookie = cookie
        self._session = _Inner(recorder)

    def _get_cookie_and_crumb(self):
        return "CRUMB123", "basic"

    def get(self, url, params=None, timeout=None):
        self.recorder.append({"url": url, "params": params or {},
                              "headers": {}, "yol": "yfinance"})
        return _Resp()


@pytest.fixture
def kayit(monkeypatch):
    rec: list[dict] = []
    monkeypatch.setattr(m, "_yf_session", lambda: _FakeYfData(rec))
    monkeypatch.setattr(m, "_quote_url_pref", None)
    return rec


def _vekilli(monkeypatch, base="https://vekil.example.dev"):
    monkeypatch.setattr("app.services.yahoo_chart_service.via_proxy",
                        lambda: True)
    monkeypatch.setattr("app.services.yahoo_chart_service.base_url",
                        lambda: base)


def test_vekile_giden_istek_cerez_ve_crumb_tasir(monkeypatch, kayit):
    _vekilli(monkeypatch)
    m._fetch_quotes_batch(["AAPL", "THYAO.IS"])

    ilk = kayit[0]
    assert ilk["url"].startswith("https://vekil.example.dev")
    assert ilk["headers"].get("Cookie") == "A3=d=AQABtest"
    assert ilk["params"]["crumb"] == "CRUMB123"
    assert ilk["params"]["symbols"] == "AAPL,THYAO.IS"
    assert ilk["yol"] == "elle"


def test_dogrudan_yahooda_eski_davranis(monkeypatch, kayit):
    """Vekil yokken yfinance kendi çerez/crumb mekanizmasını kullanmalı."""
    monkeypatch.setattr("app.services.yahoo_chart_service.via_proxy",
                        lambda: False)
    m._fetch_quotes_batch(["AAPL"])

    ilk = kayit[0]
    assert ilk["yol"] == "yfinance"
    assert "crumb" not in ilk["params"]
    assert ilk["headers"] == {}


def test_cerez_okunamazsa_eski_yola_dusulur(monkeypatch):
    """yfinance iç alanları değişirse çökme değil, bugünkü davranış."""
    rec: list[dict] = []
    monkeypatch.setattr(m, "_yf_session", lambda: _FakeYfData(rec, cookie=None))
    _vekilli(monkeypatch)
    m._fetch_quotes_batch(["AAPL"])
    assert rec[0]["yol"] == "yfinance"


def test_auth_hazirlanmasi_saf(monkeypatch):
    rec: list[dict] = []
    auth = m._proxy_quote_auth(_FakeYfData(rec))
    assert auth == {"crumb": "CRUMB123", "cookie": "A3=d=AQABtest"}
