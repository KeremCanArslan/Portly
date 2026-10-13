"""Teknik analiz tahmin servisi.

Klasik TA göstergeleri (SMA, RSI, MACD) hesaplar, Groq LLM'e yorumlatır.
"""

import json
from datetime import datetime, timedelta
from loguru import logger

from app.services import llm_service

_cache: dict[str, tuple[dict, datetime]] = {}
_CACHE_TTL_MINUTES = 15


def _sma(values: list[float], period: int) -> float | None:
    if len(values) < period:
        return None
    return sum(values[-period:]) / period


def _rsi(closes: list[float], period: int = 14) -> float | None:
    if len(closes) < period + 1:
        return None
    gains, losses = 0.0, 0.0
    for i in range(-period, 0):
        delta = closes[i] - closes[i - 1]
        if delta >= 0:
            gains += delta
        else:
            losses -= delta
    if losses == 0:
        return 100.0
    rs = (gains / period) / (losses / period)
    return round(100 - 100 / (1 + rs), 2)


def _ema(values: list[float], period: int) -> float | None:
    if len(values) < period:
        return None
    k = 2 / (period + 1)
    ema = values[0]
    for v in values[1:]:
        ema = v * k + ema * (1 - k)
    return ema


def _macd(closes: list[float]) -> dict | None:
    if len(closes) < 35:
        return None
    ema12 = _ema(closes, 12)
    ema26 = _ema(closes, 26)
    if ema12 is None or ema26 is None:
        return None
    macd = ema12 - ema26
    return {"macd": round(macd, 3), "ema12": round(ema12, 2), "ema26": round(ema26, 2)}


def _bollinger(closes: list[float], period: int = 20, mult: float = 2.0) -> dict | None:
    if len(closes) < period:
        return None
    recent = closes[-period:]
    mean = sum(recent) / period
    var = sum((c - mean) ** 2 for c in recent) / period
    std = var ** 0.5
    upper = mean + mult * std
    lower = mean - mult * std
    current = closes[-1]
    # %B göstergesi: 0 = alt banda yakın, 1 = üst banda yakın
    pct_b = (current - lower) / (upper - lower) if upper != lower else 0.5
    bandwidth = (upper - lower) / mean * 100
    return {
        "upper": round(upper, 2),
        "middle": round(mean, 2),
        "lower": round(lower, 2),
        "pct_b": round(pct_b, 2),
        "bandwidth_pct": round(bandwidth, 2),
    }


def _stochastic(highs: list[float], lows: list[float], closes: list[float],
                period: int = 14) -> float | None:
    if len(closes) < period:
        return None
    recent_high = max(highs[-period:])
    recent_low = min(lows[-period:])
    if recent_high == recent_low:
        return 50.0
    return round((closes[-1] - recent_low) / (recent_high - recent_low) * 100, 2)


def _atr(highs: list[float], lows: list[float], closes: list[float],
         period: int = 14) -> float | None:
    """Average True Range — volatilite ölçüsü, stop-loss mesafesi için iyi."""
    if len(closes) < period + 1:
        return None
    trs = []
    for i in range(1, len(closes)):
        tr = max(
            highs[i] - lows[i],
            abs(highs[i] - closes[i - 1]),
            abs(lows[i] - closes[i - 1]),
        )
        trs.append(tr)
    if len(trs) < period:
        return None
    return round(sum(trs[-period:]) / period, 2)


def _support_resistance(highs: list[float], lows: list[float]) -> dict:
    """Son 3 aydaki dikkat çeken seviyeleri çıkarır."""
    return {
        "resistance_3m": round(max(highs[-60:]) if len(highs) >= 60 else max(highs), 2),
        "support_3m": round(min(lows[-60:]) if len(lows) >= 60 else min(lows), 2),
        "resistance_1m": round(max(highs[-20:]) if len(highs) >= 20 else max(highs), 2),
        "support_1m": round(min(lows[-20:]) if len(lows) >= 20 else min(lows), 2),
    }


