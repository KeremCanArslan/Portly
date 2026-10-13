from fastapi import APIRouter, BackgroundTasks, HTTPException, Request
from app.core.limiter import limiter
from app.services import (
    market_data_service,
    fear_greed_service,
    ta_quiz_service,
    macro_calendar_service,
    what_if_service,
    gold_rates_service,
)


router = APIRouter()


@router.get("/fear-greed")
def get_fear_greed(force: bool = False):
    """Fear & Greed Index — VIX + momentum + haber sentiment compozit skor."""
    return fear_greed_service.get_fear_greed_index(force_refresh=force)


@router.get("/what-if")
def what_if(symbol: str, amount: float, years_back: float = 1.0,
            start_date: str | None = None, end_date: str | None = None):
    """X TL geçmişte (net tarih ya da yıllar önce) alınmış olsaydı bugün (ya da
    verilen bitiş tarihinde) ne olurdu hesaplar."""
    if amount <= 0:
        raise HTTPException(status_code=400, detail="Tutar pozitif olmalı")
    if years_back <= 0 or years_back > 30:
        raise HTTPException(status_code=400, detail="Yıl 0-30 arası olmalı")
    return what_if_service.calculate(symbol, amount, years_back,
                                     start_date, end_date)


@router.get("/dca")
def dca(symbol: str, monthly_amount: float, years_back: float = 3.0,
        start_date: str | None = None, end_date: str | None = None):
    """Her ay X TL yatırsaydım (maliyet ortalaması) simülasyonu. Net başlangıç
    ve/veya bitiş tarihi verilebilir."""
    if monthly_amount <= 0:
        raise HTTPException(status_code=400, detail="Tutar pozitif olmalı")
    if years_back <= 0 or years_back > 30:
        raise HTTPException(status_code=400, detail="Yıl 0-30 arası olmalı")
    return what_if_service.calculate_dca(symbol, monthly_amount, years_back,
                                         start_date, end_date)


@router.get("/gold-rates")
def get_gold_rates():
    """Türk bankalarının gram altın alış/satış fiyatları, makas küçük → büyük."""
    return gold_rates_service.get_bank_gold_rates()


@router.get("/macro-calendar")
def get_macro_calendar(force: bool = False):
    """Bugünün ve yaklaşan haftadaki önemli ekonomik takvim olayları."""
    return macro_calendar_service.get_upcoming_events(force_refresh=force)


@router.get("/quiz")
def get_quiz(horizon: str = "medium"):
    """TA eğitim quizi için rastgele bir soru üretir."""
    if horizon not in ("short", "medium", "long"):
        raise HTTPException(status_code=400, detail="Vade kısa/orta/uzun olmalı")
    try:
        return ta_quiz_service.generate_question(horizon=horizon)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/price/{symbol}")
def get_price(symbol: str, background_tasks: BackgroundTasks):
    """Cache fresh ise anında, stale ise stale veriyi döner + arka planda yeniler."""
    return market_data_service.get_stock_data(symbol, background_tasks)

@router.get("/prices")
def get_prices(symbols: str):
    """Çok sembol fiyatı TEK istekte (izleme listesi / ana ekran hot-path'i).

    `?symbols=AAPL,THYAO.IS,BTC-USD` — sembol başına ayrı `/price/{sym}`
    çağrısı açılışta N HTTP demekti; burada tek batch + yedek kaynak zinciri.
    Veri gelmeyen semboller `missing` listesinde DÜRÜSTÇE bildirilir (0 fiyat
    uydurulmaz)."""
    syms = [s for s in (symbols or "").split(",") if s.strip()][:60]
    if not syms:
        return {"quotes": [], "missing": []}
    return market_data_service.get_stock_prices_named(syms)


@router.get("/history/{symbol}")
@limiter.limit("60/minute")
def get_price_history(request: Request, symbol: str, period: str = "1mo",
                      interval: str | None = None):
    """Bir hissenin geçmiş fiyat verilerini döndürür.

    period: 1d, 5d, 1mo, 3mo, 6mo, 1y, 2y, 5y, max
    interval: opsiyonel — 1m, 5m, 15m, 30m, 1h, 1d. Verilmezse period'a göre seçilir.

    C4: yfinance çağrısı (1-2sn). IP başına 60/dk — grafik zaplaması
    serbest ama spam yfinance kotasını yakamaz.
    """
    return market_data_service.get_stock_history(
        symbol=symbol, period=period, interval=interval
    )
@router.get("/search")
def search_stocks(q: str, limit: int = 10):
    """
    Hisse/şirket arar. BIST, NYSE, NASDAQ, kripto destekli.
    Örnek: /api/v1/market/search?q=garanti
    """
    return market_data_service.search_symbols(query=q, limit=limit)