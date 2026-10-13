"""Temel analiz servisi.

yfinance ticker.info'dan şirket finansal göstergelerini çeker (P/E, P/B,
ROE, marj, büyüme, temettü vb.) ve LLM ile derin yorum üretir.
"""

import json
import math
import time
from datetime import datetime, timedelta
from loguru import logger
import yfinance as yf

from app.core.yf_session import get_session
from app.services import llm_service, finnhub_service

_cache: dict[str, tuple[dict, datetime]] = {}
_CACHE_TTL_HOURS = 12


def _safe(val, default=None):
    if val is None:
        return default
    if isinstance(val, (int, float)) and (val != val):  # NaN check
        return default
    return val


def _json_safe(value):
    """NaN/inf'i JSON-uyumlu yapar (Starlette JSONResponse `allow_nan=False` →
    NaN görürse 500). LLM JSON-mode'da bazen `NaN` token'ı dönebilir;
    `json.loads` bunu float('nan')'a çevirir → temizlenmezse endpoint çökerdi."""
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    return value


def _pct(val):
    """Kesir → yüzde. yfinance bu alanları (marj, ROE/ROA, büyüme, payout)
    DAİMA kesir döndürür (0.27 = %27); sürüm farkı yok → koşulsuz ×100.
    Eski 'abs<10 ise ×100' heuristiği yüksek ROE'de (örn. 12 = %1200'ü
    %12 sanması) bozuluyordu — kaldırıldı."""
    if val is None:
        return None
    try:
        return round(float(val) * 100, 2)
    except (TypeError, ValueError):
        return None


def _yield_pct(val):
    """Temettü verimi — yfinance 1.3.0 (bu projede pinli, requirements'ta
    sabit) bunu ZATEN yüzde döndürür: AAPL 0.36 = %0.36, KO 2.62 = %2.62,
    THYAO 2.29 = %2.29. ×100 yapmak %36/%262 gibi 100× şişmiş değer
    üretiyordu (eski _pct bunu yapıyordu). Olduğu gibi yuvarla."""
    if val is None:
        return None
    try:
        v = float(val)
    except (TypeError, ValueError):
        return None
    return round(max(v, 0.0), 2)


def _fast_price(symbol: str) -> tuple[float | None, object]:
    """`.info` (quoteSummary) Render datacenter IP'sinde sık BLOKLU → boş gelir.
    Chart-endpoint tabanlı `fast_info` aynı IP'de çalışıyor (BTC/macro yolu bunu
    kanıtladı). En azından cari fiyatı buradan al → 404 yerine fiyat-çıpalı
    analiz dönebilelim. Son çare history son-kapanış."""
    try:
        fi = yf.Ticker(symbol, session=get_session()).fast_info
        price = _safe(getattr(fi, "last_price", None))
        if price is not None:
            return float(price), fi
    except Exception:
        fi = None
    try:
        hist = yf.Ticker(symbol, session=get_session()).history(period="5d")
        closes = hist["Close"].dropna() if not hist.empty else None
        if closes is not None and not closes.empty:
            return float(closes.iloc[-1]), fi
    except Exception:
        pass
    return None, fi


# yfinance `.info` (Yahoo quoteSummary) Render'ın çıkış IP'sinde BLOKLU.
# Her sembolde iki kez denenip 0,6 sn uyunuyordu → 35 hisselik sinyal
# taramasının 24 saniyesi buradan geliyordu (ölçüldü: temel oran cache'i
# sıcakken aynı tarama 0,5 sn). Üst üste boş dönerse bir süre hiç denenmez;
# TEK bir başarı sayacı sıfırlar → lokal geliştirmede (bloklu değil) davranış
# değişmez, kaynak açılırsa kendiliğinden geri gelir.
_INFO_FAIL_THRESHOLD = 3
_INFO_COOLDOWN_SECONDS = 30 * 60
_info_fails = 0
_info_blocked_until = 0.0


def _info_available() -> bool:
    return time.time() >= _info_blocked_until


def _note_info_result(ok: bool) -> None:
    global _info_fails, _info_blocked_until
    if ok:
        _info_fails = 0
        return
    _info_fails += 1
    if _info_fails >= _INFO_FAIL_THRESHOLD:
        _info_blocked_until = time.time() + _INFO_COOLDOWN_SECONDS
        _info_fails = 0
        logger.warning(
            f"yfinance .info üst üste {_INFO_FAIL_THRESHOLD} kez boş döndü → "
            f"{_INFO_COOLDOWN_SECONDS // 60} dk atlanıyor (Finnhub yolu kullanılır)")


