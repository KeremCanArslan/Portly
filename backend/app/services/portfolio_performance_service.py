"""Portföy dönem performansı — Bugün / Hafta / Ay.

Ana ekran yalnız "Toplam" (alış maliyetine göre) ve "Bugün" gösterebiliyordu.
"Toplam" yıllar önceki maliyete bakar, "Bugün" tek güne — aradaki en faydalı
pencere (hafta/ay) yoktu.

Maliyet: EK YAHOO İSTEĞİ YOK. Günlük kapanış serisi zaten
`market_data_service.get_daily_closes` cache'inde (tek uzun pencere) duruyor;
buradaki hesap o seriden okur.

Yöntem: dönem başındaki ₺ değer ile ŞU ANKİ ₺ değeri kıyaslar.
  • USD pozisyon dönem başında o günkü kurla, bugün güncel kurla ₺'ye çevrilir
    → getiri kur hareketini de içerir (₺ yatırımcısının gerçek getirisi).
  • Dönem boyunca pozisyonların sabit kaldığı varsayılır (benchmark ile aynı
    varsayım). Dönem içinde alım/satım yapıldıysa sonuç yaklaşıktır.
  • Dönem verisi olmayan pozisyon (yeni sembol, çekilemeyen seri) DIŞLANIR ve
    `symbols_excluded` ile dürüstçe raporlanır — sessizce sıfır sayılmaz.
"""

from datetime import datetime, timedelta

from loguru import logger
from sqlalchemy.orm import Session

from app.services import fx_service, market_data_service, portfolio_service

# Ana ekranın sunduğu pencereler (gün). "Bugün" istemcide zaten canlı günlük
# değişimden hesaplanıyor; burası hafta/ay için.
_WINDOWS = {"1w": 7, "1m": 30}

# En uzun pencereyi kapsayacak kadar kapanış iste (hafta sonu/tatil payı).
_LOOKBACK_DAYS = 45


def _close_on_or_before(series: dict[str, float], target: str) -> float | None:
    """Hedef tarihte ya da ONDAN ÖNCEKİ en yakın işlem gününün kapanışı.
    Borsalar hafta sonu/tatilde kapalı → tam tarih eşleşmesi aramak çoğu
    pozisyonu boşuna dışlardı."""
    best_day = None
    for day in series:
        if day <= target and (best_day is None or day > best_day):
            best_day = day
    return series.get(best_day) if best_day else None


def compute_performance(db: Session, user_id: int) -> dict:
    positions = portfolio_service.get_user_portfolio(db, user_id)
    if not positions:
        return {"periods": {}, "has_holdings": False}

    symbols = [p["symbol"] for p in positions]
    closes = market_data_service.get_daily_closes(
        symbols + ["USDTRY=X"], _LOOKBACK_DAYS)
    fx_series = closes.get("USDTRY=X") or {}
    fx_now = fx_service.usdtry_rate()

    today = datetime.now().date()
    periods: dict[str, dict] = {}

    for name, days in _WINDOWS.items():
        target = (today - timedelta(days=days)).isoformat()
        start_total = 0.0
        end_total = 0.0
        excluded: list[str] = []

        # Dönem başı kuru: o günkü USDTRY; yoksa güncel kur (tek-kur tutarlılığı
        # bozuk kur karışımından iyidir).
        fx_start = _close_on_or_before(fx_series, target) or fx_now

        for p in positions:
            sym = p["symbol"]
            series = closes.get(sym) or {}
            start_price = _close_on_or_before(series, target)
            if not start_price or start_price <= 0:
                excluded.append(sym)
                continue
            qty = p["quantity"]
            is_try = p.get("currency") == "TRY"
            start_try = qty * start_price * (1.0 if is_try else fx_start)
            # Bitiş = kullanıcının ekranda gördüğü canlı ₺ değer.
            end_try = p.get("total_value_try", p["total_value"])
            if start_try <= 0:
                excluded.append(sym)
                continue
            start_total += start_try
            end_total += end_try

        if start_total <= 0:
            periods[name] = {
                "pnl_try": None, "pnl_percent": None,
                "symbols_included": 0, "symbols_excluded": sorted(excluded),
            }
            continue

        pnl = end_total - start_total
        periods[name] = {
            "pnl_try": round(pnl, 2),
            "pnl_percent": round(pnl / start_total * 100, 2),
            "symbols_included": len(positions) - len(excluded),
            "symbols_excluded": sorted(excluded),
        }

    if any(v.get("pnl_percent") is None for v in periods.values()):
        logger.info(f"Dönem performansı kısmi (user={user_id}): "
                    f"{ {k: v['symbols_included'] for k, v in periods.items()} }")

    return {"periods": periods, "has_holdings": True}
