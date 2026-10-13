import threading
import time
from concurrent.futures import ThreadPoolExecutor

import pandas as pd
import yfinance as yf
from fastapi import HTTPException, BackgroundTasks
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from loguru import logger

from app.core import cache
from app.services import fund_catalog, gold_catalog

# ── Cache semantiği ──────────────────────────────────────────────────────────
# Stale-while-revalidate, paylaşılan cache (app.core.cache: Redis ya da
# in-process fallback) üzerinde.
#   Fresh: cache as-is. Stale: cache + arka planda (daemon thread) yenile.
#   Expired/yok: bloklayan fetch.
#
# ⚠️ Fiyat kaydı cache'te _STALE_TTL_SECONDS değil _KEEP_TTL_SECONDS kadar
# DURUR (4 Eyl ölçümü): eskiden kayıt 10 dakikada siliniyordu ve sonraki
# kullanıcı isteği bloklayan çekime düşüyordu — canlıda /portfolio/1 ardışık
# üç çağrıda 1,2 / **5,8** / 0,3 sn ölçüldü, kullanıcı "portföy geç yükleniyor"
# dedi. Kayıt elde tutulunca istek yolu bayat-ama-GERÇEK fiyatla anında döner,
# tazeleme arka planda olur. Bayat veri "uydurma veri" değildir; üstelik arka
# plan işçisi 5 dakikada bir zaten yeniliyor.
_FRESH_TTL_SECONDS = 60
_STALE_TTL_SECONDS = 600
# Bu yaşa kadar eldeki kayıt servis edilir (+ arka planda yenilenir). Üstünde
# kayıt gerçekten eskidir → bloklayan çekim hak edilir.
_KEEP_TTL_SECONDS = 6 * 3600
_HISTORY_TTL_SECONDS = 300  # geçmiş kapanışlar değişmez

_Q = "mkt:q:"   # quote (fiyat) key prefix
# Yedek kaynak sembol başına bir istek atar → tek seferde kaç sembole
# bakılacağının üst sınırı (Finnhub ücretsiz tier ~60 istek/dk).
_FALLBACK_QUOTE_LIMIT = 40
_H = "mkt:h:"   # history key prefix

# Şirket adı KALICI cache (süresiz, in-process): ad değişmez ve yfinance `.info`
# çağrısı tek tek sembolde en yavaş kısımdır (~0.6-3sn). Bir kez çözülüp burada
# tutulur; batch fiyat çekimi adı buradan okur (yoksa sembolün kendisi).
_name_cache: dict[str, str] = {}

# Aynı sembol için aynı anda birden çok background refresh tetiklenmesin diye.
_refresh_in_progress: set[str] = set()
_refresh_lock = threading.Lock()


def _cache_get(full_key: str) -> tuple[dict, float] | None:
    return cache.get(full_key)


def _cache_set(full_key: str, data: dict, ttl: int) -> None:
    cache.set(full_key, data, ttl)


# ── Negatif cache ("bu sembol şu an hiçbir kaynaktan gelmiyor") ──────────────
# Neden: 429 sürerken BIST/kripto sembolleri HİÇBİR kaynaktan gelmiyordu ama
# her istek tüm zinciri (yfinance indirmesi + yedekler) baştan deniyordu →
# canlıda ölçüldü: /portfolio 4,2 sn · /performance 10,6 sn · /health 8,7 sn
# (cache SICAKKEN). Başarısızlığı kısa süre hatırlayınca istek yolu anında
# döner; arka plan işçisi (refresh_*) bu bayrağa BAKMAZ, denemeye devam eder →
# kaynak açılınca veri kendiliğinden geri gelir.
_MISS_TTL_SECONDS = 600
_M = "mkt:miss:"


def _miss_key(kind: str, symbol: str) -> str:
    return f"{_M}{kind}:{symbol}"


def _recently_failed(kind: str, symbol: str) -> bool:
    return _cache_get(_miss_key(kind, symbol)) is not None


def _mark_failed(kind: str, symbols: list[str]) -> None:
    for sym in symbols:
        _cache_set(_miss_key(kind, sym), {"failed": True}, _MISS_TTL_SECONDS)


# ── Fiyat (quote) ────────────────────────────────────────────────────────────
# Ad cache'i PAYLAŞILAN cache'te de tutulur: süreç-içi dict her restart'ta
# (ücretsiz katman sık uyanır) sıfırlanıyordu → her uyanışta yeniden `.info`.
# Ad değişmez → uzun TTL.
_N = "mkt:n:"          # name key prefix
_NAME_TTL_SECONDS = 30 * 24 * 3600
_names_in_progress: set[str] = set()


# Şifreli Yahoo sembollerinin Türkçe karşılığı. Frontend'de zaten var
# (SymbolDisplay._labels) ama backend adı AI Koç'a ve haber sorgularına da
# gidiyor: toplu quote ucu bunlara Yahoo'nun KONTRAT adını veriyor
# ("GC=F" → "Gold Dec 26"), yani "ham sembol yerine anlaşılır ad" düzeltmesi
# (6. tur) emtia/dövizde yeniden bozulurdu.
_ENCODED_NAMES = {
    "GC=F": "Altın (ons)",
    "SI=F": "Gümüş (ons)",
    "CL=F": "Ham Petrol",
    "USDTRY=X": "Dolar/TL",
    "EURTRY=X": "Euro/TL",
    "GBPTRY=X": "Sterlin/TL",
    "^GSPC": "S&P 500",
    "^IXIC": "Nasdaq Composite",
    "^DJI": "Dow Jones",
    "^XU100": "BIST 100",
    "XU100.IS": "BIST 100",
}


def _catalog_name(symbol: str) -> str | None:
    """Ağ GEREKTİRMEYEN ad kaynakları: şifreli sembol sözlüğü + BIST ve TEFAS
    fon katalogları (yerel)."""
    encoded = _ENCODED_NAMES.get(symbol)
    if encoded:
        return encoded
    if symbol.endswith(".IS"):
        from app.services.bist_catalog import CATALOG
        return CATALOG.get(symbol[:-3])
    if symbol.endswith(fund_catalog.SUFFIX):
        return fund_catalog.name_of(symbol)
    if gold_catalog.is_gold_suffix(symbol):
        return gold_catalog.name_of(symbol)
    return None


def _known_name(symbol: str) -> str | None:
    """Bilinen adı ağ İSTEĞİ ATMADAN döndürür (süreç-içi → paylaşılan cache →
    yerel katalog). Yoksa None — çağıran sembolü kullanır."""
    name = _name_cache.get(symbol)
    if name and name != symbol:
        return name
    hit = _cache_get(_N + symbol)
    if hit and isinstance(hit[0], str) and hit[0] != symbol:
        _name_cache[symbol] = hit[0]
        return hit[0]
    cat = _catalog_name(symbol)
    if cat:
        _name_cache[symbol] = cat
        _cache_set(_N + symbol, cat, _NAME_TTL_SECONDS)
        return cat
    return None


def _resolve_name(symbol: str) -> str:
    """Adı ağdan çözer. Sıra: yerel katalog → Finnhub profil (ABD; Render'da
    çalışır) → yfinance `.info` (Render IP'sinde çoğu zaman BLOKLU, son çare).
    Sonuç kalıcı cache'lenir."""
    known = _known_name(symbol)
    if known:
        return known
    name = None
    if _is_us_equity(symbol):
        try:
            from app.services import finnhub_service
            profile = finnhub_service.get_profile(symbol)
            name = (profile or {}).get("name") or None
        except Exception as exc:
            logger.debug(f"Finnhub ad çözümü atlandı ({symbol}): {exc}")
    if not name:
        try:
            info = yf.Ticker(symbol).info
            name = info.get("longName") or info.get("shortName") or None
        except Exception:
            name = None
    name = name or symbol
    _name_cache[symbol] = name
    if name != symbol:
        _cache_set(_N + symbol, name, _NAME_TTL_SECONDS)
    return name


def _schedule_name_resolution(symbols: list[str]) -> None:
    """Adı bilinmeyen sembollerin adını ARKA PLANDA çözer (batch fiyat yolu
    yanıtı beklemesin). Bir sonraki açılışta gerçek ad görünür."""
    with _refresh_lock:
        todo = [s for s in symbols
                if _known_name(s) is None and s not in _names_in_progress]
        for s in todo:
            _names_in_progress.add(s)
    if not todo:
        return

    def _work() -> None:
        try:
            for sym in todo:
                try:
                    _resolve_name(sym)
                except Exception as exc:
                    logger.debug(f"Ad çözümü atlandı ({sym}): {exc}")
        finally:
            with _refresh_lock:
                for s in todo:
                    _names_in_progress.discard(s)

    threading.Thread(target=_work, daemon=True).start()


def _ensure_name(symbol: str) -> str:
    """Şirket adını cache'ten döndürür; yoksa bir kez ağdan çözer. Tek-sembol
    path (get_stock_data / /market/price) gerçek adı garanti etmek için
    kullanır; batch path (get_stock_prices/_named) ağ İSTEMEZ — bilineni
    verir, bilinmeyeni arka planda çözer."""
    known = _known_name(symbol)
    if known:
        return known
    return _resolve_name(symbol)


