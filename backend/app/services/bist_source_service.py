# =============================================================================
# BIST yedek veri kaynağı — ücretsiz, ANAHTARSIZ (İş Yatırım açık veri ucu)
#
# Neden: BIST'in TEK dayanağı Yahoo'ydu. Render'ın paylaşılan IP'si 429 yiyince
# Cloudflare Worker vekili devreye alındı, ama o da tek nokta: Yahoo Cloudflare
# çıkışını da kısarsa BIST tarafı komple düşüyor (fiyat yok, sinyal yok, grafik
# yok). Kripto (Coinbase/Binance), fon (TEFAS), ABD hissesi (Finnhub) ve
# altın/gümüş (truncgil) için ikinci kaynak vardı; BIST'te yoktu.
#
# Kaynak: İş Yatırım'ın halka açık `HisseTekil` ucu — GÜNLÜK kapanış/min/maks/
# hacim serisi verir, anahtar istemez. (Aynı sitenin canlı fiyat uçları 401
# döndüğü için gün içi fiyat BURADAN GELMEZ; bkz. get_quotes.)
#
# Sözleşme diğer yedek kaynaklarla AYNI (crypto_source_service /
# fund_source_service): fiyat sözlüğü · OHLCV sütun listeleri · kapanış serisi.
#
# ⚠️ Kapsam sınırları — bilerek:
#   · Gün içi fiyat YOK. Seans AÇIKKEN `get_quotes` boş döner: dünkü kapanışı
#     "şu anki fiyat" diye basmak, projenin dürüst-boş-durum kuralını ihlal
#     eder (kullanıcı "Fiyat —" görür, uydurma rakam görmez).
#   · Açılış (open) fiyatı kaynakta YOK → mumda open=close (fon yolundaki
#     aynı yaklaşım); min/maks/kapanış GERÇEK.
#   · Hacim TL cinsindendir (Yahoo'da adet). Göstergeler hacmi yalnız kendi
#     ortalamasına oranlayarak kullandığı için birim fark etmez; bir sembolün
#     serisi tek kaynaktan geldiği için seri içinde birim karışmaz.
#
# ⚠️ Ağ erişimi olmayan ortamda (test/CI) her fonksiyon SESSİZCE boş döner.
# =============================================================================
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import httpx
from loguru import logger

# Uç DEĞİŞKEN hızlı: kısa aralık (~10 gün) 0,1 sn, uzun aralık kimi zaman
# 0,2 sn kimi zaman ~10 sn (canlıda ölçüldü). Son çare kaynağı olduğu için
# cömert timeout veriyoruz — 8 sn'de 6 aylık seri kopuyordu.
_TIMEOUT = 20.0
_URL = ("https://www.isyatirim.com.tr/_layouts/15/IsYatirim.Website/Common/"
        "Data.aspx/HisseTekil")

_SUFFIX = ".IS"
_TR = ZoneInfo("Europe/Istanbul")

# BIST pay piyasası seansı (TSİ): 10:00–18:10. Tatilleri yok sayar — ABD
# tarafındaki `_us_market_state` ile aynı kabul.
_OPEN_MIN = 10 * 60
_CLOSE_MIN = 18 * 60 + 10

# Kapanış serisi kaç gün geriden gelirse "bayat" sayılır. Uzun bayram
# tatillerinde (Kurban/Ramazan + hafta sonu) 9 güne kadar seanssız gün olur.
_MAX_STALE_DAYS = 10


def is_bist(symbol: str) -> bool:
    return symbol.upper().endswith(_SUFFIX)


def _ticker(symbol: str) -> str:
    return symbol.upper()[: -len(_SUFFIX)]


def session_open(now: datetime | None = None) -> bool:
    """BIST pay piyasası şu anda açık mı? (gün içi fiyat verilemeyeceği için)"""
    now = now or datetime.now(_TR)
    if now.weekday() >= 5:
        return False
    mins = now.hour * 60 + now.minute
    return _OPEN_MIN <= mins < _CLOSE_MIN


def _client() -> httpx.Client:
    # Uç tarayıcı dışı UA'ya da yanıt veriyor; yine de kimliğimizi açıkça yaz.
    return httpx.Client(timeout=_TIMEOUT,
                        headers={"User-Agent": "portly/1.0"})


def _fetch_rows(symbol: str, days: int, client: httpx.Client) -> list[dict]:
    """Ham satırlar → [{date(iso), high, low, close, volume}, ...] ESKİDEN YENİYE.

    Uç tarihleri gün-ay-yıl bekler ve satırları SIRASIZ döndürür (canlıda
    doğrulandı) → burada sıralanır.
    """
    end = datetime.now(_TR).date()
    # Takvim günü ≠ seans günü: hafta sonu + tatil payı bırak.
    start = end - timedelta(days=int(days * 1.6) + 10)
    try:
        r = client.get(_URL, params={
            "hisse": _ticker(symbol),
            "startdate": start.strftime("%d-%m-%Y"),
            "enddate": end.strftime("%d-%m-%Y"),
        })
        if r.status_code != 200:
            return []
        payload = r.json()
    except Exception as exc:
        logger.debug(f"BIST yedeği hatası ({symbol}): {exc}")
        return []

    if not isinstance(payload, dict) or not payload.get("ok"):
        return []

    rows: list[dict] = []
    for item in payload.get("value") or []:
        try:
            close = float(item["HGDG_KAPANIS"])
            if close <= 0:
                continue
            day = datetime.strptime(item["HGDG_TARIH"], "%d-%m-%Y").date()
            rows.append({
                "date": day.isoformat(),
                "high": float(item.get("HGDG_MAX") or close),
                "low": float(item.get("HGDG_MIN") or close),
                "close": close,
                "volume": float(item.get("HGDG_HACIM") or 0.0),
            })
        except (KeyError, TypeError, ValueError):
            continue  # tek bozuk satır seriyi düşürmesin
    rows.sort(key=lambda b: b["date"])
    return rows