def _compute_indicators(symbol: str, bars: dict | None = None) -> dict:
    """6 aylık günlük OHLC'den kapsamlı TA göstergeleri.

    Veri PAYLAŞILAN batch cache'ten okunur (market_data_service.get_daily_ohlcv):
    çağıran önce tüm sembolleri tek `yf.download` ile ısıtırsa burası ağa hiç
    çıkmaz. Eskiden sembol başına ayrı `yf.Ticker().history()` vardı → 40
    sembollük sinyal taraması Yahoo'dan 429 yiyip sinyalleri boşaltıyordu.

    `bars` verilirse cache'e HİÇ gidilmez: sinyal taraması zaten tüm sembolleri
    tek çağrıda ısıtıyor, aynı seriyi işçi başına yeniden okumak (Redis'te ağ
    gidiş-dönüşü + JSON çözme) boşuna maliyetti."""
    if bars is None:
        from app.services import market_data_service
        bars = market_data_service.get_daily_ohlcv([symbol], "6mo").get(symbol.upper())
    if not bars or not bars.get("close"):
        raise ValueError(f"Veri bulunamadı: {symbol}")

    closes = [float(c) for c in bars["close"]]
    highs = [float(h) for h in bars["high"]]
    lows = [float(l) for l in bars["low"]]
    volumes = [float(v) for v in bars["volume"]]

    current = closes[-1]
    # Fon birim pay değeri 1,096196 gibi olabiliyor → 2 basamağa yuvarlamak
    # binde 3'lük hata demek. Fiyat/SMA'lar fonda 6 basamak tutulur.
    from app.services import fund_catalog
    dp = 6 if fund_catalog.is_fund_symbol(symbol) else 2
    sma20 = _sma(closes, 20)
    sma50 = _sma(closes, 50)
    sma200 = _sma(closes, 200)
    rsi14 = _rsi(closes, 14)
    macd_data = _macd(closes)
    bb = _bollinger(closes, 20, 2.0)
    stoch = _stochastic(highs, lows, closes, 14)
    atr = _atr(highs, lows, closes, 14)
    sr = _support_resistance(highs, lows)

    # Hacim trendi: son 5 günün hacim ortalaması vs son 20 günün
    vol_recent = sum(volumes[-5:]) / 5 if len(volumes) >= 5 else 0
    vol_baseline = sum(volumes[-20:]) / 20 if len(volumes) >= 20 else 0
    volume_trend = (
        round((vol_recent - vol_baseline) / vol_baseline * 100, 2)
        if vol_baseline > 0 else None
    )

    # 30 günlük volatilite
    if len(closes) >= 30:
        recent = closes[-30:]
        mean = sum(recent) / len(recent)
        var = sum((c - mean) ** 2 for c in recent) / len(recent)
        volatility_pct = round((var ** 0.5) / mean * 100, 2)
    else:
        volatility_pct = None

    # 1g, 5g, 30g getirileri
    def _ret(days: int) -> float | None:
        if len(closes) <= days:
            return None
        return round((closes[-1] - closes[-1 - days]) / closes[-1 - days] * 100, 2)

    return {
        "current_price": round(current, dp),
        "sma20": round(sma20, dp) if sma20 else None,
        "sma50": round(sma50, dp) if sma50 else None,
        "sma200": round(sma200, dp) if sma200 else None,
        "rsi14": rsi14,
        "macd": macd_data,
        "bollinger": bb,
        "stochastic": stoch,
        "atr": atr,
        **sr,
        "volume_trend_pct": volume_trend,
        "volatility_30d_pct": volatility_pct,
        "return_1d_pct": _ret(1),
        "return_5d_pct": _ret(5),
        "return_30d_pct": _ret(30),
    }


