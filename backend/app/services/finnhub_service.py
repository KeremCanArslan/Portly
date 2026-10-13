"""Finnhub temel veri kaynağı (hisse oran + bilanço + analist).

NEDEN: yfinance `.info`/`income_stmt` (Yahoo **quoteSummary**) Render datacenter
IP'sinde BLOKLU → temel analiz oranları ve bilanço boş geliyordu. Finnhub
API-key'li (IP-bağımsız) bir REST API → Render'dan güvenilir çalışır. Ücretsiz
tier ABD hisselerini kapsar (BIST/uluslararası premium); kapsanmayan sembolde
boş döner, çağıran yfinance/degrade moda düşer.

Ölçek notu: Finnhub `/stock/metric` yüzde alanlarını (roeTTM, marj, büyüme)
ZATEN yüzde verir (örn. 30.5 = %30.5) → projedeki `_pct` (kesir×100) çıktısıyla
birebir uyumlu, ek çarpım YOK. Borç/özkaynak oran olarak gelir (0.5) → yfinance
`debtToEquity` yüzde-ölçeğiyle (50) hizalamak için ×100. marketCap milyon
cinsindendir → ×1e6.
"""

import requests
from loguru import logger

from app.core.config import settings

_BASE = "https://finnhub.io/api/v1"
_TIMEOUT = 8

available = bool(settings.FINNHUB_API_KEY)


def _get(path: str, params: dict) -> dict | list | None:
    if not available:
        return None
    try:
        params = {**params, "token": settings.FINNHUB_API_KEY}
        r = requests.get(f"{_BASE}{path}", params=params, timeout=_TIMEOUT)
        if r.status_code != 200:
            logger.warning(f"Finnhub {path} HTTP {r.status_code}")
            return None
        return r.json()
    except Exception as exc:
        logger.warning(f"Finnhub {path} hata: {exc}")
        return None


def _num(val):
    """Sayıya çevir; None/parse hatası/NaN → None."""
    if val is None:
        return None
    try:
        f = float(val)
    except (TypeError, ValueError):
        return None
    return None if f != f else f  # NaN ele


def _round(val, n=2):
    v = _num(val)
    return round(v, n) if v is not None else None


def get_profile(symbol: str) -> dict | None:
    """/stock/profile2 ham profili (hafif; sektör dağılımı için tek çağrı yeter).

    Çağıran, profilin DÖNÜP dönmediğini bilmek zorunda: profil geldi ama
    `finnhubIndustry` boşsa sembol bir ETF/fondur (sepetin sanayisi olmaz);
    profil hiç gelmediyse sembolü Finnhub tanımıyordur. İkisi "Diğer" ile
    aynı kefeye konunca ETF'ler sektör dağılımında kayboluyordu.
    Anahtar yok / kapsam dışı / hata → None.
    """
    profile = _get("/stock/profile2", {"symbol": symbol})
    if isinstance(profile, dict) and profile:
        return profile
    return None


def get_sector(symbol: str) -> str | None:
    """Sembolün Finnhub sanayi adı (get_profile üzerinden). Yoksa None
    → çağıran BIST haritası / yfinance .info fallback'ine düşer."""
    profile = get_profile(symbol)
    return (profile or {}).get("finnhubIndustry") or None


def get_quote(symbol: str) -> dict | None:
    """/quote → anlık fiyat + günlük değişim. Yahoo YEDEĞİ.

    Yahoo Render IP'sini 429'ladığında portföydeki ABD hisseleri fiyatsız
    kalıp `avg_cost`'a düşüyordu → her pozisyon "%0,00 kâr/zarar" görünüyordu
    (fiyat = maliyet). Finnhub API-key'li ve IP-bağımsız olduğu için o anda
    çalışmaya devam eder.

    Ücretsiz tier ABD hisseleri; BIST/emtia/kripto KAPSAM DIŞI (çağıran
    `_is_us_equity` ile eler). Kapsanmayan sembolde `c` 0 gelir → None.
    Dönüş market_data_service'in quote sözleşmesiyle aynı biçimde.
    """
    q = _get("/quote", {"symbol": symbol})
    if not isinstance(q, dict):
        return None
    price = _num(q.get("c"))
    if not price or price <= 0:
        return None          # kapsam dışı sembolde Finnhub 0 döndürür
    change = _num(q.get("dp"))
    return {
        "symbol": symbol,
        "current_price": round(price, 2),
        "change_percent": round(change, 2) if change is not None else 0.0,
    }


