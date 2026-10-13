"""Toplu kapanış serisi — /v8/finance/spark yolu.

10. turda ölçüldü: `yf.download` "batch" DEĞİL, sembol başına ayrı
`/v8/finance/chart/` isteği atıyor → 51 sembollük sinyal taraması 51 Yahoo
isteği. spark aynı seriyi TEK istekte 20 sembole kadar veriyor.

Burada kilitlenen:
 1. 20'lik gruplama (Yahoo 21+ sembolde "Bad Request" döndürüyor — 7 Eyl'de
    canlı ölçüldü),
 2. None kapanışların atılması (uydurma bar yok),
 3. spark'ın veremediği sembolde ESKİ yolun (yf.download) yedek kalması,
 4. 429'da devre kesici.

Ağ yok: HTTP katmanı mock'lanır.
"""

import pytest

from app.services import yahoo_chart_service as ycs


class _FakeResponse:
    def __init__(self, payload, status=200):
        self._payload = payload
        self.status_code = status

    def json(self):
        return self._payload


class _FakeClient:
    """httpx.Client yerine geçer; hangi sembollerin istendiğini kaydeder."""

    def __init__(self, payload_for, status=200):
        self.payload_for = payload_for
        self.status = status
        self.calls: list[list[str]] = []

    def get(self, url, params=None):
        syms = (params or {}).get("symbols", "").split(",")
        self.calls.append(syms)
        return _FakeResponse(self.payload_for(syms), self.status)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def _seri(sym):
    return {"timestamp": [1757079000, 1757165400],
            "close": [100.0, 101.5], "symbol": sym}


@pytest.fixture(autouse=True)
def _breaker_acik():
    ycs._blocked_until = 0.0
    yield
    ycs._blocked_until = 0.0


def _kur(monkeypatch, payload_for, status=200):
    client = _FakeClient(payload_for, status)
    monkeypatch.setattr(ycs.httpx, "Client", lambda **kw: client)
    return client


def test_yirmilik_gruplara_bolunur(monkeypatch):
    """Yahoo istek başına 20 sembol kabul ediyor; 45 sembol → 3 istek."""
    client = _kur(monkeypatch, lambda syms: {s: _seri(s) for s in syms})
    semboller = [f"S{i}.IS" for i in range(45)]
    out = ycs.get_daily_closes_batch(semboller)

    assert len(client.calls) == 3
    # Gruplar paralel gidiyor → sıra garanti değil, boyut dağılımı garanti
    assert sorted((len(c) for c in client.calls), reverse=True) == [20, 20, 5]
    assert len(out) == 45


def test_seri_iso_gune_cevrilir(monkeypatch):
    _kur(monkeypatch, lambda syms: {s: _seri(s) for s in syms})
    out = ycs.get_daily_closes_batch(["AAPL"])
    assert out["AAPL"] == {"2025-09-05": 100.0, "2025-09-06": 101.5}


def test_none_kapanis_atilir(monkeypatch):
    """Uydurma bar yok: None kapanış seriye girmez."""
    _kur(monkeypatch, lambda syms: {
        "AAPL": {"timestamp": [1757079000, 1757165400, 1757251800],
                 "close": [100.0, None, 102.0]}})
    out = ycs.get_daily_closes_batch(["AAPL"])
    assert list(out["AAPL"].values()) == [100.0, 102.0]


def test_hata_govdesi_bos_doner(monkeypatch):
    """{"spark": {"result": null, "error": ...}} → sessizce boş (yedek yol devreye girer)."""
    _kur(monkeypatch, lambda syms: {
        "spark": {"result": None, "error": {"code": "Bad Request"}}})
    assert ycs.get_daily_closes_batch(["AAPL"]) == {}


def test_429_devre_kesiciyi_tetikler(monkeypatch):
    _kur(monkeypatch, lambda syms: {}, status=429)
    assert ycs.get_daily_closes_batch(["AAPL"]) == {}
    assert not ycs.available()


def test_devre_kesik_ken_istek_atilmaz(monkeypatch):
    client = _kur(monkeypatch, lambda syms: {s: _seri(s) for s in syms})
    ycs._blocked_until = ycs.time.time() + 60
    assert ycs.get_daily_closes_batch(["AAPL"]) == {}
    assert client.calls == []


# ── market_data_service ile bütünleşme ───────────────────────────────────

def test_spark_once_denenir_eksikte_eski_yol(monkeypatch):
    """spark'ın veremediği sembol için yf.download yolu YEDEK kalmalı."""
    from app.services import market_data_service as m

    monkeypatch.setattr(
        "app.services.yahoo_chart_service.get_daily_closes_batch",
        lambda syms, rng="400d": {"AAPL": {"2026-09-05": 100.0}})

    dusenler: list[list[str]] = []

    def _fake_download(syms):
        dusenler.append(sorted(syms))
        return {"THYAO.IS": {"2026-09-05": 300.0}}

    monkeypatch.setattr(m, "_download_closes", _fake_download)
    monkeypatch.setattr(m, "_cache_set", lambda *a, **k: None)

    out = m.refresh_daily_closes(["AAPL", "THYAO.IS"])
    assert set(out) == {"AAPL", "THYAO.IS"}
    # Eski yola YALNIZ spark'ın veremediği sembol gitmeli
    assert dusenler == [["THYAO.IS"]]


def test_fon_ve_altin_sparka_gitmez(monkeypatch):
    """TEFAS fonu ve fiziki altın Yahoo'da YOK → boşuna istek atılmasın."""
    from app.services import market_data_service as m

    gidenler: list[list[str]] = []

    def _fake_spark(syms, rng="400d"):
        gidenler.append(sorted(syms))
        return {}

    monkeypatch.setattr(
        "app.services.yahoo_chart_service.get_daily_closes_batch", _fake_spark)
    monkeypatch.setattr(m, "_download_closes", lambda syms: {})
    monkeypatch.setattr(m, "_cache_set", lambda *a, **k: None)

    m.refresh_daily_closes(["AAPL", "TLY.FON", "CEYREK.ALTIN"])
    assert gidenler == [["AAPL"]]