def info_available() -> bool:
    """`.info` denemeye değer mi (devre kesici açık mı)?

    Kesici bu modülde doğdu ama maliyet her `.info` çağrısında aynı: Render
    çıkış IP'sinde Yahoo quoteSummary BLOKLU, her deneme boşuna saniyeler
    yiyor. Sektör çözümü de aynı ucu çağırıyor → aynı kesiciye baksın.
    """
    return _info_available()


def note_info_result(ok: bool) -> None:
    """`.info` denemesinin sonucunu kesiciye bildir (dışarıdan çağıranlar için)."""
    _note_info_result(ok)


def _compute_fundamentals(symbol: str) -> dict:
    # Render free instance cold-start'ta yfinance'in ilk quoteSummary çağrısı
    # (Yahoo crumb/cookie anlaşması) sık sık BOŞ döner; kullanıcıya "yüklenemedi"
    # olarak yansıyordu. Boşsa kısa bir bekleyişle bir kez daha dene — ikinci
    # çağrı çoğu zaman dolu gelir.
    info = {}
    if _info_available():
        for attempt in range(2):
            ticker = yf.Ticker(symbol, session=get_session())
            try:
                info = ticker.info
            except Exception:
                info = {}
            if info and "regularMarketPrice" in info:
                break
            if attempt == 0:
                time.sleep(0.6)
        _note_info_result(bool(info and "regularMarketPrice" in info))

    price = _safe(info.get("regularMarketPrice")) if info else None

    # .info bloklu/boş ise fiyatı chart-endpoint'ten (fast_info/history) al.
    # data_limited=True → derin oranlar (F/K, ROE...) yok, LLM güncel fiyat +
    # kendi bilgisiyle değerlendirir; 404 ATMA (demo'da "yüklenemedi" görünmesin).
    fast = None
    data_limited = False
    if price is None:
        # yfinance `.info` (quoteSummary) Render IP'sinde bloklu → Finnhub'tan
        # TAM oran setini dene (ABD hisseleri; API-key'li, IP-bağımsız).
        # Başarılıysa degrade DEĞİL — gerçek F/K/ROE/marj döner.
        fin = finnhub_service.get_fundamentals(symbol)
        if fin and fin.get("current_price") is not None:
            return fin
        # Finnhub da kapsamıyor (BIST/uluslararası ücretsiz tier) → fiyat-çıpalı.
        price, fast = _fast_price(symbol)
        data_limited = True

    if price is None:
        # Gerçekten fiyat yok: kripto/döviz/emtia (macro yoluna gider) ya da
        # kalıcı Yahoo bloğu.
        raise ValueError(f"{symbol} için temel analiz verisi yok (kripto/döviz/emtia olabilir)")

    info = info or {}

    def _fast(attr):
        return _safe(getattr(fast, attr, None)) if fast is not None else None

    return {
        "data_limited": data_limited,
        "company_name": _safe(info.get("longName") or info.get("shortName"), symbol),
        "sector": _safe(info.get("sector")),
        "industry": _safe(info.get("industry")),
        "country": _safe(info.get("country")),
        "currency": _safe(info.get("currency")) or _fast("currency") or "USD",
        "market_cap": _safe(info.get("marketCap")) or _fast("market_cap"),
        "current_price": price,
        # Değerleme oranları
        "pe_trailing": _safe(info.get("trailingPE")),
        "pe_forward": _safe(info.get("forwardPE")),
        "pb": _safe(info.get("priceToBook")),
        "peg": _safe(info.get("pegRatio")),
        "ps": _safe(info.get("priceToSalesTrailing12Months")),
        # Karlılık
        "profit_margin_pct": _pct(info.get("profitMargins")),
        "operating_margin_pct": _pct(info.get("operatingMargins")),
        "roe_pct": _pct(info.get("returnOnEquity")),
        "roa_pct": _pct(info.get("returnOnAssets")),
        # Büyüme
        "revenue_growth_pct": _pct(info.get("revenueGrowth")),
        "earnings_growth_pct": _pct(info.get("earningsGrowth")),
        # Borç ve sağlık
        "debt_to_equity": _safe(info.get("debtToEquity")),
        "current_ratio": _safe(info.get("currentRatio")),
        "quick_ratio": _safe(info.get("quickRatio")),
        # Temettü
        "dividend_yield_pct": _yield_pct(info.get("dividendYield")),
        "payout_ratio_pct": _pct(info.get("payoutRatio")),
        # Fiyat istatistikleri
        "fifty_two_week_high": _safe(info.get("fiftyTwoWeekHigh")) or _fast("year_high"),
        "fifty_two_week_low": _safe(info.get("fiftyTwoWeekLow")) or _fast("year_low"),
        "beta": _safe(info.get("beta")),
        # Analist konsensüsü
        "analyst_target": _safe(info.get("targetMeanPrice")),
        "analyst_recommendation": _safe(info.get("recommendationKey")),
        "analyst_count": _safe(info.get("numberOfAnalystOpinions")),
    }