def get_fundamentals(symbol: str) -> dict | None:
    """Hisse oranları + şirket profili + analist konsensüsü. Veri yoksa None
    (çağıran degrade moda düşer). `_compute_fundamentals` ile AYNI anahtarlar."""
    metric_resp = _get("/stock/metric", {"symbol": symbol, "metric": "all"})
    if not isinstance(metric_resp, dict):
        return None
    m = metric_resp.get("metric") or {}
    profile = _get("/stock/profile2", {"symbol": symbol})
    profile = profile if isinstance(profile, dict) else {}
    quote = _get("/quote", {"symbol": symbol})
    quote = quote if isinstance(quote, dict) else {}

    price = _num(quote.get("c"))
    # Hiç temel sinyal yoksa (ücretsiz tier sembolü kapsamıyor) → None döndür.
    has_signal = any(_num(m.get(k)) is not None for k in (
        "peTTM", "peBasicExclExtraTTM", "roeTTM", "netProfitMarginTTM",
        "pbAnnual", "52WeekHigh"))
    if not has_signal and price is None:
        return None

    de = _num(m.get("totalDebt/totalEquityQuarterly")
              or m.get("totalDebt/totalEquityAnnual")
              or m.get("longTermDebt/equityQuarterly")
              or m.get("longTermDebt/equityAnnual"))
    mcap = _num(profile.get("marketCapitalization"))
    industry = profile.get("finnhubIndustry") or None

    return {
        "data_limited": False,
        "data_source": "finnhub",
        "company_name": profile.get("name") or symbol,
        "sector": industry,
        "industry": industry,
        "country": profile.get("country"),
        "currency": profile.get("currency") or "USD",
        "market_cap": round(mcap * 1_000_000) if mcap is not None else None,
        "current_price": _round(price, 4) if price is not None else None,
        # Değerleme
        "pe_trailing": _round(m.get("peTTM") or m.get("peBasicExclExtraTTM")),
        "pe_forward": None,  # ücretsiz tier forward P/E vermiyor → dürüstçe boş
        "pb": _round(m.get("pbQuarterly") or m.get("pbAnnual")),
        "peg": _round(m.get("pegTTM") or m.get("pegRatio")),
        "ps": _round(m.get("psTTM") or m.get("psAnnual")),
        # Kârlılık (Finnhub ZATEN yüzde → ek çarpım yok)
        "profit_margin_pct": _round(m.get("netProfitMarginTTM")),
        "operating_margin_pct": _round(m.get("operatingMarginTTM")),
        "roe_pct": _round(m.get("roeTTM")),
        "roa_pct": _round(m.get("roaTTM")),
        # Büyüme (yüzde)
        "revenue_growth_pct": _round(m.get("revenueGrowthTTMYoy")),
        "earnings_growth_pct": _round(m.get("epsGrowthTTMYoy")),
        # Mali sağlık (borç/özkaynak oranını yfinance yüzde-ölçeğine ×100)
        "debt_to_equity": round(de * 100, 2) if de is not None else None,
        "current_ratio": _round(m.get("currentRatioQuarterly")
                                or m.get("currentRatioAnnual")),
        "quick_ratio": _round(m.get("quickRatioQuarterly")
                              or m.get("quickRatioAnnual")),
        # Temettü (Finnhub yüzde)
        "dividend_yield_pct": _round(m.get("currentDividendYieldTTM")
                                     or m.get("dividendYieldIndicatedAnnual")),
        "payout_ratio_pct": _round(m.get("payoutRatioTTM")
                                   or m.get("payoutRatioAnnual")),
        # Fiyat istatistiği
        "fifty_two_week_high": _round(m.get("52WeekHigh")),
        "fifty_two_week_low": _round(m.get("52WeekLow")),
        "beta": _round(m.get("beta")),
        # Analist
        **_analyst_consensus(symbol),
    }


