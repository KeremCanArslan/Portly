"""Fiyat için ikinci kaynak — Yahoo 429'ladığında portföy fiyatsız kalmasın.

Yahoo Render IP'sini rate-limit'lediğinde `get_stock_prices` boş dönüyordu;
portföy her pozisyonu `avg_cost`'a düşürüp "%0,00 kâr/zarar" gösteriyordu
(fiyat = maliyet). Artık Yahoo'nun veremediği ABD hisseleri Finnhub'dan
denenir.

Sınırlar bilinçli: yalnız ABD hisseleri (ücretsiz tier BIST/emtia/kripto
kapsamaz) ve üst sınırlı sembol sayısı (sembol başına bir istek).
"""

import pytest

from app.core import cache
from app.services import market_data_service as mds
from app.services.gold_rates_service import spot_metal_usd as _real_spot_metal

# NOT: aşağıdaki autouse fixture `spot_metal_usd`'yi mock'luyor (testler ağa
# çıkmasın). Fonksiyonun KENDİ davranışını sınayan testler yukarıdaki gerçek
# referansı kullanır.


@pytest.fixture(autouse=True)
def _clean(monkeypatch):
    cache._mem.clear()
    # Emtia yedeği ağa çıkmasın; ilgilenen testler kendisi override eder.
    from app.services import gold_rates_service
    monkeypatch.setattr(gold_rates_service, "spot_metal_usd",
                        lambda symbols: {})
    yield
    cache._mem.clear()


@pytest.fixture
def yahoo_down(monkeypatch):
    """Yahoo hiçbir sembolü veremiyor (429)."""
    monkeypatch.setattr(mds, "_fetch_many", lambda symbols: {})


def _fake_finnhub(monkeypatch, prices: dict, calls: list | None = None):
    from app.services import finnhub_service

    def get_quote(symbol):
        if calls is not None:
            calls.append(symbol)
        p = prices.get(symbol)
        if p is None:
            return None
        return {"symbol": symbol, "current_price": p, "change_percent": 1.5}

    monkeypatch.setattr(finnhub_service, "get_quote", get_quote)
    monkeypatch.setattr(finnhub_service, "available", True)


def test_us_equity_recovered_from_second_source(yahoo_down, monkeypatch):
    _fake_finnhub(monkeypatch, {"LMT": 533.23, "NVDA": 180.0})

    out = mds.get_stock_prices(["LMT", "NVDA"])

    assert out["LMT"]["current_price"] == 533.23
    assert out["NVDA"]["change_percent"] == 1.5


def test_non_us_symbols_are_not_attempted(yahoo_down, monkeypatch):
    """BIST/emtia/kripto Finnhub ücretsiz tier'da yok — boşuna istek atma."""
    calls = []
    _fake_finnhub(monkeypatch, {}, calls)

    mds.get_stock_prices(["THYAO.IS", "GC=F", "BTC-USD", "USDTRY=X"])

    assert calls == [], f"kapsam dışı sembollere istek atıldı: {calls}"


def test_fallback_only_for_symbols_yahoo_missed(monkeypatch):
    """Yahoo verebildiği sembol için ikinci kaynağa gidilmemeli."""
    monkeypatch.setattr(mds, "_fetch_many", lambda symbols: {
        "AAPL": {"symbol": "AAPL", "company_name": "AAPL",
                 "current_price": 325.0, "change_percent": 0.5}})
    calls = []
    _fake_finnhub(monkeypatch, {"AAPL": 1.0, "LMT": 533.23}, calls)

    out = mds.get_stock_prices(["AAPL", "LMT"])

    assert calls == ["LMT"], f"Yahoo'nun verdiği sembol tekrar sorgulandı: {calls}"
    assert out["AAPL"]["current_price"] == 325.0   # Yahoo değeri korunur
    assert out["LMT"]["current_price"] == 533.23


def test_fallback_result_is_cached(yahoo_down, monkeypatch):
    calls = []
    _fake_finnhub(monkeypatch, {"LMT": 533.23}, calls)

    mds.get_stock_prices(["LMT"])
    mds.get_stock_prices(["LMT"])

    assert calls == ["LMT"], "yedek kaynaktan gelen fiyat cache'lenmedi"


def test_no_finnhub_key_is_graceful(yahoo_down, monkeypatch):
    from app.services import finnhub_service
    monkeypatch.setattr(finnhub_service, "available", False)

    assert mds.get_stock_prices(["LMT"]) == {}


def test_fallback_respects_symbol_limit(yahoo_down, monkeypatch):
    calls = []
    many = [f"AAA{i}" for i in range(mds._FALLBACK_QUOTE_LIMIT + 15)]
    _fake_finnhub(monkeypatch, {}, calls)

    mds.get_stock_prices(many)

    assert len(calls) == mds._FALLBACK_QUOTE_LIMIT


