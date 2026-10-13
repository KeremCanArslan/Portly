from fastapi import HTTPException
from sqlalchemy.orm import Session
from loguru import logger
from app.models.portfolio import Portfolio
from app.services.market_data_service import get_stock_prices
from app.services.symbol_alias import canonical
from app.services import fx_service
import yfinance as yf
import math


# order_service'teki kapanmış-pozisyon eşiğiyle aynı (tek tanım).
_QTY_EPSILON = 1e-6


def _safe(v: float, fallback: float = 0.0) -> float:
    """NaN ve sonsuz değerleri JSON-uyumlu hale getir."""
    try:
        f = float(v)
        if math.isnan(f) or math.isinf(f):
            return fallback
        return f
    except Exception:
        return fallback


def _valid_position(symbol: str, quantity: float, current_price: float,
                    avg_cost: float) -> bool:
    """Bozuk veri (NaN/inf/negatif/sıfır-adet) toplamlara ve bölmelere
    SIZMADAN önce pozisyonu ele. Eskiden NaN bir adet 0.0'a sıkıştırılıp
    kayıt yine de dönüyor, sonra bölmede patlayabiliyordu. order_service
    ile aynı 1e-6 eşiği."""
    for name, v in (("quantity", quantity),
                    ("current_price", current_price),
                    ("average_cost", avg_cost)):
        if v is None or math.isnan(v) or math.isinf(v) or v < 0:
            logger.warning(f"portföy pozisyonu atlandı {symbol}: {name}={v}")
            return False
    if quantity < _QTY_EPSILON:
        return False
    return True


def _price_from_quotes(symbol: str, quotes: dict[str, dict],
                       fallback: float) -> tuple[float, bool]:
    """Batch sonucundan (get_stock_prices) güncel fiyatı çeker.

    Dönüş: (fiyat, canlı_mı). Sembol yoksa ya da NaN/inf/≤0 edge case'inde
    avg_cost'a düşülür ve ikinci değer **False** olur.

    ⚠️ İkinci değer ŞART: fiyat alınamayınca maliyet fiyat yerine geçiyor ve
    ekranda "Fiyat ₺35,00 · Maliyet ₺35,00 · +%0,00 · Bugün +%0,00" çıkıyordu
    — kullanıcı bunu "hiç değişmemiş" diye okur, oysa VERİ YOK (canlıda BIST
    pozisyonlarının tamamında görüldü). Sayı aynı kalır (toplamlar bozulmasın)
    ama satır artık dürüstçe işaretlenir."""
    q = quotes.get(symbol)
    if not q:
        return fallback, False
    try:
        price = float(q["current_price"])
    except (KeyError, TypeError, ValueError):
        return fallback, False
    if math.isnan(price) or math.isinf(price) or price <= 0:
        return fallback, False
    return price, True


def _currency_of(symbol: str) -> str:
    """Sembol → para birimi. fx_service tek kaynak (geriye uyum için sarmalayıcı)."""
    return fx_service.currency_of(symbol)


