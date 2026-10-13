# =============================================================================
# Yahoo "chart" ucuna DOĞRUDAN erişim (yfinance'siz) — 429 için ikinci yol
#
# Kök sorun: Yahoo, Render ücretsiz katmanının PAYLAŞILAN çıkış IP'sini
# rate-limit'liyor (429). BIST ve kripto dışındaki her şeyde yedek kaynak var;
# BIST'in ücretsiz + sunucudan erişilebilir + güvenilir bir alternatifi
# bulunamadı → tek kalıcı ve ÜCRETSİZ çare, Yahoo'ya BAŞKA BİR IP'den gitmek.
#
# Bu modül iki işe yarar:
#   1) `YAHOO_PROXY_BASE` tanımlıysa (Cloudflare Worker, ücretsiz plan 100k
#      istek/gün — kurulum: infra/cloudflare-worker/README.md) tüm istekler
#      oradan geçer → Render'ın IP'si devreden çıkar, ceza etkisiz kalır.
#   2) Proxy yoksa: yfinance'in kullandığı çerez/crumb uçlarına (quoteSummary,
#      fc.yahoo.com) HİÇ dokunmadan yalnız açık `chart` ucunu dener. Bu uç
#      Render'da tarihsel olarak crumb uçlarından daha az bloklu.
#
# Nazik davranış: 429 görülürse modül kendini `_COOLDOWN` boyunca kapatır
# (ceza süresini uzatmamak için) — devre kesici.
#
# Sözleşme market_data_service ile aynı: quote sözlüğü ve sütun-listesi OHLCV.
# =============================================================================
import time
from concurrent.futures import ThreadPoolExecutor

import httpx
from loguru import logger

from app.core.config import settings

_DEFAULT_BASE = "https://query1.finance.yahoo.com"
_TIMEOUT = 10.0
_COOLDOWN = 15 * 60          # 429 sonrası bu modül bu kadar süre susar
_MAX_WORKERS = 4             # tek seferde kaç sembol (nazik olmak için düşük)

_blocked_until: float = 0.0


def base_url() -> str:
    return settings.YAHOO_PROXY_BASE or _DEFAULT_BASE


def via_proxy() -> bool:
    return bool(settings.YAHOO_PROXY_BASE)


def available() -> bool:
    """Devre kesici açık mı? (429 sonrası soğuma penceresinde False.)"""
    return time.time() >= _blocked_until


def _mark_rate_limited() -> None:
    global _blocked_until
    _blocked_until = time.time() + _COOLDOWN
    logger.warning(
        f"Yahoo chart 429 → doğrudan yol {_COOLDOWN // 60} dk devre dışı "
        f"({'proxy' if via_proxy() else 'proxy YOK'})")


def _fetch(symbol: str, rng: str, interval: str,
           client: httpx.Client) -> dict | None:
    """Tek sembolün chart JSON'ı. 429 → devre kesici; diğer hata → None."""
    url = f"{base_url()}/v8/finance/chart/{symbol}"
    try:
        r = client.get(url, params={"range": rng, "interval": interval,
                                    "includePrePost": "false"})
    except Exception as exc:
        logger.debug(f"Yahoo chart hatası ({symbol}): {exc}")
        return None
    if r.status_code == 429:
        _mark_rate_limited()
        return None
    if r.status_code != 200:
        return None
    try:
        result = (r.json().get("chart") or {}).get("result") or []
    except Exception:
        return None
    return result[0] if result else None


def probe(symbol: str) -> str:
    """Sembol GERÇEKTEN yok mu, kaynak mı ulaşılamıyor? → "unknown" |
    "unavailable" | "ok".

    Neden: yfinance her hatada "Too Many Requests. Rate limited." metnini
    döndürüyor (kendi global durumundan) → kullanıcı OLMAYAN bir sembol için
    de "çok fazla istek" görüyordu. Canlıda doğrulandı: uydurma ZZZZTEST.IS
    ile portföydeki LTL.IS/TLY.IS birebir aynı mesajı veriyordu. Yahoo'nun
    chart ucu ayrımı net yapar (404 + "No data found, symbol may be delisted").
    Yalnız HATA yolunda çağrılır (nadir) — normal akışa ek istek getirmez."""
    if not available():
        return "unavailable"
    url = f"{base_url()}/v8/finance/chart/{symbol}"
    try:
        with httpx.Client(timeout=_TIMEOUT, follow_redirects=True,
                          headers={"User-Agent": "Mozilla/5.0 (compatible; portly/1.0)"}
                          ) as client:
            r = client.get(url, params={"range": "5d", "interval": "1d"})
    except Exception:
        return "unavailable"
    if r.status_code == 429:
        _mark_rate_limited()
        return "unavailable"
    if r.status_code == 404:
        return "unknown"
    if r.status_code != 200:
        return "unavailable"
    try:
        chart = r.json().get("chart") or {}
    except Exception:
        return "unavailable"
    if chart.get("error"):
        return "unknown"
    return "ok" if (chart.get("result") or []) else "unknown"