def _build_prompt(symbol: str, indicators: dict) -> str:
    ind = indicators
    return f"""{symbol} hissesi için profesyonel teknik analiz yap. Aşağıdaki göstergeleri yorumla.

═══ FİYAT ═══
Cari fiyat: {ind['current_price']}
1 gün: %{ind.get('return_1d_pct')}, 5 gün: %{ind.get('return_5d_pct')}, 30 gün: %{ind.get('return_30d_pct')}

═══ TREND (Hareketli Ortalamalar) ═══
SMA20: {ind.get('sma20')}  SMA50: {ind.get('sma50')}  SMA200: {ind.get('sma200')}
(SMA20 > SMA50 yükseliş, SMA50 > SMA200 uzun vade yükseliş)

═══ MOMENTUM ═══
RSI(14): {ind.get('rsi14')}  (>70 aşırı alım, <30 aşırı satım)
Stochastic(14): {ind.get('stochastic')}  (>80 aşırı alım, <20 aşırı satım)
MACD: {ind.get('macd')}  (MACD > 0 yükseliş)

═══ VOLATİLİTE ═══
Bollinger: {ind.get('bollinger')}  (%B > 1 üst banda taşma, < 0 alt banda taşma)
ATR(14): {ind.get('atr')}  (önerilen stop-loss mesafesi)
30g volatilite: %{ind.get('volatility_30d_pct')}

═══ DESTEK / DİRENÇ ═══
Yakın direnç (1ay): {ind.get('resistance_1m')}, uzak direnç (3ay): {ind.get('resistance_3m')}
Yakın destek (1ay): {ind.get('support_1m')}, uzak destek (3ay): {ind.get('support_3m')}

═══ HACİM ═══
Son 5 gün hacim trendi: %{ind.get('volume_trend_pct')} (pozitif = artan ilgi)

ÇIKTI: Yalnızca geçerli JSON dön, başka metin yok. Detaylı, profesyonel ve dürüst yorum yap:

{{
  "direction": "BULLISH" | "BEARISH" | "NEUTRAL",
  "confidence": 0-100,
  "target_price": destek/dirence göre realist hedef fiyat (sayı),
  "stop_loss": ATR'a göre mantıklı stop-loss (sayı),
  "horizon_days": tahmin süresi (gün),
  "trend_strength": "Güçlü" | "Orta" | "Zayıf",
  "key_signals": [
    "Hangi gösterge ne diyor — somut sayılarla 4-6 madde, örn: 'RSI 68 — aşırı alım yakın, dikkat'"
  ],
  "risks": ["bu tahmini bozabilecek 2-3 risk maddesi"],
  "summary": "3-4 cümle Türkçe yorum — başlıca sinyaller, hedef, neden, risk"
}}"""


def predict(symbol: str, force_refresh: bool = False) -> dict:
    symbol = symbol.upper()
    now = datetime.now()
    if not force_refresh and symbol in _cache:
        data, ts = _cache[symbol]
        if now - ts < timedelta(minutes=_CACHE_TTL_MINUTES):
            return data

    if not llm_service.available:
        raise RuntimeError("AI sağlayıcı (Gemini/Groq) ayarlı değil")

    indicators = _compute_indicators(symbol)
    prompt = _build_prompt(symbol, indicators)

    try:
        raw = llm_service.complete(
            [
                {"role": "system", "content": "Finansal teknik analiz uzmanısın. Yalnızca geçerli JSON dön, hiç açıklama yapma."},
                {"role": "user", "content": prompt},
            ],
            temperature=0.4,
            # 400 yetersizdi: prompt 4-6 sinyal + 2-3 risk + 3-4 cümle özet
            # (Türkçe) istiyor; yanıt yarıda kesilip JSON bozuluyordu
            # ("Unterminated string") → fallback. 1000 ile tam JSON sığıyor.
            max_tokens=1000,
            json_mode=True,
            model=llm_service.MODEL_LITE,
        )
        parsed = json.loads(raw)
    except Exception as exc:
        logger.warning(f"LLM tahmin hatası ({symbol}): {exc}")
        # Fallback — basit heuristik
        parsed = {
            "direction": "NEUTRAL",
            "confidence": 50,
            "target_price": indicators["current_price"],
            "stop_loss": indicators["current_price"] * 0.95,
            "horizon_days": 14,
            "key_signals": ["AI yanıtı alınamadı"],
            "summary": "Tahmin üretilemedi.",
        }

    result = {
        "symbol": symbol,
        "indicators": indicators,
        "prediction": parsed,
        "generated_at": now.isoformat(),
    }
    _cache[symbol] = (result, now)
    return result