def _try_amounts(item, currency: str, total_value: float,
                 total_cost: float) -> dict:
    """Pozisyonun ₺ karşılıkları — maliyet ALIŞ kuruyla, değer CANLI kurla.

    Maliyet de canlı kurla çevrilirse kurdan gelen reel kâr K/Z'de HİÇ
    görünmez: kur yükselince maliyet de aynı oranda büyür ve fark sıfırlanır.
    Yatırımcının ₺ cinsinden gerçekte kazandığı budur, o yüzden ₺ K/Z artık
    `değer − maliyet` olarak hesaplanıyor (native K/Z'nin çevirisi değil).

    `fx_gain_try` bu kârın kur kaynaklı kısmını ayırır (arayüz açıklayabilsin):
        kur kazancı = native_maliyet × (canlı_kur − alış_kuru)
        varlık kazancı = (fiyat − maliyet) × adet × canlı_kur
    İkisinin toplamı ₺ K/Z'ye eşittir.

    Alış kuru bilinmiyorsa (kolon öncesi kayıt, kur kaynağı düştü) ESKİ
    davranışa düşülür: her iki taraf da canlı kurla çevrilir, kur kazancı 0.
    """
    value_try = fx_service.to_try(total_value, currency)
    cost_fx = None
    if currency != "TRY":
        try:
            raw = getattr(item, "fx_rate_at_cost", None)
            cost_fx = float(raw) if raw else None
        except (TypeError, ValueError):
            cost_fx = None

    if cost_fx is None:
        cost_try = fx_service.to_try(total_cost, currency)
        fx_gain = 0.0
    else:
        cost_try = total_cost * cost_fx
        fx_gain = total_cost * (fx_service.usdtry_rate() - cost_fx)

    return {
        "total_value_try": _safe(value_try),
        "total_cost_try": _safe(cost_try),
        "pnl_try": _safe(value_try - cost_try),
        "fx_gain_try": _safe(fx_gain),
    }


def get_user_portfolio(db: Session, user_id: int):
    # Forward-only hisse bölünmesi mutabakatı (self-healing): portföy
    # okunmadan önce yeni bölünmeler adet/maliyete yansıtılır ki bölünme
    # günü yapay -%50 düşüş gibi görünmesin. Hata olursa portföy okuması
    # ASLA bozulmaz (geç import → import döngüsü riski de yok).
    try:
        from app.services import order_service
        order_service.reconcile_splits(db, user_id)
    except Exception as exc:
        logger.warning(f"split mutabakatı atlandı user={user_id}: {exc}")

    portfolio_items = db.query(Portfolio).filter(Portfolio.user_id == user_id).all()
    if not portfolio_items:
        return []

    avg_costs = [float(item.average_cost) for item in portfolio_items]
    # Çıplak BIST kodlarını / takma adları kanonikleştir (THY → THYAO.IS)
    # → fiyat, para birimi ve gruplama tutarlı olsun.
    symbols = [canonical(item.symbol) for item in portfolio_items]

    # Tek batch (yf.download) ile tüm fiyatlar — N ayrı HTTP yerine 1. Cache
    # fresh/stale anında döner, eksikler tek istekte çekilir, stale arka planda
    # yenilenir. Batch'te dönmeyen sembol → avg_cost'a düş (NaN/inf koruması).
    quotes = get_stock_prices(symbols)
    priced = [_price_from_quotes(sym, quotes, fb)
              for sym, fb in zip(symbols, avg_costs)]

    result = []
    for item, (current_price, price_live), csym in zip(
            portfolio_items, priced, symbols):
        quantity = float(item.quantity)
        avg_cost = float(item.average_cost)
        if not _valid_position(csym, quantity, current_price, avg_cost):
            continue
        total_value = quantity * current_price
        total_cost = quantity * avg_cost
        pnl = total_value - total_cost
        pnl_percent = (pnl / total_cost * 100) if total_cost > 0 else 0.0
        currency = _currency_of(csym)

        # ₺ karşılıkları: USD pozisyonlar canlı USDTRY ile çevrilir. Tek-birim
        # toplam/ağırlık/sektör hesapları MUTLAKA *_try alanlarını okumalı;
        # ham total_value (kendi para biriminde) yalnız satır gösterimi için.
        result.append({
            "symbol": csym,
            "quantity": _safe(quantity),
            "average_cost": _safe(avg_cost),
            "current_price": _safe(current_price, fallback=avg_cost),
            "total_value": _safe(total_value),
            "pnl": _safe(pnl),
            "pnl_percent": _safe(pnl_percent),
            "change_percent": _safe((quotes.get(csym) or {}).get("change_percent", 0.0)),
            # Fiyat CANLI mı, yoksa maliyete mi düşüldü? Ekran buna göre
            # "+%0,00" yerine "—" gösterir (uydurma sıfır yok).
            "price_available": price_live,
            # GÜNLÜK DEĞİŞİM biliniyor mu? Fiyatı bilinip değişimi bilinmeyen
            # kaynak var (altın/gümüş spot: fiyat verir, dünkü kapanışı
            # vermez) → aynı dürüstlük kuralı değişim için de gerekli:
            # False ise ekran "Bugün" satırını hiç göstermez.
            # Sembol için HİÇ kotasyon dönmediyse değişim de bilinmiyordur:
            # varsayılan True bırakılırsa satır "bugün %0 oynadı" demiş olur ve
            # portföyün günlük yüzdesini sıfıra doğru seyreltirdi (fiyatı
            # bilinmeyen pozisyonun değeri maliyetten geliyor, oradaki 0
            # gerçek bir ölçüm değil).
            "change_available": bool(
                (quotes.get(csym) or {}).get("change_available", True))
            and price_live,
            "currency": currency,
            **_try_amounts(item, currency, total_value, total_cost),
        })

    return result

