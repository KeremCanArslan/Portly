"""signal_service birim testleri — kural skoru, etiket eşleme, kullanıcı taraması.

Ağ YOK: teknik göstergeler ve temel oranlar sahte dict'lerle beslenir;
get_signals_for_user testinde get_signal monkeypatch'lenir.
"""

import pytest

from app.services import signal_service
from app.models.portfolio import Portfolio
from app.models.watchlist import WatchlistItem


def _bullish_indicators() -> dict:
    return {
        "current_price": 110.0,
        "sma50": 100.0,
        "sma200": 90.0,
        "rsi14": 28.0,
        "macd": {"macd": 1.2},
        "bollinger": {"pct_b": 0.4},
        "stochastic": 15.0,
        "volume_trend_pct": 40.0,
        "return_5d_pct": 3.0,
    }


def _bearish_indicators() -> dict:
    return {
        "current_price": 80.0,
        "sma50": 100.0,
        "sma200": 110.0,
        "rsi14": 78.0,
        "macd": {"macd": -0.8},
        "bollinger": {"pct_b": 1.2},
        "stochastic": 88.0,
        "volume_trend_pct": 40.0,
        "return_5d_pct": -4.0,
    }


class TestTechnicalRules:
    def test_bullish_setup_scores_high(self):
        r = signal_service._technical_rules(_bullish_indicators())
        assert r.clamped() >= 65
        assert any("RSI" in t for t in r.top_reasons())

    def test_bearish_setup_scores_low(self):
        r = signal_service._technical_rules(_bearish_indicators())
        assert r.clamped() <= 35

    def test_missing_indicators_stay_neutral(self):
        r = signal_service._technical_rules({"current_price": 100.0})
        assert r.clamped() == 50
        assert r.top_reasons() == []

    def test_nan_indicator_ignored(self):
        ind = _bullish_indicators()
        ind["rsi14"] = float("nan")
        r = signal_service._technical_rules(ind)
        assert all("RSI" not in t for t in r.top_reasons())

    def test_reasons_sorted_by_weight(self):
        r = signal_service._Rules()
        r.add(2, "küçük")
        r.add(-9, "büyük")
        assert r.top_reasons()[0] == "büyük"


class TestFundamentalRules:
    def test_cheap_profitable_grower_scores_high(self):
        f = {
            "pe_trailing": 10.0, "peg": 0.8, "roe_pct": 25.0,
            "profit_margin_pct": 20.0, "revenue_growth_pct": 18.0,
            "debt_to_equity": 40.0, "dividend_yield_pct": 3.5,
            "analyst_recommendation": "buy", "analyst_count": 30,
            "current_price": 52.0, "fifty_two_week_low": 50.0,
            "fifty_two_week_high": 100.0,
        }
        r = signal_service._fundamental_rules(f)
        assert r.clamped() >= 80
        assert any("Analist" in t for t in r.top_reasons(10))

    def test_expensive_loser_scores_low(self):
        f = {
            "pe_trailing": 60.0, "peg": 3.0, "roe_pct": -5.0,
            "profit_margin_pct": -10.0, "revenue_growth_pct": -8.0,
            "debt_to_equity": 300.0,
            "analyst_recommendation": "sell", "analyst_count": 12,
        }
        r = signal_service._fundamental_rules(f)
        assert r.clamped() <= 20

    def test_empty_ratios_neutral(self):
        r = signal_service._fundamental_rules({})
        assert r.clamped() == 50


class TestCombineAndLabel:
    def test_no_fundamental_uses_technical(self):
        assert signal_service._combine(70, None) == 70

    def test_blend_55_45(self):
        assert signal_service._combine(80, 40) == round(0.55 * 80 + 0.45 * 40)

    @pytest.mark.parametrize("score,label", [
        (65, "AL"), (100, "AL"), (64, "TUT"), (36, "TUT"), (35, "SAT"), (0, "SAT"),
    ])
    def test_labels(self, score, label):
        assert signal_service._label(score) == label


class TestGetSignal:
    @pytest.fixture(autouse=True)
    def _clear_caches(self):
        # Temel oran cache'i paylaşılan cache'te (Redis/in-process) yaşıyor.
        from app.core import cache
        signal_service._signal_cache.clear()
        cache._mem.clear()
        yield
        signal_service._signal_cache.clear()
        cache._mem.clear()

    def test_stock_with_fundamentals(self, monkeypatch):
        monkeypatch.setattr(
            signal_service.technical_analysis_service,
            "_compute_indicators", lambda s, bars=None: _bullish_indicators())
        monkeypatch.setattr(
            signal_service, "_get_fundamentals_cached",
            lambda s: {"pe_trailing": 10.0, "roe_pct": 25.0,
                       "profit_margin_pct": 20.0})
        sig = signal_service.get_signal("AAPL")
        assert sig["signal"] == "AL"
        assert sig["fundamental_available"] is True
        assert sig["fundamental_score"] is not None
        assert sig["asset_class"] == "stock"
        assert sig["reasons"]

    def test_crypto_skips_fundamentals(self, monkeypatch):
        monkeypatch.setattr(
            signal_service.technical_analysis_service,
            "_compute_indicators", lambda s, bars=None: _bearish_indicators())
        sig = signal_service.get_signal("BTC-USD")
        assert sig["asset_class"] == "crypto"
        assert sig["fundamental_score"] is None
        assert sig["signal"] == "SAT"
        assert any("teknik göstergelere dayalı" in t for t in sig["reasons"])

    def test_stock_without_fundamentals_notes_it(self, monkeypatch):
        monkeypatch.setattr(
            signal_service.technical_analysis_service,
            "_compute_indicators", lambda s, bars=None: {"current_price": 100.0})
        monkeypatch.setattr(
            signal_service, "_get_fundamentals_cached", lambda s: None)
        sig = signal_service.get_signal("THYAO.IS")
        assert sig["signal"] == "TUT"
        assert sig["fundamental_available"] is False
        assert any("Temel oran verisi şu an yok" in t for t in sig["reasons"])

    def test_cache_hit_skips_recompute(self, monkeypatch):
        calls = {"n": 0}

        def fake_ind(s, bars=None):
            calls["n"] += 1
            return _bullish_indicators()

        monkeypatch.setattr(
            signal_service.technical_analysis_service,
            "_compute_indicators", fake_ind)
        monkeypatch.setattr(
            signal_service, "_get_fundamentals_cached", lambda s: None)
        signal_service.get_signal("NVDA")
        signal_service.get_signal("NVDA")
        assert calls["n"] == 1
        signal_service.get_signal("NVDA", force_refresh=True)
        assert calls["n"] == 2