def _build_prompt(symbol: str, f: dict) -> str:
    limited_note = ""
    if f.get("data_limited"):
        limited_note = (
            "\n⚠️ NOT: Canlı finansal oran verisi (F/K, ROE, marj, büyüme) şu an "
            "çekilemedi (None). Bu hisse hakkındaki kendi güncel bilginle + "
            "yukarıdaki GÜNCEL FİYAT çıpasıyla değerlendir. Bilmediğin oranı "
            "UYDURMA; emin değilsen summary/zayıflıkta 'güncel oran verisi sınırlı' "
            "diye belirt. Yine de net bir genel değerlendirme + skor + tavsiye ver.\n"
        )
    return f"""{symbol} ({f['company_name']}) için profesyonel TEMEL analiz yap.
{limited_note}

═══ ŞIRKET ═══
Sektör: {f.get('sector')} / {f.get('industry')}
Ülke: {f.get('country')}
Piyasa değeri: {f.get('market_cap')}

═══ DEĞERLEME ═══
F/K (trailing): {f.get('pe_trailing')}  (düşük = ucuz, sektör ortalaması ile kıyas)
F/K (forward): {f.get('pe_forward')}    (gelecek beklenti)
PD/DD (P/B): {f.get('pb')}             (>1 marka primi, <1 indirimli)
PEG: {f.get('peg')}                   (<1 büyümeye göre ucuz)
P/S: {f.get('ps')}

═══ KÂRLILIK ═══
Kâr marjı: %{f.get('profit_margin_pct')}
Faaliyet marjı: %{f.get('operating_margin_pct')}
ROE: %{f.get('roe_pct')}                (>%15 iyi)
ROA: %{f.get('roa_pct')}

═══ BÜYÜME ═══
Gelir büyümesi (YoY): %{f.get('revenue_growth_pct')}
Kâr büyümesi (YoY): %{f.get('earnings_growth_pct')}

═══ MALİ SAĞLIK ═══
Borç/Özkaynak: {f.get('debt_to_equity')}  (<100 sağlıklı genelde)
Cari Oran: {f.get('current_ratio')}        (>1 kısa vade borç çevirebilir)
Asit Test: {f.get('quick_ratio')}

═══ TEMETTÜ ═══
Temettü verimi: %{f.get('dividend_yield_pct')}
Ödeme oranı: %{f.get('payout_ratio_pct')}

═══ FİYAT İSTATİSTİĞİ ═══
52H yüksek: {f.get('fifty_two_week_high')}, düşük: {f.get('fifty_two_week_low')}
Beta: {f.get('beta')}                    (>1 piyasadan oynak, <1 daha sakin)

═══ ANALİSTLER ═══
Hedef fiyat (ort.): {f.get('analyst_target')}
Tavsiye: {f.get('analyst_recommendation')}  ({f.get('analyst_count')} analist)
Cari fiyat: {f.get('current_price')}

ÇIKTI: Yalnızca geçerli JSON, başka metin yok. Derinlemesine analiz et:

{{
  "valuation": "Pahalı" | "Adil" | "Ucuz",
  "valuation_score": 0-100,
  "growth_quality": "Güçlü" | "Orta" | "Zayıf",
  "growth_score": 0-100,
  "financial_health": "Sağlam" | "Orta" | "Riskli",
  "health_score": 0-100,
  "overall_score": 0-100,
  "recommendation": "AL" | "TUT" | "SAT",
  "fair_value_estimate": tahmini gerçeğe uygun değer (sayı),
  "key_strengths": [4-5 güçlü yön — somut sayılarla, Türkçe],
  "key_weaknesses": [3-4 zayıflık — somut sayılarla, Türkçe],
  "competitive_position": "Bu şirketin sektördeki konumu — 2-3 cümle",
  "summary": "Genel değerlendirme — 3-4 cümle Türkçe"
}}"""


# ── Hisse-dışı varlıklar (kripto / forex / emtia): sınıfa uygun analiz ──────
# Hisse mantığı (F/K, bilanço) bu sınıflarda anlamsız → her sınıfa kendi
# çerçevesi (kripto=benimsenme, forex=makro, emtia=arz-talep). Skor barı
# yüksek=yeşil renklendiriyor → üç eksen de "yüksek=iyi" (3. eksen Risk DEĞİL,
# Dayanıklılık/İstikrar — yüksek=düşük oynaklık).

_SCORE_LABELS = {
    "crypto": ("Benimsenme", "Momentum", "Dayanıklılık"),
    "forex": ("Makro Görünüm", "Momentum", "İstikrar"),
    "commodity": ("Arz-Talep", "Momentum", "İstikrar"),
}