_SECTOR_TRANSLATIONS = {
    # yfinance sektör adları
    "Technology": "Teknoloji",
    "Financial Services": "Finans",
    "Financial": "Finans",
    "Consumer Cyclical": "Tüketim",
    "Consumer Defensive": "Temel Tüketim",
    "Communication Services": "İletişim",
    "Healthcare": "Sağlık",
    "Industrials": "Sanayi",
    "Energy": "Enerji",
    "Basic Materials": "Hammadde",
    "Real Estate": "Gayrimenkul",
    "Utilities": "Kamu Hizmetleri",
    # Finnhub finnhubIndustry adları (farklı taksonomi)
    "Semiconductors": "Teknoloji",
    "Internet": "Teknoloji",
    "Software": "Teknoloji",
    "Media": "İletişim",
    "Telecommunication": "İletişim",
    "Communications": "İletişim",
    "Retail": "Perakende",
    "Banking": "Bankacılık",
    "Insurance": "Sigorta",
    "Pharmaceuticals": "Sağlık",
    "Biotechnology": "Sağlık",
    "Health Care": "Sağlık",
    "Automobiles": "Otomotiv",
    "Oil & Gas": "Enerji",
    "Aerospace & Defense": "Savunma",
    "Machinery": "Sanayi",
    "Industrial Conglomerates": "Sanayi",
    "Chemicals": "Kimya",
    "Metals & Mining": "Metal",
    "Airlines": "Ulaştırma",
    "Logistics & Transportation": "Ulaştırma",
    "Food Products": "Gıda",
    "Beverages": "Gıda",
    "Consumer products": "Tüketim",
    "Hotels, Restaurants & Leisure": "Tüketim",
    # Ekranda ham İngilizce kalan Finnhub adları (çevirisi yoksa ad olduğu
    # gibi basılıyor → "Road & Rail", "Electrical E..." gibi karışık lejant).
    "Road & Rail": "Ulaştırma",
    "Marine": "Ulaştırma",
    "Transportation Infrastructure": "Ulaştırma",
    "Electrical Equipment": "Sanayi",
    "Electronic Equipment": "Teknoloji",
    "Commercial Services & Supplies": "Sanayi",
    "Trading Companies & Distributors": "Sanayi",
    "Building": "İnşaat",
    "Construction Materials": "İnşaat",
    "Constr. Mat.": "İnşaat",
    "Homebuilding": "İnşaat",
    "Professional Services": "Hizmet",
    "Business Services": "Hizmet",
    "Diversified Consumer Services": "Hizmet",
    "IT Services": "Teknoloji",
    "Hardware": "Teknoloji",
    "Telecommunications Equipment": "İletişim",
    "Wireless Telecom": "İletişim",
    "Broadcasting": "İletişim",
    "Cable & Satellite": "İletişim",
    "Advertising": "İletişim",
    "Publishing": "İletişim",
    "Life Sciences Tools & Services": "Sağlık",
    "Health Care Providers": "Sağlık",
    "Health Care Equipment": "Sağlık",
    "Health Care Technology": "Sağlık",
    "Medical Equipment": "Sağlık",
    "Capital Markets": "Finans",
    "Asset Management": "Finans",
    "Investment Banking": "Finans",
    "Consumer Finance": "Finans",
    "Diversified Financial Services": "Finans",
    "Financial Conglomerates": "Finans",
    "Holding Companies": "Holding",
    "Real Estate Management & Development": "Gayrimenkul",
    "REIT": "Gayrimenkul",
    "Precious Metals": "Madencilik",
    "Renewable Energy": "Enerji",
    "Gas Utilities": "Kamu Hizmetleri",
    "Water Utilities": "Kamu Hizmetleri",
    "Packaging": "Sanayi",
    "Paper & Forest": "Sanayi",
    "Textiles, Apparel & Luxury": "Tüketim",
    "Apparel": "Tüketim",
    "Household Products": "Temel Tüketim",
    "Tobacco": "Temel Tüketim",
    "Furnishings": "Tüketim",
    "Leisure Products": "Tüketim",
    "Distributors": "Perakende",
    "Multiline Retail": "Perakende",
    "Specialty Retail": "Perakende",
    "Restaurants": "Tüketim",
    "Casinos & Gaming": "Tüketim",
    "Auto Components": "Otomotiv",
    "Agriculture": "Gıda",
}


