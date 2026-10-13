"""Döviz kuru — tek doğruluk kaynağı.

Eskiden 3 ayrı serviste (portfolio/health/stress/dividend) farklı fallback'li
(41.0 / 0.0 / 1.0) ve farklı çekimli `_usdtry_rate` kopyaları vardı; bu da
"USD pozisyon ₺ sayılıyor" hatasının tekrar tekrar sızmasına yol açıyordu.
Artık herkes buradan okur.

⚠️ Kur TEK KAYNAĞA bağlı bırakılamaz. Yahoo, Render IP'sini rate-limit'lediğinde
(429) burası sabit 41.0'e düşüyordu; gerçek kur ~48 iken portföydeki HER USD
pozisyonu ₺ karşılığında ~%15 eksik görünüyordu — toplam değer, sektör
ağırlıkları ve sağlık skoru dahil. Artık sıralı kaynak zinciri var; sabit
değer yalnız hepsi düşerse kullanılır ve o durumda KISA süre cache'lenir
(bir sonraki istek yeniden dener).
"""

import math
import time

import requests
from loguru import logger

from app.core import cache
from app.services import market_data_service

_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
       "(KHTML, like Gecko) Chrome/122.0 Safari/537.36")

# Kur çekilemezse simülasyon/portföyü durdurmaktansa makul bir değerle
# devam et. SON çare; canlı kaynakların hepsi düşerse.
_FALLBACK = 41.0

# Gerçek kur 10 dk taze tutulur. Fallback'e düşülmüşse 60 sn sonra tekrar
# denenir — yoksa tek bir kötü an tüm süreç ömrü boyunca yanlış kuru
# sabitliyordu (eski kod TTL'siz cache'liyordu).
_TTL_LIVE = 600
_TTL_FALLBACK = 60

# {"rate": float, "ts": epoch, "source": str}
_cache: dict = {}


def _valid(rate) -> float | None:
    """Makul bir USDTRY mi? Bozuk/sıfır/absürt değer cache'e girmesin."""
    try:
        r = float(rate)
    except (TypeError, ValueError):
        return None
    if r <= 0 or math.isnan(r) or math.isinf(r):
        return None
    # Geniş ama anlamlı bant: kaynak biçim değiştirip 48.30 yerine 4830 ya da
    # 0.0207 (ters kur) döndürürse sessizce kabul etmeyelim.
    if not (5.0 <= r <= 500.0):
        logger.warning(f"USDTRY bandı dışında, atlandı: {r}")
        return None
    return r


def _parse_tr_number(s) -> float | None:
    """'48,3000' / '1.234,56' → float (truncgil eski şeması Türkçe biçimli)."""
    if isinstance(s, (int, float)):
        return float(s)
    if not isinstance(s, str):
        return None
    try:
        return float(s.strip().replace(".", "").replace(",", "."))
    except ValueError:
        return None


def _from_yahoo() -> float | None:
    """market_data_service üzerinden (kendi cache'i var)."""
    try:
        data = market_data_service.get_stock_data("USDTRY=X")
        return _valid(data.get("current_price"))
    except Exception:
        return None


def _from_truncgil() -> float | None:
    """finans.truncgil.com — Türkiye serbest piyasa. Render'dan ERİŞİLEBİLİR
    (Banka Altın ekranı zaten bu kaynaktan besleniyor), Yahoo'nun aksine
    rate-limit sorunu yok.

    İki şema dolaşımda: yeni `Rates.USD.{Buying,Selling}` (float) ve eski düz
    `USD.{Alış,Satış}` (Türkçe biçimli string). İkisi de desteklenir.
    Alış/satış ortası alınır — Yahoo'nun USDTRY=X'i de orta kurdur.
    """
    for url in ("https://finance.truncgil.com/api/today.json",
                "https://finans.truncgil.com/today.json"):
        try:
            r = requests.get(url, headers={"User-Agent": _UA}, timeout=8)
            if r.status_code != 200:
                continue
            d = r.json()
            usd = (d.get("Rates") or {}).get("USD") or d.get("USD") or {}
            buy = _parse_tr_number(usd.get("Buying") or usd.get("Alış"))
            sell = _parse_tr_number(usd.get("Selling") or usd.get("Satış"))
            mid = None
            if buy and sell:
                mid = (buy + sell) / 2
            elif sell or buy:
                mid = sell or buy
            ok = _valid(mid)
            if ok:
                return ok
        except Exception as exc:
            logger.debug(f"truncgil USDTRY hata ({url}): {exc}")
    return None


def _from_frankfurter() -> float | None:
    """frankfurter.dev — ECB referans kuru, anahtarsız ve ücretsiz. Üçüncü
    kaynak: ilk ikisi de düşerse sabit sayıya düşmeden önce denenir.
    ECB günlük referansı olduğu için hafta sonu/tatilde bir gün gecikebilir —
    sabit 41.0'den her hâlükârda çok daha doğru."""
    try:
        r = requests.get("https://api.frankfurter.dev/v1/latest",
                         params={"base": "USD", "symbols": "TRY"},
                         headers={"User-Agent": _UA}, timeout=8)
        if r.status_code != 200:
            return None
        return _valid((r.json().get("rates") or {}).get("TRY"))
    except Exception as exc:
        logger.debug(f"frankfurter USDTRY hata: {exc}")
        return None


# Sıra önemli: Yahoo (en taze, ama sık 429) → truncgil (TR serbest piyasa,
# Render'dan güvenilir) → frankfurter (ECB, anahtarsız).
_SOURCES = (
    ("yahoo", _from_yahoo),
    ("truncgil", _from_truncgil),
    ("frankfurter", _from_frankfurter),
)


