# =============================================================================
# Kripto yedek veri kaynağı — ücretsiz, ANAHTARSIZ, borsa API'leri
#
# Neden: Yahoo, Render'ın paylaşılan çıkış IP'sini 429'luyor. USDTRY (truncgil/
# frankfurter), ABD hissesi (Finnhub) ve altın/gümüş (truncgil) için yedek
# zinciri vardı; KRİPTO ve BIST için yoktu → BTC-USD fiyatı "veri alınamadı",
# kripto sinyali hiç üretilemiyordu (6 aylık mum gerekiyor, Finnhub ücretsiz
# tier mum vermiyor).
#
# Bu modül kriptoyu iki keysiz borsa API'siyle karşılar:
#   1) Coinbase Exchange  — GERÇEK USD paritesi (BTC-USD). Kur sapması YOK.
#      quote: /products/{p}/candles (son 2 günlük bar) · OHLC: aynı uç, 300 bara kadar.
#   2) Binance            — USDT paritesi (BTCUSDT). USDT≈USD, tipik sapma
#      binde birin altında ama SIFIR DEĞİL → yalnız Coinbase vermezse kullanılır
#      ve log'a hangi kaynağın kullanıldığı yazılır.
#
# Sözleşme market_data_service ile AYNI: fiyat sözlüğü {symbol, company_name,
# current_price, change_percent}; OHLCV {date[], open[], high[], low[],
# close[], volume[]}. Böylece çağıran taraf kaynağı bilmek zorunda değil.
#
# ⚠️ Ağ erişimi olmayan ortamda (test/CI) her fonksiyon SESSİZCE boş döner —
# çağıran zaten "veri yoksa boş" sözleşmesine göre yazılmış.
# =============================================================================
import time
from concurrent.futures import ThreadPoolExecutor

import httpx
from loguru import logger

_TIMEOUT = 8.0
_COINBASE = "https://api.exchange.coinbase.com"
_BINANCE = "https://api.binance.com/api/v3"

# Yahoo kripto sembolü daima "-USD" ile biter (BTC-USD, ETH-USD, SOL-USD).
_SUFFIX = "-USD"

# Borsalarda farklı yazılan taban varlıklar (Yahoo → borsa tabanı).
_BASE_ALIAS = {
    "IOTA": "MIOTA",
}

# Son kullanılan kaynak (log/teşhis için; fx_service.rate_source ile aynı fikir).
_last_source: str | None = None


def last_source() -> str | None:
    """Son başarılı kripto çağrısının kaynağı ('coinbase' | 'binance' | None)."""
    return _last_source


def is_crypto(symbol: str) -> bool:
    return symbol.upper().endswith(_SUFFIX)


def _base(symbol: str) -> str:
    base = symbol.upper()[: -len(_SUFFIX)]
    return _BASE_ALIAS.get(base, base)


def _client() -> httpx.Client:
    return httpx.Client(timeout=_TIMEOUT,
                        headers={"User-Agent": "portly/1.0"})


# ── Coinbase Exchange (gerçek USD paritesi) ──────────────────────────────────
def _coinbase_candles(symbol: str, client: httpx.Client) -> list[list] | None:
    """[[time, low, high, open, close, volume], ...] — YENİDEN ESKİYE sıralı.
    Günlük granularity, uç en fazla 300 bar döndürür (≈10 ay > 6 ay)."""
    product = f"{_base(symbol)}-USD"
    try:
        r = client.get(f"{_COINBASE}/products/{product}/candles",
                       params={"granularity": 86400})
        if r.status_code != 200:
            return None
        rows = r.json()
        return rows if isinstance(rows, list) and rows else None
    except Exception as exc:
        logger.debug(f"Coinbase mum hatası ({symbol}): {exc}")
        return None


# ── Binance (USDT paritesi — yalnız Coinbase vermezse) ───────────────────────
def _binance_klines(symbol: str, client: httpx.Client,
                    limit: int = 200) -> list[list] | None:
    """[[openTime, open, high, low, close, volume, ...], ...] — ESKİDEN YENİYE."""
    pair = f"{_base(symbol)}USDT"
    try:
        r = client.get(f"{_BINANCE}/klines",
                       params={"symbol": pair, "interval": "1d",
                               "limit": limit})
        if r.status_code != 200:
            return None
        rows = r.json()
        return rows if isinstance(rows, list) and rows else None
    except Exception as exc:
        logger.debug(f"Binance mum hatası ({symbol}): {exc}")
        return None