def _fetch_stock_data(symbol: str) -> dict:
    """Tek sembol yfinance fiyatı (BLOCKING, history-only). company_name burada
    _name_cache'ten okunur (yoksa sembol); gerçek ad get_stock_data'da overlay
    edilir → cache'lenen değerin adı batch ile aynı sözleşmeye uyar."""
    ticker = yf.Ticker(symbol)
    # 5d (2d değil): gece/BIST kapalıyken "2d" tek bar döndürüp günlük değişimi
    # 0 gösteriyordu (THYAO/ASELS "Bugün %0"). 5d son 2 işlem günü için tampon.
    hist = ticker.history(period="5d")
    # NaN kapanışları AT: BIST kapalıyken yfinance son barı NaN döndürebiliyor
    # → iloc[-1] NaN → fiyat NaN (TÜPRAŞ'ta 500 / "veri alınamadı"). Son
    # GEÇERLİ kapanışı kullan; hiç geçerli kapanış yoksa 404 (graceful).
    closes = hist["Close"].dropna() if not hist.empty else None
    if closes is None or closes.empty:
        raise HTTPException(status_code=404, detail=f"Sembol bulunamadı: {symbol}")
    current_price = float(closes.iloc[-1])
    # Dünkü kapanış YOKSA günlük değişim BİLİNMİYOR demektir; 0.0 basmak
    # arayüzde "bugün hiç oynamadı" diye okunuyordu → bayrakla işaretle.
    change_known = False
    if len(closes) >= 2:
        prev_close = float(closes.iloc[-2])
        change_percent = ((current_price - prev_close) / prev_close) * 100 \
            if prev_close else 0.0
        change_known = bool(prev_close)
    else:
        change_percent = 0.0
    return {
        "symbol": symbol,
        "company_name": _name_cache.get(symbol, symbol),
        "current_price": round(current_price, 2),
        "change_percent": round(change_percent, 2),
        "change_available": change_known,
    }


# ── GERÇEK toplu fiyat: TEK istekte N sembol (Yahoo v7/quote) ───────────────
# 4 Eyl (10. tur) ölçümü: 54 sembol (ABD + BIST + kripto + altın + FX) TEK
# istekte **1,09 sn**, eksiksiz döndü — fiyat, önceki kapanış, değişim yüzdesi
# ve şirket adı dahil.
#
# ⚠️ `yf.download` "batch" adını taşır ama gerçekte sembol BAŞINA bir
# `/v8/finance/chart/` isteği atar (ölçüldü: 5 sembol = 5 istek, 10 = 10).
# 51 sembollük sinyal taraması = 51 Yahoo isteği → Render'ın PAYLAŞILAN çıkış
# IP'sinde 429'un asıl kaynağı buydu. Bu uç istek sayısını ~50 kat düşürür.
#
# Uç crumb+çerez ister: ÇIPLAK istek 429 alıyor (ölçüldü), yfinance'in kendi
# oturumu (YfData) ile 200 dönüyor → oturum ondan ödünç alınıyor. Uç kapanırsa
# çağıran eski `yf.download` yoluna düşer (aşağıda yedek olarak duruyor).
_QUOTE_PATH = "/v7/finance/quote"
_QUOTE_DIRECT = f"https://query2.finance.yahoo.com{_QUOTE_PATH}"
_QUOTE_CHUNK = 50          # tek istekte gönderilen sembol sayısı
_QUOTE_TIMEOUT = 20
_quote_session = None
# İlk chunk'ta hangi uç 200 verdiyse sonrakiler önce onu dener (her chunk'ta
# baştan sıraya girmesin).
_quote_url_pref: str | None = None


def _quote_urls() -> list[str]:
    """Denenecek quote uçları, sırayla.

    `YAHOO_PROXY_BASE` tanımlıysa ÖNCE vekil (Cloudflare Worker): Yahoo,
    Render'ın paylaşılan çıkış IP'sini 429'luyor — 51 istek 1 isteğe indi ama
    o tek istek de aynı cezalı IP'den gidiyor. Vekil başarısız olursa (yol
    izin listesinde değil, çerez düşmüş, Worker kurulu değil) doğrudan Yahoo
    denenir → davranış en kötü ihtimalle bugünküne döner.

    ⚠️ Vekil bu uçta ancak `Cookie` başlığını İLETİRSE çalışır (v7/quote çerez
    + crumb ister); Worker'da o iletim var (infra/cloudflare-worker)."""
    from app.services import yahoo_chart_service

    urls: list[str] = []
    if yahoo_chart_service.via_proxy():
        urls.append(f"{yahoo_chart_service.base_url()}{_QUOTE_PATH}")
    urls.append(_QUOTE_DIRECT)
    if _quote_url_pref in urls:
        urls.remove(_quote_url_pref)
        urls.insert(0, _quote_url_pref)
    return urls


def _yf_session():
    """yfinance'in çerez/crumb yöneten oturumu (bir kez kurulur)."""
    global _quote_session
    if _quote_session is None:
        import yfinance.data as yf_data
        _quote_session = yf_data.YfData()
    return _quote_session


def _quote_to_record(q: dict) -> tuple[str, dict] | None:
    """v7/quote kaydını market_data sözleşmesine çevirir (saf; ağ yok)."""
    sym = q.get("symbol")
    price = q.get("regularMarketPrice")
    if not sym or price is None:
        return None
    prev = q.get("regularMarketPreviousClose")
    change = q.get("regularMarketChangePercent")
    if change is None:
        change = ((price - prev) / prev * 100) if prev else 0.0
    # Yerel katalog adı (BIST/fon) ÖNCELİKLİ: Yahoo bazı sembollerde kontrat
    # adı veriyor (GC=F → "Gold Dec 26"). Katalogta yoksa Yahoo'nun adı bedava
    # geldi → `.info` çağrısına gerek kalmaz (o uç Render'da bloklu, sembol
    # başına 0,6-3 sn yiyor).
    name = _known_name(sym) or q.get("longName") or q.get("shortName")
    if name and name != sym:
        _name_cache.setdefault(sym, name)
    return sym, {
        "symbol": sym,
        "company_name": name or sym,
        "current_price": round(float(price), 2),
        "change_percent": round(float(change), 2),
        # Önceki kapanış yoksa günlük değişim BİLİNMİYOR (sıfır basma).
        "change_available": prev is not None,
    }


def quote_source() -> str | None:
    """Toplu fiyat çağrısı en son HANGİ uçtan başarılı oldu?
    "proxy" (Cloudflare Worker) · "direct" (doğrudan Yahoo) · None (henüz
    çağrı yok). /health bunu gösteriyor: vekil kurulduktan sonra gerçekten
    kullanılıp kullanılmadığı tahmine kalmasın."""
    if not _quote_url_pref:
        return None
    return "direct" if _quote_url_pref == _QUOTE_DIRECT else "proxy"


def _proxy_quote_auth(session) -> dict | None:
    """Vekile giderken taşınacak çerez + crumb.

    ÖLÇÜLDÜ (7 Eyl): `/v7/finance/quote` vekil üzerinden **401** dönüyordu,
    doğrudan Yahoo'ya giderken 200. Sebep yfinance'in oturumu DEĞİL, çerez
    kavanozunun alan adı kuralı: çerez `.yahoo.com` için saklanıyor, istek
    `…workers.dev`e gidince kavanoz onu TAKMIYOR → Yahoo kimliksiz istek
    görüp 401 veriyor. Worker `Cookie` başlığını zaten iletiyor (izin listesi
    doğru), ama ortada iletilecek çerez olmuyordu. Sonuç: toplu fiyat her
    turda önce vekilde 401 yiyip Render'ın CEZALI IP'sine düşüyordu — yani
    vekilin varlık sebebi bu uçta hiç işlemiyordu.

    Çözüm: vekile giderken çerezi ELLE `Cookie` başlığına koy, crumb'ı da
    açıkça parametreye ekle (ikisi eşleşmek zorunda: crumb o çereze bağlı).

    yfinance iç alanlarına dokunuyoruz (`_cookie`, `_get_cookie_and_crumb`);
    sürüm değişirse None döner ve davranış bugünküne (doğrudan Yahoo) döner.
    """
    try:
        crumb, _strategy = session._get_cookie_and_crumb()
        cookie = session._cookie
        if not crumb or cookie is None:
            return None
        name = getattr(cookie, "name", None)
        value = getattr(cookie, "value", None)
        if not name or not value:
            return None
        return {"crumb": crumb, "cookie": f"{name}={value}"}
    except Exception as exc:
        logger.debug(f"Vekil çerezi hazırlanamadı: {exc}")
        return None


def _quote_get(session, url: str, symbols_param: str, proxy_auth: dict | None):
    """Tek quote isteği. Vekil URL'inde çerez+crumb elle taşınır; doğrudan
    Yahoo'da yfinance'in kendi mekanizması (kavanoz + crumb) kullanılır."""
    params = {"symbols": symbols_param}
    if url != _QUOTE_DIRECT and proxy_auth:
        return session._session.get(
            url,
            params={**params, "crumb": proxy_auth["crumb"]},
            headers={"Cookie": proxy_auth["cookie"]},
            timeout=_QUOTE_TIMEOUT,
        )
    return session.get(url, params=params, timeout=_QUOTE_TIMEOUT)