def test_quote_contract_matches_yahoo_shape(yahoo_down, monkeypatch):
    """Yedek kayıt, portföyün okuduğu alanları eksiksiz taşımalı."""
    _fake_finnhub(monkeypatch, {"LMT": 533.23})
    row = mds.get_stock_prices(["LMT"])["LMT"]
    assert set(row) >= {"symbol", "company_name", "current_price",
                        "change_percent"}


# ── finnhub_service.get_quote biçimi ──────────────────────────────────────

def test_get_quote_parses_finnhub_payload(monkeypatch):
    from app.services import finnhub_service
    monkeypatch.setattr(finnhub_service, "_get",
                        lambda p, q: {"c": 533.2345, "dp": 1.234, "pc": 527.0})
    assert finnhub_service.get_quote("LMT") == {
        "symbol": "LMT", "current_price": 533.23, "change_percent": 1.23}


@pytest.mark.parametrize("payload", [
    {"c": 0},          # kapsam dışı sembolde Finnhub 0 döndürür
    {"c": None},
    {},
    None,
])
def test_get_quote_rejects_empty_payloads(monkeypatch, payload):
    from app.services import finnhub_service
    monkeypatch.setattr(finnhub_service, "_get", lambda p, q: payload)
    assert finnhub_service.get_quote("NOPE") is None


# ── Emtia yedeği (altın/gümüş) ────────────────────────────────────────────

def _fake_spot(monkeypatch, prices: dict, calls: list | None = None):
    from app.services import gold_rates_service

    def spot_metal_usd(symbols):
        if calls is not None:
            calls.append(sorted(symbols))
        return {s: p for s, p in prices.items() if s in set(symbols)}

    monkeypatch.setattr(gold_rates_service, "spot_metal_usd", spot_metal_usd)


def test_gold_recovered_from_spot_source(yahoo_down, monkeypatch):
    """GC=F portföyün %18'i olabiliyor; fiyatsız kalınca avg_cost'a düşüp
    kâr/zararı %0 gösteriyordu."""
    _fake_spot(monkeypatch, {"GC=F": 4323.03, "SI=F": 63.98})

    out = mds.get_stock_prices(["GC=F", "SI=F"])

    assert out["GC=F"]["current_price"] == 4323.03
    assert out["SI=F"]["current_price"] == 63.98
    # Spot kaynak günlük değişim vermiyor ve chart da kapalı → uydurma yüzde
    # basılmamalı; ayrıca "bilinmiyor" bilgisi arayüze TAŞINMALI (yoksa ekran
    # yeşil "+%0,00" basıp "altın bugün hiç oynamadı" der).
    assert out["GC=F"]["change_percent"] == 0.0
    assert out["GC=F"]["change_available"] is False
    assert out["SI=F"]["change_available"] is False


def test_metal_daily_change_completed_from_chart(yahoo_down, monkeypatch):
    """Spot fiyat + chart'tan günlük değişim: fiyat spot kalır, değişim gerçek."""
    _fake_spot(monkeypatch, {"GC=F": 4323.03})
    from app.services import yahoo_chart_service
    monkeypatch.setattr(
        yahoo_chart_service, "get_quotes",
        lambda symbols: {"GC=F": {"symbol": "GC=F", "company_name": "GC=F",
                                  "current_price": 4375.10,
                                  "change_percent": 0.87}}
        if "GC=F" in symbols else {})

    out = mds.get_stock_prices(["GC=F"])

    assert out["GC=F"]["current_price"] == 4323.03   # fiyat spot kaynaktan
    assert out["GC=F"]["change_percent"] == 0.87     # değişim chart'tan
    assert out["GC=F"]["change_available"] is True


def test_spot_source_not_called_when_yahoo_has_data(monkeypatch):
    calls = []
    monkeypatch.setattr(mds, "_fetch_many", lambda symbols: {
        "GC=F": {"symbol": "GC=F", "company_name": "GC=F",
                 "current_price": 4375.1, "change_percent": 0.4}})
    _fake_spot(monkeypatch, {"GC=F": 4323.03}, calls)

    out = mds.get_stock_prices(["GC=F"])

    assert calls == [], "Yahoo verirken emtia yedeği çağrıldı"
    assert out["GC=F"]["current_price"] == 4375.1


def test_metal_and_equity_fallbacks_combine(yahoo_down, monkeypatch):
    _fake_spot(monkeypatch, {"GC=F": 4323.03})
    _fake_finnhub(monkeypatch, {"LMT": 533.23})

    out = mds.get_stock_prices(["GC=F", "LMT", "THYAO.IS"])

    assert set(out) == {"GC=F", "LMT"}     # BIST'in yedeği yok, dürüstçe eksik
    assert out["GC=F"]["current_price"] == 4323.03
    assert out["LMT"]["current_price"] == 533.23