# Sektör cache'i: süreç-içi + PAYLAŞILAN (Redis). Sektör değişmez, ama
# süreç-içi sözlük her deploy/uyanışta sıfırlanıyordu → ücretsiz katmanda
# yeniden başlayan her örnek, portföydeki her sembol için Finnhub profilini
# yeniden çekiyordu. Canlı ölçüm: /portfolio/{id}/health soğuk süreçte 6-8 sn,
# ikinci çağrıda 0,3 sn. Paylaşılan cache ile bu bedel bir kez ödenir.
_sector_cache = {}
_SECTOR_KEY = "pf:sector:"
_SECTOR_TTL_SECONDS = 30 * 24 * 3600


def _sector_remember(symbol: str, sector: str) -> str:
    """Sektörü iki katmana da yaz ve döndür (çağrı yerlerini kısaltır)."""
    _sector_cache[symbol] = sector
    try:
        from app.core import cache
        cache.set(_SECTOR_KEY + symbol, sector, _SECTOR_TTL_SECONDS)
    except Exception as exc:
        logger.debug(f"Sektör cache yazılamadı ({symbol}): {exc}")
    return sector


def _sector_cached(symbol: str) -> str | None:
    hit = _sector_cache.get(symbol)
    if hit:
        return hit
    try:
        from app.core import cache
        shared = cache.get(_SECTOR_KEY + symbol)
    except Exception:
        return None
    if shared and isinstance(shared[0], str):
        _sector_cache[symbol] = shared[0]
        return shared[0]
    return None


_FALLBACK_SECTORS = {
    "GC=F": "Altın",
    "SI=F": "Gümüş",
    "CL=F": "Petrol",
    "USDTRY=X": "Döviz",
    "EURTRY=X": "Döviz",
    "GBPTRY=X": "Döviz",
    "BTC-USD": "Kripto",
    "ETH-USD": "Kripto",
    "SOL-USD": "Kripto",
}