def _fetch_quotes_batch(symbols: list[str]) -> dict[str, dict]:
    """N sembolü 50'lik parçalarla TEK istekte çeker. Hata/429 → kısmi (ya da
    boş) sonuç; çağıran eksikleri eski yolla tamamlar."""
    out: dict[str, dict] = {}
    if not symbols:
        return out
    try:
        session = _yf_session()
    except Exception as exc:
        logger.warning(f"Toplu quote oturumu kurulamadı: {exc}")
        return out

    proxy_auth = _proxy_quote_auth(session)

    global _quote_url_pref
    for i in range(0, len(symbols), _QUOTE_CHUNK):
        chunk = symbols[i:i + _QUOTE_CHUNK]
        results = None
        for url in _quote_urls():
            try:
                resp = _quote_get(session, url, ",".join(chunk), proxy_auth)
            except Exception as exc:
                logger.warning(f"Toplu quote hatası ({url}): {exc}")
                continue
            if resp.status_code != 200:
                logger.warning(
                    f"Toplu quote HTTP {resp.status_code} ({url}, "
                    f"{len(chunk)} sembol)")
                continue
            try:
                results = (resp.json().get("quoteResponse") or {}).get("result") or []
            except Exception as exc:
                logger.warning(f"Toplu quote gövdesi okunamadı ({url}): {exc}")
                continue
            _quote_url_pref = url
            break
        if results is None:
            # Hiçbir uç vermedi → kalan chunk'ları denemeye gerek yok, çağıran
            # eksikleri eski yolla tamamlar.
            break
        for item in results:
            rec = _quote_to_record(item)
            if rec:
                out[rec[0]] = rec[1]
    return out


def _fetch_many(symbols: list[str]) -> dict[str, dict]:
    """Çok sembol fiyatı — önce TEK istekli toplu uç, eksik kalan sembollerde
    eski sembol-başına-istek yolu (yedek)."""
    # TEFAS fonları Yahoo'da HİÇ yok (kapsam sorunu) → batch'i kirletmesin,
    # yedek zincirinde fon kaynağına gider.
    syms = [s.upper() for s in symbols
            if not fund_catalog.is_fund_symbol(s)
            and not gold_catalog.is_gold_suffix(s)]
    if not syms:
        return {}
    out = _fetch_quotes_batch(syms)
    missing = [s for s in syms if s not in out]
    if missing:
        if out:
            logger.debug(
                f"Toplu quote {len(out)}/{len(syms)} sembolü verdi; "
                f"{len(missing)} sembol eski yola düşüyor")
        out.update(_fetch_many_via_download(missing))
    return out


def _fetch_many_via_download(symbols: list[str]) -> dict[str, dict]:
    """YEDEK yol: yf.download. "Batch" görünür ama sembol BAŞINA bir chart
    isteği atar — yalnız toplu uç yanıt vermediğinde kullanılır.

    company_name `.info`'dan gelmez → _name_cache varsa oradan, yoksa sembol.
    Kısmi başarısızlık sembol bazında atlanır (çağıran fallback'ler — portföyde
    avg_cost). Hata → boş dict (çağıran tek-tek yola düşebilir)."""
    syms = list(symbols)
    out: dict[str, dict] = {}
    if not syms:
        return out
    try:
        df = yf.download(
            # 5d (2d değil): gece/BIST kapalıyken "2d" tek bar → günlük değişim 0.
            syms, period="5d", interval="1d", group_by="ticker",
            threads=True, progress=False, auto_adjust=True,
        )
    except Exception as exc:
        logger.warning(f"Batch download hatası: {exc}")
        return out
    if df is None or df.empty:
        return out

    multi = isinstance(df.columns, pd.MultiIndex)
    level0 = set(df.columns.get_level_values(0)) if multi else set()
    for sym in syms:
        try:
            if multi:
                if sym not in level0:
                    continue
                sub = df[sym]
            else:
                sub = df  # tek sembol → düz kolonlar
            closes = sub["Close"].dropna()
            if closes.empty:
                continue
            current = float(closes.iloc[-1])
            prev = float(closes.iloc[-2]) if len(closes) >= 2 else None
            change = ((current - prev) / prev * 100) if prev else 0.0
            out[sym] = {
                "symbol": sym,
                "company_name": _name_cache.get(sym, sym),
                "current_price": round(current, 2),
                "change_percent": round(change, 2),
                # Tek bar geldiyse (gece/borsa kapalı) değişim BİLİNMİYOR.
                "change_available": bool(prev),
            }
        except Exception as exc:
            logger.debug(f"Batch parse atlandı ({sym}): {exc}")
    return out


# ── Pre/Post-market (uzatılmış seans) ────────────────────────────────────────
# Yahoo `.info`'daki preMarketPrice Render IP'sinde bloklu; ama chart-endpoint
# (`history(prepost=True)`) Render'da ÇALIŞIR → uzatılmış seans fiyatını oradan al.
# Yalnız ABD hisseleri + yalnız pre/post saatlerinde; portföyün current_price'ı
# (normal seans kapanışı) DEĞİŞMEZ — bu ayrı bir overlay'dir.
_ET = ZoneInfo("America/New_York")
_EXT_TTL_SECONDS = 45  # pre/post fiyat hızlı oynar → kısa cache
_E = "mkt:ext:"        # extended (pre/post) key prefix


def _us_market_state(now_et: datetime | None = None) -> str:
    """ABD hisse piyasası durumu (ET saatine göre). Tatilleri yok sayar (kabul
    edilebilir yaklaşım). PRE 04:00–09:30 · REGULAR 09:30–16:00 · POST 16:00–20:00."""
    now = now_et or datetime.now(_ET)
    if now.weekday() >= 5:  # Cmt/Paz
        return "CLOSED"
    mins = now.hour * 60 + now.minute
    if 4 * 60 <= mins < 9 * 60 + 30:
        return "PRE"
    if 9 * 60 + 30 <= mins < 16 * 60:
        return "REGULAR"
    if 16 * 60 <= mins < 20 * 60:
        return "POST"
    return "CLOSED"


def _is_us_equity(symbol: str) -> bool:
    """ABD hissesi mi? BIST (.IS / nokta), kripto (-USD), döviz (=X), emtia (=F) hariç."""
    s = symbol.upper()
    return "." not in s and "=" not in s and not s.endswith("-USD")


# ── Piyasa durumu (tüm varlık sınıfları) ─────────────────────────────────────
# `market_state` eskiden YALNIZ ABD hisselerinde dolduruluyordu (pre/post
# overlay'in yan ürünüydü) → BIST, kripto ve altın için null geliyordu; UI
# "açık mı kapalı mı" diyemiyordu. Her sınıf kendi takvimine göre yanıtlanır.
# Tatiller yok sayılır (ABD tarafında da öyle — kabul edilen yaklaşım).
_TR = ZoneInfo("Europe/Istanbul")
# BIST sürekli müzayede 10:00–18:00 (kapanış seansı sonrası veri değişmez).
_BIST_OPEN_MIN = 10 * 60
_BIST_CLOSE_MIN = 18 * 60


def _bist_market_state(now_tr: datetime | None = None) -> str:
    now = (now_tr.astimezone(_TR) if now_tr else datetime.now(_TR))
    if now.weekday() >= 5:
        return "CLOSED"
    mins = now.hour * 60 + now.minute
    return "REGULAR" if _BIST_OPEN_MIN <= mins < _BIST_CLOSE_MIN else "CLOSED"


def market_state_of(symbol: str, now: datetime | None = None) -> str | None:
    """Sembolün ait olduğu piyasanın durumu; bilinmiyorsa None (UI çizmez).

    Kripto 7/24 açıktır. Döviz/emtia vadelileri hafta içi kesintisiz sayılır
    (gerçek takvim Pazar akşamı–Cuma akşamı; hafta sonu kapalı yaklaşımı
    kullanıcı için doğru cevabı verir). TEFAS fonunun seansı yoktur (günde tek
    fiyat) → None."""
    s = (symbol or "").upper()
    if fund_catalog.is_fund_symbol(s):
        return None
    # Fiziki altının borsa seansı yok (kuyumcu/serbest piyasa) → nokta çizme.
    if gold_catalog.is_gold_suffix(s):
        return None
    if s.endswith("-USD"):
        return "REGULAR"
    if s.endswith(".IS") or s.startswith("^X"):
        return _bist_market_state(now)
    if s.endswith("=X") or s.endswith("=F"):
        ref = now.astimezone(_TR) if now else datetime.now(_TR)
        return "CLOSED" if ref.weekday() >= 5 else "REGULAR"
    if _is_us_equity(s):
        # ⚠️ Saat dilimi ÇEVRİLMELİ: _us_market_state ham `hour` okuyor.
        return _us_market_state(now.astimezone(_ET) if now else None)
    return None


def _fetch_extended(symbol: str, regular_price: float | None) -> dict | None:
    """Pre/post-market son fiyatı (chart-endpoint, Render'da çalışır). Değişim,
    normal seans kapanışına (regular_price) göre. Son bar normal seans içindeyse
    ya da veri yoksa None."""
    try:
        h = yf.Ticker(symbol).history(period="1d", interval="5m", prepost=True)
        if h is None or h.empty:
            return None
        closes = h["Close"].dropna()
        if closes.empty:
            return None
        last_ts = closes.index[-1].tz_convert(_ET)
        mins = last_ts.hour * 60 + last_ts.minute
        if 9 * 60 + 30 <= mins < 16 * 60:  # son bar normal seans → uzatılmış değil
            return None
        ext_price = float(closes.iloc[-1])
        chg = ((ext_price - regular_price) / regular_price * 100) \
            if regular_price else 0.0
        return {
            "extended_price": round(ext_price, 2),
            "extended_change_percent": round(chg, 2),
        }
    except Exception as exc:
        logger.debug(f"Extended-hours atlandı ({symbol}): {exc}")
        return None