def _analyst_consensus(symbol: str) -> dict:
    """En güncel tavsiye dağılımından AL/TUT/SAT + analist sayısı + hedef fiyat."""
    out = {"analyst_target": None, "analyst_recommendation": None,
           "analyst_count": None}
    rec = _get("/stock/recommendation", {"symbol": symbol})
    if isinstance(rec, list) and rec:
        r = rec[0]  # en yeni dönem
        buy = (_num(r.get("strongBuy")) or 0) + (_num(r.get("buy")) or 0)
        hold = _num(r.get("hold")) or 0
        sell = (_num(r.get("sell")) or 0) + (_num(r.get("strongSell")) or 0)
        total = buy + hold + sell
        if total > 0:
            out["analyst_count"] = int(total)
            out["analyst_recommendation"] = (
                "buy" if buy >= hold and buy >= sell
                else "sell" if sell >= hold and sell >= buy
                else "hold")
    pt = _get("/stock/price-target", {"symbol": symbol})
    if isinstance(pt, dict):
        out["analyst_target"] = _round(pt.get("targetMean"))
    return out


def get_financials(symbol: str) -> dict | None:
    """Yıllık + çeyreklik gelir tablosu (gelir / net kâr / marj) — `get_financials`
    çıktısının çekirdeğiyle uyumlu. Veri yoksa None."""
    annual = _income_rows(symbol, "annual", 4)
    if not annual:
        return None
    quarterly = _income_rows(symbol, "quarterly", 6)
    return {
        "symbol": symbol.upper(),
        "has_data": True,
        "data_source": "finnhub",
        "currency": "USD",
        "history": annual,        # yeni→eski
        "quarterly": quarterly,
        "forecast": _forecast_from(annual),
        "analyst": None,          # ileride Finnhub price-target ile zenginleştir
        "note": "Veriler Finnhub gelir tablosundan. İleri tahmin son yılların "
                "büyüme oranına dayalı deterministik projeksiyondur.",
    }


def _income_rows(symbol: str, freq: str, limit: int) -> list:
    """Finnhub income statement → [{period, revenue, net_income, net_margin_pct}]."""
    resp = _get("/stock/financials", {"symbol": symbol, "statement": "ic",
                                      "freq": freq})
    if not isinstance(resp, dict):
        return []
    rows = resp.get("financials") or resp.get("data") or []
    out = []
    for item in rows[:limit]:
        rep = item.get("report", item) if isinstance(item, dict) else {}
        period = (item.get("period") or item.get("endDate")
                  or str(item.get("year", "")))
        rev = _num(_first(rep, "revenue", "totalRevenue", "Revenues",
                          "RevenueFromContractWithCustomerExcludingAssessedTax"))
        ni = _num(_first(rep, "netIncome", "netIncomeLoss", "NetIncomeLoss"))
        if rev is None and ni is None:
            continue
        out.append({
            "period": str(period)[:10],
            "revenue": round(rev) if rev is not None else None,
            "net_income": round(ni) if ni is not None else None,
            "net_margin_pct": round(ni / rev * 100, 2)
            if rev and ni is not None and rev != 0 else None,
        })
    return out


def _first(d: dict, *keys):
    for k in keys:
        if k in d and d[k] is not None:
            return d[k]
    return None


def _forecast_from(annual: list) -> dict | None:
    """Yıllık gelir/net kâr CAGR'ını bir sonraki yıla uygula (deterministik)."""
    revs = [r["revenue"] for r in reversed(annual) if r.get("revenue")]
    nets = [r["net_income"] for r in reversed(annual)
            if r.get("net_income") is not None]
    if len(revs) < 2 or revs[0] <= 0:
        return None
    n = len(revs) - 1
    try:
        rev_cagr = (revs[-1] / revs[0]) ** (1 / n) - 1
    except Exception:
        return None
    last_rev = revs[-1]
    f_rev = last_rev * (1 + rev_cagr)
    try:
        last_year = int(str(annual[0]["period"])[:4])
        label = f"{last_year + 1} (tahmin)"
    except Exception:
        label = "Gelecek yıl (tahmin)"
    return {
        "period": label,
        "revenue": round(f_rev),
        "net_income": None,
        "net_margin_pct": None,
        "revenue_growth_pct": round(rev_cagr * 100, 2),
        "net_income_growth_pct": None,
    }