_CLASS_GUIDE = {
    "fund": (
        "Bu varlık bir TEFAS YATIRIM FONU — tek bir şirket değil, bir PORTFÖY. "
        "Şirket oranları (F/K, ROE, bilanço) UYGULANMAZ; fonun kendi "
        "hissesi/kârı yoktur. Şu eksenlerde değerlendir: fon türünün "
        "(hisse/borçlanma/para piyasası/serbest/kıymetli maden) hangi piyasa "
        "riskini taşıdığı, birim pay değerinin trendi ve istikrarı, "
        "TL enflasyonu ve mevduat/faiz alternatifine göre reel getiri, "
        "yönetim giderinin uzun vadeli etkisi, likidite ve alım-satım valörü. "
        "primary_score = fonun kendi kategorisindeki getiri gücü; "
        "stability_score yüksek = birim pay değerinde düşük oynaklık."
    ),
    "crypto": (
        "Bu varlık bir KRİPTO PARA — hisse mantığı (F/K, bilanço, ROE) "
        "UYGULANMAZ. Şu eksenlerde değerlendir: benimsenme ve ağ etkisi "
        "(kullanıcı/işlem büyümesi, kurumsal giriş, ETF), düzenleme ortamı, "
        "likidite ve oynaklık, arz mekaniği (halving, dolaşan arz, enflasyon), "
        "makro likidite (faiz, risk iştahı). primary_score = benimsenme/temel "
        "güç; stability_score yüksek = daha düşük oynaklık ve olgunluk."
    ),
    "forex": (
        "Bu varlık bir DÖVİZ PARİTESİ — şirket finansalı YOKTUR, MAKRO analiz "
        "yap. Şu eksenlerde değerlendir: iki para biriminin faiz farkı, "
        "enflasyon ayrışması, merkez bankası politikaları, cari denge, büyüme, "
        "jeopolitik/risk iştahı. primary_score = baz para lehine makro "
        "görünümün gücü; stability_score yüksek = düşük oynaklık/istikrar."
    ),
    "commodity": (
        "Bu varlık bir EMTİA — ARZ-TALEP analizi yap. Şu eksenlerde "
        "değerlendir: küresel arz (üretim, stoklar, OPEC/maden arzı), talep "
        "(sanayi, mevsimsellik, güvenli liman talebi), USD gücü ve reel faiz "
        "korelasyonu, jeopolitik riskler. primary_score = arz-talep dengesinin "
        "fiyat lehine gücü; stability_score yüksek = düşük oynaklık/istikrar."
    ),
}


def _classify(symbol: str) -> str:
    """Son ekten varlık sınıfı: -USD/-USDT→kripto, =X→forex, =F→emtia,
    .FON→TEFAS yatırım fonu, .ALTIN/.GUMUS→fiziki altın, else hisse."""
    s = symbol.upper()
    if s.endswith(".FON"):
        return "fund"
    if s.endswith((".ALTIN", ".GUMUS")):
        # Fiziki altının bilançosu, mumu, oranı YOK — teknik/temel analizin
        # hiçbiri uygulanamaz; kendi sınıfı olsun ki çağıranlar denemesin.
        return "physical"
    if s.endswith("-USD") or s.endswith("-USDT"):
        return "crypto"
    if s.endswith("=X"):
        return "forex"
    if s.endswith("=F"):
        return "commodity"
    return "stock"


def _ccy_prefix(code: str | None) -> str:
    if not code:
        return ""
    return {"USD": "$", "TRY": "₺", "EUR": "€", "GBP": "£", "JPY": "¥"}.get(
        code.upper(), f"{code} ")


def _overview(symbol: str, asset_class: str) -> dict:
    """Hisse-dışı varlık için çıpa verisi: cari fiyat, 52H aralık, 1A/6A/1Y
    performans, para birimi; kripto için ek piyasa değeri/arz/hacim."""
    if asset_class == "fund":
        return _fund_overview(symbol)

    t = yf.Ticker(symbol, session=get_session())
    try:
        info = t.info or {}
    except Exception:
        info = {}
    try:
        hist = t.history(period="1y", interval="1d")
    except Exception:
        hist = None

    closes = None
    if hist is not None and not hist.empty and "Close" in hist:
        s = hist["Close"].dropna()
        closes = s if not s.empty else None

    last = float(closes.iloc[-1]) if closes is not None else None
    price = _safe(info.get("regularMarketPrice")) or last

    def _perf(n: int):
        if closes is None or last is None or len(closes) < 2:
            return None
        base = (float(closes.iloc[0]) if len(closes) <= n
                else float(closes.iloc[-n - 1]))
        if base <= 0:
            return None
        return round((last / base - 1) * 100, 2)

    hi = _safe(info.get("fiftyTwoWeekHigh"))
    lo = _safe(info.get("fiftyTwoWeekLow"))
    if closes is not None:
        hi = hi if hi is not None else round(float(closes.max()), 4)
        lo = lo if lo is not None else round(float(closes.min()), 4)

    ccy = _safe(info.get("currency"), "USD")
    ov = {
        "display_name": _safe(info.get("longName") or info.get("shortName"), symbol),
        "currency": ccy,
        "currency_prefix": _ccy_prefix(ccy),
        "current_price": round(price, 4) if price is not None else None,
        "week52_high": hi,
        "week52_low": lo,
        "perf_1m_pct": _perf(21),
        "perf_6m_pct": _perf(126),
        "perf_1y_pct": _perf(252),
    }
    if asset_class == "crypto":
        ov["market_cap"] = _safe(info.get("marketCap"))
        ov["circulating_supply"] = _safe(info.get("circulatingSupply"))
        ov["volume"] = _safe(info.get("volume24Hr")
                             or info.get("regularMarketVolume"))
    return ov


