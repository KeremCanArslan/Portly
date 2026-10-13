# =============================================================================
# TEFAS yatırım fonu veri kaynağı (TLY.FON, LTL.FON …)
#
# Neden ayrı bir kaynak: Yahoo TEFAS fonlarını HİÇ kapsamıyor — sorun erişim
# (429/IP cezası) değil, KAPSAM. Cloudflare Worker vekili bunu çözmez. Fon
# satırları bu modül olmadan portföyde "Fiyat —" görünüyor, sinyal taramasında
# `failed[]`'e düşüyordu; değer ise maliyetle sayılıyordu.
#
# Kaynak: TEFAS'ın kendi web arayüzünün kullandığı açık uç. TEFAS 2026-04'te
# Next.js mimarisine geçti → ESKİ `/api/DB/BindHistoryInfo` KAPALI
# ("Method not found or disabled!"); güncel uç `/api/funds/fonFiyatBilgiGetir`
# (JSON gövde, `periyod` sabit kodları — serbest tarih aralığı kabul etmiyor).
#
# Nazik davranış (TEFAS ~4 hızlı istekten sonra 429 veriyor, ~45 sn sürüyor):
#   - fon başına TEK istek 3 yıllık seriyi verir → fiyat, günlük değişim,
#     kapanış serisi ve grafiğin HEPSİ o tek seriden türetilir,
#   - seri paylaşılan cache'te (Redis) tutulur; fon fiyatı GÜNDE BİR
#     açıklandığı için taze süresi saatlerdir, hisse gibi dakika değil,
#   - istekler sıralı ve aralıklı gider; 429 görülürse modül `_COOLDOWN`
#     boyunca kendini kapatır (devre kesici — cezayı uzatmamak için).
#
# Sözleşme market_data_service ile AYNI: quote sözlüğü + sütun-listesi OHLCV +
# grafik satırları. Çağıran kaynağı bilmek zorunda değil.
#
# ⚠️ OHLC UYARISI: fonun günde tek fiyatı (birim pay değeri) vardır; gün içi
# yüksek/düşük DİYE BİR ŞEY YOK. OHLCV'de open=high=low=close verilir ve
# volume=0 bırakılır (uydurma hacim basılmaz). Gün içi aralığa dayanan
# göstergeler (Stochastic, hacim onayı) bu yüzden fonda anlamsızdır —
# sinyal tarafı fonu `data_limited` olarak işaretler.
# =============================================================================
import time

import httpx
from loguru import logger

from app.core import cache
from app.core.config import settings
from app.services import fund_catalog

_DEFAULT_BASE = "https://www.tefas.gov.tr"
_PATH = "/api/funds/fonFiyatBilgiGetir"
# Tüm YATIRIM fonlarının kod/unvan/tür listesi — katalog üreticisinin
# (scripts/generate_tefas_catalog.py) kullandığı uçla AYNI.
_CATALOG_PATH = "/api/funds/fonGetiriBazliBilgiGetir"
_TIMEOUT = 15.0
_COOLDOWN = 5 * 60           # 429 sonrası bu kadar süre susulur
_GAP_SECONDS = 0.35          # ardışık fon istekleri arası nefes payı
_PERIYOD_3Y = 36             # ucun kabul ettiği sabit kod (serbest aralık YOK)

# Fon fiyatı günde bir kez (akşam) açıklanır → gün içinde tekrar sormanın
# faydası yok. Taze: 3 saat; bayat ama kullanılabilir: 5 gün (kaynak düşse
# bile portföy fiyatsız kalmasın — hafta sonu/tatilde zaten yeni fiyat yok).
_FRESH_SECONDS = 3 * 3600
_STALE_SECONDS = 5 * 24 * 3600
_KEY = "fund:nav:"

_blocked_until: float = 0.0

_HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
}


def base_url() -> str:
    """TEFAS kökü. `TEFAS_PROXY_BASE` tanımlıysa Cloudflare Worker vekili
    üzerinden gidilir (Render'ın çıkış IP'si kısıtlanırsa tek gereken bu)."""
    return settings.TEFAS_PROXY_BASE or _DEFAULT_BASE


def is_fund(symbol: str) -> bool:
    """market_data_service'in yol ayrımı için tek doğruluk kaynağı."""
    return fund_catalog.is_fund_symbol(symbol)


def available() -> bool:
    """Devre kesici açık mı? (429 sonrası soğuma penceresinde False.)"""
    return time.time() >= _blocked_until