def usdtry_rate() -> float:
    """1 USD kaç ₺. Sıralı kaynak zinciri; hepsi düşerse son çare sabit.
    Asla 0/NaN döndürmez → ₺'ye çeviren çağıran taraf güvenle çarpabilir."""
    hit = _cache.get("rate")
    if hit is not None:
        age = time.time() - _cache.get("ts", 0)
        ttl = _TTL_FALLBACK if _cache.get("source") == "fallback" else _TTL_LIVE
        if age < ttl:
            return hit

    for name, fetch in _SOURCES:
        try:
            rate = fetch()
        except Exception as exc:
            logger.debug(f"USDTRY kaynak hatası ({name}): {exc}")
            continue
        if rate:
            if _cache.get("source") not in (None, name):
                logger.info(f"USDTRY kaynağı değişti → {name} ({rate})")
            _cache.update({"rate": rate, "ts": time.time(), "source": name})
            return rate

    logger.warning(
        f"USDTRY hiçbir kaynaktan alınamadı → geçici sabit {_FALLBACK} "
        f"({_TTL_FALLBACK}sn sonra tekrar denenecek)")
    _cache.update({"rate": _FALLBACK, "ts": time.time(), "source": "fallback"})
    return _FALLBACK


# ── GEÇMİŞ kur (maliyet tarafı) ────────────────────────────────────────
# Pozisyonun ₺ maliyeti ALIŞ GÜNÜNÜN kuruyla hesaplanır; canlı kurla değil.
# Canlı kur kullanılırsa kurdan gelen reel kâr K/Z'de hiç görünmez (100$'lık
# hisse bir yıl önce alındıysa maliyet de bugünkü kurla büyür, fark sıfırlanır).
#
# Kaynak frankfurter (ECB, anahtarsız, tarih ucu var) — Yahoo BİLEREK
# kullanılmıyor: Render IP'si zaten 429 yiyor, geçmiş kur sorgusu o kotayı
# daha da yakardı. ECB günlük referansı hafta sonu/tatilde yayınlanmaz;
# uç en yakın ÖNCEKİ iş gününü döndürür (alış günü için doğru davranış).
#
# Geçmiş kur DEĞİŞMEZ → uzun TTL (30 gün) ve paylaşımlı cache.
_HIST_TTL = 30 * 24 * 3600
_HIST_KEY = "fx:usdtry:"


def usdtry_rate_on(day) -> float | None:
    """`day` tarihindeki 1 USD = ? ₺. Bulunamazsa None.

    `day` date/datetime ya da ISO metin olabilir: SQLite `DATETIME` kolonunu
    METİN olarak döndürür (Postgres datetime verir), migration/backfill her
    ikisiyle de çalışmalı.

    None dönmesi çağıran için "kur bilinmiyor" demektir — uydurma bir sayı
    yerine mevcut davranışa (canlı kur) düşülmesi gerekir.
    """
    try:
        if isinstance(day, str):
            iso = day.strip()[:10]
            if len(iso) != 10:
                return None
        else:
            d = day.date() if hasattr(day, "date") else day
            iso = d.isoformat()
    except Exception:
        return None

    key = _HIST_KEY + iso
    hit = cache.get(key)
    if hit is not None:
        return _valid(hit[0])

    try:
        r = requests.get(f"https://api.frankfurter.dev/v1/{iso}",
                         params={"base": "USD", "symbols": "TRY"},
                         headers={"User-Agent": _UA}, timeout=8)
        if r.status_code != 200:
            return None
        rate = _valid((r.json().get("rates") or {}).get("TRY"))
    except Exception as exc:
        logger.debug(f"frankfurter geçmiş USDTRY hata ({iso}): {exc}")
        return None

    if rate:
        cache.set(key, rate, ttl=_HIST_TTL)
    return rate


def rate_at_cost(currency: str | None, day=None) -> float | None:
    """Maliyet kaydı için kur. TRY varlıkta anlamsız → None.

    `day` verilirse o günün kuru, yoksa bugünkü canlı kur. Geçmiş kur
    alınamazsa canlı kura düşülür (maliyeti hiç işaretlememekten iyi).
    """
    if currency == "TRY":
        return None
    if day is not None:
        historical = usdtry_rate_on(day)
        if historical:
            return historical
    return usdtry_rate()


def rate_source() -> str | None:
    """Son kurun hangi kaynaktan geldiği ('yahoo'/'truncgil'/'frankfurter'/
    'fallback'). Teşhis ve UI'da 'yaklaşık' rozeti için."""
    return _cache.get("source")


def currency_of(symbol: str) -> str:
    """Sembol → para birimi (sonek tabanlı). .IS/.TR (BIST), .FON (TEFAS
    yatırım fonu — birim pay değeri daima TL) ve *TRY=X → TRY, diğer her şey
    → USD. Para/çeviri mantığı tek yerde olsun diye
    portfolio_service._currency_of buraya delege eder."""
    s = (symbol or "").upper()
    # .ALTIN/.GUMUS = fiziki altın/gümüş; serbest piyasa fiyatı ₺ cinsindendir.
    if s.endswith((".IS", ".TR", ".FON", ".ALTIN", ".GUMUS")):
        return "TRY"
    if "TRY=X" in s:
        return "TRY"
    return "USD"


def to_try(value: float, currency: str | None) -> float:
    """Bir tutarı ₺'ye çevir. currency 'TRY' ise olduğu gibi, değilse
    (USD vb.) canlı USDTRY ile çarp. Tek-birim toplam/ağırlık/sektör
    hesapları MUTLAKA bunu kullanmalı (ham toplama = $1266 ≈ ₺1266 bug)."""
    try:
        v = float(value)
    except (TypeError, ValueError):
        return 0.0
    if currency == "TRY":
        return v
    return v * usdtry_rate()
