"""Fear & Greed Index hesaplama servisi.

Composite skor (0-100) üç sinyalden hesaplanır:
  1. VIX (volatilite) — yüksek VIX = korku
  2. S&P 500 momentum (5 günlük yüzde değişim) — pozitif = açgözlülük
  3. Haber sentiment ortalaması (VADER) — pozitif = açgözlülük

Klasik CNN Fear & Greed Index'in basitleştirilmiş versiyonu.
Cache: 10 dakika (verinin hızlı değişmesi gerekmiyor).
"""

import math
from datetime import datetime, timedelta
from loguru import logger
import yfinance as yf

from app.services import nlp_sentiment_service

_cache: dict[str, tuple[dict, datetime]] = {}
_CACHE_TTL_MINUTES = 10


def _json_safe(value):
    """NaN/inf değerleri JSON-uyumlu hale getirir (Starlette JSONResponse
    `allow_nan=False` ile render eder → NaN görürse 500 fırlatır). Son savunma:
    yfinance ara sıra NaN son-kapanış döndürür, sonuca sızarsa endpoint çökerdi."""
    if isinstance(value, float):
        return value if math.isfinite(value) else 0.0
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    return value


def _vix_score() -> tuple[float, float]:
    """VIX değerini 0-100 skora dönüştürür.
    Düşük VIX (10-15) → açgözlülük (yüksek skor)
    Yüksek VIX (35+) → aşırı korku (düşük skor)
    """
    try:
        vix = yf.Ticker("^VIX")
        hist = vix.history(period="5d")
        # NaN son-kapanışları at (yarım/eksik bar) — yoksa skora NaN sızar
        closes = hist["Close"].dropna() if not hist.empty else None
        if closes is None or closes.empty:
            return 50.0, 0.0
        current = float(closes.iloc[-1])
        # VIX 10-40 aralığını 100-0'a doğrusal eşle (ters orantı)
        clamped = max(10.0, min(40.0, current))
        score = (40.0 - clamped) / 30.0 * 100.0
        return score, current
    except Exception as exc:
        logger.warning(f"VIX fetch error: {exc}")
        return 50.0, 0.0


def _momentum_score() -> tuple[float, float]:
    """S&P 500 5 günlük momentum.
    +%3 üstü → 100, -%3 altı → 0, arası doğrusal.
    """
    try:
        spy = yf.Ticker("^GSPC")
        hist = spy.history(period="10d")
        # NaN son-kapanışları at — sızarsa pct_change=NaN → endpoint 500
        closes = hist["Close"].dropna() if not hist.empty else None
        if closes is None or len(closes) < 2:
            return 50.0, 0.0
        last = float(closes.iloc[-1])
        five_ago = float(closes.iloc[-6]) if len(closes) >= 6 else float(closes.iloc[0])
        if five_ago == 0:
            return 50.0, 0.0
        pct_change = ((last - five_ago) / five_ago) * 100
        # -3% → 0, +3% → 100, doğrusal
        clamped = max(-3.0, min(3.0, pct_change))
        score = (clamped + 3.0) / 6.0 * 100.0
        return score, pct_change
    except Exception as exc:
        logger.warning(f"Momentum fetch error: {exc}")
        return 50.0, 0.0


def _sentiment_score() -> tuple[float, float]:
    """Son haberlerin VADER sentiment ortalaması.
    -1 → 0 (aşırı korku), +1 → 100 (aşırı açgözlülük).
    """
    try:
        news = nlp_sentiment_service.get_financial_news(query="stock market")
        if not news:
            return 50.0, 0.0
        scores = [n["sentiment_score"] for n in news
                  if isinstance(n.get("sentiment_score"), (int, float))
                  and math.isfinite(n["sentiment_score"])]
        if not scores:
            return 50.0, 0.0
        avg = sum(scores) / len(scores)
        score = (avg + 1.0) / 2.0 * 100.0
        return score, avg
    except Exception as exc:
        logger.warning(f"Sentiment fetch error: {exc}")
        return 50.0, 0.0


def _label_for(score: float) -> str:
    if score < 20:
        return "Aşırı Korku"
    if score < 40:
        return "Korku"
    if score < 60:
        return "Nötr"
    if score < 80:
        return "Açgözlülük"
    return "Aşırı Açgözlülük"


def get_fear_greed_index(force_refresh: bool = False) -> dict:
    now = datetime.now()
    if not force_refresh and "data" in _cache:
        data, ts = _cache["data"]
        if now - ts < timedelta(minutes=_CACHE_TTL_MINUTES):
            return data

    vix_s, vix_v = _vix_score()
    mom_s, mom_v = _momentum_score()
    sent_s, sent_v = _sentiment_score()

    # Ağırlıklar: VIX %40, momentum %35, sentiment %25
    composite = vix_s * 0.40 + mom_s * 0.35 + sent_s * 0.25

    result = {
        "score": round(composite, 1),
        "label": _label_for(composite),
        "components": {
            "volatility": {
                "score": round(vix_s, 1),
                "vix_value": round(vix_v, 2),
                "weight": 0.40,
            },
            "momentum": {
                "score": round(mom_s, 1),
                "sp500_5d_pct": round(mom_v, 2),
                "weight": 0.35,
            },
            "sentiment": {
                "score": round(sent_s, 1),
                "news_avg": round(sent_v, 3),
                "weight": 0.25,
            },
        },
        "updated_at": now.isoformat(),
    }
    result = _json_safe(result)
    _cache["data"] = (result, now)
    return result