def test_spot_failure_does_not_break_equity_fallback(yahoo_down, monkeypatch):
    from app.services import gold_rates_service

    def boom(symbols):
        raise RuntimeError("truncgil düştü")

    monkeypatch.setattr(gold_rates_service, "spot_metal_usd", boom)
    _fake_finnhub(monkeypatch, {"LMT": 533.23})

    out = mds.get_stock_prices(["GC=F", "LMT"])
    assert out["LMT"]["current_price"] == 533.23


# ── spot_metal_usd biçimi ─────────────────────────────────────────────────

def _truncgil_payload():
    return {
        "USD": {"Alış": "48,2947", "Satış": "48,3000"},
        "ons": {"Alış": "$4.322,75", "Satış": "$4.323,31"},
        "gumus": {"Alış": "99,30", "Satış": "99,39"},
    }


def test_spot_metal_parses_and_converts(monkeypatch):
    from app.services import gold_rates_service as g
    monkeypatch.setattr(g, "_fetch_truncgil", lambda attempts=2: _truncgil_payload())

    out = _real_spot_metal(["GC=F", "SI=F"])

    assert out["GC=F"] == pytest.approx(4323.03, abs=0.05)
    # gümüş ₺/gram → USD/ons çevrimi
    assert out["SI=F"] == pytest.approx(63.98, abs=0.05)


def test_spot_metal_ignores_unrelated_symbols(monkeypatch):
    from app.services import gold_rates_service as g
    calls = []
    monkeypatch.setattr(g, "_fetch_truncgil",
                        lambda attempts=2: calls.append(1) or _truncgil_payload())

    assert _real_spot_metal(["AAPL", "THYAO.IS"]) == {}
    assert calls == [], "ilgisiz sembol için kaynak yorulmamalı"


def test_spot_metal_handles_dead_source(monkeypatch):
    from app.services import gold_rates_service as g
    monkeypatch.setattr(g, "_fetch_truncgil", lambda attempts=2: None)
    assert _real_spot_metal(["GC=F"]) == {}


def test_spot_metal_skips_zero_rows(monkeypatch):
    """Kaynak bazen 0 döndürüyor (yeni şemada ONS böyle geldi) — 0 fiyat
    portföye SIZMAMALI."""
    from app.services import gold_rates_service as g
    monkeypatch.setattr(g, "_fetch_truncgil", lambda attempts=2: {
        "USD": {"Alış": "48,29", "Satış": "48,30"},
        "ons": {"Alış": "0", "Satış": "0"},
    })
    assert _real_spot_metal(["GC=F"]) == {}


def test_primary_source_raising_still_reaches_fallback(monkeypatch):
    """Birincil kaynak {} DÖNDÜRMEK yerine FIRLATIRSA da yedek çalışmalı —
    yedeğin var olma sebebi tam olarak bu an."""
    def boom(symbols):
        raise RuntimeError("Yahoo 429")

    monkeypatch.setattr(mds, "_fetch_many", boom)
    _fake_finnhub(monkeypatch, {"LMT": 533.23})

    out = mds.get_stock_prices(["LMT"])
    assert out["LMT"]["current_price"] == 533.23


# ── Tek sembol yolu (/market/price/{symbol}) ──────────────────────────────

def test_single_symbol_path_also_has_fallback(monkeypatch):
    """Batch yolunda yedek vardı ama tek sembol yolunda YOKTU: hisse detayı
    Yahoo 429'ladığında 400 hatası dönüyordu."""
    def boom(symbol):
        raise RuntimeError("Yahoo 429")

    monkeypatch.setattr(mds, "_fetch_stock_data", boom)
    monkeypatch.setattr(mds, "_ensure_name", lambda s: "Lockheed Martin")
    _fake_finnhub(monkeypatch, {"LMT": 533.23})

    out = mds.get_stock_data("LMT")
    assert out["current_price"] == 533.23
    assert out["company_name"] == "Lockheed Martin"


def test_single_symbol_path_raises_when_no_fallback(monkeypatch):
    """Yedeği olmayan sembolde (BIST) dürüstçe hata — uydurma fiyat yok."""
    from fastapi import HTTPException

    def boom(symbol):
        raise RuntimeError("Yahoo 429")

    monkeypatch.setattr(mds, "_fetch_stock_data", boom)
    _fake_finnhub(monkeypatch, {})
    with pytest.raises(HTTPException):
        mds.get_stock_data("THYAO.IS")


def test_single_symbol_fallback_is_cached(monkeypatch):
    def boom(symbol):
        raise RuntimeError("Yahoo 429")

    monkeypatch.setattr(mds, "_fetch_stock_data", boom)
    monkeypatch.setattr(mds, "_ensure_name", lambda s: s)
    calls = []
    _fake_finnhub(monkeypatch, {"LMT": 533.23}, calls)

    mds.get_stock_data("LMT")
    mds.get_stock_data("LMT")
    assert calls == ["LMT"], "yedekten gelen tek sembol fiyatı cache'lenmedi"