def _with_extended(symbol: str, quote: dict) -> dict:
    """ABD hissesi + pre/post seansındaysa uzatılmış fiyatı overlay eder
    (market_state + extended_price + extended_change_percent). Diğer sembol/
    saatlerde quote'u aynen döner (market_state yalnız ABD hissesinde eklenir)."""
    state = market_state_of(symbol)
    out = {**quote, "market_state": state} if state else dict(quote)
    if not _is_us_equity(symbol):
        return out
    if state in ("PRE", "POST"):
        cached = _cache_get(_E + symbol)
        if cached and (time.time() - cached[1] < _EXT_TTL_SECONDS):
            ext = cached[0]
        else:
            ext = _fetch_extended(symbol, quote.get("current_price"))
            if ext:
                _cache_set(_E + symbol, ext, _EXT_TTL_SECONDS)
        if ext:
            out.update(ext)
    return out


def _schedule_batch_refresh(symbols: list[str]) -> None:
    """Stale sembolleri TEK batch ile arka planda (daemon thread) yeniler.
    FastAPI BackgroundTasks gerektirmez → portföy dahil her path SWR kazanır.
    Aynı sembol için eşzamanlı tekrar tetiklenmez."""
    with _refresh_lock:
        todo = [s.upper() for s in symbols if s.upper() not in _refresh_in_progress]
        for s in todo:
            _refresh_in_progress.add(s)
    if not todo:
        return

    def _work() -> None:
        try:
            fetched = _fetch_many(todo)
            for sym, data in fetched.items():
                _cache_set(_Q + sym, data, _KEEP_TTL_SECONDS)
            if fetched:
                logger.debug(f"Cache yenilendi (batch): {', '.join(fetched)}")
        except Exception as exc:
            logger.warning(f"Background batch refresh hatası: {exc}")
        finally:
            with _refresh_lock:
                for s in todo:
                    _refresh_in_progress.discard(s)

    threading.Thread(target=_work, daemon=True).start()


def get_stock_data(symbol: str, background_tasks: BackgroundTasks | None = None) -> dict:
    """Stale-while-revalidate ile tek sembol fiyatı.

    - Fresh (<60sn): direkt döner.
    - Stale (<10dk): stale veriyi döner + arka planda (daemon) yeniler.
    - Yok/çok eski: yfinance'i bekler.

    `background_tasks` artık gerekmez (daemon thread ile yenileniyor); imza
    geriye uyum için korunuyor."""
    symbol = symbol.upper()
    now = time.time()

    cached = _cache_get(_Q + symbol)
    if cached:
        data, ts = cached
        age = now - ts
        if age < _FRESH_TTL_SECONDS:
            return _with_extended(symbol, {**data, "company_name": _ensure_name(symbol)})
        if age < _STALE_TTL_SECONDS:
            _schedule_batch_refresh([symbol])
            return _with_extended(symbol, {**data, "company_name": _ensure_name(symbol)})

    if gold_catalog.is_gold_suffix(symbol):
        # Fiziki altın/gümüş Yahoo'da YOK (GC=F ons cinsinden VADELİ altın,
        # Türkiye serbest piyasası değil) → tek kaynağı gold_rates_service.
        if not gold_catalog.is_gold_symbol(symbol):
            raise HTTPException(
                status_code=404,
                detail=f"Fiziki varlık bulunamadı: {symbol}")
        from app.services import gold_rates_service
        gold_quote = gold_rates_service.get_quotes([symbol]).get(symbol)
        if gold_quote:
            _cache_set(_Q + symbol, gold_quote, _KEEP_TTL_SECONDS)
            return gold_quote
        raise HTTPException(
            status_code=503,
            detail="Altın fiyatına şu an ulaşılamıyor, birazdan tekrar "
                   "deneyin.")

    if fund_catalog.is_fund_symbol(symbol):
        # Fonun yfinance'te karşılığı yok → doğrudan TEFAS. Bulunamazsa
        # aşağıdaki "sembol bulunamadı" yolu değil, dürüst 503 döner
        # (kod katalogda var ama kaynak cevap vermiyor demektir).
        fund_quote = _fallback_quotes([symbol]).get(symbol)
        if fund_quote:
            _cache_set(_Q + symbol, fund_quote, _KEEP_TTL_SECONDS)
            return {**fund_quote, "company_name": _ensure_name(symbol)}
        if not fund_catalog.is_known_code(fund_catalog.code_of(symbol)):
            raise HTTPException(
                status_code=404,
                detail=f"Fon bulunamadı: {fund_catalog.code_of(symbol)} — "
                       f"TEFAS'ta bu kodla bir yatırım fonu yok.")
        raise HTTPException(
            status_code=503,
            detail="TEFAS fon fiyatına şu an ulaşılamıyor, birazdan tekrar "
                   "deneyin.")

    try:
        result = _fetch_stock_data(symbol)
        _cache_set(_Q + symbol, result, _KEEP_TTL_SECONDS)
        # Gerçek adı overlay et (batch cache adı sembol bırakmış olabilir).
        return _with_extended(symbol, {**result, "company_name": _ensure_name(symbol)})
    except Exception as exc:
        # Batch yolunda (get_stock_prices) yedek kaynaklar vardı ama TEK sembol
        # yolunda yoktu → hisse detayı/arama Yahoo 429'ladığında 400 dönüyordu.
        fallback = _fallback_quotes([symbol]).get(symbol)
        if fallback:
            _cache_set(_Q + symbol, fallback, _KEEP_TTL_SECONDS)
            return _with_extended(
                symbol, {**fallback, "company_name": _ensure_name(symbol)})
        if isinstance(exc, HTTPException):
            raise
        # yfinance HER hatada "Too Many Requests" metnini döndürüyor (kendi
        # global durumundan) → OLMAYAN sembolde de kullanıcı "çok fazla istek"
        # görüyordu. Canlıda doğrulandı: uydurma ZZZZTEST.IS ile portföydeki
        # LTL.IS aynı mesajı veriyordu. Hangisi olduğunu SORUP doğru söyle.
        try:
            from app.services import yahoo_chart_service
            verdict = yahoo_chart_service.probe(symbol)
        except Exception:
            verdict = "unavailable"
        if verdict == "unknown":
            raise HTTPException(
                status_code=404,
                detail=f"Sembol bulunamadı: {symbol} — borsada bu kodla "
                       f"işlem gören bir varlık yok (kod yanlış ya da "
                       f"işlemden kaldırılmış olabilir).")
        raise HTTPException(
            status_code=503,
            detail="Fiyat kaynağına şu an ulaşılamıyor, birazdan tekrar "
                   "deneyin.")


def _fallback_quotes(symbols: list[str]) -> dict[str, dict]:
    """Yahoo'nun veremediği semboller için ikinci kaynak (Finnhub /quote).

    Yalnız ABD hisseleri: Finnhub ücretsiz tier BIST/emtia/kripto kapsamaz,
    boşuna çağrı yapılmaz. Sembol başına bir istek olduğu için liste kasten
    sınırlı tutulur — amaç Yahoo'yu taklit etmek değil, 429 anında portföyün
    fiyatsız kalmasını önlemek.
    """
    if not symbols:
        return {}

    out: dict[str, dict] = {}

    # TEFAS yatırım fonu (TLY.FON) → tek gerçek kaynağı TEFAS'ın kendi ucu.
    # Yahoo'nun kapsamadığı tek varlık sınıfı bu; sırada ÖNCE olması hem
    # doğru hem ucuz (fon serisi günde bir değişir, cache'ten döner).
    # Fiziki altın/gümüş (CEYREK.ALTIN …): Yahoo kapsamıyor, kaynağı
    # serbest piyasa. Toplu fiyat yolu buradan geçer.
    try:
        from app.services import gold_rates_service
        out.update(gold_rates_service.get_quotes(symbols))
    except Exception as exc:
        logger.debug(f"Fiziki altın kaynağı atlandı: {exc}")

    try:
        from app.services import fund_source_service
        out.update(fund_source_service.get_quotes(symbols))
    except Exception as exc:
        logger.debug(f"Fon kaynağı atlandı: {exc}")

    # Altın/gümüş → truncgil spot (tek istek, TR kaynağı Render'dan çalışıyor)
    metal_spot: dict[str, float] = {}
    try:
        from app.services import gold_rates_service
        metal_spot = gold_rates_service.spot_metal_usd(symbols)
        for sym, price in metal_spot.items():
            out[sym] = {"symbol": sym,
                        "company_name": _name_cache.get(sym, sym),
                        "current_price": price,
                        # Spot kaynak günlük değişimi VERMİYOR. Buraya 0.0
                        # yazmak arayüzde "+%0,00" basıyordu → kullanıcı
                        # "altın bugün hiç oynamamış" okuyordu (uydurma sıfır;
                        # oysa fiyat canlı oynuyordu). Değişim aşağıda chart
                        # barlarından TAMAMLANIR; gelmezse bayrak False kalır
                        # ve arayüz "Bugün" satırını hiç göstermez.
                        "change_percent": 0.0,
                        "change_available": False}
    except Exception as exc:
        logger.debug(f"Emtia yedeği atlandı: {exc}")

    # Kripto → keysiz borsa API'si (Coinbase USD paritesi, olmazsa Binance).
    # Yahoo 429'ladığında BTC/ETH "veri alınamadı" dönüyordu; kriptonun
    # ücretsiz ve güvenilir yedeği VAR, tek eksik bağlanmasıydı.
    try:
        from app.services import crypto_source_service
        for sym, quote in crypto_source_service.get_quotes(
                [s for s in symbols if s not in out]).items():
            out[sym] = {**quote,
                        "company_name": _name_cache.get(sym, sym)}
    except Exception as exc:
        logger.debug(f"Kripto yedeği atlandı: {exc}")

    # ABD hisseleri → Finnhub (sembol başına bir istek, üst sınırlı)
    targets = [s for s in symbols
               if s not in out and _is_us_equity(s)][:_FALLBACK_QUOTE_LIMIT]
    if targets:
        try:
            from app.services import finnhub_service
            if finnhub_service.available:
                def _one(sym: str):
                    try:
                        return sym, finnhub_service.get_quote(sym)
                    except Exception as exc:
                        logger.debug(f"Yedek fiyat atlandı ({sym}): {exc}")
                        return sym, None

                with ThreadPoolExecutor(max_workers=8) as ex:
                    for sym, q in ex.map(_one, targets):
                        if q:
                            out[sym] = {**q,
                                        "company_name": _name_cache.get(sym, sym)}
        except Exception as exc:
            logger.debug(f"Finnhub yedeği atlandı: {exc}")

    # Son halka: Yahoo'nun AÇIK chart ucuna yfinance'siz git (kurulmuşsa
    # Cloudflare Worker proxy'si üzerinden → Render'ın cezalı IP'si devre dışı).
    # BIST'in başka ücretsiz+güvenilir kaynağı olmadığı için asıl faydası orada.
    remaining = [s for s in symbols if s not in out]
    # Emtianın FİYATI spot kaynaktan geldi ama GÜNLÜK DEĞİŞİMİ orada yok →
    # onları da aynı chart isteğine kat ve YALNIZ değişimi devral (fiyat spot
    # kalır: iki farklı kaynak ama her biri kendi içinde tutarlı — değişim
    # chart'ın dünkü kapanışına göre hesaplanır, spot fiyata göre DEĞİL).
    need_change = [s for s in metal_spot
                   if s in out and not out[s].get("change_available", True)]
    ask = remaining + need_change
    if ask:
        try:
            from app.services import yahoo_chart_service
            for sym, quote in yahoo_chart_service.get_quotes(ask).items():
                if sym in need_change:
                    # Chart da dünkü kapanışı veremediyse (tek bar) bayrak
                    # False KALIR — sıfırı gerçek değişim gibi göstermeyelim.
                    if quote.get("change_available", True):
                        out[sym]["change_percent"] = quote["change_percent"]
                        out[sym]["change_available"] = True
                    continue
                out[sym] = {**quote,
                            "company_name": _name_cache.get(sym, sym)}
        except Exception as exc:
            logger.debug(f"Yahoo chart yedeği atlandı: {exc}")

    # Gerçek son halka: Yahoo (vekil dahil) tamamen düşerse BIST'i İş Yatırım'ın
    # açık günlük serisinden karşıla. Seans AÇIKKEN boş döner (o kaynakta gün
    # içi fiyat yok; dünkü kapanışı canlı fiyat gibi göstermeyiz) → kullanıcı
    # yine "Fiyat —" görür, uydurma rakam görmez.
    still_missing = [s for s in symbols if s not in out]
    if still_missing:
        try:
            from app.services import bist_source_service
            for sym, quote in bist_source_service.get_quotes(
                    still_missing).items():
                out[sym] = {**quote,
                            "company_name": _name_cache.get(sym, sym)}
        except Exception as exc:
            logger.debug(f"BIST yedeği atlandı: {exc}")

    if out:
        logger.info(f"Yedek fiyat kaynağı kullanıldı ({len(out)}): "
                    f"{', '.join(sorted(out))}")
    return out