# BIST sektör haritası (base sembol, .IS'siz). Finnhub ücretsiz tier BIST'i
# KAPSAMAZ, yfinance .info Render'da BLOKLU → en çok tutulan BIST hisseleri için
# elle sektör. Kapsanmayan BIST sembolü yine 'Diğer'e düşer (kabul edilebilir).
_BIST_SECTORS = {
    "THYAO": "Ulaştırma", "PGSUS": "Ulaştırma", "TAVHL": "Ulaştırma",
    "TUPRS": "Enerji", "ODAS": "Enerji", "ZOREN": "Enerji", "AKSEN": "Enerji",
    "GARAN": "Bankacılık", "AKBNK": "Bankacılık", "ISCTR": "Bankacılık",
    "YKBNK": "Bankacılık", "VAKBN": "Bankacılık", "HALKB": "Bankacılık", "TSKB": "Bankacılık",
    "ASELS": "Savunma",
    "EREGL": "Metal", "KRDMD": "Metal", "KOZAL": "Madencilik", "KOZAA": "Madencilik",
    "PETKM": "Kimya", "HEKTS": "Kimya", "SASA": "Kimya", "GUBRF": "Kimya",
    "BIMAS": "Perakende", "MGROS": "Perakende", "SOKM": "Perakende",
    "KCHOL": "Holding", "SAHOL": "Holding", "ALARK": "Holding", "GSDHO": "Holding",
    "SISE": "Sanayi", "TTRAK": "Sanayi", "ENKAI": "İnşaat",
    "FROTO": "Otomotiv", "TOASO": "Otomotiv", "DOAS": "Otomotiv", "OTKAR": "Otomotiv",
    "ARCLK": "Tüketim", "VESTL": "Tüketim", "ULKER": "Gıda", "CCOLA": "Gıda", "AEFES": "Gıda",
    "TCELL": "İletişim", "TTKOM": "İletişim",
    "OYAKC": "Çimento", "AKCNS": "Çimento",
    "EKGYO": "Gayrimenkul",
    # bist_catalog.CATALOG'daki kalan hisseler — katalogda adı olup sektörü
    # olmayan her sembol "Diğer"e düşüyordu. Katalog ile eşleşik tutulur;
    # kapsam testi: tests/test_sector_breakdown.py
    "AKSA": "Kimya", "KORDS": "Kimya", "BAGFS": "Kimya",
    "ASTOR": "Sanayi", "EUPWR": "Sanayi", "KONTR": "Sanayi",
    "GLRMK": "İnşaat", "BINHO": "İnşaat", "KLSER": "İnşaat",
    "TKFEN": "İnşaat", "CIMSA": "Çimento",
    "ALTNY": "Savunma",
    "ARDYZ": "Teknoloji", "LOGO": "Teknoloji", "MIATK": "Teknoloji",
    "PENTA": "Teknoloji", "REEDR": "Teknoloji", "YEOTK": "Teknoloji",
    "NETAS": "İletişim",
    "AYGAZ": "Enerji", "ENJSA": "Enerji", "GWIND": "Enerji",
    "SMRTG": "Enerji", "CWENE": "Enerji", "CANTE": "Enerji",
    "ESEN": "Enerji", "IZENR": "Enerji", "HUNER": "Enerji",
    "SKBNK": "Bankacılık", "ISMEN": "Finans",
    "DOHOL": "Holding", "BRYAT": "Holding",
    "ECILC": "Sağlık", "DEVA": "Sağlık", "SELEC": "Sağlık",
    "BIZIM": "Perakende", "MAVI": "Perakende",
    "TABGD": "Gıda", "KAYSE": "Gıda",
    "KARSN": "Otomotiv", "TMSN": "Sanayi", "EGEEN": "Sanayi",
    "BRSAN": "Metal",
    "ISGYO": "Gayrimenkul", "TRGYO": "Gayrimenkul", "PASEU": "Gayrimenkul",
    "FENER": "Spor", "GSRAY": "Spor", "BJKAS": "Spor",
}


