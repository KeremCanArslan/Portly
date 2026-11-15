"""Makro ekonomik takvim — bu haftanın önemli olayları, GERÇEK kaynaklardan.

16 Kas 2026'ya kadar olaylar tarih ve saatleriyle LLM'e ürettiriliyordu; LLM
yokken her gün aynı iki sabit "örnek" olay dönüyordu → kullanıcıya gerçek takvim
gibi görünen uydurma veri. Kaynaklar artık:

- Küresel: ForexFactory haftalık akışı (nfs.faireconomy.media/ff_calendar_thisweek.json).
  Yalnız içinde bulunulan hafta; tarih ABD saatiyle ISO; etki High/Medium/Low;
  beklenti/önceki değer. Türkiye (TRY) olaylarını KAPSAMIYOR.
- Türkiye: TCMB resmî "Takvim" sayfası (PPK karar/özet, Enflasyon Raporu,
  Finansal İstikrar Raporu tarihleri). PPK kararı 14.00'te açıklanır.

TÜİK yayın takvimi makineyle okunur biçimde yok (veri portalı tarayıcıda
oluşuyor) → TÜFE tarihleri gösterilmez. Bir kaynak çökerse o kaynaktan olay
gelmez; yerine hiçbir şey UYDURULMAZ.
"""

import html
import re
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import requests
from loguru import logger

_IST = ZoneInfo("Europe/Istanbul")
_FF_URL = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
_TCMB_URL = ("https://tcmb.gov.tr/wps/wcm/connect/TR/TCMB%2BTR/Main%2BMenu/"
             "Duyurular/Takvim")
_HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; Portly/1.0)"}
_TIMEOUT = 12
_MAX_EVENTS = 6           # widget en fazla 6 satır gösteriyor
_TCMB_DAYS = 7

_cache: dict[str, tuple[list, datetime]] = {}
_CACHE_TTL = timedelta(hours=3)
_FAIL_TTL = timedelta(minutes=15)   # kaynak çöktüyse kısa süre sonra yeniden dene
_FORCE_MIN = timedelta(minutes=5)   # ?force=true kaynağı dakikada bir kez dövmesin

# Para birimi → (ülke kodu, Türkçe önek). Kapsam: portföydeki ABD hisseleri ve
# küresel risk iştahını en çok oynatan bölgeler.
_FF_REGIONS = {
    "USD": ("USA", "ABD"),
    "EUR": ("EU", "Avro Bölgesi"),
    "GBP": ("GBR", "İngiltere"),
    "JPY": ("JPN", "Japonya"),
    "CNY": ("CHN", "Çin"),
}
# Orta etkili olay yalnız bu bölgelerden alınır (yoksa liste İngiltere/Japonya
# ayrıntısıyla dolar).
_FF_MEDIUM_OK = {"USD", "EUR"}
# Avro Bölgesi akışında ülke önekiyle gelen başlıklar ("German ifo ...").
_EU_COUNTRY_PREFIX = {
    "German ": ("DEU", "Almanya"),
    "French ": ("FRA", "Fransa"),
    "Italian ": ("ITA", "İtalya"),
    "Spanish ": ("ESP", "İspanya"),
}