def _mark_rate_limited() -> None:
    global _blocked_until
    _blocked_until = time.time() + _COOLDOWN
    logger.warning(f"TEFAS 429 → fon kaynağı {_COOLDOWN // 60} dk devre dışı")


# ── Ağ ────────────────────────────────────────────────────────────────────────
def _fetch_series(code: str, client: httpx.Client) -> dict[str, float] | None:
    """{iso_gün: birim_pay_değeri} — 3 yıllık günlük seri. Hata → None."""
    try:
        r = client.post(f"{base_url()}{_PATH}",
                        json={"fonKodu": code, "dil": "TR",
                              "periyod": _PERIYOD_3Y})
    except Exception as exc:
        logger.debug(f"TEFAS isteği başarısız ({code}): {exc}")
        return None

    if r.status_code == 429:
        _mark_rate_limited()
        return None
    if r.status_code != 200:
        logger.debug(f"TEFAS {code} → HTTP {r.status_code}")
        return None

    try:
        payload = r.json()
    except Exception:
        return None

    if payload.get("errorMessage"):
        logger.debug(f"TEFAS {code} hatası: {payload['errorMessage']}")
        return None

    series: dict[str, float] = {}
    for row in payload.get("resultList") or []:
        day, price = row.get("tarih"), row.get("fiyat")
        if not day or price in (None, 0):
            continue
        try:
            series[str(day)[:10]] = float(price)
        except (TypeError, ValueError):
            continue
    return series or None


def _series(symbols: list[str]) -> dict[str, dict[str, float]]:
    """{SEMBOL: {gün: fiyat}} — cache öncelikli, eksikler tek tek çekilir.

    Bayat seri, kaynak cevap vermese bile SERVİS EDİLİR (son bilinen fiyat,
    "veri yok"tan iyidir); taze değilse arka planda değil, burada yenilenir
    çünkü fon başına istek günde birkaç kez olur."""
    out: dict[str, dict[str, float]] = {}
    todo: list[str] = []
    now = time.time()

    for raw in symbols:
        sym = raw.upper()
        if not is_fund(sym):
            continue
        hit = cache.get(_KEY + sym)
        if hit and isinstance(hit[0], dict):
            data, ts = hit
            age = now - ts
            if age < _FRESH_SECONDS:
                out[sym] = data
                continue
            if age < _STALE_SECONDS:
                out[sym] = data          # bayat ama elde; yenilemeyi dene
        todo.append(sym)

    if not todo or not available():
        return out

    with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
        for i, sym in enumerate(todo):
            if not available():          # sıradaki isteklerde devre açıldıysa dur
                break
            if i:
                time.sleep(_GAP_SECONDS)
            series = _fetch_series(fund_catalog.code_of(sym), client)
            if series:
                out[sym] = series
                cache.set(_KEY + sym, series, _STALE_SECONDS)

    if out:
        logger.info(f"TEFAS fon serisi: {len(out)}/{len(todo) or len(out)} fon")
    return out


# ── Dışa açık API (market_data_service sözleşmesi) ───────────────────────────
def _sorted_days(series: dict[str, float]) -> list[str]:
    return sorted(series)


def _window(series: dict[str, float], days: int) -> list[str]:
    """Son `days` TAKVİM gününün işlem günleri (satır sayısı değil).

    Fon yalnız iş günlerinde fiyat açıklar → son 180 SATIR ≈ 8,5 ay eder.
    Çağıranlar (market_data_service._period_days) takvim günü veriyor, o
    yüzden pencere tarihe göre kesilir."""
    ordered = _sorted_days(series)
    if not days or not ordered:
        return ordered
    from datetime import date, timedelta
    try:
        last = date.fromisoformat(ordered[-1])
    except ValueError:
        return ordered[-days:]
    cutoff = (last - timedelta(days=days)).isoformat()
    return [d for d in ordered if d >= cutoff]


def get_quotes(symbols: list[str]) -> dict[str, dict]:
    """{SEMBOL: {symbol, company_name, current_price, change_percent}}.

    Fiyat 6 basamağa yuvarlanır: birim pay değeri 1,096196 gibi olabiliyor →
    2 basamağa yuvarlamak binde 3'lük bir hata demek."""
    out: dict[str, dict] = {}
    for sym, series in _series(symbols).items():
        days = _sorted_days(series)
        if not days:
            continue
        current = series[days[-1]]
        prev = series[days[-2]] if len(days) >= 2 else current
        change = ((current - prev) / prev * 100) if prev else 0.0
        out[sym] = {
            "symbol": sym,
            "company_name": fund_catalog.name_of(sym) or sym,
            "current_price": round(current, 6),
            "change_percent": round(change, 2),
        }
    return out