def _fund_overview(symbol: str) -> dict:
    """TEFAS fonu için çıpa verisi — kaynak Yahoo değil, TEFAS birim pay
    değeri serisi (fonun Yahoo'da karşılığı YOK)."""
    from app.services import fund_catalog, fund_source_service

    series = fund_source_service.get_daily_closes([symbol]).get(symbol.upper(), {})
    days = sorted(series)
    last = series[days[-1]] if days else None

    def _perf(n: int):
        if not days or last is None or len(days) < 2:
            return None
        base = series[days[0]] if len(days) <= n else series[days[-n - 1]]
        return round((last / base - 1) * 100, 2) if base > 0 else None

    # 52 hafta = son ~252 işlem günü (fon her iş günü fiyat açıklar).
    window = [series[d] for d in days[-252:]] if days else []
    return {
        "display_name": fund_catalog.name_of(symbol) or symbol,
        "fund_kind": fund_catalog.kind_of(symbol),
        "currency": "TRY",
        "currency_prefix": "₺",
        "current_price": round(last, 6) if last is not None else None,
        "week52_high": round(max(window), 6) if window else None,
        "week52_low": round(min(window), 6) if window else None,
        "perf_1m_pct": _perf(21),
        "perf_6m_pct": _perf(126),
        "perf_1y_pct": _perf(252),
    }


def _build_macro_prompt(symbol: str, asset_class: str, ov: dict) -> str:
    pfx = ov.get("currency_prefix", "")
    lines = [
        f"Cari fiyat: {pfx}{ov.get('current_price')}",
        f"52 hafta aralık: {pfx}{ov.get('week52_low')} – {pfx}{ov.get('week52_high')}",
        f"Performans: 1A {ov.get('perf_1m_pct')}% · 6A {ov.get('perf_6m_pct')}% · "
        f"1Y {ov.get('perf_1y_pct')}%",
    ]
    if asset_class == "crypto":
        lines.append(
            f"Piyasa değeri: {ov.get('market_cap')} · "
            f"Dolaşan arz: {ov.get('circulating_supply')}")
    if asset_class == "fund" and ov.get("fund_kind"):
        lines.append(f"Fon türü: {ov['fund_kind']}")
    data_block = "\n".join(lines)
    return f"""{ov.get('display_name')} ({symbol}) için profesyonel analiz yap.

{_CLASS_GUIDE[asset_class]}

GÜNCEL VERİ (fiyat/çıpa olarak bunu kullan):
{data_block}

Bilgi tarihin güncel olmayabilir; somut sayılar için yukarıdaki güncel veriyi
çıpa al, yapısal ve EĞİTSEL bir çerçeve sun, kesin al-sat tahmini verme.

ÇIKTI: Yalnızca geçerli JSON, başka metin yok. Türkçe, somut:

{{
  "recommendation": "AL" | "TUT" | "SAT",
  "overall_score": 0-100,
  "primary_score": 0-100,
  "momentum_score": 0-100,
  "stability_score": 0-100,
  "key_strengths": [3-4 güçlü yön — somut, Türkçe],
  "key_weaknesses": [3-4 risk/zayıflık — somut, Türkçe],
  "summary": "Genel değerlendirme — 3-4 cümle Türkçe"
}}"""


