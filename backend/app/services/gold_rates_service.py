"""Türk bankalarının altın alış/satış fiyatları.

Serbest piyasa (gram/çeyrek/tam/ons …) truncgil.com'dan **canlı ve gerçek**
çekilir. Banka bazlı gram altın alış-satış için **best-effort** olarak
canlidoviz.com'daki banka sayfaları taranır; veri yoksa/şüpheliyse (hafta
sonu, sayfa değişimi vb.) o banka için tipik makas oranıyla **tahminî**
fiyata düşülür. Her banka satırı kaynağını (`source`) taşır.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
import re
import time

from loguru import logger
import requests
import yfinance as yf

_cache: dict = {}
_CACHE_TTL_MINUTES = 5
_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36"
)

_NUM_TOKEN = re.compile(r"\d[\d.,]*\d|\d")


def _parse_tl(v) -> float:
    """Türkçe biçim '6.838,45' / '$4.683,18' → float (truncgil için)."""
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).replace("$", "").replace("₺", "").strip()
    if "," in s:  # Türkçe: binlik nokta, ondalık virgül
        s = s.replace(".", "").replace(",", ".")
    return float(s)


def _parse_loose(txt: str) -> float | None:
    """Karışık biçimli ilk sayıyı çöz: '6644.06', '6.644,06',
    '6,644.06', '6644' → float. canlidoviz nokta-ondalık kullanır
    ('6644.06') ama TR/EN binlik+ondalık da tolere edilir."""
    m = _NUM_TOKEN.search(txt or "")
    if not m:
        return None
    s = m.group(0)
    try:
        if "," in s and "." in s:
            # son görülen ayraç = ondalık
            if s.rfind(",") > s.rfind("."):      # 6.644,06 (TR)
                s = s.replace(".", "").replace(",", ".")
            else:                                  # 6,644.06 (EN)
                s = s.replace(",", "")
        elif "," in s:                             # yalnız virgül → ondalık
            s = s.replace(",", ".")
        # yalnız '.' → canlidoviz '6644.06' olduğu gibi float()
        return float(s)
    except ValueError:
        return None


def _pct_from_change(txt: str | None) -> float | None:
    """'%-1,42' → -1.42. Ayrıştırılamazsa None."""
    if not txt:
        return None
    t = txt.replace("%", "").replace(".", "").replace(",", ".").strip()
    try:
        return float(t)
    except ValueError:
        return None


def _clean_change(raw: str | None, ref_pct: float | None) -> tuple[str, bool]:
    """Kaynak (truncgil) türev ürünlerin 'Değişim' alanını çoğu zaman
    doldurmuyor; gram altın %-1,42 iken çeyrek/tam/ata '%0,00' dönüyor —
    üstelik o ürünlerin FİYATI da o gün güncellenmemiş oluyor. Bunu ekranda
    'bugün hiç değişmedi' diye göstermek yanlış bilgi.

    Gram altın gerçekten hareket ettiyse (|ref| > %0,05) ve ürün tam %0,00
    diyorsa → değişimi GÖSTERME, ürünü bayat işaretle.

    Döner: (gösterilecek değişim metni, bayat mı)."""
    pct = _pct_from_change(raw)
    if pct is None:
        return "", False
    if pct == 0.0 and ref_pct is not None and abs(ref_pct) > 0.05:
        return "", True
    return raw or "", False


# canlidoviz altın sayfası: tek istekte hem gram referansı hem TÜM türev
# ürünler + her birinin GERÇEK değişim yüzdesi geliyor.
# Satır düzeni: <kod> ... <ad> <saat> <alış> <satış> <fark> <%değişim> ...
_CD_ROW = re.compile(
    r'currency-list-row.*?</tr>', re.S)
_CD_FIELDS = re.compile(
    r'currency-list-row"?>?\s*(?P<code>\S+)\s+\*\]:mr-1\s+"?>?\s*'
    r'(?P<name>.+?)\s+\d{2}:\d{2}:\d{2}\s+'
    r'(?P<buy>[\d.]+)\s+(?P<sell>[\d.]+)\s+[\d.]+\s+(?P<change>%-?[\d.]+)'
)

# canlidoviz kodu → uygulamada gösterilen ad. Sıra ekranda görünen sıradır.
_CD_PRODUCTS = [
    ("XHGLD", "Gram Has Altın"),
    ("C", "Çeyrek Altın"),
    ("Y", "Yarım Altın"),
    ("T", "Tam Altın"),
    ("CMR", "Cumhuriyet Altını"),
    ("ATA", "Ata Altın"),
    ("22", "22 Ayar Bilezik"),
    ("18", "18 Ayar Altın"),
    ("14", "14 Ayar Altın"),
    # Gümüş de canlidoviz'de gram fiyatıyla geliyor. truncgil'e geçilen
    # eski listede Gram Platin vardı; canlidoviz'de o yok, gümüş var ve
    # TR'de çok daha yaygın bir yatırım aracı.
    ("GAG", "Gümüş"),
]


def _fetch_canlidoviz_gold() -> dict | None:
    """canlidoviz altın sayfası → {kod: {buy, sell, change}}.

    BİRİNCİL kaynak. truncgil'in iki kusuru vardı: (a) türev ürünlerin
    'Değişim' alanını doldurmuyor, (b) Python istemcisiyle bağlantıyı sık
    sık yanıtsız kapatıyor (ölçüm: requests ile 1-2/6, curl ile 5/5).
    canlidoviz aynı ölçümde 5/5 ve her ürün için gerçek değişim veriyor;
    ayrıca banka fiyatları için zaten bu siteyi kullanıyoruz (Render'dan
    çalıştığı kanıtlı).
    """
    try:
        r = requests.get(
            "https://www.canlidoviz.com/altin-fiyatlari",
            headers={"User-Agent": _UA},
            timeout=8,
        )
        if r.status_code != 200:
            logger.warning(f"canlidoviz altın HTTP {r.status_code}")
            return None
    except Exception as exc:
        logger.warning(f"canlidoviz altın fetch hata: {exc}")
        return None

    out: dict[str, dict] = {}
    for seg in _CD_ROW.findall(r.text):
        flat = " ".join(re.sub(r"<[^>]+>", " ", seg).split())
        m = _CD_FIELDS.match(flat)
        if not m:
            continue
        buy, sell = _parse_loose(m.group("buy")), _parse_loose(m.group("sell"))
        if buy is None or sell is None or buy <= 0 or sell <= 0:
            continue
        out[m.group("code")] = {
            "buy": buy,
            "sell": sell,
            # canlidoviz nokta-ondalık yazıyor ('%-1.52'); uygulama Türkçe
            # gösterdiği için virgüle çevrilir.
            "change": m.group("change").replace(".", ","),
        }
    return out or None


def _fetch_truncgil(attempts: int = 3) -> dict | None:
    """finans.truncgil.com — Türkiye serbest piyasa altın+döviz, free API.

    Kaynak bağlantıyı sık sık yanıtsız kapatıyor (RemoteDisconnected); tek
    denemede ~%40 başarı ölçüldü. Başarısızlıkta "Altın Ürünleri" bölümü
    ekrandan tamamen kaybolduğu için kısa aralıklı tekrar denenir.
    """
    for i in range(attempts):
        try:
            r = requests.get(
                "https://finans.truncgil.com/today.json",
                headers={"User-Agent": _UA},
                timeout=8,
            )
            if r.status_code == 200:
                return r.json()
            logger.warning(f"truncgil altın HTTP {r.status_code}")
        except Exception as exc:
            logger.warning(
                f"truncgil altın fetch hata ({i + 1}/{attempts}): {exc}"
            )
        if i < attempts - 1:
            time.sleep(0.4 * (i + 1))
    return None


# Banka → (canlidoviz slug, (alış spread %, satış spread %) tahmini fallback).
# Spread'ler gerçek scrape başarısız olursa kullanılır (hafta sonu vb.).
_BANKS = {
    "Ziraat Bankası": ("ziraat-bankasi", (-0.005, 0.008)),
    "VakıfBank": ("vakifbank", (-0.005, 0.009)),
    "Halkbank": ("halkbank", (-0.006, 0.010)),
    "Garanti BBVA": ("garanti-bankasi", (-0.006, 0.010)),
    "İş Bankası": ("is-bankasi", (-0.007, 0.011)),
    "Akbank": ("akbank", (-0.008, 0.012)),
    "Yapı Kredi": ("yapi-kredi", (-0.009, 0.013)),
    "QNB Finansbank": ("qnb-finansbank", (-0.010, 0.015)),
    "Kuveyt Türk": ("kuveyt-turk", (-0.009, 0.013)),
    "DenizBank": ("denizbank", (-0.011, 0.016)),
    "TEB": ("teb", (-0.010, 0.014)),
    "Enpara": ("enpara", (-0.004, 0.007)),
}


def _fetch_canlidoviz_bank(slug: str) -> tuple[float, float] | None:
    """Bir bankanın gram altın (alış, satış)'ını canlidoviz'den çek."""
    try:
        r = requests.get(
            f"https://www.canlidoviz.com/altin-fiyatlari/{slug}",
            headers={"User-Agent": _UA},
            timeout=6,
        )
        if r.status_code != 200:
            return None
        h = r.text
        m = re.search(r"currency-list-row.*?Gram Altın.*?</tr>", h, re.S)
        if not m:
            return None
        seg = m.group(0)
        tds = re.findall(r"<td[^>]*>(.*?)</td>", seg, re.S)
        if len(tds) < 3:
            return None

        def cell(i: int) -> float | None:
            txt = re.sub(r"<[^>]+>", " ", tds[i]).strip()
            return _parse_loose(txt)

        buy, sell = cell(1), cell(2)
        if buy is None or sell is None:
            return None
        return (buy, sell)
    except Exception as exc:
        logger.debug(f"canlidoviz {slug} fetch hata: {exc}")
        return None


def _gram_gold_in_try() -> float | None:
    """Gram altın referans fiyatı (TL) — yfinance fallback."""
    try:
        gold_hist = yf.Ticker("GC=F").history(period="2d")
        usdtry_hist = yf.Ticker("USDTRY=X").history(period="2d")
        if gold_hist.empty or usdtry_hist.empty:
            return None
        ounce_usd = float(gold_hist["Close"].iloc[-1])
        rate = float(usdtry_hist["Close"].iloc[-1])
        return (ounce_usd * rate) / 31.1035
    except Exception as exc:
        logger.warning(f"Gold rate fetch error: {exc}")
        return None


# Yahoo sembolü → truncgil anahtarı. `ons` doğrudan USD/ons; `gumus` ₺/gram
# geldiği için USD/ons'a çevrilir.
_SPOT_KEYS = {"GC=F": ("ons", False), "SI=F": ("gumus", True)}
_TROY_OUNCE_GRAMS = 31.1035


def spot_metal_usd(symbols: list[str]) -> dict[str, float]:
    """Altın/gümüşün USD/ons SPOT fiyatı — Yahoo YEDEĞİ (tek istek).

    Yahoo, Render IP'sini 429'ladığında GC=F/SI=F fiyatsız kalıp portföyde
    `avg_cost`'a düşüyordu. truncgil Render'dan erişilebilir (Banka Altın
    ekranı zaten buradan besleniyor).

    ⚠️ truncgil SPOT verir, GC=F ise VADELİ (futures). Aradaki taşıma maliyeti
    farkı ölçüldüğünde ~%1 (altın -%1,2 · gümüş -%1,0). Yaklaşık ama
    "fiyat = maliyet, kâr/zarar %0" göstermekten çok daha doğru.
    """
    wanted = {s.upper() for s in symbols} & set(_SPOT_KEYS)
    if not wanted:
        return {}
    data = _fetch_truncgil(attempts=2)
    if not data:
        return {}

    usdtry = None
    out: dict[str, float] = {}
    for sym in wanted:
        key, needs_fx = _SPOT_KEYS[sym]
        row = data.get(key)
        if not isinstance(row, dict):
            continue
        try:
            buy = _parse_tl(row.get("Alış"))
            sell = _parse_tl(row.get("Satış"))
        except Exception:
            continue
        mid = (buy + sell) / 2 if (buy and sell) else (sell or buy)
        if not mid or mid <= 0:
            continue
        if needs_fx:
            if usdtry is None:
                try:
                    u = data.get("USD") or {}
                    usdtry = (_parse_tl(u.get("Alış")) + _parse_tl(u.get("Satış"))) / 2
                except Exception:
                    usdtry = 0
            if not usdtry or usdtry <= 0:
                continue
            mid = mid / usdtry * _TROY_OUNCE_GRAMS
        out[sym] = round(mid, 2)
    return out


def _valid_bank_quote(buy: float, sell: float, ref: float) -> bool:
    """Scrape edilen fiyat mantıklı mı? (hafta sonu sıfır/eski veri filtrele)"""
    if buy <= 0 or sell <= 0 or sell <= buy:
        return False
    mid = (buy + sell) / 2
    if abs(mid / ref - 1) > 0.15:  # referanstan %15+ sapma → şüpheli
        return False
    if (sell - buy) / ref > 0.06:  # %6+ makas → şüpheli
        return False
    return True


def get_bank_gold_rates() -> dict:
    now = datetime.now()
    if "data" in _cache:
        data, ts = _cache["data"]
        if now - ts < timedelta(minutes=_CACHE_TTL_MINUTES):
            return data

    # 1) Serbest piyasa (gerçek, canlı) + diğer ürünler
    #
    # BİRİNCİL: canlidoviz — tek istekte gram referansı + tüm türev ürünler
    # + her birinin GERÇEK değişimi. YEDEK: truncgil (bağlantıyı sık kapatıyor
    # ve türev ürünlerin değişimini doldurmuyor; yalnız canlidoviz düşerse
    # ya da onda olmayan ürün için — ör. Gram Platin).
    cd = _fetch_canlidoviz_gold()
    real_data = _fetch_truncgil() if cd is None else None
    market_buy: float | None = None
    market_sell: float | None = None
    extra_products: list[dict] = []

    reference_change: str = ""
    ref_pct: float | None = None

    if cd:
        gram = cd.get("GA")
        if gram:
            market_buy, market_sell = gram["buy"], gram["sell"]
            reference_change = gram["change"]
            ref_pct = _pct_from_change(reference_change)
        for code, label in _CD_PRODUCTS:
            item = cd.get(code)
            if not item:
                continue
            change, stale = _clean_change(item["change"], ref_pct)
            extra_products.append({
                "name": label,
                "buy": round(item["buy"], 2),
                "sell": round(item["sell"], 2),
                "change": change,
                "stale": stale,
            })

    if real_data:
        try:
            gram = real_data.get("gram-altin")
            if gram:
                market_buy = _parse_tl(gram.get("Alış"))
                market_sell = _parse_tl(gram.get("Satış"))
                # Gram altının değişimi, türev ürünlerin bayatlığını ölçmek
                # için referans; ayrıca ekranda gösterilir.
                reference_change = gram.get("Değişim", "") or ""
                ref_pct = _pct_from_change(reference_change)
            product_map = [
                ("gram-has-altin", "Gram Has Altın"),
                ("ceyrek-altin", "Çeyrek Altın"),
                ("yarim-altin", "Yarım Altın"),
                ("tam-altin", "Tam Altın"),
                ("cumhuriyet-altini", "Cumhuriyet Altını"),
                ("ata-altin", "Ata Altın"),
                ("22-ayar-bilezik", "22 Ayar Bilezik"),
                ("18-ayar-altin", "18 Ayar Altın"),
                ("14-ayar-altin", "14 Ayar Altın"),
                ("gram-platin", "Gram Platin"),
            ]
            for key, label in product_map:
                obj = real_data.get(key)
                if not obj:
                    continue
                try:
                    change, stale = _clean_change(obj.get("Değişim"), ref_pct)
                    extra_products.append({
                        "name": label,
                        "buy": round(_parse_tl(obj.get("Alış")), 2),
                        "sell": round(_parse_tl(obj.get("Satış")), 2),
                        "change": change,
                        "stale": stale,
                    })
                except Exception:
                    continue
        except Exception as exc:
            logger.warning(f"truncgil parse hata: {exc}")

    if market_buy is None or market_sell is None:
        ref0 = _gram_gold_in_try()
        if ref0 is None:
            return {"error": "Altın fiyatı alınamadı", "banks": []}
        market_buy, market_sell = ref0 * 0.998, ref0 * 1.003

    reference = (market_buy + market_sell) / 2

    # 2) Banka fiyatları: önce gerçek scrape (paralel), olmazsa tahmin
    scraped: dict[str, tuple[float, float]] = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {
            ex.submit(_fetch_canlidoviz_bank, slug): name
            for name, (slug, _) in _BANKS.items()
        }
        for fut in as_completed(futs, timeout=12):
            name = futs[fut]
            try:
                res = fut.result()
            except Exception:
                res = None
            if res and _valid_bank_quote(res[0], res[1], reference):
                scraped[name] = res

    banks = []
    real_count = 0
    for name, (slug, (buy_pct, sell_pct)) in _BANKS.items():
        if name in scraped:
            buy, sell = scraped[name]
            source = "canlidoviz"
            real_count += 1
        else:
            buy = market_buy + reference * buy_pct
            sell = market_sell + reference * sell_pct
            source = "tahminî"
        spread = sell - buy
        banks.append({
            "name": name,
            "buy": round(buy, 2),
            "sell": round(sell, 2),
            "spread": round(spread, 2),
            "spread_pct": round(spread / reference * 100, 3),
            "source": source,
        })

    banks.sort(key=lambda b: b["spread"])

    if real_count == len(_BANKS):
        note = ("Banka gram altın alış-satış fiyatları canlidoviz.com'dan "
                "canlı çekilmiştir.")
        data_source = "Serbest piyasa: truncgil • Banka: canlidoviz (canlı)"
    elif real_count > 0:
        note = (f"{real_count}/{len(_BANKS)} banka fiyatı canlidoviz.com'dan "
                "canlı; kalanı (hafta sonu/erişilemeyen) tipik makas ile "
                "tahminîdir.")
        data_source = "Serbest piyasa: truncgil • Banka: canlidoviz + tahmin"
    else:
        note = ("Banka fiyatları şu an canlı alınamadı (hafta sonu olabilir); "
                "serbest piyasa referansına tipik bankalararası makas "
                "uygulanarak tahmin edilmiştir.")
        data_source = "Serbest piyasa: truncgil • Banka: tahminî makas"

    result = {
        "reference_gram_try": round(reference, 2),
        "reference_change": reference_change,
        "market_buy": round(market_buy, 2),
        "market_sell": round(market_sell, 2),
        "banks": banks,
        "extra_products": extra_products,
        "data_source": data_source,
        "products_source": "canlidoviz" if cd else ("truncgil" if real_data else None),
        "real_bank_count": real_count,
        "updated_at": now.isoformat(),
        "note": note,
        "external_link": "https://www.canlidoviz.com/altin-fiyatlari",
    }
    # Kaynak (truncgil) bu turda patlarsa ürün listesi BOŞ gelir ve bu boş
    # sonuç 5 dk cache'lenerek bölümü ekrandan tamamen silerdi. Elde bir
    # önceki iyi liste varsa onu koru (stale-while-revalidate) — bayat fiyat,
    # hiç göstermemekten iyi; kesim zamanı `updated_at`'te zaten yazıyor.
    if not extra_products and "data" in _cache:
        prev = _cache["data"][0]
        if prev.get("extra_products"):
            result["extra_products"] = prev["extra_products"]
            result["products_stale"] = True
            if not reference_change:
                result["reference_change"] = prev.get("reference_change", "")

    _cache["data"] = (result, now)
    return result


# ── Portföy kaynağı: fiziki altın/gümüş sembolleri ───────────────────────
# `market_data_service` sözleşmesi ({symbol, company_name, current_price,
# change_percent}) — CEYREK.ALTIN gibi semboller Yahoo'da YOK, tek kaynağı bu.

def _change_pct(raw: str | None) -> float:
    """'%-0,67' → -0.67. Çözülemezse 0."""
    pct = _pct_from_change(raw)
    return round(pct, 2) if pct is not None else 0.0


def get_quotes(symbols: list[str]) -> dict[str, dict]:
    """Fiziki altın/gümüş sembolleri için fiyat.

    Değerleme ALIŞ (bozdurma) fiyatıyla: kullanıcı "hepsini satsam ne kadar
    gelir" diye soruyor, sattığında eline geçen alış fiyatıdır. Satış
    fiyatıyla değerlemek portföyü makas kadar şişirirdi (çeyrekte ~%1,6).
    """
    from app.services import gold_catalog

    wanted = [s.upper() for s in symbols if gold_catalog.is_gold_symbol(s)]
    if not wanted:
        return {}

    data = get_bank_gold_rates()
    if not data:
        return {}

    by_product = {p["name"]: p for p in data.get("extra_products", [])}
    # "Gram Altın" ürün listesinde yok — serbest piyasa referansı odur.
    if data.get("market_buy") and data.get("market_sell"):
        by_product.setdefault("Gram Altın", {
            "name": "Gram Altın",
            "buy": data["market_buy"],
            "sell": data["market_sell"],
            "change": data.get("reference_change", ""),
        })

    out: dict[str, dict] = {}
    for symbol in wanted:
        product = by_product.get(gold_catalog.product_of(symbol) or "")
        if not product or not product.get("buy"):
            continue
        out[symbol] = {
            "symbol": symbol,
            "company_name": gold_catalog.name_of(symbol) or symbol,
            "current_price": round(float(product["buy"]), 2),
            "change_percent": _change_pct(product.get("change")),
            "change_available": bool(product.get("change")),
            # Kullanıcı yeni alacaksa ödeyeceği fiyat — UI "alış/satış"
            # makasını gösterebilsin diye taşınır.
            "ask_price": round(float(product.get("sell") or product["buy"]), 2),
        }
    return out
