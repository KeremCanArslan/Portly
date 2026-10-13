"""Alım-satım sinyal motoru (kural tabanlı).

Portföy + izleme listesi sembollerini teknik göstergeler (trend/SMA, RSI, MACD,
Bollinger, Stochastic, hacim) ve temel oranlar (F/K, PEG, ROE, marj, büyüme,
borç, analist konsensüsü) üzerinden tarar; sembol başına **AL / TUT / SAT**
sinyali + Türkçe gerekçe listesi üretir.

TASARIM — LLM YOK: tarama sembol-başına LLM çağırsaydı AI kotası (flash 20/gün)
tek taramada biterdi; kural tabanlı skor hem hızlı hem deterministik. Derin AI
yorumu isteyen kullanıcı hisse detayındaki AI Teknik/Temel analize gider.

Skor ekseni KALICI KURALLA uyumlu: 0-100, **yüksek = alım lehine**.
AL ≥ 65 · SAT ≤ 35 · arası TUT. Kripto/döviz/emtiada temel oran anlamsız →
sinyal yalnız teknik bileşenden gelir (gerekçede belirtilir).
"""

import math
import threading
import time
import zlib
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta

from loguru import logger
from sqlalchemy.orm import Session

from app.core import cache

from app.services import fundamental_analysis_service, technical_analysis_service
from app.services.fundamental_analysis_service import _classify
from app.services.symbol_alias import canonical

_signal_cache: dict[str, tuple[dict, datetime]] = {}
_SIGNAL_TTL_MINUTES = 15

# Temel oran cache'i PAYLAŞILAN cache'te (Redis): süreç-içi tutulunca her
# deploy ve her uyandırma sonrası ilk tarama oranları baştan çekiyordu —
# canlıda ölçülen soğuk tarama 24 sn, oysa cache sıcakken aynı tarama 0,5 sn.
#
# KAYIT ≠ TAZELİK PENCERESİ (4 Eyl ölçümü — fiyat cache'inde öğrenilen aynı
# ders). Canlı ölçüm: soğuk /signals **20,7 sn**; aynı anda tek kripto sembolü
# 0,3 sn, tek ABD hissesi 2,8-5,3 sn → aradaki fark tamamen temel oran çekimi
# (yfinance `.info` Render IP'sinde bloklu → Finnhub → degrade zinciri).
# 44 hisse x ~3 sn / 6 işçi ~= 21 sn, ölçülen süreyi birebir açıklıyor.
# Neden hepsi BİRDEN soğuktu: bir tarama 44 sembolü aynı 20 saniye içinde
# yazıyor → 12 saat sonra hepsi aynı 20 saniye içinde düşüyor; faturayı
# Sinyaller'e ilk giren kullanıcı ödüyordu (günde iki kez).
# Çözüm: kayıt _FUND_KEEP_HOURS boyunca DURUR, 12 saat yalnız TAZELİK eşiğidir.
# Bayatlamış oran ANINDA servis edilir, tazeleme arka planda yapılır — F/K ve
# ROE çeyrekte bir değişir, 12 saatlik veri için kullanıcı bekletilmez.
_FUND_FRESH_HOURS = 12
_FUND_KEEP_HOURS = 7 * 24
# Tazelik eşiğine sembole özgü DETERMİNİSTİK sapma — yalnız AŞAĞI yönde
# (12 saat → 9-12 saat): birlikte yazılan kayıtlar aksi halde birlikte bayatlar
# ve arka plan tazelemesi Finnhub ücretsiz tier'ına sürü hâlinde gider.
# Yukarı sapma YOK, çünkü eşik kaydın kendi ömrünü geçmemeli: bu sürümden önce
# yazılmış kayıtlar Redis'te hâlâ 12 saatlik TTL taşıyor; eşik 12 saati aşsaydı
# o kayıtlar bayat sayılıp tazelenmeden ölür, geçişte yine bloklayan çekim olurdu.
_FUND_JITTER = 0.25
_FUND_KEY = "sig:fund:"