# Yahoo sembol son ekinden varlık sınıfı. Elle liste tutmak yerine KURAL:
# yeni bir kripto/emtia/parite eklendiğinde haritayı güncellemek gerekmez,
# aksi halde hepsi "Diğer"e düşüyordu.
def _sector_from_suffix(symbol: str) -> str | None:
    if symbol.endswith(".ALTIN"):
        # Fiziki altın (çeyrek/gram/bilezik) — kâğıt altınla (GC=F) aynı
        # dilimde toplansın; kullanıcı için ikisi de "altın".
        return "Altın"
    if symbol.endswith(".GUMUS"):
        return "Gümüş"
    if symbol.endswith(".FON"):
        # TEFAS yatırım fonu — sepetin kendi içinde zaten çok sektör var.
        # ABD ETF'leriyle aynı dilime giriyor ki donut'ta tek bir "fon"
        # kalemi olsun; drill-down içeride hangi fon olduğunu gösteriyor.
        return "Fon/ETF"
    if symbol.endswith("-USD"):
        return "Kripto"
    if symbol.endswith("=X"):
        return "Döviz"
    if symbol.endswith("=F"):
        return "Emtia"
    if symbol.startswith("^"):
        return "Endeks"
    return None


def _is_probably_fund(symbol: str, finnhub_saw_it: bool) -> bool:
    """ETF/fon mu? Finnhub profile2 ETF'e `finnhubIndustry` VERMEZ; profil hiç
    dönmediyse (fh_seen=False) sembolü tanımıyoruz demektir → fon deme.
    Profil döndü ama sanayi yoksa → şirket değil, sepet (ETF/fon).

    Bilinen büyük ETF'ler ayrıca listede: Finnhub ücretsiz tier bazılarında
    profili hiç döndürmüyor."""
    if symbol in _KNOWN_FUNDS:
        return True
    return finnhub_saw_it


# Finnhub'ın profil bile döndürmediği yaygın ETF'ler (ücretsiz tier boşlukları).
_KNOWN_FUNDS = {
    "SPY", "VOO", "IVV", "QQQ", "QQQM", "DIA", "IWM", "VTI", "VT", "VEA",
    "VWO", "VXUS", "EFA", "EEM", "SCHD", "VYM", "VIG", "JEPI", "JEPQ",
    "SMH", "SOXX", "XLK", "XLF", "XLE", "XLV", "XLI", "XLY", "XLP", "XLU",
    "XLB", "XLRE", "XLC", "ARKK", "ARKG", "ARKW", "GLD", "IAU", "SLV",
    "TLT", "IEF", "SHY", "AGG", "BND", "LQD", "HYG", "TQQQ", "SQQQ",
    "UPRO", "VOOG", "VUG", "VTV", "MGK", "RSP", "ITA", "PPA", "XAR",
    "TUR", "EWZ", "EWJ", "EWG", "FXI", "MCHI", "INDA", "IBIT", "FBTC",
}


