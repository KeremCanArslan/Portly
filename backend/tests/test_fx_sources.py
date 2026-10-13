"""USDTRY kaynak zinciri — tek kaynağa bağlı kalmama garantisi.

Neden var: Yahoo, Render IP'sini 429'ladığında `usdtry_rate()` sabit 41.0'e
düşüyor VE bunu süreç ömrü boyunca cache'liyordu. Gerçek kur ~48 iken
portföydeki her USD pozisyonu ₺ karşılığında ~%15 eksik görünüyordu.

Garantiler:
 1. Yahoo düşerse truncgil, o da düşerse frankfurter denenir.
 2. Sabit değere SON çare olarak düşülür ve KISA cache'lenir (bir sonraki
    istek kaynakları yeniden dener).
 3. Bozuk/absürt değer (ters kur, 100x kayma) sessizce kabul edilmez.

Ağ yok: her kaynak monkeypatch'lenir.
"""

import pytest

from app.services import fx_service as fx


@pytest.fixture(autouse=True)
def _clear():
    fx._cache.clear()
    yield
    fx._cache.clear()


def _patch(monkeypatch, *, yahoo=None, truncgil=None, frankfurter=None):
    """Kaynakları sırayla sahteler; None = o kaynak düştü."""
    calls = []

    def mk(name, value):
        def _f():
            calls.append(name)
            return value
        return _f

    monkeypatch.setattr(fx, "_SOURCES", (
        ("yahoo", mk("yahoo", yahoo)),
        ("truncgil", mk("truncgil", truncgil)),
        ("frankfurter", mk("frankfurter", frankfurter)),
    ))
    return calls


# ── Zincir sırası ─────────────────────────────────────────────────────────

def test_yahoo_wins_when_available(monkeypatch):
    calls = _patch(monkeypatch, yahoo=48.1, truncgil=48.3)
    assert fx.usdtry_rate() == 48.1
    assert calls == ["yahoo"], "Yahoo çalışırken diğer kaynaklar yorulmamalı"
    assert fx.rate_source() == "yahoo"


def test_falls_to_truncgil_when_yahoo_down(monkeypatch):
    """429 senaryosu — asıl düzeltilen hata."""
    calls = _patch(monkeypatch, yahoo=None, truncgil=48.3, frankfurter=48.2)
    assert fx.usdtry_rate() == 48.3
    assert calls == ["yahoo", "truncgil"]
    assert fx.rate_source() == "truncgil"


def test_falls_to_frankfurter_when_first_two_down(monkeypatch):
    calls = _patch(monkeypatch, yahoo=None, truncgil=None, frankfurter=48.2)
    assert fx.usdtry_rate() == 48.2
    assert calls == ["yahoo", "truncgil", "frankfurter"]


def test_constant_is_last_resort_only(monkeypatch):
    _patch(monkeypatch)  # hepsi düştü
    assert fx.usdtry_rate() == fx._FALLBACK
    assert fx.rate_source() == "fallback"


def test_source_exception_does_not_break_chain(monkeypatch):
    def boom():
        raise RuntimeError("ağ patladı")

    monkeypatch.setattr(fx, "_SOURCES", (
        ("yahoo", boom),
        ("truncgil", lambda: 48.3),
    ))
    assert fx.usdtry_rate() == 48.3


# ── Cache: kötü bir an kalıcı hale gelmemeli ──────────────────────────────

def test_fallback_is_retried_soon(monkeypatch):
    """Sabit değere düşülünce KISA cache — eski kod TTL'siz cache'leyip
    yanlış kuru süreç ömrü boyunca sabitliyordu."""
    _patch(monkeypatch)
    assert fx.usdtry_rate() == fx._FALLBACK

    # _TTL_FALLBACK kadar zaman geçmiş gibi yap, kaynak da düzelmiş olsun
    fx._cache["ts"] -= fx._TTL_FALLBACK + 1
    _patch(monkeypatch, truncgil=48.3)
    assert fx.usdtry_rate() == 48.3, "fallback sonrası tekrar denenmedi"


def test_live_rate_is_cached_not_refetched(monkeypatch):
    calls = _patch(monkeypatch, yahoo=48.1)
    fx.usdtry_rate()
    fx.usdtry_rate()
    fx.usdtry_rate()
    assert calls == ["yahoo"], "taze kur her çağrıda yeniden çekiliyor"


def test_live_rate_refreshes_after_ttl(monkeypatch):
    _patch(monkeypatch, yahoo=48.1)
    assert fx.usdtry_rate() == 48.1
    fx._cache["ts"] -= fx._TTL_LIVE + 1
    _patch(monkeypatch, yahoo=49.5)
    assert fx.usdtry_rate() == 49.5


# ── Bozuk değer savunması ─────────────────────────────────────────────────

@pytest.mark.parametrize("bad", [0, -1, 4830.0, 0.0207, float("nan"),
                                 float("inf"), None, "abc"])
def test_invalid_rates_rejected(bad):
    """Ters kur (0.0207), 100x kayma (4830) ve bozuk tipler reddedilmeli —
    kabul edilse portföyün ₺ değeri sessizce saçmalardı."""
    assert fx._valid(bad) is None


@pytest.mark.parametrize("good,expected", [(48.3, 48.3), ("48.3", 48.3),
                                           (41, 41.0)])
def test_valid_rates_accepted(good, expected):
    assert fx._valid(good) == pytest.approx(expected)


def test_bad_source_value_is_skipped_for_next_source(monkeypatch):
    """Kaynak absürt değer döndürürse zincir durmamalı."""
    monkeypatch.setattr(fx, "_SOURCES", (
        ("yahoo", lambda: fx._valid(0.0207)),   # ters kur → None
        ("truncgil", lambda: 48.3),
    ))
    assert fx.usdtry_rate() == 48.3


# ── truncgil şema uyumu (iki biçim de dolaşımda) ──────────────────────────

def test_parses_both_truncgil_schemas(monkeypatch):
    yeni = {"Rates": {"USD": {"Buying": 48.2944, "Selling": 48.3004}}}
    eski = {"USD": {"Alış": "48,2947", "Satış": "48,3000"}}

    for payload, beklenen in ((yeni, 48.2974), (eski, 48.29735)):
        class _R:
            status_code = 200

            @staticmethod
            def json():
                return payload

        monkeypatch.setattr(fx.requests, "get", lambda *a, **k: _R())
        assert fx._from_truncgil() == pytest.approx(beklenen, abs=1e-3)


def test_truncgil_tr_number_format():
    assert fx._parse_tr_number("1.234,56") == pytest.approx(1234.56)
    assert fx._parse_tr_number("48,3000") == pytest.approx(48.3)
    assert fx._parse_tr_number(48.3) == pytest.approx(48.3)
    assert fx._parse_tr_number(None) is None