def get_stock_prices(symbols: list[str]) -> dict[str, dict]:
    """Çok sembol için batch fiyat (portföy hot-path'i).

    Cache fresh/stale anında döner; stale set arka planda TEK batch ile yenilenir;
    eksik/expired set TEK bloklayan batch fetch ile çekilir (N ayrı HTTP yerine 1).
    Dönüş: {SYMBOL: {symbol, company_name, current_price, change_percent}}.
    Çekilemeyen semboller dönüşte yer almaz (çağıran fallback uygular)."""
    now = time.time()
    out: dict[str, dict] = {}
    stale: list[str] = []
    missing: list[str] = []

    for raw in symbols:
        sym = raw.upper()
        cached = _cache_get(_Q + sym)
        if cached:
            data, ts = cached
            age = now - ts
            if age < _FRESH_TTL_SECONDS:
                out[sym] = data
                continue
            if age < _KEEP_TTL_SECONDS:
                # Bayat ama gerçek fiyat: kullanıcıyı bekletmeden dön, arka
                # planda tazele. Kullanıcı isteği ASLA kaynak beklemesin.
                out[sym] = data
                stale.append(sym)
                continue
        missing.append(sym)

    # Yakın zamanda HİÇBİR kaynaktan gelmeyen sembolü istek yolunda tekrar
    # deneme (arka plan işçisi denemeye devam ediyor).
    attempt = [s for s in missing if not _recently_failed("q", s)]
    if attempt:
        # Birincil kaynak beklenmedik bir hata fırlatırsa YEDEĞE sıra gelmeden
        # tüm istek patlıyordu — yedeğin var olma sebebi tam da bu an.
        try:
            fetched = _fetch_many(attempt)
        except Exception as exc:
            logger.warning(f"Birincil fiyat kaynağı düştü: {exc}")
            fetched = {}
        for sym, data in fetched.items():
            _cache_set(_Q + sym, data, _KEEP_TTL_SECONDS)
            out[sym] = data
        # Yahoo'nun veremediklerini ikinci kaynaktan dene. Aksi halde portföy
        # o pozisyonları avg_cost'a düşürüyor → "%0,00 kâr/zarar" (fiyat =
        # maliyet) görünüyordu.
        for sym, data in _fallback_quotes(
                [s for s in attempt if s not in out]).items():
            _cache_set(_Q + sym, data, _KEEP_TTL_SECONDS)
            out[sym] = data
        _mark_failed("q", [s for s in attempt if s not in out])

    if stale:
        _schedule_batch_refresh(stale)

    return out


def get_stock_prices_named(symbols: list[str]) -> dict:
    """İstemcinin izleme listesi yolu: TEK çağrıda N sembol fiyatı + adı.

    Eskiden istemci her sembol için ayrı `/market/price/{sym}` atıyordu
    (8 sembol = 8 HTTP + her biri ad çözümü için `.info`) — açılışın en
    pahalı parçasıydı. Burada fiyatlar batch (yedek kaynak zinciri dahil),
    ad ağ İSTEĞİ ATMADAN bilinenden verilir; bilinmeyen adlar arka planda
    çözülür (sonraki açılışta görünür).

    Dönüş: {"quotes": [...istenen sırayla...], "missing": [...]}
    """
    syms: list[str] = []
    for raw in symbols:
        sym = raw.strip().upper()
        if sym and sym not in syms:
            syms.append(sym)
    if not syms:
        return {"quotes": [], "missing": []}

    data = get_stock_prices(syms)
    quotes = []
    for sym in syms:
        quote = data.get(sym)
        if not quote:
            continue
        quotes.append({**quote,
                       "company_name": _known_name(sym)
                       or quote.get("company_name") or sym})
    _schedule_name_resolution(syms)
    return {"quotes": quotes,
            "missing": [s for s in syms if s not in data]}


def prewarm_symbols(symbols: list[str]) -> None:
    """Startup'ta arka planda çağrılır — sembolleri TEK batch ile önceden ısıtır
    (eskiden sembol-sembol döngü). Halihazırda fresh olanlar atlanır."""
    now = time.time()
    todo: list[str] = []
    for raw in symbols:
        sym = raw.upper()
        cached = _cache_get(_Q + sym)
        if cached and (now - cached[1]) < _FRESH_TTL_SECONDS:
            continue
        todo.append(sym)
    if not todo:
        return
    fetched = _fetch_many(todo)
    # YEDEK ZİNCİRİ DE ARKA PLANDA: eskiden prewarm yalnız Yahoo'yu deniyordu →
    # Yahoo'nun veremediği semboller (kripto, BIST, 429 anında hepsi) hiç
    # ısıtılmıyor, yedek kaynak maliyeti KULLANICI İSTEĞİNDE ödeniyordu
    # (portföy ucu ölçümde 4-10 sn). Yedekler de burada çalışsın ki istek
    # yolunda cache dolu olsun.
    missing = [s for s in todo if s not in fetched]
    if missing:
        try:
            fetched.update(_fallback_quotes(missing))
        except Exception as exc:
            logger.debug(f"Prewarm yedek kaynak atlandı: {exc}")
    for sym, data in fetched.items():
        _cache_set(_Q + sym, data, _KEEP_TTL_SECONDS)
    logger.info(f"Prewarm OK ({len(fetched)}/{len(todo)}): {', '.join(fetched)}")


# ── Seri cache'lerinde tazeleme (kapanış + OHLCV) ────────────────────────────
# 4 Eylül ölçümü: soğuk /signals 10,0 sn, hemen ardından tam tarama 0,41 sn.
# Fark ne ısıtma ne de taramaydı — bu iki cache "stale-while-revalidate" DEĞİL
# "stale-if-error"du: kayıt 15 dakikadan eskiyse istek yolunda BLOKLAYAN batch
# çekim yapılıyor, eski kayıt yalnız çekim PATLARSA servis ediliyordu. Arka plan
# yenileyicisi de 30 dk boştan sonra duruyor (main._REFRESH_ACTIVE_WINDOW) →
# faturayı her sessizlik sonrası Sinyaller'e ilk giren kullanıcı ödüyordu.
# Fiyat ve temel oran cache'lerinde öğrenilen aynı kural: KAYIT ≠ TAZELİK.
# Bayat seri anında servis edilir (gerçek veri, sadece biraz eski), tazeleme
# arka planda TEK batch ile yapılır; yalnız hiç kayıt yoksa bloklanır.
# Temel oranlardan farklı olarak JITTER YOK: burada semboller tek batch'te
# iniyor, senkron bayatlama tek istek demek — dağıtmak batch'i parçalardı.
_SERIES_REFRESH_COOLDOWN = 120  # aynı seri için arka arkaya tur açma
_series_refresh_in_progress: set[str] = set()
_series_refresh_last: dict[str, float] = {}
_series_refresh_lock = threading.Lock()