# ── Ortak: tek sembol → normalize bar listesi (eskiden yeniye) ───────────────
def _bars(symbol: str, client: httpx.Client) -> tuple[list[dict], str] | None:
    """[{date, open, high, low, close, volume}, ...] (ESKİDEN YENİYE) + kaynak."""
    rows = _coinbase_candles(symbol, client)
    if rows:
        bars = []
        for t, low, high, opn, close, vol in (r[:6] for r in rows):
            bars.append({
                "date": time.strftime("%Y-%m-%d", time.gmtime(int(t))),
                "open": float(opn), "high": float(high),
                "low": float(low), "close": float(close),
                "volume": float(vol),
            })
        bars.sort(key=lambda b: b["date"])
        return bars, "coinbase"

    rows = _binance_klines(symbol, client)
    if rows:
        bars = []
        for r in rows:
            bars.append({
                "date": time.strftime("%Y-%m-%d",
                                      time.gmtime(int(r[0]) // 1000)),
                "open": float(r[1]), "high": float(r[2]),
                "low": float(r[3]), "close": float(r[4]),
                "volume": float(r[5]),
            })
        bars.sort(key=lambda b: b["date"])
        return bars, "binance"

    return None


def _collect(symbols: list[str]) -> dict[str, tuple[list[dict], str]]:
    """Sembolleri paralel çeker (borsa API'leri sembol başına istek ister;
    havuz küçük tutulur — amaç Yahoo'yu taklit etmek değil, boşluğu kapatmak)."""
    global _last_source
    targets = [s.upper() for s in symbols if is_crypto(s)]
    if not targets:
        return {}
    out: dict[str, tuple[list[dict], str]] = {}
    with _client() as client:
        def _one(sym: str):
            try:
                return sym, _bars(sym, client)
            except Exception as exc:
                logger.debug(f"Kripto yedeği atlandı ({sym}): {exc}")
                return sym, None

        with ThreadPoolExecutor(max_workers=6) as ex:
            for sym, res in ex.map(_one, targets):
                if res:
                    out[sym] = res
    if out:
        sources = {src for _, src in out.values()}
        _last_source = sorted(sources)[0]
        logger.info(f"Kripto yedek kaynağı ({'/'.join(sorted(sources))}): "
                    f"{len(out)}/{len(targets)} sembol")
    return out


# ── Dışa açık API (market_data_service sözleşmesi) ───────────────────────────
def get_quotes(symbols: list[str]) -> dict[str, dict]:
    """{SYMBOL: {symbol, company_name, current_price, change_percent}}.

    Değişim yüzdesi son iki GÜNLÜK bar'dan (dünkü kapanış → bugünkü) —
    Yahoo'nun günlük değişimiyle aynı tanım."""
    out: dict[str, dict] = {}
    for sym, (bars, _src) in _collect(symbols).items():
        if not bars:
            continue
        current = bars[-1]["close"]
        prev = bars[-2]["close"] if len(bars) >= 2 else current
        change = ((current - prev) / prev * 100) if prev else 0.0
        out[sym] = {
            "symbol": sym,
            "company_name": sym,
            "current_price": round(current, 2),
            "change_percent": round(change, 2),
        }
    return out


def get_daily_ohlcv(symbols: list[str], days: int = 200) -> dict[str, dict]:
    """market_data_service._download_ohlcv ile AYNI şekil: sütun listeleri."""
    out: dict[str, dict] = {}
    for sym, (bars, _src) in _collect(symbols).items():
        window = bars[-days:] if days and len(bars) > days else bars
        if not window:
            continue
        out[sym] = {
            "date": [b["date"] for b in window],
            "open": [b["open"] for b in window],
            "high": [b["high"] for b in window],
            "low": [b["low"] for b in window],
            "close": [b["close"] for b in window],
            "volume": [b["volume"] for b in window],
        }
    return out


def get_daily_closes(symbols: list[str]) -> dict[str, dict[str, float]]:
    """{SYMBOL: {iso_gün: kapanış}} — kapanış serisi sözleşmesi."""
    out: dict[str, dict[str, float]] = {}
    for sym, (bars, _src) in _collect(symbols).items():
        ser = {b["date"]: b["close"] for b in bars}
        if ser:
            out[sym] = ser
    return out
