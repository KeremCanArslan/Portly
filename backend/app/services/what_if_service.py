"""'Eğer almış olsaydım' hesaplayıcı.

Geçmiş bir tarihte verilen sembole X TL yatırılsaydı bugün ne olurdu?
yfinance ile geçmiş ve cari fiyatı alıp basit getiri + adet hesaplar.
"""

from datetime import datetime, timedelta
from loguru import logger
import yfinance as yf


def _slice_to_end(hist, end_date_str: str | None):
    """`hist`'i bitiş tarihine (dahil) kadar kırpar. tz-aware/naive farkı
    olmasın diye `index.date` üzerinden karşılaştırır. Geçersiz tarih → kırpmaz."""
    if not end_date_str or hist.empty:
        return hist
    try:
        ed = datetime.strptime(end_date_str, "%Y-%m-%d").date()
    except ValueError:
        return hist
    return hist[hist.index.date <= ed]


def _slice_from_start(hist, start_date_str: str | None):
    """`hist`'i başlangıç tarihinden (dahil) itibaren kırpar."""
    if not start_date_str or hist.empty:
        return hist
    try:
        sd = datetime.strptime(start_date_str, "%Y-%m-%d").date()
    except ValueError:
        return hist
    return hist[hist.index.date >= sd]


def calculate(symbol: str, amount: float, years_back: float,
              start_date_str: str | None = None,
              end_date_str: str | None = None) -> dict:
    """Kullanıcı X TL'yi geçmişte hisseye yatırsaydı bugün (ya da verilen bitiş
    tarihinde) pozisyonun değeri ne olurdu, hesaplar. Net tarih
    (`start_date_str`, YYYY-MM-DD) verilirse onu; yoksa `years_back` yıl
    öncesini başlangıç alır. `end_date_str` verilirse o tarihe kadarki veriyle
    hesaplar (yoksa son işlem günü = bugün)."""
    sym = symbol.upper()
    if start_date_str:
        try:
            start_date = datetime.strptime(start_date_str, "%Y-%m-%d") - timedelta(days=5)
        except ValueError:
            start_date = datetime.now() - timedelta(days=int(years_back * 365) + 5)
    else:
        start_date = datetime.now() - timedelta(days=int(years_back * 365) + 5)
    try:
        t = yf.Ticker(sym)
        hist = t.history(
            start=start_date.strftime("%Y-%m-%d"),
            interval="1d",
        )
        hist = _slice_to_end(hist, end_date_str)
        if hist.empty or len(hist) < 2:
            return {"error": f"{sym} için geçmiş veri bulunamadı"}

        start_price = float(hist["Close"].iloc[0])
        end_price = float(hist["Close"].iloc[-1])
        start_date_actual = hist.index[0].strftime("%Y-%m-%d")
        end_date_actual = hist.index[-1].strftime("%Y-%m-%d")

        # Alınacak adet ve bugünkü değer
        quantity = amount / start_price if start_price > 0 else 0
        current_value = quantity * end_price
        profit = current_value - amount
        profit_pct = profit / amount * 100 if amount > 0 else 0

        # Yıllık ortalama getiri (CAGR)
        actual_years = (
            datetime.strptime(end_date_actual, "%Y-%m-%d")
            - datetime.strptime(start_date_actual, "%Y-%m-%d")
        ).days / 365
        if actual_years > 0 and start_price > 0:
            cagr = ((end_price / start_price) ** (1 / actual_years) - 1) * 100
        else:
            cagr = 0

        return {
            "symbol": sym,
            "amount_invested": round(amount, 2),
            "quantity": round(quantity, 4),
            "start_date": start_date_actual,
            "start_price": round(start_price, 2),
            "end_date": end_date_actual,
            "end_price": round(end_price, 2),
            "current_value": round(current_value, 2),
            "profit": round(profit, 2),
            "profit_pct": round(profit_pct, 2),
            "cagr_pct": round(cagr, 2),
            "years": round(actual_years, 2),
        }
    except Exception as exc:
        logger.warning(f"What-if error: {exc}")
        return {"error": f"Hesaplama hatası: {exc}"}