def get_daily_closes(symbols: list[str]) -> dict[str, dict[str, float]]:
    """{SEMBOL: {iso_gün: kapanış}} — kapanış serisi sözleşmesi."""
    return {sym: dict(series) for sym, series in _series(symbols).items()
            if series}


def get_daily_ohlcv(symbols: list[str], days: int = 200) -> dict[str, dict]:
    """market_data_service._download_ohlcv ile aynı şekil (sütun listeleri).

    Fonun gün içi aralığı YOKTUR → open=high=low=close, volume=0."""
    out: dict[str, dict] = {}
    for sym, series in _series(symbols).items():
        window = _window(series, days)
        if not window:
            continue
        closes = [series[d] for d in window]
        out[sym] = {
            "date": window,
            "open": list(closes),
            "high": list(closes),
            "low": list(closes),
            "close": list(closes),
            "volume": [0.0] * len(window),
        }
    return out


def get_history_rows(symbol: str, days: int) -> list[dict]:
    """Grafik ucu satırları (market_data_service._history_from_fallbacks şekli).

    Yalnız GÜNLÜK bar; fonun gün içi fiyatı olmadığı için intraday istek
    boş döner — uydurma mum basılmaz."""
    series = _series([symbol]).get(symbol.upper())
    if not series:
        return []
    window = _window(series, days)

    rows: list[dict] = []
    for day in window:
        price = round(series[day], 6)
        try:
            stamp = int(time.mktime(time.strptime(day, "%Y-%m-%d")))
        except (ValueError, OverflowError):
            continue
        rows.append({"date": day, "timestamp": stamp,
                     "open": price, "high": price, "low": price,
                     "close": price, "volume": 0})
    return rows


def fetch_catalog() -> dict[str, tuple[str, str]]:
    """TEFAS'ın GÜNCEL fon listesi → {KOD: (unvan, tür)}. Hata/şüphe → {}.

    Statik katalog (`app/data/tefas_funds.json`) yılda birkaç kez elle
    üretiliyordu; arada kurulan fon "bulunamadı" görünüyordu. Bu uç aynı
    veriyi TEK istekte verdiği için arka plan işçisi katalogu günde bir
    tazeleyebiliyor — dosya yine de temel (baseline) olarak kalıyor, ağ
    yoksa davranış değişmiyor.
    """
    if not available():
        return {}

    payload = {
        "fonTipi": "YAT",        # YAT = yatırım fonu (emeklilik kapsam dışı)
        "dil": "TR",
        "calismaTipi": 2,
        "donemGetiri1a": "1", "donemGetiri3a": "1", "donemGetiri6a": "1",
        "donemGetiriyb": "1", "donemGetiri1y": "1", "donemGetiri3y": "1",
        "donemGetiri5y": "1",
    }
    try:
        with httpx.Client(timeout=60.0, headers=_HEADERS) as client:
            r = client.post(f"{base_url()}{_CATALOG_PATH}", json=payload)
        if r.status_code == 429:
            _mark_rate_limited()
            return {}
        if r.status_code != 200:
            logger.debug(f"TEFAS katalog → HTTP {r.status_code}")
            return {}
        data = r.json()
    except Exception as exc:
        logger.debug(f"TEFAS katalog isteği başarısız: {exc}")
        return {}

    if data.get("errorMessage"):
        logger.debug(f"TEFAS katalog hatası: {data['errorMessage']}")
        return {}

    out: dict[str, tuple[str, str]] = {}
    for row in data.get("resultList") or []:
        code = (row.get("fonKodu") or "").strip().upper()
        name = (row.get("fonUnvan") or "").strip()
        if code and name:
            out[code] = (name, (row.get("fonTurAciklama") or "").strip())

    # Üretici scriptiyle aynı akıl sağlığı eşiği: uç değişip yarım liste
    # dönerse katalogu ZEHİRLEME, olduğu gibi bırak.
    if len(out) < 500:
        logger.debug(f"TEFAS katalog beklenenden kısa ({len(out)}) — yok sayıldı")
        return {}
    return out