class TestUserScan:
    @pytest.fixture(autouse=True)
    def _clear_caches(self):
        signal_service._signal_cache.clear()
        yield
        signal_service._signal_cache.clear()

    def test_scan_merges_portfolio_and_watchlist(self, db, make_user, monkeypatch):
        user = make_user()
        db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=5,
                         average_cost=100.0))
        db.add(WatchlistItem(user_id=user.id, symbol="NVDA", position=0))
        db.add(WatchlistItem(user_id=user.id, symbol="AAPL", position=1))
        db.commit()

        def fake_signal(symbol, force_refresh=False, bars=None):
            return {"symbol": symbol, "score": 70 if symbol == "NVDA" else 55,
                    "signal": "AL", "reasons": []}

        monkeypatch.setattr(signal_service, "get_signal", fake_signal)
        out = signal_service.get_signals_for_user(db, user.id)
        by_symbol = {s["symbol"]: s for s in out["signals"]}
        assert set(by_symbol) == {"AAPL", "NVDA"}
        assert by_symbol["AAPL"]["source"] == "both"
        assert by_symbol["NVDA"]["source"] == "watchlist"
        # Güçlü sinyal (50'den sapması büyük) üstte
        assert out["signals"][0]["symbol"] == "NVDA"
        assert out["disclaimer"]

    def test_failed_symbol_reported_not_fatal(self, db, make_user, monkeypatch):
        user = make_user()
        db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=5,
                         average_cost=100.0))
        db.add(Portfolio(user_id=user.id, symbol="BOZUK", quantity=1,
                         average_cost=1.0))
        db.commit()

        def fake_signal(symbol, force_refresh=False, bars=None):
            if symbol == "BOZUK":
                raise ValueError("veri yok")
            return {"symbol": symbol, "score": 60, "signal": "TUT", "reasons": []}

        monkeypatch.setattr(signal_service, "get_signal", fake_signal)
        out = signal_service.get_signals_for_user(db, user.id)
        assert [s["symbol"] for s in out["signals"]] == ["AAPL"]
        assert out["failed"] == ["BOZUK"]

    def test_empty_user_returns_empty(self, db, make_user):
        user = make_user()
        out = signal_service.get_signals_for_user(db, user.id)
        assert out["signals"] == [] and out["failed"] == []


class TestFundamentalCachePersistence:
    """Temel oran cache'i PAYLAŞILAN cache'te olmalı: süreç-içi tutulunca her
    deploy/uyanış sonrası ilk tarama 24 sn sürüyordu (canlı ölçüm)."""

    @pytest.fixture(autouse=True)
    def _clean(self):
        from app.core import cache
        cache._mem.clear()
        signal_service._signal_cache.clear()
        yield
        cache._mem.clear()
        signal_service._signal_cache.clear()

    def test_oranlar_paylasilan_cache_ten_okunur(self, monkeypatch):
        calls = []

        def _compute(symbol):
            calls.append(symbol)
            return {"pe_trailing": 10.0, "data_limited": False}

        monkeypatch.setattr(
            signal_service.fundamental_analysis_service,
            "_compute_fundamentals", _compute)

        assert signal_service._get_fundamentals_cached("AAPL")["pe_trailing"] == 10.0
        assert signal_service._get_fundamentals_cached("AAPL")["pe_trailing"] == 10.0
        assert calls == ["AAPL"]          # ikinci çağrı ağa/hesaba gitmedi

    def test_oran_yok_sonucu_da_cachelenir(self, monkeypatch):
        """BIST hisselerinde oran gelmiyor; cache'lenmezse her tarama boşuna
        yeniden deniyordu."""
        calls = []

        def _compute(symbol):
            calls.append(symbol)
            return {"data_limited": True}

        monkeypatch.setattr(
            signal_service.fundamental_analysis_service,
            "_compute_fundamentals", _compute)

        assert signal_service._get_fundamentals_cached("THYAO.IS") is None
        assert signal_service._get_fundamentals_cached("THYAO.IS") is None
        assert calls == ["THYAO.IS"]