# ForexFactory başlığı → Türkçe (canlı akıştaki gerçek başlıklardan). Haritada
# olmayan başlık İngilizce kalır — uydurma çeviri yok.
_TITLE_TR = {
    "CPI m/m": "TÜFE (aylık)",
    "CPI y/y": "TÜFE (yıllık)",
    "CPI q/q": "TÜFE (çeyreklik)",
    "Prelim CPI m/m": "TÜFE (aylık, öncü)",
    "Final CPI y/y": "TÜFE (yıllık, nihai)",
    "CPI Flash Estimate y/y": "TÜFE (yıllık, öncü)",
    "Core CPI Flash Estimate y/y": "Çekirdek TÜFE (yıllık, öncü)",
    "Median CPI y/y": "Medyan TÜFE (yıllık)",
    "Trimmed CPI y/y": "Budanmış TÜFE (yıllık)",
    "Core CPI m/m": "Çekirdek TÜFE (aylık)",
    "Core CPI y/y": "Çekirdek TÜFE (yıllık)",
    "PPI m/m": "ÜFE (aylık)",
    "Core PPI m/m": "Çekirdek ÜFE (aylık)",
    "Core PCE Price Index m/m": "Çekirdek PCE fiyat endeksi (aylık)",
    "Retail Sales m/m": "Perakende satışlar (aylık)",
    "Core Retail Sales m/m": "Çekirdek perakende satışlar (aylık)",
    "Non-Farm Employment Change": "Tarım dışı istihdam",
    "ADP Non-Farm Employment Change": "ADP özel sektör istihdamı",
    "Claimant Count Change": "İşsizlik yardımı başvuru değişimi",
    "Employment Change": "İstihdam değişimi",
    "Unemployment Rate": "İşsizlik oranı",
    "Unemployment Claims": "Haftalık işsizlik başvuruları",
    "Average Hourly Earnings m/m": "Saatlik ortalama kazanç (aylık)",
    "Average Earnings Index 3m/y": "Ortalama kazanç endeksi (3 ay, yıllık)",
    "JOLTS Job Openings": "JOLTS açık iş pozisyonları",
    "Advance GDP q/q": "GSYH (çeyreklik, öncü)",
    "Prelim GDP q/q": "GSYH (çeyreklik, ön)",
    "Final GDP q/q": "GSYH (çeyreklik, nihai)",
    "GDP q/q": "GSYH (çeyreklik)",
    "GDP y/y": "GSYH (yıllık)",
    "ISM Manufacturing PMI": "ISM imalat PMI",
    "ISM Services PMI": "ISM hizmet PMI",
    "Flash Manufacturing PMI": "İmalat PMI (öncü)",
    "Flash Services PMI": "Hizmet PMI (öncü)",
    "Manufacturing PMI": "İmalat PMI",
    "Caixin Manufacturing PMI": "Caixin imalat PMI",
    "Industrial Production m/m": "Sanayi üretimi (aylık)",
    "Industrial Production y/y": "Sanayi üretimi (yıllık)",
    "Trade Balance": "Dış ticaret dengesi",
    "Durable Goods Orders m/m": "Dayanıklı mal siparişleri (aylık)",
    "Core Durable Goods Orders m/m": "Çekirdek dayanıklı mal siparişleri (aylık)",
    "CB Consumer Confidence": "Conference Board tüketici güveni",
    "Building Permits": "İnşaat izinleri",
    "Housing Starts": "Konut başlangıçları",
    "New Home Sales": "Yeni konut satışları",
    "Existing Home Sales": "Mevcut konut satışları",
    "Pending Home Sales m/m": "Bekleyen konut satışları (aylık)",
    "Flash GDP q/q": "GSYH (çeyreklik, öncü)",
    "Retail Sales y/y": "Perakende satışlar (yıllık)",
    "Philly Fed Manufacturing Index": "Philadelphia Fed imalat endeksi",
    "Empire State Manufacturing Index": "New York Fed imalat endeksi",
    "Prelim UoM Consumer Sentiment": "Michigan tüketici güveni (öncü)",
    "Revised UoM Consumer Sentiment": "Michigan tüketici güveni (revize)",
    "Prelim UoM Inflation Expectations": "Michigan enflasyon beklentisi (öncü)",
    "Revised UoM Inflation Expectations": "Michigan enflasyon beklentisi (revize)",
    "ifo Business Climate": "ifo iş ortamı endeksi",
    "ZEW Economic Sentiment": "ZEW ekonomik güven endeksi",
    "Federal Funds Rate": "Fed faiz kararı",
    "FOMC Statement": "FOMC karar metni",
    "FOMC Press Conference": "FOMC basın toplantısı",
    "FOMC Meeting Minutes": "FOMC toplantı tutanakları",
    "Main Refinancing Rate": "ECB faiz kararı",
    "ECB Press Conference": "ECB basın toplantısı",
    "ECB Financial Stability Review": "ECB Finansal İstikrar Raporu",
    "Official Bank Rate": "BoE faiz kararı",
    "Monetary Policy Summary": "BoE para politikası özeti",
    "Monetary Policy Statement": "Para politikası metni",
    "BOJ Policy Rate": "BoJ faiz kararı",
}
# Konuşmacı adı değişen başlıklar ("Fed Chairman Warsh Speaks").
_SPEAKER_TR = [
    (re.compile(r"^Fed Chairman (.+) Speaks$"), "Fed Başkanı {} konuşuyor"),
    (re.compile(r"^FOMC Member (.+) Speaks$"), "FOMC üyesi {} konuşuyor"),
    (re.compile(r"^ECB President (.+) Speaks$"), "ECB Başkanı {} konuşuyor"),
    (re.compile(r"^BOE Gov (.+) Speaks$"), "BoE Başkanı {} konuşuyor"),
    (re.compile(r"^BOJ Gov (.+) Speaks$"), "BoJ Başkanı {} konuşuyor"),
]
# Bu ifadelerle başlayan Türkçe başlık zaten kurumu söylüyor → ülke öneki yok.
_INSTITUTION_PREFIXES = ("Fed ", "FOMC ", "ECB ", "BoE ", "BoJ ", "Philadelphia Fed",
                         "New York Fed", "Michigan ")