# Arka planda tazelenen semboller — aynı sembol için ikinci tur açılmaz
# (market_data_service._schedule_batch_refresh ile aynı desen).
_fund_refresh_lock = threading.Lock()
_fund_refresh_in_progress: set[str] = set()
# Aynı anda kaç sembol tazelenebilir: bir tarama 44 bayat sembol görürse
# 44 thread açıp Finnhub ücretsiz tier'ını (~60 istek/dk) 429'latırdı. Tavana
# takılan sembol bayat kalır — sonraki istek ya da ısıtma turu devralır.
_FUND_REFRESH_MAX_INFLIGHT = 3

_SCAN_WORKERS = 6

DISCLAIMER = (
    "Sinyaller teknik göstergeler ve temel oranlardan kural tabanlı üretilir; "
    "yatırım tavsiyesi değildir."
)


def _num(val):
    """Sonlu sayı değilse None (NaN/inf sinyal kuralına girmesin)."""
    if val is None:
        return None
    try:
        f = float(val)
    except (TypeError, ValueError):
        return None
    return f if math.isfinite(f) else None


class _Rules:
    """Kural sonuçlarını biriktirir: skor katkısı + gerekçe metni.

    Gerekçeler mutlak ağırlığa göre sıralanır → kullanıcı en belirleyici
    2-3 nedeni üstte görür.
    """

    def __init__(self):
        self.score = 50.0
        self.reasons: list[tuple[float, str]] = []

    def add(self, weight: float, text: str):
        self.score += weight
        self.reasons.append((weight, text))

    def top_reasons(self, n: int = 6) -> list[str]:
        ordered = sorted(self.reasons, key=lambda r: abs(r[0]), reverse=True)
        return [t for _, t in ordered[:n]]

    def clamped(self) -> int:
        return int(round(max(0.0, min(100.0, self.score))))


def _technical_rules(ind: dict) -> _Rules:
    """technical_analysis_service._compute_indicators çıktısından kural skoru."""
    r = _Rules()
    price = _num(ind.get("current_price"))
    sma50 = _num(ind.get("sma50"))
    sma200 = _num(ind.get("sma200"))

    # Trend (hareketli ortalamalar)
    if price is not None and sma50 is not None:
        if price > sma50:
            r.add(7, "Fiyat SMA50 üzerinde — orta vadeli trend yukarı")
        else:
            r.add(-7, "Fiyat SMA50 altında — orta vadeli trend aşağı")
    if price is not None and sma200 is not None:
        if price > sma200:
            r.add(7, "Fiyat SMA200 üzerinde — uzun vadeli trend yukarı")
        else:
            r.add(-7, "Fiyat SMA200 altında — uzun vadeli trend aşağı")
    if sma50 is not None and sma200 is not None:
        if sma50 > sma200:
            r.add(8, "SMA50 > SMA200 (golden cross düzeni) — trend yapısı güçlü")
        else:
            r.add(-8, "SMA50 < SMA200 (death cross düzeni) — trend yapısı zayıf")

    # Momentum
    rsi = _num(ind.get("rsi14"))
    if rsi is not None:
        if rsi < 30:
            r.add(10, f"RSI {rsi:.0f} — aşırı satım bölgesi, tepki alımı potansiyeli")
        elif rsi < 40:
            r.add(5, f"RSI {rsi:.0f} — satım bölgesine yakın, momentum ucuzlamış")
        elif rsi > 70:
            r.add(-10, f"RSI {rsi:.0f} — aşırı alım bölgesi, geri çekilme riski")
        elif rsi > 60:
            r.add(-5, f"RSI {rsi:.0f} — alım bölgesine yakın, momentum ısınmış")

    macd = (ind.get("macd") or {})
    macd_val = _num(macd.get("macd") if isinstance(macd, dict) else None)
    if macd_val is not None:
        if macd_val > 0:
            r.add(6, "MACD pozitif — kısa vadeli momentum yukarı")
        else:
            r.add(-6, "MACD negatif — kısa vadeli momentum aşağı")

    bb = ind.get("bollinger") or {}
    pct_b = _num(bb.get("pct_b") if isinstance(bb, dict) else None)
    if pct_b is not None:
        if pct_b < 0:
            r.add(6, "Fiyat Bollinger alt bandının altında — aşırı gerilmiş, tepki gelebilir")
        elif pct_b > 1:
            r.add(-6, "Fiyat Bollinger üst bandının üstünde — kısa vadede gerilmiş")

    stoch = _num(ind.get("stochastic"))
    if stoch is not None:
        if stoch < 20:
            r.add(5, f"Stochastic {stoch:.0f} — aşırı satım")
        elif stoch > 80:
            r.add(-5, f"Stochastic {stoch:.0f} — aşırı alım")

    # Hacim onayı: artan hacim mevcut yönü güçlendirir
    vol = _num(ind.get("volume_trend_pct"))
    ret5 = _num(ind.get("return_5d_pct"))
    if vol is not None and ret5 is not None and vol > 25:
        if ret5 > 0:
            r.add(4, f"Hacim %{vol:.0f} arttı — yükselişe katılım güçlü")
        else:
            r.add(-4, f"Düşüş %{vol:.0f} hacim artışıyla geldi — satış baskısı belirgin")

    return r


