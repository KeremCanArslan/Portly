"""Mum tahmin oyunu servisi.

Akış (sade, "grafiği oku" oyunu):
  1. Havuzdan rastgele bir enstrüman seç.
  2. Geçmişten rastgele bir pencere al: ilk `visible_bars` mum gösterilir,
     sonraki `hidden_bars` mum GİZLENİR.
  3. Kullanıcı tek bir şey tahmin eder: gizli pencerenin SONUNDA fiyat
     görünür kısmın son kapanışına göre YUKARI mı, AŞAĞI mı?  (neticesel yön)

Eski sürüm vade (kısa/orta/uzun) + hedef/stop/yatay (3 şık) soruyordu;
"yatay" bandı kalibre etmek kırılgandı ve oyunu karmaşıklaştırıyordu. Artık
ikili (yukarı/aşağı) — okunması ve oynanması kolay, gerçek bir tahmin.
"""

import random
from loguru import logger
import yfinance as yf

_POOL = [
    "AAPL", "MSFT", "TSLA", "NVDA", "META", "GOOGL", "AMZN",
    "BTC-USD", "ETH-USD",
    "THYAO.IS", "ASELS.IS", "GARAN.IS", "TUPRS.IS",
    "GC=F", "CL=F",
]

# Görünür / gizli mum sayısı. Gizli ~1 ay → "neticesel" yön anlamlı olur,
# tek-bar gürültüsüne takılmaz.
_VISIBLE_BARS = 70
_HIDDEN_BARS = 20


def _row(idx, row) -> dict:
    return {
        "date": idx.strftime("%Y-%m-%d"),
        "open": round(float(row["Open"]), 2),
        "high": round(float(row["High"]), 2),
        "low": round(float(row["Low"]), 2),
        "close": round(float(row["Close"]), 2),
    }


def generate_question(horizon: str | None = None,
                      symbol: str | None = None) -> dict:
    """Rastgele bir mum-tahmin sorusu üretir (ikili: yukarı/aşağı).

    `horizon` parametresi geriye-uyumluluk için kabul edilir ama artık
    KULLANILMAZ (sabit ~1 aylık ileri pencere)."""
    need = _VISIBLE_BARS + _HIDDEN_BARS
    last_err = None
    for _ in range(6):
        sym = symbol or random.choice(_POOL)
        try:
            # 5y → bol rastgele pencere çeşitliliği (aynı grafik tekrarı azalır).
            hist = yf.Ticker(sym).history(period="5y", interval="1d")
            total = len(hist)
            if total < need + 5:
                continue
            start_idx = random.randint(0, total - need)
            window = hist.iloc[start_idx:start_idx + need]
            visible = window.iloc[:_VISIBLE_BARS]
            hidden = window.iloc[_VISIBLE_BARS:]

            visible_rows = [_row(i, r) for i, r in visible.iterrows()]
            hidden_rows = [_row(i, r) for i, r in hidden.iterrows()]
            if not visible_rows or not hidden_rows:
                continue

            reference = visible_rows[-1]["close"]
            end_price = hidden_rows[-1]["close"]
            if reference <= 0:
                continue
            pct = (end_price - reference) / reference * 100
            direction = "UP" if end_price >= reference else "DOWN"

            return {
                "symbol": sym,
                "visible": visible_rows,
                "hidden": hidden_rows,
                "reference": round(reference, 2),
                "hidden_bars": _HIDDEN_BARS,
                "answer": {
                    "direction": direction,          # UP / DOWN (ikili)
                    "pct_change": round(pct, 2),
                    "end_price": round(end_price, 2),
                    "max_high": round(max(b["high"] for b in hidden_rows), 2),
                    "min_low": round(min(b["low"] for b in hidden_rows), 2),
                },
            }
        except Exception as exc:
            last_err = exc
            logger.warning(f"Quiz veri hata ({sym}): {exc}")
            if symbol:
                break
    raise RuntimeError(f"Quiz sorusu üretilemedi: {last_err}")