_TR_MONTHS = {"ocak": 1, "şubat": 2, "mart": 3, "nisan": 4, "mayıs": 5,
              "haziran": 6, "temmuz": 7, "ağustos": 8, "eylül": 9, "ekim": 10,
              "kasım": 11, "aralık": 12}
# TCMB tablosunun sütun başlığı → (olay adı, saat, önem)
_TCMB_COLUMNS = {
    "Para Politikası Kurulu Toplantı Kararı": ("TCMB faiz kararı (PPK)", "14:00", "high"),
    "Para Politikası Kurulu Toplantı Özeti": ("TCMB PPK toplantı özeti", "", "low"),
    "Enflasyon Raporu": ("TCMB Enflasyon Raporu", "", "medium"),
    "Finansal İstikrar Raporu": ("TCMB Finansal İstikrar Raporu", "", "low"),
}
_TAG_RE = re.compile(r"<[^>]+>")


def _now() -> datetime:
    return datetime.now(_IST)


def _fetch_ff() -> list | None:
    try:
        r = requests.get(_FF_URL, headers=_HEADERS, timeout=_TIMEOUT)
        if r.status_code != 200:
            logger.warning(f"Makro takvim: ForexFactory HTTP {r.status_code}")
            return None
        data = r.json()
        return data if isinstance(data, list) else None
    except Exception as exc:
        logger.warning(f"Makro takvim: ForexFactory alınamadı: {exc}")
        return None


def _fetch_tcmb_html() -> str | None:
    try:
        r = requests.get(_TCMB_URL, headers=_HEADERS, timeout=_TIMEOUT)
        if r.status_code != 200:
            logger.warning(f"Makro takvim: TCMB HTTP {r.status_code}")
            return None
        return r.text
    except Exception as exc:
        logger.warning(f"Makro takvim: TCMB alınamadı: {exc}")
        return None


_SCALE_TR = {"K": " bin", "M": " milyon", "B": " milyar", "T": " trilyon"}


def _tr_number(v: str) -> str:
    """ForexFactory "0.3%" / "-0.4%" / "88.4" / "199K" → "%0,3" / "−%0,4" / "88,4" / "199 bin"."""
    v = (v or "").strip()
    if not v:
        return ""
    sign = ""
    if v[0] in "-+":
        sign, v = ("−" if v[0] == "-" else "+"), v[1:]
    v = v.replace(".", ",")
    if v.endswith("%"):
        return f"{sign}%{v[:-1]}"
    if v[-1:] in _SCALE_TR:
        return f"{sign}{v[:-1]}{_SCALE_TR[v[-1]]}"
    return sign + v


def _ff_title(raw: str, currency: str) -> tuple[str, str]:
    """(Türkçe başlık, ülke kodu)."""
    country, prefix = _FF_REGIONS[currency]
    title = raw.strip()
    if currency == "EUR":
        for en, (code, tr) in _EU_COUNTRY_PREFIX.items():
            if title.startswith(en):
                title, country, prefix = title[len(en):], code, tr
                break
    tr_title = _TITLE_TR.get(title)
    if tr_title is None:
        for pattern, template in _SPEAKER_TR:
            m = pattern.match(title)
            if m:
                tr_title = template.format(m.group(1))
                break
    tr_title = tr_title or title
    if tr_title.startswith(_INSTITUTION_PREFIXES):
        return tr_title, country
    first = tr_title.split(" ", 1)[0]
    if title in _TITLE_TR and not first.isupper():   # "Perakende" → "perakende"; TÜFE/ISM kalır
        head = {"I": "ı", "İ": "i"}.get(tr_title[0], tr_title[0].lower())
        tr_title = head + tr_title[1:]
    return f"{prefix} {tr_title}", country