# Bir fonun günlük birim pay değerinin kaçta kaçı düşüş günü. Para piyasası /
# faiz benzeri fonlar neredeyse hiç düşmez → RSI daima 100, Stochastic daima
# 100 çıkar ve motor bunu "aşırı alım, geri çekilme riski" diye okur. Bu
# sinyal UYDURMADIR: fonun düşmemesi aşırı ısınma değil, ürünün doğasıdır.
_ACCRUAL_MAX_DOWN_RATIO = 0.05


def _down_day_ratio(symbol: str, bars: dict | None = None) -> float | None:
    """Son 6 ayın düşüş günü oranı (paylaşılan OHLCV cache'inden, ek ağ yok).

    `bars` verilirse (tarama yolu) cache'e hiç gidilmez."""
    try:
        if bars is None:
            from app.services import market_data_service
            bars = market_data_service.get_daily_ohlcv(
                [symbol], "6mo").get(symbol.upper())
    except Exception as exc:
        logger.debug(f"Düşüş günü oranı hesaplanamadı ({symbol}): {exc}")
        return None
    closes = [float(c) for c in (bars or {}).get("close", [])]
    if len(closes) < 20:
        return None
    down = sum(1 for i in range(1, len(closes)) if closes[i] < closes[i - 1])
    return down / (len(closes) - 1)


def _fund_rules(symbol: str, ind: dict, bars: dict | None = None) -> tuple[_Rules, bool]:
    """Fon için kural seti. Dönüş: (kurallar, birikimli_mi).

    Dalgalanan fonlarda (hisse senedi/serbest fonlar) teknik kurallar aynen
    geçerli — birim pay değeri piyasayı takip eder. Birikimli fonlarda
    (para piyasası, kısa vadeli borçlanma) mean-reversion göstergeleri
    anlamsız olduğu için hiç uygulanmaz ve neden uygulanmadığı yazılır."""
    ratio = _down_day_ratio(symbol, bars)
    if ratio is not None and ratio < _ACCRUAL_MAX_DOWN_RATIO:
        r = _Rules()   # skor 50 → TUT
        r.add(0, "Bu fon neredeyse hiç değer kaybetmiyor (para piyasası/faiz "
                 "benzeri birikimli getiri) — aşırı alım/satım göstergeleri "
                 "bu üründe sinyal üretmez")
        ret30 = _num(ind.get("return_30d_pct"))
        if ret30 is not None:
            r.add(0, f"Son 30 günde birim pay değeri %{ret30:.2f} arttı")
        return r, True
    return _technical_rules(ind), False