def calculate_dca(symbol: str, monthly_amount: float,
                  years_back: float,
                  start_date_str: str | None = None,
                  end_date_str: str | None = None) -> dict:
    """DCA (maliyet ortalaması): her ay `monthly_amount` TL yatırılsaydı.

    Her ayın ilk işlem gününün fiyatından alım yapılır; toplam yatırılan,
    biriken adet, bugünkü değer, getiri ve aynı parayı tek seferde
    yatırmaya (lump-sum) kıyas hesaplanır. Grafik için aylık seri döner.
    Net tarih (`start_date_str`) verilirse `years_back` yerine onu başlangıç
    alır; `end_date_str` verilirse o tarihe kadarki veriyle hesaplar.
    """
    sym = symbol.upper()
    days_back = int(years_back * 365)
    if start_date_str:
        try:
            fetch_start = datetime.strptime(start_date_str, "%Y-%m-%d")
        except ValueError:
            fetch_start = datetime.now() - timedelta(days=days_back)
    else:
        fetch_start = datetime.now() - timedelta(days=days_back)
    fetch_start -= timedelta(days=5)
    try:
        hist = yf.Ticker(sym).history(
            start=fetch_start.strftime("%Y-%m-%d"), interval="1d")
        hist = _slice_from_start(hist, start_date_str)
        hist = _slice_to_end(hist, end_date_str)
        if hist.empty or len(hist) < 2:
            return {"error": f"{sym} için geçmiş veri bulunamadı"}

        # Her ay ilk işlem günü → kapanış
        monthly = (
            hist["Close"]
            .groupby([hist.index.year, hist.index.month])
            .first()
        )
        if len(monthly) < 2:
            return {"error": "Yeterli aylık veri yok"}

        end_price = float(hist["Close"].iloc[-1])
        total_invested = 0.0
        total_qty = 0.0
        series = []
        for (yr, mo), price in monthly.items():
            price = float(price)
            if price <= 0:
                continue
            total_invested += monthly_amount
            total_qty += monthly_amount / price
            series.append({
                "date": f"{int(yr)}-{int(mo):02d}",
                "price": round(price, 2),
                "invested": round(total_invested, 2),
                "value": round(total_qty * price, 2),
            })

        current_value = total_qty * end_price
        profit = current_value - total_invested
        profit_pct = profit / total_invested * 100 if total_invested else 0
        avg_cost = total_invested / total_qty if total_qty else 0

        # Lump-sum kıyas: aynı toplam parayı ilk ay tek seferde yatırsaydı
        first_price = float(monthly.iloc[0])
        lump_qty = total_invested / first_price if first_price > 0 else 0
        lump_value = lump_qty * end_price
        lump_profit_pct = (
            (lump_value - total_invested) / total_invested * 100
            if total_invested else 0
        )

        return {
            "symbol": sym,
            "monthly_amount": round(monthly_amount, 2),
            "months": len(series),
            "start_date": hist.index[0].strftime("%Y-%m-%d"),
            "end_date": hist.index[-1].strftime("%Y-%m-%d"),
            "total_invested": round(total_invested, 2),
            "quantity": round(total_qty, 4),
            "avg_cost": round(avg_cost, 2),
            "end_price": round(end_price, 2),
            "current_value": round(current_value, 2),
            "profit": round(profit, 2),
            "profit_pct": round(profit_pct, 2),
            "lump_sum_value": round(lump_value, 2),
            "lump_sum_profit_pct": round(lump_profit_pct, 2),
            "series": series,
        }
    except Exception as exc:
        logger.warning(f"DCA error: {exc}")
        return {"error": f"Hesaplama hatası: {exc}"}