def _analyze_macro(symbol: str, asset_class: str, now: datetime) -> dict:
    ov = _overview(symbol, asset_class)
    if ov.get("current_price") is None:
        raise ValueError(f"{symbol} için fiyat verisi alınamadı")
    prompt = _build_macro_prompt(symbol, asset_class, ov)
    try:
        raw = llm_service.complete(
            [
                {"role": "system", "content": "Profesyonel piyasa analisti. Yalnızca geçerli JSON dön, hiç açıklama yapma."},
                {"role": "user", "content": prompt},
            ],
            temperature=0.5,
            max_tokens=900,
            json_mode=True,
            model=llm_service.MODEL_LITE,
        )
        parsed = json.loads(raw)
    except Exception as exc:
        logger.warning(f"Macro LLM hata ({symbol}): {exc}")
        parsed = {
            "recommendation": "TUT",
            "overall_score": 50,
            "primary_score": 50,
            "momentum_score": 50,
            "stability_score": 50,
            "key_strengths": ["AI yanıtı alınamadı"],
            "key_weaknesses": ["Lütfen tekrar dene"],
            "summary": "Analiz üretilemedi.",
        }

    labels = _SCORE_LABELS[asset_class]
    scores = [
        {"label": labels[0], "score": parsed.get("primary_score", 50)},
        {"label": labels[1], "score": parsed.get("momentum_score", 50)},
        {"label": labels[2], "score": parsed.get("stability_score", 50)},
    ]
    result = {
        "symbol": symbol,
        "asset_class": asset_class,
        "overview": ov,
        "analysis": {
            "recommendation": parsed.get("recommendation", "TUT"),
            "overall_score": parsed.get("overall_score", 50),
            "summary": parsed.get("summary", ""),
            "key_strengths": parsed.get("key_strengths", []),
            "key_weaknesses": parsed.get("key_weaknesses", []),
            "scores": scores,
        },
        "generated_at": now.isoformat(),
    }
    result = _json_safe(result)
    _cache[symbol] = (result, now)
    return result


def analyze(symbol: str, force_refresh: bool = False) -> dict:
    symbol = symbol.upper()
    now = datetime.now()
    if not force_refresh and symbol in _cache:
        data, ts = _cache[symbol]
        # Sınırlı (data_limited) sonucu UZUN cache'leme → kaynak (yfinance/Finnhub)
        # açılınca otomatik TAM veriye dönsün. Tam sonuç 12h, sınırlı 15dk.
        limited = (isinstance(data.get("fundamentals"), dict)
                   and data["fundamentals"].get("data_limited"))
        ttl = timedelta(minutes=15) if limited else timedelta(hours=_CACHE_TTL_HOURS)
        if now - ts < ttl:
            return data

    if not llm_service.available:
        raise RuntimeError("AI sağlayıcı (Gemini/Groq) ayarlı değil")

    asset_class = _classify(symbol)
    if asset_class != "stock":
        return _analyze_macro(symbol, asset_class, now)

    fundamentals = _compute_fundamentals(symbol)
    prompt = _build_prompt(symbol, fundamentals)

    try:
        raw = llm_service.complete(
            [
                {"role": "system", "content": "Profesyonel temel analist. Yalnızca geçerli JSON dön, hiç açıklama yapma."},
                {"role": "user", "content": prompt},
            ],
            temperature=0.4,
            max_tokens=900,
            json_mode=True,
            model=llm_service.MODEL_LITE,
        )
        parsed = json.loads(raw)
    except Exception as exc:
        logger.warning(f"Fundamental LLM hata ({symbol}): {exc}")
        parsed = {
            "valuation": "Adil",
            "valuation_score": 50,
            "growth_quality": "Orta",
            "growth_score": 50,
            "financial_health": "Orta",
            "health_score": 50,
            "overall_score": 50,
            "recommendation": "TUT",
            "fair_value_estimate": fundamentals.get("current_price"),
            "key_strengths": ["AI yanıtı alınamadı"],
            "key_weaknesses": ["Lütfen tekrar dene"],
            "competitive_position": "Veri yetersiz.",
            "summary": "Temel analiz üretilemedi.",
        }

    result = {
        "symbol": symbol,
        "asset_class": "stock",
        "fundamentals": fundamentals,
        "analysis": parsed,
        "generated_at": now.isoformat(),
    }
    result = _json_safe(result)
    _cache[symbol] = (result, now)
    return result


# ── Bilanço / gelir tablosu takibi (geçmiş + ileri tahmin) ──────────────
_fin_cache: dict[str, tuple[dict, datetime]] = {}


def _row(df, *names):
    """DataFrame'den ilk eşleşen satırı (en yeni→eski) liste döndür."""
    if df is None or df.empty:
        return None
    for n in names:
        if n in df.index:
            return [None if _is_nan(v) else float(v) for v in df.loc[n].values]
    return None


def _is_nan(v):
    try:
        return v != v
    except Exception:
        return v is None


def _cagr(series):
    """En eski→en yeni büyüme CAGR'ı (series: yeni→eski sıralı)."""
    vals = [v for v in reversed(series) if v not in (None, 0)]
    if len(vals) < 2 or vals[0] <= 0:
        return None
    n = len(vals) - 1
    try:
        return (vals[-1] / vals[0]) ** (1 / n) - 1
    except Exception:
        return None