def _fundamental_rules(f: dict) -> _Rules:
    """Temel oran setinden kural skoru (yalnız hisse; oranlar mevcutsa)."""
    r = _Rules()

    pe = _num(f.get("pe_trailing"))
    if pe is not None and pe > 0:
        if pe <= 12:
            r.add(8, f"F/K {pe:.1f} — belirgin iskontolu değerleme")
        elif pe <= 20:
            r.add(4, f"F/K {pe:.1f} — makul değerleme")
        elif pe > 35:
            r.add(-6, f"F/K {pe:.1f} — primli değerleme")

    peg = _num(f.get("peg"))
    if peg is not None and peg > 0:
        if peg < 1:
            r.add(5, f"PEG {peg:.2f} — büyümesine göre ucuz")
        elif peg > 2.5:
            r.add(-4, f"PEG {peg:.2f} — büyümesine göre pahalı")

    roe = _num(f.get("roe_pct"))
    if roe is not None:
        if roe >= 20:
            r.add(7, f"ROE %{roe:.0f} — sermaye verimliliği güçlü")
        elif roe >= 12:
            r.add(4, f"ROE %{roe:.0f} — sermaye verimliliği iyi")
        elif roe < 0:
            r.add(-8, "ROE negatif — özkaynak zarar üretiyor")
        elif roe < 5:
            r.add(-4, f"ROE %{roe:.0f} — sermaye verimliliği zayıf")

    margin = _num(f.get("profit_margin_pct"))
    if margin is not None:
        if margin >= 15:
            r.add(4, f"Net kâr marjı %{margin:.0f} — kârlılık sağlam")
        elif margin < 0:
            r.add(-8, "Şirket zarar ediyor (negatif kâr marjı)")

    growth = _num(f.get("revenue_growth_pct"))
    if growth is not None:
        if growth >= 15:
            r.add(5, f"Gelir büyümesi %{growth:.0f} — güçlü büyüme")
        elif growth >= 5:
            r.add(2, f"Gelir büyümesi %{growth:.0f}")
        elif growth < 0:
            r.add(-5, f"Gelir %{abs(growth):.0f} daraldı — büyüme sorunu")

    de = _num(f.get("debt_to_equity"))
    if de is not None:
        if de > 200:
            r.add(-6, f"Borç/özkaynak %{de:.0f} — borçluluk yüksek")
        elif de < 60:
            r.add(3, "Borçluluk düşük — bilanço sağlam")

    dy = _num(f.get("dividend_yield_pct"))
    if dy is not None and dy >= 3:
        r.add(2, f"Temettü verimi %{dy:.1f}")

    rec = f.get("analyst_recommendation")
    count = f.get("analyst_count")
    if rec in ("buy", "strong_buy"):
        suffix = f" ({int(count)} analist)" if count else ""
        r.add(6, f"Analist konsensüsü AL{suffix}")
    elif rec in ("sell", "strong_sell"):
        suffix = f" ({int(count)} analist)" if count else ""
        r.add(-6, f"Analist konsensüsü SAT{suffix}")

    # 52 haftalık banda göre konum — dibe yakınlık değer fırsatı sayılır
    price = _num(f.get("current_price"))
    low = _num(f.get("fifty_two_week_low"))
    high = _num(f.get("fifty_two_week_high"))
    if price is not None and low is not None and high is not None and high > low:
        pos = (price - low) / (high - low)
        if pos < 0.15:
            r.add(3, "Fiyat 52 haftalık dibe yakın")

    return r


def _combine(tech_score: int, fund_score: int | None) -> int:
    """Temel oran varsa 55/45 harman; yoksa sinyal tamamen teknik."""
    if fund_score is None:
        return tech_score
    return int(round(0.55 * tech_score + 0.45 * fund_score))


def _label(score: int) -> str:
    if score >= 65:
        return "AL"
    if score <= 35:
        return "SAT"
    return "TUT"


def _fund_fresh_seconds(symbol: str) -> float:
    """Sembole özgü tazelik eşiği: 12 saat - (0…%25), sembolden deterministik.

    Rastgele değil — aynı sembol her süreçte aynı eşiği görür (testlenebilir,
    süreçler arası tutarlı), ama semboller birbirinden farklı zamanlarda
    bayatlar → toplu düşüş yok.
    """
    h = zlib.crc32(symbol.encode()) / 0xFFFFFFFF
    return _FUND_FRESH_HOURS * 3600 * (1 - _FUND_JITTER * h)