def _resolve_sector(symbol: str) -> str:
    """Sembolün sektörünü bul. Öncelik: statik emtia/döviz/kripto → BIST haritası →
    Finnhub (ABD, Render'da çalışır) → yfinance .info (lokal fallback) → 'Diğer'.

    NOT: yfinance .info (Yahoo quoteSummary) Render IP'sinde BLOKLU → tek başına
    bırakılırsa TÜM hisseler 'Diğer'e düşerdi. Finnhub + BIST haritası bu yüzden önce.
    """
    symbol = symbol.upper()

    cached = _sector_cached(symbol)
    if cached:
        return cached

    if symbol in _FALLBACK_SECTORS:
        return _sector_remember(symbol, _FALLBACK_SECTORS[symbol])

    # Son ek kuralı (haritadan SONRA, ağdan ÖNCE): kripto/emtia/parite/endeks
    # zaten Finnhub'da yok — boşuna çağrı yapıp "Diğer"e düşmesin.
    suffixed = _sector_from_suffix(symbol)
    if suffixed:
        return _sector_remember(symbol, suffixed)

    # BIST — Finnhub kapsamaz. Önce elle kürasyon (yukarıdaki harita), sonra
    # üretilmiş tam harita (`app/data/bist_sectors.json`, ~620 hisse). Elle
    # olan üstte kalır: FENER→Spor, AKCNS→Çimento gibi tercihler otomatik
    # eşlemeyle ezilmesin.
    if symbol.endswith(".IS"):
        bist_sector = _BIST_SECTORS.get(symbol[:-3])
        if not bist_sector:
            from app.services import bist_sectors as _bs
            bist_sector = _bs.sector_of(symbol)
        if bist_sector:
            return _sector_remember(symbol, bist_sector)

    # ABD hisseleri — Finnhub /stock/profile2 (Render'da çalışır, .info bloğunu by-pass)
    fh_seen = False
    try:
        from app.services import finnhub_service
        profile = finnhub_service.get_profile(symbol)
        if profile:
            fh_seen = True
            fh_industry = profile.get("finnhubIndustry")
            if fh_industry:
                return _sector_remember(
                    symbol, _SECTOR_TRANSLATIONS.get(fh_industry, fh_industry))
    except Exception:
        pass

    # ETF/fon: Finnhub profile2 sanayi vermez (şirket değil, sepet). Sepetin
    # kendi içinde zaten çok sektör var — "Diğer" yerine dürüst etiket.
    if _is_probably_fund(symbol, fh_seen):
        return _sector_remember(symbol, "Fon/ETF")

    # yfinance .info — lokal fallback (Render'da BLOKLU, orada boş döner).
    # Devre kesici ortak: aynı uç temel oranlar için de çağrılıyor ve Render'da
    # her deneme boşuna 0,6-3 sn yiyor. Kesici kapalıyken hiç denenmez; tek
    # başarı onu sıfırlar (lokalde davranış değişmez).
    from app.services import fundamental_analysis_service as _fa
    if _fa.info_available():
        try:
            from app.core.yf_session import get_session
            ticker = yf.Ticker(symbol, session=get_session())
            info = ticker.info
            en_sector = info.get("sector") or info.get("industry")
            _fa.note_info_result(bool(en_sector))
            if en_sector:
                return _sector_remember(
                    symbol, _SECTOR_TRANSLATIONS.get(en_sector, en_sector))
        except Exception:
            _fa.note_info_result(False)

    # "Diğer" de cache'lenir ama KISA süreyle: kaynak geçici olarak
    # ulaşılamadıysa sembol 30 gün "Diğer" kalmasın.
    _sector_cache[symbol] = "Diğer"
    try:
        from app.core import cache
        cache.set(_SECTOR_KEY + symbol, "Diğer", 3600)
    except Exception:
        pass
    return "Diğer"


def prewarm_sectors(symbols: list[str], limit: int = 10) -> int:
    """Sektör çözümünü ARKA PLANDA ısıtır; çözülen sembol sayısını döner.

    Neden: `/portfolio/{id}/health` (sağlık skoru) sektör dağılımına dayanıyor
    ve süreç-içi sözlük her deploy/uyanışta sıfırlanıyor. Paylaşılan cache'te
    olmayan sembol kullanıcı isteği sırasında çözülüyordu: Finnhub profili →
    (gerekirse) yfinance `.info` → sembol başına saniyeler. Canlı ölçüm:
    soğuk `/health` 7,5 sn, ikinci çağrı 0,28 sn.

    Nazik davranış: yalnız cache'te OLMAYANLAR denenir (sıcakken tur bedava —
    sektör 30 gün, "Diğer" 1 saat cache'te), tur başına en fazla `limit`
    sembol ve sıra sıra (Finnhub ücretsiz tier ~60 istek/dk).
    """
    warmed = 0
    for symbol in symbols:
        if warmed >= limit:
            break
        sym = (symbol or "").upper()
        if not sym or _sector_cached(sym):
            continue
        try:
            _resolve_sector(sym)
            warmed += 1
        except Exception as exc:
            logger.debug(f"Sektör ısıtma atlandı ({sym}): {exc}")
    return warmed