def _bars(payload: dict) -> list[dict]:
    """chart JSON → [{date, open, high, low, close, volume}] (eskiden yeniye).
    NaN/None bar ATILIR (KALICI KURAL: null mum çizme, NaN sayı üretme)."""
    stamps = payload.get("timestamp") or []
    quote = ((payload.get("indicators") or {}).get("quote") or [{}])[0]
    opens = quote.get("open") or []
    highs = quote.get("high") or []
    lows = quote.get("low") or []
    closes = quote.get("close") or []
    vols = quote.get("volume") or []
    bars: list[dict] = []
    for i, ts in enumerate(stamps):
        try:
            o, h, low, c = opens[i], highs[i], lows[i], closes[i]
        except IndexError:
            break
        if None in (o, h, low, c):
            continue
        try:
            vol = vols[i] if i < len(vols) and vols[i] is not None else 0
        except IndexError:
            vol = 0
        bars.append({
            "date": time.strftime("%Y-%m-%d", time.gmtime(int(ts))),
            "open": float(o), "high": float(h),
            "low": float(low), "close": float(c), "volume": float(vol),
        })
    bars.sort(key=lambda b: b["date"])
    return bars


def _collect(symbols: list[str], rng: str,
             interval: str = "1d") -> dict[str, list[dict]]:
    syms = [s.upper() for s in symbols if s]
    if not syms or not available():
        return {}
    out: dict[str, list[dict]] = {}
    headers = {"User-Agent": "Mozilla/5.0 (compatible; portly/1.0)",
               "Accept": "application/json"}
    with httpx.Client(timeout=_TIMEOUT, headers=headers,
                      follow_redirects=True) as client:
        def _one(sym: str):
            if not available():
                return sym, None
            payload = _fetch(sym, rng, interval, client)
            return sym, (_bars(payload) if payload else None)

        with ThreadPoolExecutor(max_workers=_MAX_WORKERS) as ex:
            for sym, bars in ex.map(_one, syms):
                if bars:
                    out[sym] = bars
    if out:
        logger.info(f"Yahoo chart yolu ({'proxy' if via_proxy() else 'doğrudan'}): "
                    f"{len(out)}/{len(syms)} sembol")
    return out


# ── Dışa açık API ────────────────────────────────────────────────────────────
def get_quotes(symbols: list[str]) -> dict[str, dict]:
    """{SYMBOL: {symbol, company_name, current_price, change_percent,
    change_available}}.

    `change_available=False`: elde tek bar var (dünkü kapanış YOK) → günlük
    değişim hesaplanamıyor. Eskiden bu durumda 0.0 dönüyordu ve arayüz
    "Bugün +%0,00" basıyordu — oysa bilgi YOKTU (aynı tuzağa BIST'te
    `period=2d` ile bir kez düşülmüştü).
    """
    out: dict[str, dict] = {}
    for sym, bars in _collect(symbols, rng="5d").items():
        if not bars:
            continue
        current = bars[-1]["close"]
        prev = bars[-2]["close"] if len(bars) >= 2 else None
        change = ((current - prev) / prev * 100) if prev else 0.0
        out[sym] = {"symbol": sym, "company_name": sym,
                    "current_price": round(current, 2),
                    "change_percent": round(change, 2),
                    "change_available": bool(prev)}
    return out


def get_daily_ohlcv(symbols: list[str], period: str = "6mo") -> dict[str, dict]:
    out: dict[str, dict] = {}
    for sym, bars in _collect(symbols, rng=period).items():
        out[sym] = {
            "date": [b["date"] for b in bars],
            "open": [b["open"] for b in bars],
            "high": [b["high"] for b in bars],
            "low": [b["low"] for b in bars],
            "close": [b["close"] for b in bars],
            "volume": [b["volume"] for b in bars],
        }
    return out