def _fetch_and_store_fundamentals(symbol: str) -> dict | None:
    """Oranları kaynaktan çeker ve paylaşılan cache'e yazar (BLOKLAR).

    `_compute_fundamentals` sırasıyla yfinance `.info` → Finnhub → fiyat-çıpalı
    degrade dener; degrade (`data_limited`) sonuçta oran yok → sinyal için
    None say (teknik-only'ye düşer). "Oran yok" sonucu da cache'lenir, yoksa
    BIST hisseleri her taramada boşuna yeniden deneniyor.
    """
    try:
        f = fundamental_analysis_service._compute_fundamentals(symbol)
        if f.get("data_limited"):
            f = None
    except Exception as exc:
        logger.warning(f"Sinyal temel verisi alınamadı ({symbol}): {exc}")
        f = None
    if f is None:
        # Elde GERÇEK oran varken "oran yok" YAZMA: geçici bir kaynak hatası
        # (Finnhub 429 / .info bloğu) hisseyi saatlerce temelsiz bırakırdı.
        # Kayıt olduğu gibi — bayat damgasıyla — kalır, sonraki tur yeniden
        # dener. Hiç kayıt yoksa "oran yok" cache'lenir (BIST hisseleri her
        # taramada boşuna yeniden denenmesin).
        prev = cache.get(_FUND_KEY + symbol)
        if prev is not None and isinstance(prev[0], dict):
            logger.debug(f"Temel oran tazelenemedi, eldeki kayıt korundu ({symbol})")
            return prev[0]
    # JSON-serileştirilebilir olmalı (paylaşılan cache JSON saklıyor).
    cache.set(_FUND_KEY + symbol,
              fundamental_analysis_service._json_safe(f) if f else None,
              _FUND_KEEP_HOURS * 3600)
    return f


def _schedule_fund_refresh(symbol: str) -> None:
    """Bayatlamış oranı arka planda (daemon thread) tazeler; istek yolu beklemez.

    Aynı sembol için eşzamanlı ikinci tur açılmaz — 51 sembollük bir tarama
    aynı bayat sembolü birden çok işçiden görebilir — ve toplam eşzamanlı tur
    `_FUND_REFRESH_MAX_INFLIGHT` ile sınırlıdır.
    """
    with _fund_refresh_lock:
        if symbol in _fund_refresh_in_progress:
            return
        if len(_fund_refresh_in_progress) >= _FUND_REFRESH_MAX_INFLIGHT:
            return
        _fund_refresh_in_progress.add(symbol)

    def _work() -> None:
        try:
            _fetch_and_store_fundamentals(symbol)
        except Exception as exc:   # pragma: no cover - _fetch zaten yutuyor
            logger.warning(f"Temel oran arka plan tazelemesi düştü ({symbol}): {exc}")
        finally:
            with _fund_refresh_lock:
                _fund_refresh_in_progress.discard(symbol)

    threading.Thread(target=_work, daemon=True).start()


def _fund_is_stale(ts: float, symbol: str) -> bool:
    return (time.time() - ts) >= _fund_fresh_seconds(symbol)


def _get_fundamentals_cached(symbol: str) -> dict | None:
    """Hafif temel oran seti (LLM'siz), paylaşılan cache — stale-while-revalidate.

    Taze kayıt as-is döner. Bayat kayıt DA anında döner (+ arka planda
    tazelenir): oranın 12 saat eskimiş olması kullanıcıyı 3 saniye bekletmeyi
    hak etmez. Kayıt hiç yoksa bloklayan çekim yapılır (ilk kurulum).
    """
    hit = cache.get(_FUND_KEY + symbol)
    if hit is not None:
        data, ts = hit
        if _fund_is_stale(ts, symbol):
            _schedule_fund_refresh(symbol)
        return data if isinstance(data, dict) else None
    return _fetch_and_store_fundamentals(symbol)