def _quarter_label(col) -> str:
    """'2026-03-31' → '2026 Ç1' (Mar=Ç1, Haz=Ç2, Eyl=Ç3, Ara=Ç4)."""
    s = str(col)
    try:
        y, m = int(s[:4]), int(s[5:7])
        return f"{y} Ç{(m - 1) // 3 + 1}"
    except Exception:
        return s[:7]


def _quarterly(t, n: int = 6) -> list:
    """Son n çeyrek gelir/net kâr/marj (yeni→eski)."""
    try:
        q = t.quarterly_income_stmt
    except Exception:
        q = None
    if q is None or q.empty:
        return []
    rev = _row(q, "Total Revenue", "Operating Revenue")
    net = _row(q, "Net Income", "Net Income Common Stockholders")
    if not rev or not net:
        return []
    cols = list(q.columns)
    out = []
    for i, col in enumerate(cols[:n]):
        r = rev[i] if i < len(rev) else None
        ni = net[i] if i < len(net) else None
        out.append({
            "period": _quarter_label(col),
            "revenue": round(r, 0) if r is not None else None,
            "net_income": round(ni, 0) if ni is not None else None,
            "net_margin_pct": round(ni / r * 100, 2)
            if r and ni is not None and r != 0 else None,
        })
    return out


_EST_LABELS = {"0q": "Bu çeyrek (tah.)", "+1q": "Gelecek çeyrek (tah.)",
               "0y": "Bu yıl (tah.)", "+1y": "Gelecek yıl (tah.)"}


def _est_rows(df) -> list:
    """earnings/revenue_estimate DataFrame → temiz satır listesi."""
    if df is None or getattr(df, "empty", True):
        return []
    out = []
    for key in ("0q", "+1q", "0y", "+1y"):
        if key not in df.index:
            continue
        row = df.loc[key]
        avg = row.get("avg")
        if avg is None or _is_nan(avg):
            continue
        g = row.get("growth")
        out.append({
            "period": _EST_LABELS.get(key, key),
            "avg": round(float(avg), 2),
            "low": None if _is_nan(row.get("low")) else round(float(row["low"]), 2),
            "high": None if _is_nan(row.get("high")) else round(float(row["high"]), 2),
            "analysts": None if _is_nan(row.get("numberOfAnalysts"))
            else int(row["numberOfAnalysts"]),
            "growth_pct": None if (g is None or _is_nan(g))
            else round(float(g) * 100, 1),
        })
    return out


def _analyst_block(t) -> dict | None:
    """Analist fiyat hedefi aralığı + tavsiye dağılımı + EPS/gelir tahmini."""
    block = {}
    try:
        pt = t.analyst_price_targets or {}
        if pt.get("mean"):
            block["price_target"] = {
                k: (round(float(pt[k]), 2) if pt.get(k) is not None else None)
                for k in ("current", "low", "mean", "high")
            }
    except Exception:
        pass
    try:
        rec = t.recommendations
        if rec is not None and not rec.empty:
            r = rec.iloc[0]
            dist = {k: int(r.get(k, 0) or 0)
                    for k in ("strongBuy", "buy", "hold", "sell", "strongSell")}
            if sum(dist.values()) > 0:
                block["recommendation"] = dist
    except Exception:
        pass
    try:
        block["eps_estimate"] = _est_rows(t.earnings_estimate)
    except Exception:
        block["eps_estimate"] = []
    try:
        block["revenue_estimate"] = _est_rows(t.revenue_estimate)
    except Exception:
        block["revenue_estimate"] = []
    # Geçmiş tahmin isabeti (analist EPS tahmini vs gerçekleşen + sürpriz).
    # Yahoo'da çoğunlukla ABD hisseleri için dolu, BIST'te boş gelir.
    try:
        eh = t.earnings_history
        rows = []
        if eh is not None and not eh.empty and "epsActual" in eh.columns:
            for idx in list(eh.index)[::-1][:8]:  # yeni→eski, son 8 çeyrek
                r = eh.loc[idx]
                act = r.get("epsActual")
                est = r.get("epsEstimate")
                if _is_nan(act) or _is_nan(est):
                    continue
                act, est = float(act), float(est)
                sp = r.get("surprisePercent")
                rows.append({
                    "quarter": _quarter_label(idx),
                    "eps_actual": round(act, 2),
                    "eps_estimate": round(est, 2),
                    "surprise_pct": None if _is_nan(sp)
                    else round(float(sp) * 100, 1),
                    "beat": act >= est,
                })
        if rows:
            beats = sum(1 for x in rows if x["beat"])
            sps = [x["surprise_pct"] for x in rows
                   if x["surprise_pct"] is not None]
            block["earnings_history"] = {
                "rows": rows,
                "beats": beats,
                "total": len(rows),
                "avg_surprise_pct": round(sum(sps) / len(sps), 1)
                if sps else None,
            }
    except Exception:
        pass
    # Analist revizyon yönü (tahminler yukarı mı aşağı mı çekiliyor).
    try:
        rv = t.eps_revisions
        if rv is not None and not rv.empty:
            revs = []
            for key, lbl in (("0y", "Bu yıl"), ("+1y", "Gelecek yıl")):
                if key not in rv.index:
                    continue
                row = rv.loc[key]
                up = row.get("upLast30days")
                dn = row.get("downLast30days")
                if _is_nan(up) and _is_nan(dn):
                    continue
                revs.append({
                    "period": lbl,
                    "up": 0 if _is_nan(up) else int(up),
                    "down": 0 if _is_nan(dn) else int(dn),
                })
            if revs:
                block["eps_revisions"] = revs
    except Exception:
        pass
    return block or None