def _ff_events(raw: list, now: datetime) -> list[dict]:
    out = []
    for item in raw:
        currency = item.get("country")
        impact = item.get("impact")
        if currency not in _FF_REGIONS:
            continue
        if impact == "High":
            importance = "high"
        elif impact == "Medium" and currency in _FF_MEDIUM_OK:
            importance = "medium"
        else:
            continue
        try:
            when = datetime.fromisoformat(item["date"]).astimezone(_IST)
        except (KeyError, TypeError, ValueError):
            continue
        if when < now:
            continue
        title, country = _ff_title(item.get("title", ""), currency)
        parts = []
        if (item.get("forecast") or "").strip():
            parts.append(f"Beklenti {_tr_number(item['forecast'])}")
        if (item.get("previous") or "").strip():
            parts.append(f"Önceki {_tr_number(item['previous'])}")
        out.append({
            "date": when.strftime("%Y-%m-%d"),
            "time": when.strftime("%H:%M"),
            "title": title,
            "country": country,
            "importance": importance,
            "impact": " · ".join(parts),
            "source": "ForexFactory",
        })
    return out


def _parse_tr_date(text: str) -> date | None:
    m = re.match(r"^\s*(\d{1,2})\s+(\S+)\s+(\d{4})\s*$", text)
    if not m:
        return None
    month = _TR_MONTHS.get(m.group(2).lower())
    if month is None:
        return None
    try:
        return date(int(m.group(3)), month, int(m.group(1)))
    except ValueError:
        return None


def _tcmb_events(page: str, now: datetime) -> list[dict]:
    table = re.search(r'<table[^>]*id="midTable"[^>]*>(.*?)</table>', page, re.S)
    if not table:
        logger.warning("Makro takvim: TCMB sayfasında takvim tablosu bulunamadı")
        return []
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", table.group(1), re.S)
    if not rows:
        return []

    def cells(row: str) -> list[str]:
        return [html.unescape(_TAG_RE.sub("", c)).replace("\xa0", " ").strip()
                for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)]

    header = cells(rows[0])
    columns = [_TCMB_COLUMNS.get(h) for h in header]
    today = now.date()
    last = today + timedelta(days=_TCMB_DAYS)
    out = []
    for row in rows[1:]:
        for col, text in zip(columns, cells(row)):
            if col is None:
                continue
            day = _parse_tr_date(text)
            if day is None or not (today <= day <= last):
                continue
            name, hhmm, importance = col
            if day == today and hhmm and hhmm < now.strftime("%H:%M"):
                continue
            out.append({
                "date": day.isoformat(),
                "time": hhmm,
                "title": name,
                "country": "TUR",
                "importance": importance,
                "impact": "",
                "source": "TCMB",
            })
    return out


def _upcoming(e: dict, now: datetime) -> bool:
    today = now.strftime("%Y-%m-%d")
    if e["date"] != today:
        return e["date"] > today
    return not e["time"] or e["time"] >= now.strftime("%H:%M")


# Portföy TR + ABD ağırlıklı → aynı önemde önce bunlar, sonra Avro Bölgesi.
_REGION_RANK = {"TUR": 0, "USA": 0, "EU": 1, "DEU": 1, "FRA": 1, "ITA": 1, "ESP": 1}


def _pick(events: list[dict], now: datetime) -> list[dict]:
    """En fazla _MAX_EVENTS: önem → bölge → zaman. Aynı başlık bir kez
    (BoE Başkanı haftada iki kez konuşunca liste onunla dolmasın)."""
    events = [e for e in events if _upcoming(e, now)]
    rank = {"high": 0, "medium": 1, "low": 2}
    by_time = sorted(events, key=lambda e: (e["date"], e["time"] or "99:99"))
    seen: set[str] = set()
    unique = []
    for e in by_time:
        if e["title"] not in seen:
            seen.add(e["title"])
            unique.append(e)
    chosen = sorted(unique, key=lambda e: (rank.get(e["importance"], 3),
                                           _REGION_RANK.get(e["country"], 2)))[:_MAX_EVENTS]
    return sorted(chosen, key=lambda e: (e["date"], e["time"] or "99:99"))


def get_upcoming_events(force_refresh: bool = False) -> list[dict]:
    now = _now()
    key = now.strftime("%Y-%m-%d")
    if key in _cache:
        data, ts = _cache[key]
        ttl = _FORCE_MIN if force_refresh else (_CACHE_TTL if data else _FAIL_TTL)
        if now - ts < ttl:
            return _pick(data, now)   # cache'teyken saati geçen olay düşer

    events: list[dict] = []
    ff = _fetch_ff()
    if ff:
        events += _ff_events(ff, now)
    page = _fetch_tcmb_html()
    if page:
        events += _tcmb_events(page, now)

    _cache[key] = (events, now)
    return _pick(events, now)