def prewarm_fundamentals(symbols: list[str], limit: int = 8) -> int:
    """Temel oran cache'ini arka planda ısıtır; ISITILAN sembol sayısını döner.

    İlk sinyal taraması ~32 sn sürüyordu ve bunun büyük kısmı sembol sembol
    temel oran çekmekti (ölçüm: cache sıcakken aynı tarama 0,5 sn). Bu maliyet
    Sinyaller sekmesine ilk giren KULLANICIYA ödetiliyordu; oysa 12 saatlik
    paylaşılan cache'i arka planda doldurmak aynı işi görüyor.

    Nazik davranış: yalnız EKSİK ya da BAYATLAMIŞ olanlar hesaplanır (hepsi
    tazeyken tur bedavadır), tur başına en fazla `limit` sembol denenir
    (Finnhub ücretsiz tier ~60 istek/dk) ve sıra sıra gidilir — paralel değil.

    Bayatı da ısıtması ŞART (4 Eyl): kayıt artık 12 saatte silinmiyor, yalnız
    bayatlıyor. Isıtma "eksik mi" diye baksaydı hiçbir kaydı yenilemez, tazeleme
    tamamen istek yolundaki arka plan thread'ine kalırdı.
    """
    warmed = 0
    for symbol in symbols:
        if warmed >= limit:
            break
        # Fon/kripto/döviz/emtiada temel oran KAVRAMI yok (hisse dışı sınıflar
        # zaten teknik-only değerlendiriliyor) → boşuna istek atma.
        if _classify(symbol) != "stock":
            continue
        hit = cache.get(_FUND_KEY + symbol)
        if hit is not None and not _fund_is_stale(hit[1], symbol):
            continue
        try:
            _fetch_and_store_fundamentals(symbol)
            warmed += 1
        except Exception as exc:
            logger.debug(f"Temel oran ısıtma atlandı ({symbol}): {exc}")
    return warmed


def get_signal(symbol: str, force_refresh: bool = False,
               bars: dict | None = None) -> dict:
    """Tek sembol için birleşik AL/TUT/SAT sinyali (15 dk cache).

    `bars`: çağıran OHLCV'yi zaten çektiyse (toplu tarama) o seri kullanılır."""
    symbol = canonical(symbol)
    now = datetime.now()
    if not force_refresh and symbol in _signal_cache:
        data, ts = _signal_cache[symbol]
        if now - ts < timedelta(minutes=_SIGNAL_TTL_MINUTES):
            return data

    asset_class = _classify(symbol)
    indicators = technical_analysis_service._compute_indicators(symbol, bars)
    accrual_fund = False
    if asset_class == "fund":
        tech, accrual_fund = _fund_rules(symbol, indicators, bars)
    else:
        tech = _technical_rules(indicators)
    tech_score = tech.clamped()

    fund_score = None
    fund_reasons: list[str] = []
    fundamental_available = False
    if asset_class == "stock":
        f = _get_fundamentals_cached(symbol)
        if f is not None:
            fund = _fundamental_rules(f)
            fund_score = fund.clamped()
            fund_reasons = fund.top_reasons(4)
            fundamental_available = True

    score = _combine(tech_score, fund_score)
    reasons = tech.top_reasons(4) + fund_reasons
    if asset_class == "fund":
        # Fon tek şirket değil, portföy: F/K-ROE anlamsız. Ayrıca gün içi
        # yüksek/düşük ve hacim YOK (günde tek birim pay değeri) → aralığa ve
        # hacme dayanan göstergeler devreye girmiyor, gerekçe bunu söylüyor.
        reasons.append(
            "Yatırım fonu — şirket oranları (F/K, ROE) uygulanmaz; "
            + ("sinyal üretilmedi, yalnız durum özeti" if accrual_fund
               else "sinyal birim pay değeri trendine dayalı"))
    elif asset_class != "stock":
        reasons.append("Bu varlık sınıfında temel oran uygulanmaz — sinyal teknik göstergelere dayalı")
    elif not fundamental_available:
        reasons.append("Temel oran verisi şu an yok — sinyal teknik göstergelere dayalı")

    result = {
        "symbol": symbol,
        "asset_class": asset_class,
        "current_price": _num(indicators.get("current_price")),
        "signal": _label(score),
        "score": score,
        "technical_score": tech_score,
        "fundamental_score": fund_score,
        "fundamental_available": fundamental_available,
        "reasons": reasons,
        "generated_at": now.isoformat(),
    }
    _signal_cache[symbol] = (result, now)
    return result