def _financials_fallback(sym: str, now: datetime) -> dict:
    """yfinance income_stmt (quoteSummary) Render'da bloklu/boş → Finnhub'tan
    gelir tablosunu dene (ABD hisseleri). Yoksa has_data:False."""
    fin = finnhub_service.get_financials(sym)
    if fin and fin.get("has_data"):
        _fin_cache[sym] = (fin, now)
        return fin
    return {"symbol": sym, "has_data": False}


def get_financials(symbol: str) -> dict:
    """Geçmiş yıllık + çeyreklik gelir tablosu + trend tahmini + analist.

    Yıllık/çeyreklik gerçek gelir tablosu (yfinance). İleri tahmin:
    gelir/net kâr CAGR'ı bir sonraki yıla uygulanır (deterministik model).
    Ayrıca analist fiyat hedefi aralığı, tavsiye dağılımı ve EPS/gelir
    tahminleri (yfinance analyst verisi — varsa).
    """
    sym = symbol.upper()
    now = datetime.now()
    if sym in _fin_cache:
        data, ts = _fin_cache[sym]
        if now - ts < timedelta(hours=_CACHE_TTL_HOURS):
            return data
    try:
        t = yf.Ticker(sym, session=get_session())
        inc = t.income_stmt
        if inc is None or inc.empty:
            return _financials_fallback(sym, now)

        years = [str(c)[:4] for c in inc.columns]  # yeni→eski
        revenue = _row(inc, "Total Revenue", "Operating Revenue")
        gross = _row(inc, "Gross Profit")
        op = _row(inc, "Operating Income", "EBIT")
        net = _row(inc, "Net Income",
                   "Net Income Common Stockholders")
        if not revenue or not net:
            return _financials_fallback(sym, now)

        periods = []
        for i, yr in enumerate(years[:4]):
            rev = revenue[i] if i < len(revenue) else None
            ni = net[i] if i < len(net) else None
            periods.append({
                "period": yr,
                "revenue": rev,
                "gross_profit": gross[i] if gross and i < len(gross) else None,
                "operating_income": op[i] if op and i < len(op) else None,
                "net_income": ni,
                "net_margin_pct": round(ni / rev * 100, 2)
                if rev and ni is not None and rev != 0 else None,
            })

        rev_cagr = _cagr(revenue[:4])
        ni_cagr = _cagr(net[:4])
        last_rev = revenue[0]
        last_ni = net[0]
        forecast = None
        if last_rev and rev_cagr is not None:
            f_rev = last_rev * (1 + rev_cagr)
            f_ni = (last_ni * (1 + ni_cagr)
                    if last_ni is not None and ni_cagr is not None else None)
            forecast = {
                "period": f"{int(years[0]) + 1} (tahmin)",
                "revenue": round(f_rev, 0),
                "net_income": round(f_ni, 0) if f_ni is not None else None,
                "net_margin_pct": round(f_ni / f_rev * 100, 2)
                if f_ni is not None and f_rev else None,
                "revenue_growth_pct": round(rev_cagr * 100, 2),
                "net_income_growth_pct": round(ni_cagr * 100, 2)
                if ni_cagr is not None else None,
            }

        result = {
            "symbol": sym,
            "has_data": True,
            "currency": _safe(t.info.get("financialCurrency")) or "—",
            "history": periods,          # yıllık, yeni→eski
            "quarterly": _quarterly(t),  # son ~6 çeyrek, yeni→eski
            "forecast": forecast,        # trend-tabanlı model tahmini
            "analyst": _analyst_block(t),  # fiyat hedefi + tavsiye + tahmin
            "note": "Geçmiş veriler yfinance gelir tablosundan. İleri "
                    "tahmin son yılların CAGR'ına dayalı deterministik "
                    "projeksiyondur; analist tahmini değildir.",
            "generated_at": now.isoformat(),
        }
        _fin_cache[sym] = (result, now)
        return result
    except Exception as exc:
        logger.warning(f"Financials error ({sym}): {exc}")
        return _financials_fallback(sym, now)