def _schedule_series_refresh(kind: str, symbols: list[str], period: str = "") -> None:
    """Bayat seriyi arka planda (daemon thread) TEK batch ile tazeler.

    `kind`: "c" kapanış · "o" OHLCV. Aynı seri için eşzamanlı ikinci tur
    açılmaz; kaynak sürekli düşse bile her istekte yeni tur açılmasın diye
    `_SERIES_REFRESH_COOLDOWN` bekler. Tazeleme başarısızsa eldeki kayıt
    OLDUĞU GİBİ kalır (refresh_* yalnız çekebildiğini yazar) — geçici bir hata
    iyi veriyi silmez.
    """
    now = time.time()
    with _series_refresh_lock:
        todo: list[str] = []
        for sym in symbols:
            tag = f"{kind}:{sym}:{period}"
            if tag in _series_refresh_in_progress:
                continue
            if now - _series_refresh_last.get(tag, 0.0) < _SERIES_REFRESH_COOLDOWN:
                continue
            _series_refresh_in_progress.add(tag)
            todo.append(sym)
    if not todo:
        return

    def _work() -> None:
        try:
            if kind == "c":
                refresh_daily_closes(todo)
            else:
                refresh_daily_ohlcv(todo, period)
        except Exception as exc:
            logger.warning(f"Seri arka plan tazelemesi düştü ({kind}): {exc}")
        finally:
            done = time.time()
            with _series_refresh_lock:
                for sym in todo:
                    tag = f"{kind}:{sym}:{period}"
                    _series_refresh_in_progress.discard(tag)
                    _series_refresh_last[tag] = done

    threading.Thread(target=_work, daemon=True).start()


# ── Günlük kapanış serisi (paylaşılan, batch) ─────────────────────────────────
# Neden: benchmark + sinyal + sağlık yolları her biri SEMBOL BAŞINA ayrı
# `yf.Ticker().history()` çağırıyordu. 40 pozisyonlu bir portföyde tek sayfa
# açılışı 100+ Yahoo isteği demek → Yahoo Render IP'sini 429'luyor ("Too Many
# Requests"), getiriler 0.00 görünüyor, sayfa yavaşlıyor. Burada TEK
# `yf.download` ile hepsi çekilir ve paylaşılan cache'e yazılır.
_CLOSES_FRESH_SECONDS = 900              # 15 dk taze (günlük bar; sık değişmez)
_CLOSES_STALE_SECONDS = 7 * 24 * 3600    # 429'da bir haftaya kadar ESKİ veri servis et
_C = "mkt:c:"  # daily closes key prefix

# Benchmark 4 dönem sorar (1A/3A/6A/1Y). Her dönem için ayrı indirme = 4 batch.
# Bunun yerine TEK uzun pencere çekilir, kısa dönemler ondan DİLİMLENİR →
# dört sekme de aynı veriden beslenir, Yahoo'ya tek istek gider.
_CLOSES_WINDOW_DAYS = 400
_CLOSES_PERIOD = f"{_CLOSES_WINDOW_DAYS}d"


def _closes_key(symbol: str) -> str:
    return f"{_C}{symbol}"


def _slice_closes(series: dict[str, float], days: int) -> dict[str, float]:
    """Uzun seriden son `days` takvim gününü kes. Gün sayısı yetmiyorsa
    elde ne varsa onu döner (çağıran zaten <2 barı eler)."""
    if not series:
        return {}
    cutoff = (datetime.now() - timedelta(days=days + 5)).date().isoformat()
    return {d: c for d, c in series.items() if d >= cutoff}


def _download_closes(symbols: list[str]) -> dict[str, dict[str, float]]:
    """TEK yf.download ile N sembolün günlük kapanışları. {sym: {iso_gün: close}}.
    Hata/boş → {} (çağıran eski cache'e düşer)."""
    symbols = [s for s in symbols if not fund_catalog.is_fund_symbol(s)
               and not gold_catalog.is_gold_suffix(s)]
    if not symbols:
        return {}
    try:
        df = yf.download(
            symbols, period=_CLOSES_PERIOD, interval="1d", group_by="ticker",
            threads=True, progress=False, auto_adjust=True,
        )
    except Exception as exc:
        logger.warning(f"Kapanış batch hatası ({len(symbols)} sembol): {exc}")
        return {}
    if df is None or df.empty:
        return {}

    out: dict[str, dict[str, float]] = {}
    multi = isinstance(df.columns, pd.MultiIndex)
    level0 = set(df.columns.get_level_values(0)) if multi else set()
    for sym in symbols:
        try:
            if multi:
                if sym not in level0:
                    continue
                sub = df[sym]
            else:
                sub = df
            closes = sub["Close"].dropna()
            if closes.empty:
                continue
            # Takvim gününe indir: yfinance index'i borsaya göre tz-AWARE döner
            # (BIST=İstanbul, NYSE=New York) → çapraz-piyasa hizalama bozulurdu.
            ser = {d.date().isoformat(): float(v) for d, v in closes.items()
                   if v == v and abs(v) != float("inf")}
            if ser:
                out[sym] = ser
        except Exception as exc:
            logger.debug(f"Kapanış parse atlandı ({sym}): {exc}")
    return out


def refresh_daily_closes(symbols: list[str]) -> dict[str, dict[str, float]]:
    """Uzun pencereyi TEK batch ile çekip cache'e yazar (arka plan işçisi ve
    `get_daily_closes`'un cache-miss yolu buradan geçer). Dönen: çekilenler."""
    syms = sorted({s.upper() for s in symbols if s})
    if not syms:
        return {}

    # ÖNCE spark: `yf.download` adı "batch" ama sembol başına ayrı
    # `/v8/finance/chart/` isteği atıyor (10. turda ölçüldü, 5 sembol = 5
    # istek). `/v8/finance/spark` aynı seriyi 20'şerli TEK istekte veriyor →
    # 51 sembollük tarama 51 istek yerine 3. Vermediği sembol için eski yol
    # (`yf.download`) YEDEK olarak duruyor: davranış kaybı yok.
    fetched: dict[str, dict[str, float]] = {}
    spark_targets = [s for s in syms if not fund_catalog.is_fund_symbol(s)
                     and not gold_catalog.is_gold_suffix(s)]
    if spark_targets:
        try:
            from app.services import yahoo_chart_service
            fetched.update(yahoo_chart_service.get_daily_closes_batch(
                spark_targets, rng=_CLOSES_PERIOD))
        except Exception as exc:
            logger.debug(f"spark toplu kapanış atlandı: {exc}")

    still_missing = [s for s in syms if s not in fetched]
    if still_missing:
        fetched.update(_download_closes(still_missing))
    # TEFAS fonları (Yahoo kapsamıyor) → kendi kaynağından.
    funds = [s for s in syms if fund_catalog.is_fund_symbol(s)]
    if funds:
        try:
            from app.services import fund_source_service
            fetched.update(fund_source_service.get_daily_closes(funds))
        except Exception as exc:
            logger.debug(f"Fon kapanış kaynağı atlandı: {exc}")
    # Yahoo'nun veremediği KRİPTO sembollerini keysiz borsa API'sinden tamamla.
    remaining = [s for s in syms if s not in fetched]
    if remaining:
        try:
            from app.services import crypto_source_service
            fetched.update(crypto_source_service.get_daily_closes(remaining))
        except Exception as exc:
            logger.debug(f"Kripto kapanış yedeği atlandı: {exc}")
    remaining = [s for s in syms if s not in fetched]
    if remaining:
        try:
            from app.services import yahoo_chart_service
            # chart ucu "400d" kabul etmez; en yakın geçerli aralık 2y.
            fetched.update(
                yahoo_chart_service.get_daily_closes(remaining, period="2y"))
        except Exception as exc:
            logger.debug(f"Yahoo chart kapanış yedeği atlandı: {exc}")
    # BIST'in Yahoo dışı tek ücretsiz kaynağı (İş Yatırım günlük serisi).
    # Kapanış serisi tarih-etiketli olduğu için burada dürüstlük sorunu yok:
    # gün içi fiyat değil, resmi kapanış.
    remaining = [s for s in syms if s not in fetched]
    if remaining:
        try:
            from app.services import bist_source_service
            fetched.update(bist_source_service.get_daily_closes(remaining))
        except Exception as exc:
            logger.debug(f"BIST kapanış yedeği atlandı: {exc}")
    for sym, ser in fetched.items():
        _cache_set(_closes_key(sym), ser, _CLOSES_STALE_SECONDS)
    return fetched