def prewarm_signals(symbols: list[str], limit: int = 60) -> int:
    """Sinyal cache'ini (süreç-içi, 15 dk) arka planda doldurur; ısıtılan sayı.

    Neden: `_signal_cache` süreç-içi olduğu için her deploy/restart sonrası ilk
    Sinyaller açılışı sıfırdan hesaplıyor — canlı ölçüm (9. tur): taze süreçte
    `/signals` 3,9 sn, aynı tarama hemen ardından 0,25 sn. Paylaşılan cache'ler
    (fiyat/OHLCV/temel oran) sıcak olduğu için bu maliyet ağ değil hesap; yine
    de faturayı ilk kullanıcı ödüyordu. Startup'ta arka planda ısıtılır.

    OHLCV TEK batch okunur (sembol başına ayrı istek atılmaz); zaten cache'te
    olan sembol atlanır → ikinci çağrıda tur bedava.
    """
    from app.services import market_data_service
    todo = [s for s in symbols[:limit] if s and s not in _signal_cache]
    if not todo:
        return 0
    bars_map = market_data_service.get_daily_ohlcv(todo, "6mo")
    warmed = 0
    for symbol in todo:
        try:
            get_signal(symbol, bars=bars_map.get(symbol))
            warmed += 1
        except Exception as exc:
            logger.debug(f"Sinyal ısıtma atlandı ({symbol}): {exc}")
    return warmed


def get_signals_for_user(db: Session, user_id: int, force_refresh: bool = False) -> dict:
    """Kullanıcının portföy + izleme listesi sembollerini paralel tarar.

    En güçlü sinyaller (50'den sapması büyük) üstte; veri alınamayan semboller
    sonucu düşürmez, `failed` listesinde raporlanır.
    """
    from app.models.portfolio import Portfolio
    from app.models.watchlist import WatchlistItem

    held = {canonical(row[0]) for row in
            db.query(Portfolio.symbol).filter(Portfolio.user_id == user_id,
                                              Portfolio.quantity > 0)}
    watched = {canonical(row[0]) for row in
               db.query(WatchlistItem.symbol).filter(WatchlistItem.user_id == user_id)}
    # Fiziki altın/gümüş taranmaz: mumu/oranı olmayan bir varlık için
    # AL/TUT/SAT skoru üretmek uydurma olurdu (ve her turda boşuna istek).
    symbols = sorted(s for s in (held | watched) if _classify(s) != "physical")

    signals: list[dict] = []
    failed: list[str] = []
    if symbols:
        # Tüm sembollerin OHLCV'sini TEK yf.download ile ısıt: aşağıdaki
        # paralel tarama sıcak cache'ten okur. Aksi halde sembol başına ayrı
        # Yahoo isteği gidiyor, hepsi 429 yiyip liste boş kalıyordu.
        # Sonuç ARTIK ELDE TUTULUYOR: aynı seriyi işçilerde ikinci ve üçüncü
        # kez cache'ten okumak (51 sembolde ~150 Redis gidiş-dönüşü + JSON
        # çözme) bedavaya gidiyordu.
        bars_map: dict[str, dict] = {}
        try:
            from app.services import market_data_service
            bars_map = market_data_service.get_daily_ohlcv(symbols, "6mo")
        except Exception as exc:
            logger.warning(f"Sinyal ön-ısıtma atlandı: {exc}")
        with ThreadPoolExecutor(max_workers=_SCAN_WORKERS) as pool:
            # Isıtmadan dönmeyen sembol için bars=None → eski davranış (kendi
            # çekimini dener, negatif cache zaten koruyor).
            futures = {pool.submit(get_signal, s, force_refresh,
                                   bars_map.get(s.upper())): s for s in symbols}
            for fut in as_completed(futures):
                sym = futures[fut]
                try:
                    sig = fut.result()
                except Exception as exc:
                    logger.warning(f"Sinyal üretilemedi ({sym}): {exc}")
                    failed.append(sym)
                    continue
                sig["source"] = ("both" if sym in held and sym in watched
                                 else "portfolio" if sym in held else "watchlist")
                signals.append(sig)

    signals.sort(key=lambda s: abs(s["score"] - 50), reverse=True)
    return {
        "signals": signals,
        "failed": sorted(failed),
        "disclaimer": DISCLAIMER,
        "generated_at": datetime.now().isoformat(),
    }
