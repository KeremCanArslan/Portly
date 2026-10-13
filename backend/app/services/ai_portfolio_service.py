"""AI portföy oluşturma + backtest servisi.

Kullanıcının risk profili + vadesi + bütçesine göre LLM bir tahsisat (allocation)
önerir. Aynı tahsisat yfinance historical verisiyle backtest edilip vadenin
sonundaki gerçekleşen getiri hesaplanır.
"""

import json
import random
from datetime import datetime, timedelta
from loguru import logger
from app.services import llm_service
import yfinance as yf

# Risk profili → uygun sembol havuzu (LLM'e seçim için ipucu). Havuzlar GENİŞ ve
# çeşitli (her profil ~45 sembol: ABD + BIST + emtia/döviz +/- kripto) + her
# çağrıda karıştırılır (build_portfolio) → LLM hep aynı birkaç mega-cap'i seçip
# sığ/tekrarlı portföy vermesin; çağrılar arası çeşitlilik ve derinlik artar.
# (Tüm semboller yfinance'te veri döndürüyor — doğrulandı; backtest atlamasın.)
_RISK_POOLS: dict[str, list[str]] = {
    "Muhafazakar": [
        # Altın/gümüş + döviz (sermaye koruma)
        "GC=F", "SI=F", "USDTRY=X", "EURTRY=X",
        # ABD savunmacı mega-cap / istikrarlı temettü
        "AAPL", "MSFT", "JNJ", "PG", "KO", "PEP", "WMT", "MCD", "COST", "HD",
        "V", "MA", "CVX", "XOM", "ABBV", "MRK", "PFE", "UNH", "T", "VZ",
        "CSCO", "KMB", "MDLZ", "CL", "SO", "DUK", "NEE", "IBM",
        # Büyük, istikrarlı TR (banka/telekom/temel tüketim/enerji/holding)
        "AKBNK.IS", "GARAN.IS", "ISCTR.IS", "YKBNK.IS", "BIMAS.IS", "MGROS.IS",
        "TUPRS.IS", "TCELL.IS", "TTKOM.IS", "SAHOL.IS", "KCHOL.IS", "ENKAI.IS",
    ],
    "Dengeli": [
        # ABD büyüme + istikrar karması
        "AAPL", "MSFT", "GOOGL", "AMZN", "NVDA", "META", "JPM", "V", "MA", "DIS",
        "KO", "COST", "HD", "NKE", "SBUX", "AMD", "CRM", "ADBE", "NFLX", "UNH",
        "AVGO", "QCOM", "BAC", "PEP", "TXN", "INTC",
        # TR büyük/orta ölçek
        "THYAO.IS", "ASELS.IS", "KCHOL.IS", "BIMAS.IS", "EREGL.IS", "SISE.IS",
        "FROTO.IS", "TUPRS.IS", "SAHOL.IS", "TOASO.IS", "AKBNK.IS", "GARAN.IS",
        "TCELL.IS", "PGSUS.IS", "ARCLK.IS", "PETKM.IS", "TAVHL.IS",
        # Emtia + kripto (sınırlı)
        "GC=F", "SI=F", "BTC-USD", "ETH-USD",
    ],
    "Agresif": [
        # Yüksek-beta ABD teknoloji/büyüme
        "TSLA", "NVDA", "META", "AMD", "GOOGL", "AMZN", "NFLX", "PLTR", "COIN",
        "MSTR", "AVGO", "CRM", "SHOP", "UBER", "ABNB", "SNOW", "CRWD", "NET",
        "RBLX", "MRNA", "SMCI", "ARM", "MU", "MARA", "RIOT",
        # Kripto
        "BTC-USD", "ETH-USD", "SOL-USD", "AVAX-USD", "XRP-USD", "ADA-USD",
        "DOGE-USD", "LINK-USD", "DOT-USD",
        # TR büyüme/oynak
        "PGSUS.IS", "ASELS.IS", "SASA.IS", "THYAO.IS", "HEKTS.IS", "KONTR.IS",
        "SMRTG.IS", "ASTOR.IS", "ODAS.IS", "EKGYO.IS",
    ],
}

# Vade → backtest süresi
_HORIZON_DAYS = {
    "short": 30,    # 1 ay
    "medium": 180,  # 6 ay
    "long": 365,    # 1 yıl
}