def get_daily_closes(symbols: list[str], days: int) -> dict[str, dict[str, float]]:
    """N sembolün son `days` günlük kapanış serisi — batch + stale-while-revalidate.

    Tüm dönemler TEK uzun pencereden dilimlenir → 1A/3A/6A/1Y sekmeleri
    arasında gezinmek yeni indirme tetiklemez.

    Yahoo 429 verirse SESSİZCE BOŞ DÖNMEZ: elde son bilinen (eski) seri varsa
    onu döndürür. Aksi halde benchmark "+0,00%" gösteriyordu — kullanıcıya
    yanlış bilgi. Hiç veri yoksa sembol dönüşte yer almaz (çağıran dürüstçe
    'hesaplanamadı' der)."""
    syms = sorted({s.upper() for s in symbols if s})
    if not syms:
        return {}

    now = time.time()
    full: dict[str, dict[str, float]] = {}
    stale: list[str] = []
    missing: list[str] = []

    for sym in syms:
        cached = _cache_get(_closes_key(sym))
        if cached:
            data, ts = cached
            full[sym] = data  # bayat da olsa GERÇEK seri → anında servis
            if now - ts >= _CLOSES_FRESH_SECONDS:
                stale.append(sym)
            continue
        missing.append(sym)

    if stale:
        # Kullanıcı beklemez; tazeleme arka planda TEK batch.
        logger.debug(f"Kapanış bayat ({len(stale)} sembol) → arka planda tazeleniyor")
        _schedule_series_refresh("c", stale)

    # Elde HİÇ kayıt olmayan sembol → bloklayan çekim (ilk kurulum).
    attempt = [s for s in missing if not _recently_failed("c", s)]
    if attempt:
        fetched = refresh_daily_closes(attempt)
        full.update(fetched)
        _mark_failed("c", [s for s in attempt if s not in fetched])

    return {sym: _slice_closes(ser, days) for sym, ser in full.items() if ser}


# ── Günlük OHLCV (paylaşılan, batch) ──────────────────────────────────────────
# Teknik analiz / sinyal tarafı sembol başına `yf.Ticker().history("6mo")`
# çağırıyordu → 40 sembollü "Sinyaller" taraması 40 Yahoo isteği, hepsi 429
# yiyip sinyal listesi BOŞ kalıyordu ("Henüz sinyal yok"). Tek batch + cache.
_OHLCV_FRESH_SECONDS = 900               # 15 dk taze (günlük bar)
_OHLCV_STALE_SECONDS = 7 * 24 * 3600     # 429'da eski veriyle çalışmaya devam
_O = "mkt:o:"  # ohlcv key prefix


def _period_days(period: str) -> int:
    """'6mo'/'1y'/'400d' gibi yfinance dönemini yaklaşık takvim gününe çevirir
    (yedek kaynak pencereyi bar sayısıyla sınırlıyor)."""
    p = (period or "").strip().lower()
    try:
        if p.endswith("mo"):
            return int(float(p[:-2]) * 31)
        if p.endswith("y"):
            return int(float(p[:-1]) * 366)
        if p.endswith("d"):
            return int(float(p[:-1]))
    except ValueError:
        pass
    return 200


def _ohlcv_key(symbol: str, period: str) -> str:
    return f"{_O}{symbol}:{period}"


def _download_ohlcv(symbols: list[str], period: str) -> dict[str, dict]:
    """TEK yf.download ile N sembolün günlük OHLCV'si. Hata/boş → {}."""
    symbols = [s for s in symbols if not fund_catalog.is_fund_symbol(s)
               and not gold_catalog.is_gold_suffix(s)]
    if not symbols:
        return {}
    try:
        df = yf.download(
            symbols, period=period, interval="1d", group_by="ticker",
            threads=True, progress=False, auto_adjust=True,
        )
    except Exception as exc:
        logger.warning(f"OHLCV batch hatası ({len(symbols)} sembol): {exc}")
        return {}
    if df is None or df.empty:
        return {}

    out: dict[str, dict] = {}
    multi = isinstance(df.columns, pd.MultiIndex)
    level0 = set(df.columns.get_level_values(0)) if multi else set()
    for sym in symbols:
        try:
            if multi:
                if sym not in level0:
                    continue
                sub = df[sym]
            else:
                sub = df
            sub = sub.dropna(subset=["Open", "High", "Low", "Close"])
            if sub.empty:
                continue
            out[sym] = {
                "date": [d.date().isoformat() for d in sub.index],
                "open": [float(v) for v in sub["Open"]],
                "high": [float(v) for v in sub["High"]],
                "low": [float(v) for v in sub["Low"]],
                "close": [float(v) for v in sub["Close"]],
                "volume": [float(v) if v == v else 0.0 for v in sub["Volume"]],
            }
        except Exception as exc:
            logger.debug(f"OHLCV parse atlandı ({sym}): {exc}")
    return out


def refresh_daily_ohlcv(symbols: list[str], period: str = "6mo") -> dict[str, dict]:
    """OHLCV'yi TEK batch ile çekip cache'e yazar (arka plan işçisi ve
    `get_daily_ohlcv`'nin cache-miss yolu buradan geçer)."""
    syms = sorted({s.upper() for s in symbols if s})
    if not syms:
        return {}
    fetched = _download_ohlcv(syms, period)
    # TEFAS fonu: gün içi aralığı YOK → birim pay değeri O=H=L=C, hacim 0
    # (uydurma mum/hacim basılmaz; sinyal tarafı fonu data_limited sayar).
    funds = [s for s in syms if fund_catalog.is_fund_symbol(s)]
    if funds:
        try:
            from app.services import fund_source_service
            fetched.update(fund_source_service.get_daily_ohlcv(
                funds, days=_period_days(period)))
        except Exception as exc:
            logger.debug(f"Fon OHLCV kaynağı atlandı: {exc}")
    # Sinyal motoru 6 aylık mum istiyor; Yahoo 429'ladığında kripto sinyali
    # HİÇ üretilemiyordu (Finnhub ücretsiz tier mum vermiyor). Kripto için
    # keysiz borsa API'si mumu veriyor → boşluğu burada kapat.
    remaining = [s for s in syms if s not in fetched]
    if remaining:
        try:
            from app.services import crypto_source_service
            fetched.update(crypto_source_service.get_daily_ohlcv(
                remaining, days=_period_days(period)))
        except Exception as exc:
            logger.debug(f"Kripto OHLCV yedeği atlandı: {exc}")
    remaining = [s for s in syms if s not in fetched]
    if remaining:
        try:
            from app.services import yahoo_chart_service
            fetched.update(
                yahoo_chart_service.get_daily_ohlcv(remaining, period=period))
        except Exception as exc:
            logger.debug(f"Yahoo chart OHLCV yedeği atlandı: {exc}")
    # BIST son halkası: Yahoo düşse de sinyal motoru mum bulsun. Kaynak açılış
    # fiyatı vermediği için open=close (fon yolundaki kabul), hacim TL.
    remaining = [s for s in syms if s not in fetched]
    if remaining:
        try:
            from app.services import bist_source_service
            fetched.update(bist_source_service.get_daily_ohlcv(
                remaining, days=_period_days(period)))
        except Exception as exc:
            logger.debug(f"BIST OHLCV yedeği atlandı: {exc}")
    for sym, bars in fetched.items():
        _cache_set(_ohlcv_key(sym, period), bars, _OHLCV_STALE_SECONDS)
    return fetched


def get_daily_ohlcv(symbols: list[str], period: str = "6mo") -> dict[str, dict]:
    """N sembolün günlük OHLCV'si — batch + stale-while-revalidate.

    Yahoo 429'ladığında son bilinen (eski) seriyi döndürür; böylece sinyal
    taraması boş liste yerine biraz eski ama DOĞRU sinyal üretir."""
    syms = sorted({s.upper() for s in symbols if s})
    if not syms:
        return {}

    now = time.time()
    out: dict[str, dict] = {}
    stale: list[str] = []
    missing: list[str] = []

    for sym in syms:
        cached = _cache_get(_ohlcv_key(sym, period))
        if cached:
            data, ts = cached
            out[sym] = data  # bayat da olsa GERÇEK barlar → anında servis
            if now - ts >= _OHLCV_FRESH_SECONDS:
                stale.append(sym)
            continue
        missing.append(sym)

    if stale:
        logger.debug(f"OHLCV bayat ({len(stale)} sembol) → arka planda tazeleniyor")
        _schedule_series_refresh("o", stale, period)

    attempt = [s for s in missing if not _recently_failed("o", s)]
    if attempt:
        fetched = refresh_daily_ohlcv(attempt, period)
        out.update(fetched)
        _mark_failed("o", [s for s in attempt if s not in fetched])

    return out


# ── Geçmiş veri (history) ─────────────────────────────────────────────────────
def _default_interval(period: str) -> str:
    """Period'a göre en uygun interval — intraday için saatlik/dakikalık."""
    p = period.lower()
    if p == "1d":
        return "5m"
    if p == "5d":
        return "15m"
    if p == "1mo":
        return "1h"
    return "1d"


