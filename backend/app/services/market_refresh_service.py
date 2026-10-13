"""Piyasa verisi arka plan yenileyicisi — Yahoo'yu istek yolundan çıkarır.

Sorun: her kullanıcı isteği (portföy açılışı, benchmark, sinyal taraması)
Yahoo'ya çıkabiliyordu. İstek hacmi kullanıcı trafiğiyle doğru orantılı
büyüyünce Yahoo, Render IP'sini 429'luyor ve UYGULAMA VERİSİZ KALIYOR.

Çözüm: tek bir arka plan işçisi, izlenen TÜM sembolleri sabit aralıkla ve
sabit sayıda batch ile çeker; paylaşılan cache'e yazar. Kullanıcı istekleri
cache'ten okur. Böylece Yahoo'nun gördüğü hız, kaç kullanıcı olduğundan
BAĞIMSIZ ve öngörülebilir olur.

Tur başına Yahoo isteği: 3 (fiyat + günlük kapanış + OHLCV) — kaç sembol
olursa olsun. Dördüncü iş TEFAS fon kataloğunu tazeler (kendi 24 saatlik
sayacı var), beşincisi temel oran cache'ini, altıncısı sektör cache'ini
ısıtır (yalnız eksikleri, tur başına birkaç sembol) — hepsi sıcakken ağa
hiç çıkmaz.
"""

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field

from loguru import logger

from app.services import (fund_catalog, market_data_service, portfolio_service,
                          signal_service)

# Benchmark'ın her zaman ihtiyaç duyduğu semboller — kullanıcı portföyünde
# olmasalar da getirinin kıyaslandığı seriler.
_ALWAYS = ("XU100.IS", "^GSPC", "USDTRY=X", "GC=F")


@dataclass
class RefreshResult:
    """Bir turun sonucu — loglama ve test için."""
    symbols: int = 0
    quotes: int = 0
    closes: int = 0
    ohlcv: int = 0
    new_funds: int = 0
    warmed: int = 0
    sectors: int = 0
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors and (self.quotes or self.closes or self.ohlcv)


def tracked_symbols(db) -> list[str]:
    """İzlenecek semboller: kullanıcı pozisyonları ∪ izleme listeleri ∪
    benchmark sabitleri. Kanonikleştirilir (THY → THYAO.IS) ki cache
    anahtarları fiyat yollarıyla birebir aynı olsun."""
    from app.models.portfolio import Portfolio
    from app.models.watchlist import WatchlistItem
    from app.services.symbol_alias import canonical

    syms: set[str] = {canonical(s) for s in _ALWAYS}
    try:
        for (raw,) in db.query(Portfolio.symbol).distinct():
            if raw:
                syms.add(canonical(raw))
        for (raw,) in db.query(WatchlistItem.symbol).distinct():
            if raw:
                syms.add(canonical(raw))
    except Exception as exc:
        logger.warning(f"İzlenen sembol listesi okunamadı: {exc}")
    return sorted(syms)


def refresh(symbols: list[str]) -> RefreshResult:
    """Üç veri setini paralel yeniler (her biri TEK batch).

    Biri patlarsa diğerleri devam eder — kısmi tazelik, hiç tazelik yoktan
    iyidir; ayrıca çağıran hangi setin düştüğünü loglayabilsin diye hatalar
    toplanır."""
    res = RefreshResult(symbols=len(symbols))
    if not symbols:
        return res

    def _quotes():
        market_data_service.prewarm_symbols(symbols)
        return len(symbols)

    jobs = {
        "quote": _quotes,
        "closes": lambda: len(market_data_service.refresh_daily_closes(symbols)),
        "ohlcv": lambda: len(market_data_service.refresh_daily_ohlcv(symbols, "6mo")),
        # Katalog kendi 24 saatlik sayacını tutar → tur başına maliyeti sıfır,
        # günde bir TEK istek. Yeni kurulan fon için deploy beklenmesin.
        "fonlar": fund_catalog.refresh_if_due,
        # Temel oranlar 12 saatlik paylaşılan cache'te; ilk sinyal taramasının
        # ~32 sn'sinin çoğu bunları TEK TEK çekmekti. Tur başına en fazla
        # birkaç eksik sembol ısıtılır — sıcakken tur bedava.
        "temel": lambda: signal_service.prewarm_fundamentals(symbols),
        # Sektör çözümü sağlık skorunun girdisi; süreç-içi sözlük her
        # uyanışta sıfırlandığı için soğuk /health 7,5 sn ölçülmüştü.
        # Cache'te olmayan sembol arka planda çözülür (sıcakken bedava).
        "sektör": lambda: portfolio_service.prewarm_sectors(symbols),
    }

    with ThreadPoolExecutor(max_workers=6) as ex:
        futures = {name: ex.submit(fn) for name, fn in jobs.items()}
        for name, fut in futures.items():
            try:
                count = fut.result()
            except Exception as exc:
                logger.warning(f"Yenileme hatası ({name}): {exc}")
                res.errors.append(f"{name}: {exc}")
                continue
            if name == "quote":
                res.quotes = count
            elif name == "closes":
                res.closes = count
            elif name == "ohlcv":
                res.ohlcv = count
            elif name == "fonlar":
                res.new_funds = count
            elif name == "sektör":
                res.sectors = count
            else:
                res.warmed = count
    return res


def refresh_all() -> RefreshResult:
    """DB'den izlenen sembolleri okuyup bir tur yeniler. Worker'ın çağırdığı
    tek giriş noktası."""
    from app.core.database import SessionLocal

    db = SessionLocal()
    try:
        symbols = tracked_symbols(db)
    finally:
        db.close()
    return refresh(symbols)