def _build_prompt(risk_profile: str, horizon: str, amount: float, pool: list[str]) -> str:
    horizon_tr = {
        "short": "kısa vade (1 ay)",
        "medium": "orta vade (6 ay)",
        "long": "uzun vade (1 yıl)",
    }.get(horizon, horizon)
    pool_str = ", ".join(pool)
    return f"""Bir yatırım danışmanı olarak, kullanıcıya portföy öner.

Risk profili: {risk_profile}
Vade: {horizon_tr}
Tutar: {amount:.0f} TL

Bu sembol havuzundan SEÇ (sadece bunlardan, ekleme yapma):
{pool_str}

ÇIKTI: Yalnızca geçerli bir JSON dön, başka metin yok. 5-7 sembol seç ve
FARKLI sektör/varlık sınıflarına (hisse · altın/döviz · kripto) yayarak
ÇEŞİTLENDİR — hep aynı birkaç mega-cap'i seçme. Ağırlıklar toplamı 1.0 olsun
(her biri 0.05 ile 0.40 arası).

{{
  "allocations": [
    {{"symbol": "AAPL", "weight": 0.25, "reason": "neden seçildi (kısa)"}}
  ],
  "expected_return_pct": tahmini yıllık getiri yüzdesi (sayı, ortalama),
  "rationale": "1-2 cümle portföyün genel mantığı (Türkçe)"
}}"""


def _llm_allocation(risk_profile: str, horizon: str, amount: float, pool: list[str]) -> dict:
    if not llm_service.available:
        raise RuntimeError("AI sağlayıcı (Gemini/Groq) ayarlı değil")
    prompt = _build_prompt(risk_profile, horizon, amount, pool)
    raw = llm_service.complete(
        [
            {"role": "system", "content": "Yatırım danışmanısın. Yalnızca geçerli JSON dön, hiç açıklama yapma."},
            {"role": "user", "content": prompt},
        ],
        temperature=0.8,
        max_tokens=600,
        json_mode=True,
        model=llm_service.MODEL_LITE,
    )
    return json.loads(raw)


def _backtest(allocations: list[dict], horizon_days: int) -> dict:
    """Verilen tahsisatı historical data ile backtest eder.

    Mantık: vade gün sayısı kadar gün önce her sembol için kapanış al,
    bugünkü kapanış ile karşılaştır, ağırlıklı getiri hesapla.
    """
    end = datetime.now()
    start = end - timedelta(days=horizon_days + 7)  # biraz buffer

    weighted_returns = []
    per_symbol = []
    total_weight = 0.0

    for alloc in allocations:
        symbol = alloc.get("symbol")
        weight = float(alloc.get("weight", 0))
        if not symbol or weight <= 0:
            continue
        try:
            t = yf.Ticker(symbol)
            hist = t.history(start=start.strftime("%Y-%m-%d"),
                             end=end.strftime("%Y-%m-%d"),
                             interval="1d")
            if hist.empty or len(hist) < 5:
                continue
            start_price = float(hist["Close"].iloc[0])
            end_price = float(hist["Close"].iloc[-1])
            symbol_return = (end_price - start_price) / start_price * 100
            weighted_returns.append(symbol_return * weight)
            per_symbol.append({
                "symbol": symbol,
                "weight": weight,
                "start_price": round(start_price, 2),
                "end_price": round(end_price, 2),
                "return_pct": round(symbol_return, 2),
                "contribution_pct": round(symbol_return * weight, 2),
            })
            total_weight += weight
        except Exception as exc:
            logger.warning(f"Backtest hata ({symbol}): {exc}")
            continue

    if total_weight == 0:
        return {
            "actual_return_pct": 0.0,
            "per_symbol": [],
            "horizon_days": horizon_days,
        }

    # Normalize: bazı semboller atlanırsa toplam ağırlığa böl
    actual = sum(weighted_returns) / total_weight
    return {
        "actual_return_pct": round(actual, 2),
        "per_symbol": per_symbol,
        "horizon_days": horizon_days,
    }


def build_portfolio(risk_profile: str, horizon: str, amount: float) -> dict:
    # Havuzun KOPYASINI karıştır: LLM hep ilk listelenenleri (AAPL/MSFT) seçip
    # her seferinde aynı sığ portföyü vermesin → çağrılar arası çeşitlilik.
    pool = list(_RISK_POOLS.get(risk_profile, _RISK_POOLS["Dengeli"]))
    random.shuffle(pool)
    horizon_days = _HORIZON_DAYS.get(horizon, 180)

    allocation_resp = _llm_allocation(risk_profile, horizon, amount, pool)
    allocations = allocation_resp.get("allocations", [])

    # Backtest
    backtest = _backtest(allocations, horizon_days)

    # Her allocation için lot adedi (yaklaşık) hesapla
    for alloc in allocations:
        alloc_amount = amount * float(alloc.get("weight", 0))
        alloc["amount_try"] = round(alloc_amount, 2)

    return {
        "risk_profile": risk_profile,
        "horizon": horizon,
        "amount": amount,
        "allocations": allocations,
        "expected_return_pct": allocation_resp.get("expected_return_pct"),
        "rationale": allocation_resp.get("rationale", ""),
        "backtest": backtest,
        "generated_at": datetime.now().isoformat(),
    }