def get_stock_history(symbol: str, period: str = "1mo", interval: str | None = None):
    """Hisse senedinin geçmiş fiyat verilerini döndürür.

    interval verilmezse period'a göre en uygun değer seçilir
    (1d→5m, 5d→15m, 1mo→1h, daha uzun→1d).
    """
    symbol = symbol.upper()
    if gold_catalog.is_gold_suffix(symbol):
        # Fiziki altının GEÇMİŞ serisi yok: serbest piyasa kaynağı yalnız
        # anlık alış/satış veriyor. Ons altın × dolar kurundan seri türetmek
        # mümkün ama o BAŞKA bir varlığın (vadeli ons) grafiği olurdu —
        # çeyreğin kuyumcu makası oraya girmez. Boş seri + açık gerekçe
        # dönüyoruz, UI grafiği gizler.
        return {
            "symbol": symbol,
            "period": period,
            "interval": "1d",
            "data": [],
            "data_points": 0,
            "unavailable_reason": "Fiziki altının geçmiş fiyat serisi yok; "
                                  "yalnız anlık serbest piyasa fiyatı "
                                  "gösterilir.",
        }

    resolved_interval = interval or _default_interval(period)
    if fund_catalog.is_fund_symbol(symbol):
        # Fonun gün içi fiyatı yoktur → istenen aralık ne olursa olsun
        # GÜNLÜK seri döner (uydurma dakikalık mum üretmek yerine).
        resolved_interval = "1d"
    cache_key = _H + f"{symbol}:{period}:{resolved_interval}"
    now = time.time()

    cached = _cache_get(cache_key)
    if cached and (now - cached[1]) < _HISTORY_TTL_SECONDS:
        return cached[0]

    if fund_catalog.is_fund_symbol(symbol):
        rows = _history_from_fallbacks(symbol, period, resolved_interval)
        if not rows:
            raise HTTPException(
                status_code=503,
                detail="TEFAS fon fiyat geçmişine şu an ulaşılamıyor.")
        result = {"symbol": symbol, "period": period,
                  "interval": resolved_interval,
                  "data": rows, "data_points": len(rows)}
        _cache_set(cache_key, result, _HISTORY_TTL_SECONDS)
        return result

    try:
        ticker = yf.Ticker(symbol)
        # yfinance 2h/3h/4h'i native desteklemez → 1h çekip resample et
        # (TradingView'da bu aralıklar çok kullanılır).
        synthetic = {"2h": "2h", "3h": "3h", "4h": "4h"}
        if resolved_interval in synthetic:
            raw = ticker.history(period=period, interval="1h")
            if not raw.empty:
                rule = synthetic[resolved_interval]  # 2h/3h/4h (pandas≥2.2)
                hist = raw.resample(rule).agg({
                    "Open": "first",
                    "High": "max",
                    "Low": "min",
                    "Close": "last",
                    "Volume": "sum",
                }).dropna()
            else:
                hist = raw
        else:
            hist = ticker.history(period=period, interval=resolved_interval)

        if hist.empty:
            raise HTTPException(status_code=404, detail=f"Geçmiş veri bulunamadı: {symbol}")

        # Intraday verilerde saat de göster, günlüklerde sadece tarih.
        intraday = resolved_interval.endswith(("m", "h"))
        date_format = "%Y-%m-%d %H:%M" if intraday else "%Y-%m-%d"
        history = []
        for date, row in hist.iterrows():
            o, h, l, cl = row["Open"], row["High"], row["Low"], row["Close"]
            # yfinance günlük seride bugünün yarım barını / tatil boşluğunu NaN
            # OHLC olarak döndürebilir → JSON'a NaN sızınca uç 500'lüyordu
            # ("Grafik verisi alınamadı"). NaN OHLC satırını atla (null mum çizme).
            if o != o or h != h or l != l or cl != cl:
                continue
            vol = row["Volume"]
            history.append({
                "date": date.strftime(date_format),
                "timestamp": int(date.timestamp()),
                "open": round(float(o), 2),
                "high": round(float(h), 2),
                "low": round(float(l), 2),
                "close": round(float(cl), 2),
                "volume": 0 if vol != vol else int(vol),
            })

        result = {
            "symbol": symbol,
            "period": period,
            "interval": resolved_interval,
            "data": history,
            "data_points": len(history),
        }

        _cache_set(cache_key, result, _HISTORY_TTL_SECONDS)
        return result

    except HTTPException:
        raise
    except Exception as e:
        # Yahoo 429'ladığında grafik ucu 400 dönüyordu ("Grafik verisi
        # alınamadı") — canlıda 2 Eyl 2026'da HER sembolde, HER aralıkta.
        # Yedek zinciri: önce Yahoo'nun açık chart ucu (Cloudflare Worker
        # vekili üzerinden; intraday DAHİL, 2h/4h 1h'ten toplanır), o da
        # vermezse günlük aralıkta kripto borsa API'si.
        fallback = _history_from_fallbacks(symbol, period, resolved_interval)
        if fallback:
            result = {"symbol": symbol, "period": period,
                      "interval": resolved_interval,
                      "data": fallback, "data_points": len(fallback)}
            _cache_set(cache_key, result, _HISTORY_TTL_SECONDS)
            return result
        raise HTTPException(status_code=400, detail=f"Geçmiş veri alınamadı: {str(e)}")


def _history_from_fallbacks(symbol: str, period: str,
                            interval: str) -> list[dict]:
    """Grafik satırlarını yedek kaynaklardan toplar.

    1) Yahoo açık chart ucu — her aralığı destekler (vekil kuruluysa
       Render'ın cezalı IP'si devre dışı).
    2) Kripto borsa API'si — YALNIZ günlük mum verir; intraday'de
       uydurma mum basmaktansa boş dönülür.
    3) BIST günlük serisi (İş Yatırım) — aynı şekilde yalnız günlük.
    """
    if fund_catalog.is_fund_symbol(symbol):
        try:
            from app.services import fund_source_service
            return fund_source_service.get_history_rows(
                symbol, _period_days(period))
        except Exception as exc:
            logger.debug(f"Fon grafik kaynağı atlandı ({symbol}): {exc}")
            return []

    try:
        from app.services import yahoo_chart_service
        rows = yahoo_chart_service.get_history_rows(symbol, period, interval)
        if rows:
            return rows
    except Exception as exc:
        logger.debug(f"Grafik chart yedeği atlandı ({symbol}): {exc}")

    if interval != "1d":
        return []

    bars: dict | None = None
    try:
        from app.services import crypto_source_service
        bars = crypto_source_service.get_daily_ohlcv(
            [symbol], days=_period_days(period)).get(symbol)
    except Exception as exc:
        logger.debug(f"Grafik kripto yedeği atlandı ({symbol}): {exc}")
    if not bars:
        try:
            from app.services import bist_source_service
            bars = bist_source_service.get_daily_ohlcv(
                [symbol], days=_period_days(period)).get(symbol.upper())
        except Exception as exc:
            logger.debug(f"Grafik BIST yedeği atlandı ({symbol}): {exc}")
    if not bars:
        return []

    out: list[dict] = []
    for i, day in enumerate(bars.get("date", [])):
        try:
            stamp = int(time.mktime(time.strptime(day, "%Y-%m-%d")))
            out.append({
                "date": day,
                "timestamp": stamp,
                "open": round(float(bars["open"][i]), 2),
                "high": round(float(bars["high"][i]), 2),
                "low": round(float(bars["low"][i]), 2),
                "close": round(float(bars["close"][i]), 2),
                "volume": int(bars["volume"][i]),
            })
        except (KeyError, IndexError, ValueError, OverflowError):
            continue
    return out


# ── Arama (in-process cache; Redis'e gerek yok) ───────────────────────────────
_search_cache: dict[str, tuple[list, datetime]] = {}
_SEARCH_CACHE_TTL_MINUTES = 30


def search_symbols(query: str, limit: int = 10):
    """yfinance Search API'siyle BIST/NYSE/NASDAQ/kripto arar."""
    query = query.strip()
    if len(query) < 1:
        return []

    cache_key = query.lower()
    now = datetime.now()

    if cache_key in _search_cache:
        data, ts = _search_cache[cache_key]
        if now - ts < timedelta(minutes=_SEARCH_CACHE_TTL_MINUTES):
            return data[:limit]

    from app.services.bist_catalog import search_catalog, tr_fold

    # Yerel kataloglar önce (ağsız): BIST Türkçe adları ("gülermak", "türk
    # hava") Yahoo'da çözülmüyor; TEFAS fonları ise Yahoo'da HİÇ YOK — fon
    # ancak buradan bulunabilir.
    results = list(search_catalog(query, limit=limit))
    seen = {r["symbol"] for r in results}
    for fund in fund_catalog.search(query, limit=limit):
        if fund["symbol"] not in seen:
            seen.add(fund["symbol"])
            results.append(fund)
    # Fiziki altın ("çeyrek", "bilezik", "gram altın") — Yahoo'da karşılığı
    # olmadığı için ancak yerel katalogdan bulunabilir.
    for gold in gold_catalog.search(query, limit=limit):
        if gold["symbol"] not in seen:
            seen.add(gold["symbol"])
            results.append(gold)

    try:
        # Yahoo Türkçe diakritiği tanımıyor → ASCII'ye katlayıp ara.
        search = yf.Search(tr_fold(query) or query,
                           max_results=limit, news_count=0)
        quotes = search.quotes

        for q in quotes:
            symbol = q.get("symbol", "")
            if not symbol or symbol in seen:
                continue
            seen.add(symbol)

            exchange = q.get("exchange", "").upper()
            quote_type = q.get("quoteType", "").upper()

            if symbol.endswith(".IS"):
                market = "BIST"
            elif quote_type == "CRYPTOCURRENCY":
                market = "CRYPTO"
            elif exchange in ("NMS", "NASDAQ"):
                market = "NASDAQ"
            elif exchange in ("NYQ", "NYSE"):
                market = "NYSE"
            elif quote_type == "ETF":
                market = "ETF"
            elif quote_type == "INDEX":
                market = "ENDEKS"
            else:
                market = exchange or "DİĞER"

            results.append({
                "symbol": symbol,
                "name": q.get("shortname") or q.get("longname") or symbol,
                "market": market,
                "type": quote_type,
            })

        _search_cache[cache_key] = (results, now)
        return results[:limit]

    except Exception as e:
        # Yahoo düşse bile YEREL sonuçlar (BIST kataloğu + TEFAS fonları)
        # elde: eskiden burada [] dönülüyordu → 429 anında arama tamamen
        # ölüyordu, oysa kullanıcının aradığı fon zaten yerelde.
        logger.warning(f"Search error for '{query}': {e}")
        if results:
            _search_cache[cache_key] = (results, now)
        return results[:limit]