def _collect(symbols: list[str], days: int) -> dict[str, list[dict]]:
    """Sembolleri paralel çeker (uç sembol başına istek ister; havuz küçük)."""
    targets = sorted({s.upper() for s in symbols if is_bist(s)})
    if not targets:
        return {}
    out: dict[str, list[dict]] = {}
    with _client() as client:
        def _one(sym: str):
            try:
                return sym, _fetch_rows(sym, days, client)
            except Exception as exc:
                logger.debug(f"BIST yedeği atlandı ({sym}): {exc}")
                return sym, []

        with ThreadPoolExecutor(max_workers=6) as ex:
            for sym, rows in ex.map(_one, targets):
                if rows:
                    out[sym] = rows
    if out:
        logger.info(f"BIST yedek kaynağı (isyatirim): "
                    f"{len(out)}/{len(targets)} sembol")
    return out


def _fresh(rows: list[dict], now: datetime | None = None) -> bool:
    """Serinin SON kapanışı güncel mi? (bayat seriyi fiyat diye basmamak için)"""
    today = (now or datetime.now(_TR)).date()
    try:
        last = datetime.strptime(rows[-1]["date"], "%Y-%m-%d").date()
    except (IndexError, KeyError, ValueError):
        return False
    return (today - last).days <= _MAX_STALE_DAYS


# ── Dışa açık API (market_data_service sözleşmesi) ───────────────────────────
def get_quotes(symbols: list[str], now: datetime | None = None) -> dict[str, dict]:
    """{SYMBOL: {symbol, company_name, current_price, change_percent}}.

    YALNIZ seans KAPALIYKEN doldurur: o zaman son kapanış gerçekten güncel
    fiyattır (Yahoo da kapalıyken kapanışı gösterir) ve değişim son iki
    kapanışın farkıdır. Seans açıkken boş dönülür — gün içi fiyat bu kaynakta
    yok, dünkü kapanışı canlı fiyat gibi göstermek yanlış olurdu.
    """
    if session_open(now):
        return {}
    out: dict[str, dict] = {}
    for sym, rows in _collect(symbols, days=10).items():
        if len(rows) < 2 or not _fresh(rows, now):
            continue
        current, prev = rows[-1]["close"], rows[-2]["close"]
        change = ((current - prev) / prev * 100) if prev else 0.0
        out[sym] = {
            "symbol": sym,
            "company_name": sym,
            "current_price": round(current, 2),
            "change_percent": round(change, 2),
        }
    return out


def get_daily_ohlcv(symbols: list[str], days: int = 200) -> dict[str, dict]:
    """market_data_service._download_ohlcv ile AYNI şekil: sütun listeleri.

    Kaynak açılış fiyatı vermiyor → open=close (fon yolundaki kabul);
    yüksek/düşük/kapanış gerçek, hacim TL."""
    out: dict[str, dict] = {}
    for sym, rows in _collect(symbols, days).items():
        window = rows[-days:] if days and len(rows) > days else rows
        if not window:
            continue
        closes = [b["close"] for b in window]
        out[sym] = {
            "date": [b["date"] for b in window],
            "open": list(closes),
            "high": [b["high"] for b in window],
            "low": [b["low"] for b in window],
            "close": closes,
            "volume": [b["volume"] for b in window],
        }
    return out


def get_daily_closes(symbols: list[str],
                     days: int = 500) -> dict[str, dict[str, float]]:
    """{SYMBOL: {iso_gün: kapanış}} — kapanış serisi sözleşmesi."""
    out: dict[str, dict[str, float]] = {}
    for sym, rows in _collect(symbols, days).items():
        ser = {b["date"]: b["close"] for b in rows}
        if ser:
            out[sym] = ser
    return out


def get_history_rows(symbol: str, days: int) -> list[dict]:
    """Grafik ucu satırları (market_data_service._history_from_fallbacks şekli).

    Yalnız GÜNLÜK bar — bu kaynakta gün içi mum yok, uydurma mum basılmaz."""
    rows = _collect([symbol], days).get(symbol.upper()) or []
    window = rows[-days:] if days and len(rows) > days else rows

    out: list[dict] = []
    for b in window:
        try:
            stamp = int(time.mktime(time.strptime(b["date"], "%Y-%m-%d")))
        except (ValueError, OverflowError):
            continue
        out.append({
            "date": b["date"],
            "timestamp": stamp,
            "open": round(b["close"], 2),
            "high": round(b["high"], 2),
            "low": round(b["low"], 2),
            "close": round(b["close"], 2),
            "volume": int(b["volume"]),
        })
    return out