# Yahoo chart ucunun DESTEKLEDİĞİ aralıklar. 2h/3h/4h yok → 1h çekilip
# toplanır (yfinance'in yaptığı resample'ın aynısı).
_NATIVE_INTERVALS = {"1m", "2m", "5m", "15m", "30m", "60m", "90m",
                     "1h", "1d", "5d", "1wk", "1mo", "3mo"}
_SYNTHETIC_HOURS = {"2h": 2, "3h": 3, "4h": 4}


def get_history_rows(symbol: str, rng: str, interval: str) -> list[dict]:
    """Grafik ucunun (`/market/history`) satır sözleşmesi:
    [{date, timestamp, open, high, low, close, volume}].

    Tarih dizesi BORSA saatine göre biçimlenir (chart JSON'daki gmtoffset) —
    yfinance de tz-aware index döndürdüğü için davranış birebir kalır.
    """
    if not available():
        return []
    fetch_interval = interval
    bucket = _SYNTHETIC_HOURS.get(interval)
    if bucket:
        fetch_interval = "1h"
    elif interval not in _NATIVE_INTERVALS:
        return []

    headers = {"User-Agent": "Mozilla/5.0 (compatible; portly/1.0)",
               "Accept": "application/json"}
    with httpx.Client(timeout=_TIMEOUT, headers=headers,
                      follow_redirects=True) as client:
        payload = _fetch(symbol, rng, fetch_interval, client)
    if not payload:
        return []

    offset = int((payload.get("meta") or {}).get("gmtoffset") or 0)
    intraday = fetch_interval.endswith(("m", "h"))
    stamps = payload.get("timestamp") or []
    quote = ((payload.get("indicators") or {}).get("quote") or [{}])[0]
    opens, highs = quote.get("open") or [], quote.get("high") or []
    lows, closes = quote.get("low") or [], quote.get("close") or []
    vols = quote.get("volume") or []

    raw: list[dict] = []
    for i, ts in enumerate(stamps):
        try:
            o, h, low_, c = opens[i], highs[i], lows[i], closes[i]
        except IndexError:
            break
        # NaN/None barı ATLA (KALICI KURAL: null mum çizme).
        if None in (o, h, low_, c):
            continue
        vol = vols[i] if i < len(vols) and vols[i] is not None else 0
        raw.append({"ts": int(ts), "open": float(o), "high": float(h),
                    "low": float(low_), "close": float(c),
                    "volume": float(vol)})

    if bucket:
        raw = _aggregate_hours(raw, bucket)

    fmt = "%Y-%m-%d %H:%M" if intraday else "%Y-%m-%d"
    return [{
        "date": time.strftime(fmt, time.gmtime(b["ts"] + offset)),
        "timestamp": b["ts"],
        "open": round(b["open"], 2), "high": round(b["high"], 2),
        "low": round(b["low"], 2), "close": round(b["close"], 2),
        "volume": int(b["volume"]),
    } for b in raw]


def _aggregate_hours(bars: list[dict], hours: int) -> list[dict]:
    """1 saatlik barları N saatlik mumlara toplar (open=ilk, high=maks,
    low=min, close=son, volume=toplam)."""
    out: list[dict] = []
    step = hours * 3600
    for bar in bars:
        start = bar["ts"] - (bar["ts"] % step)
        if out and out[-1]["ts"] == start:
            cur = out[-1]
            cur["high"] = max(cur["high"], bar["high"])
            cur["low"] = min(cur["low"], bar["low"])
            cur["close"] = bar["close"]
            cur["volume"] += bar["volume"]
        else:
            out.append({**bar, "ts": start})
    return out


def get_daily_closes(symbols: list[str],
                     period: str = "1y") -> dict[str, dict[str, float]]:
    return {sym: {b["date"]: b["close"] for b in bars}
            for sym, bars in _collect(symbols, rng=period).items() if bars}