def get_sector_breakdown(db: Session, user_id: int, portfolio: list | None = None):
    """Kullanıcı portföyünü sektörlere göre dağıtır.

    `portfolio` verilirse yeniden okunmaz — sağlık skoru zaten pozisyonları
    yüklemiş oluyordu ve buradaki ikinci `get_user_portfolio` çağrısı tüm
    bölünme mutabakatını + fiyat batch'ini boş yere tekrarlıyordu."""
    if portfolio is None:
        portfolio = get_user_portfolio(db, user_id)

    if not portfolio:
        return {"sectors": [], "total_value": 0.0}

    sector_totals = {}
    sector_members: dict[str, list[dict]] = {}

    from concurrent.futures import ThreadPoolExecutor
    symbols = [item["symbol"] for item in portfolio]
    with ThreadPoolExecutor(max_workers=8) as ex:
        sector_list = list(ex.map(_resolve_sector, symbols))

    for item, sector in zip(portfolio, sector_list):
        # ₺ karşılığı — USD + ₺ pozisyonları ham toplamak donut'u/yüzdeleri
        # bozardı (TSLA $1266 ≈ ₺1266). total_value_try tek birimde.
        value = item.get("total_value_try", item["total_value"])
        sector_totals[sector] = sector_totals.get(sector, 0.0) + value
        sector_members.setdefault(sector, []).append({
            "symbol": item["symbol"],
            "value": round(value, 2),
        })

    total = sum(sector_totals.values())
    sectors = []
    for name, value in sorted(sector_totals.items(),
                              key=lambda x: x[1], reverse=True):
        # members: dilimin İÇİNDE ne olduğu. Özellikle "Diğer"/"Fon/ETF" gibi
        # toplayıcı dilimlerde "burada ne var?" sorusunu UI cevaplayabilsin
        # diye — sektör toplamıyla AYNI ₺ birimi (total_value_try).
        members = sorted(sector_members.get(name, []),
                         key=lambda m: m["value"], reverse=True)
        for m in members:
            m["percent"] = round((m["value"] / value * 100) if value > 0 else 0, 2)
        sectors.append({
            "name": name,
            "value": round(value, 2),
            "percent": round((value / total * 100) if total > 0 else 0, 2),
            "members": members,
        })

    return {"sectors": sectors, "total_value": round(total, 2)}

def delete_position(db: Session, user_id: int, symbol: str) -> dict:
    """Bir pozisyonu portföyden TAMAMEN kaldırır (yanlış girilmiş kayıt için).

    Satış DEĞİLDİR: satışta lot düşer, işlem kaydı geçmişte kalır ve K/Z
    hesabına girer. Burada sembol "hiç eklenmemiş" hâline döner → portföy
    satırı + o sembolün işlem kayıtları BİRLİKTE silinir. Yalnız portföy
    satırını silmek yarım bir durum bırakırdı: davranış/performans servisleri
    işlem tablosundan okuduğu için kullanıcı portföyünde görmediği bir
    pozisyonun maliyet/işlem izini raporlarda görmeye devam ederdi.

    Sembol kanonikleştirilir ama eski kayıtlar ham biçimde (ör. çıplak BIST
    kodu) yazılmış olabilir → iki biçim de silinir.
    """
    from app.models.transaction import Transaction

    raw = (symbol or "").strip().upper()
    if not raw:
        raise HTTPException(status_code=400, detail="Sembol boş olamaz")
    variants = {raw, canonical(raw)}

    item = (
        db.query(Portfolio)
        .filter(Portfolio.user_id == user_id, Portfolio.symbol.in_(variants))
        .first()
    )
    if not item:
        raise HTTPException(
            status_code=404, detail="Pozisyon portföyünde bulunamadı")

    deleted_symbol = item.symbol
    db.delete(item)
    removed = (
        db.query(Transaction)
        .filter(Transaction.user_id == user_id,
                Transaction.symbol.in_(variants))
        .delete(synchronize_session=False)
    )
    db.commit()
    logger.info(
        f"Pozisyon silindi: user={user_id} {deleted_symbol} "
        f"(+{removed} işlem kaydı)")
    return {
        "symbol": deleted_symbol,
        "deleted_transactions": int(removed or 0),
    }