# ── Toplu kapanış serisi: /v8/finance/spark ──────────────────────────────
# 10. turda ölçülmüştü: `yf.download` "batch" DEĞİL — sembol başına ayrı
# `/v8/finance/chart/` isteği atıyor (5 sembol = 5 istek). 51 sembollük sinyal
# taraması = 51 Yahoo isteği; Render'ın paylaşılan IP'sindeki 429'un kaynağı bu.
#
# `spark` aynı kapanış serisini TEK istekte N sembol için veriyor.
# 7 Eyl'de ölçüldü: 20 sembol · 400 günlük pencere · **0,48 sn** · ~140 KB.
# ⚠️ Yahoo sınırı: istek başına EN FAZLA 20 sembol — 21'de uç
# `{"error":{"code":"Bad Request","description":"Number of symbols needs to be
# less than or equal to 20"}}` dönüyor (ölçüldü). Bu yüzden 20'lik gruplar.
_SPARK_CHUNK = 20
_SPARK_WORKERS = 3           # grup sayısı azdır; nazik kalmak için düşük


def _spark_series(payload: dict) -> dict[str, float]:
    """spark kaydı → {iso_gün: kapanış}. None kapanışlar ATILIR (KALICI KURAL:
    NaN/uydurma bar yok). Gün biçimi `_bars` ile aynı (UTC gün)."""
    stamps = payload.get("timestamp") or []
    closes = payload.get("close") or []
    out: dict[str, float] = {}
    for i, ts in enumerate(stamps):
        if i >= len(closes):
            break
        close = closes[i]
        if close is None:
            continue
        try:
            out[time.strftime("%Y-%m-%d", time.gmtime(int(ts)))] = float(close)
        except (TypeError, ValueError):
            continue
    return out


def _spark_chunk(symbols: list[str], rng: str,
                 client: httpx.Client) -> dict[str, dict[str, float]]:
    """En fazla 20 sembol için tek istek. Hata → {} (çağıran yedek yola düşer)."""
    if not available():
        return {}
    url = f"{base_url()}/v8/finance/spark"
    try:
        r = client.get(url, params={"symbols": ",".join(symbols),
                                    "range": rng, "interval": "1d"})
    except Exception as exc:
        logger.debug(f"spark isteği hatası ({len(symbols)} sembol): {exc}")
        return {}
    if r.status_code == 429:
        _mark_rate_limited()
        return {}
    if r.status_code != 200:
        logger.debug(f"spark HTTP {r.status_code}")
        return {}
    try:
        data = r.json()
    except Exception:
        return {}
    # Hata gövdesi {"spark": {"result": null, "error": {...}}} biçiminde gelir.
    if not isinstance(data, dict) or "spark" in data:
        logger.debug(f"spark beklenmeyen gövde: {str(data)[:120]}")
        return {}

    out: dict[str, dict[str, float]] = {}
    for sym, payload in data.items():
        if not isinstance(payload, dict):
            continue
        series = _spark_series(payload)
        if series:
            out[sym.upper()] = series
    return out


def get_daily_closes_batch(symbols: list[str],
                           rng: str = "400d") -> dict[str, dict[str, float]]:
    """{SEMBOL: {iso_gün: kapanış}} — 20'lik gruplar hâlinde TEK istekle.

    Kapanış serisi sözleşmesi `market_data_service.refresh_daily_closes` ile
    aynı; oradaki `yf.download` yolunun ÖNÜNE geçer, eksik kalan semboller
    için o yol yedek olarak durur (sembol Yahoo'da yoksa spark da vermez)."""
    syms = sorted({s.upper() for s in symbols if s})
    if not syms or not available():
        return {}

    chunks = [syms[i:i + _SPARK_CHUNK]
              for i in range(0, len(syms), _SPARK_CHUNK)]
    headers = {"User-Agent": "Mozilla/5.0 (compatible; portly/1.0)",
               "Accept": "application/json"}
    out: dict[str, dict[str, float]] = {}
    with httpx.Client(timeout=_TIMEOUT, headers=headers,
                      follow_redirects=True) as client:
        with ThreadPoolExecutor(max_workers=_SPARK_WORKERS) as ex:
            for part in ex.map(lambda c: _spark_chunk(c, rng, client), chunks):
                out.update(part)

    if out:
        logger.info(
            f"spark toplu kapanış: {len(out)}/{len(syms)} sembol, "
            f"{len(chunks)} istek ({'proxy' if via_proxy() else 'doğrudan'})")
    return out
