"""Finansal haber akışı — RSS (gerçek zamanlı, ücretsiz, TR+EN) + VADER sentiment.

NOT (19. tur): Eski kaynak NewsAPI.org idi; ücretsiz planı makaleleri ~24 saat
GECİKMELİ veriyordu ("dünkü haberler") ve yalnız İngilizceydi. Kaynak, gerçek
zamanlı + Türkçe destekli RSS feed'lerine taşındı. feedparser'ın urllib'i macOS'ta
SSL doğrulayamadığı için içerik `requests` (certifi) ile çekilip feedparser'a verilir.

Alaka filtresi: bir haber YALNIZCA bilinen bir varlık (affected_assets) içeriyorsa
VEYA finans anahtar kelimesi geçiyorsa tutulur → ekonomi feed'lerindeki alakasız
(siyaset/magazin) öğeler elenir.
"""

import calendar
import json
import logging
import re
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import feedparser
import requests
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

from app.services.asset_extractor_service import extract_affected_assets
from app.services.llm_service import MODEL_LITE, complete

logger = logging.getLogger(__name__)

analyzer = SentimentIntensityAnalyzer()

# (ad, url) — piyasa/ekonomi bölüm feed'leri (genel haber siteleri DEĞİL → daha alakalı)
_FEEDS: list[tuple[str, str]] = [
    ("BloombergHT", "https://www.bloomberght.com/rss"),
    ("Investing TR", "https://tr.investing.com/rss/news.rss"),
    ("AA Ekonomi", "https://www.aa.com.tr/tr/rss/default?cat=ekonomi"),
    ("CNBC", "https://www.cnbc.com/id/100003114/device/rss/rss.html"),
    ("Yahoo Finance", "https://finance.yahoo.com/news/rssindex"),
    ("MarketWatch", "http://feeds.marketwatch.com/marketwatch/topstories/"),
    ("WSJ Markets", "https://feeds.a.dj.com/rss/RSSMarketsMain.xml"),
]

_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120 Safari/537.36"
)

# Alaka backstop: piyasa-odaklı feed'lerde bile ara sıra alakasız öğe gelir.
_FINANCE_KEYWORDS = {
    # TR
    "borsa", "hisse", "bist", "dolar", "euro", "sterlin", "faiz", "enflasyon",
    "piyasa", "endeks", "döviz", "altın", "tahvil", "bono", "kripto", "bitcoin",
    "ethereum", "merkez bankası", "tcmb", "ekonomi", "büyüme", "ihracat",
    "ithalat", "bütçe", "rezerv", "temettü", "halka arz", "bilanço", "kâr",
    "zarar", "yatırım", "fon", "petrol",
    # EN
    "stock", "share", "market", "nasdaq", "dow", "s&p", "index", "earnings",
    "rate", "inflation", "bond", "yield", "fed", "ecb", "ipo", "dividend",
    "crypto", "treasury", "gdp", "economy", "revenue", "profit", "forex",
    "currency", "gold", "oil", "recession", "equities",
}

_TAG_RE = re.compile(r"<[^>]+>")

# Gürültü filtresi: bazı feed'ler (özellikle Investing) insider-işlem bildirimi
# dök+yor ("X yöneticisi 1,2 milyon dolarlık hisse sattı") — teknik olarak finans
# ama haber değeri yok. Bunları ele. (Geri-alım/buyback haberlerine dokunmaz.)
# Ayrıca BIST akışına sızan TradingView kullanıcı TA-paylaşımları ("BIST:XXX için
# ... 2 saatlik teknik ve temel analizi - TradingView") — gerçek haber değil, olay
# içermez → etki analizi hep "Nötr %0" çıkıyor. Bunları da ele.
# İngilizce akışta (ABD/kripto) ise kumar/promosyon listeleri sızıyordu:
# "Best Crypto Casinos 2026 …" başlığı bitcoin sonuçlarında İKİ kez geldi
# (canlıda görüldü). Kalıplar KASTEN dar: yalnız "casino" ya da "gambling"
# geçmesi elemez — Las Vegas Sands / DraftKings gibi GERÇEK kumar sektörü
# haberleri akışta kalmalı; elenen şey promosyon/listicle kalıbıdır.
_NOISE_RE = re.compile(
    r"dolar(lık| değerinde)?\s*('?lik)?\s*hisse\s*(sat|al)"  # TR insider filing
    r"|\$[\d.,]+\s*(million|thousand|bin|milyon)?\s*(in\s+|worth of\s+)?shares"
    r"|insider"
    r"|tradingview"  # TradingView kullanıcı analiz paylaşımı (haber değil)
    r"|teknik\s+(ve\s+temel\s+)?analiz"  # "teknik (ve temel) analiz(i)" TA-paylaşımı
    # ── EN promosyon/kumar çöpü ────────────────────────────────────────
    r"|(crypto|bitcoin|btc|online|casino)\s*-?\s*casinos?\b"   # "crypto casino(s)"
    r"|casinos?\s+(and|&)\s+(betting|gambling|sportsbooks?)"
    r"|(gambling|betting)\s+sites?\b"
    r"|no\s+deposit\s+bonus|free\s+spins|welcome\s+bonus"
    r"|(best|top)\s+(\d+\s+)?(crypto|cryptos|coins?|meme\s*coins?|altcoins?)"
    r"\s+(to\s+buy|presales?|casinos?)",
    re.IGNORECASE,
)

# Pool cache — RSS sorgu-bağımsız olduğundan TÜM sorgular tek havuzu paylaşır.
_news_cache: dict = {"data": None, "timestamp": None}
_NEWS_CACHE_TTL_MINUTES = 15
_POOL_LIMIT = 40

# Sorguya özel Google News cache (her sembol/şirket için ayrı): THYAO, AKBNK gibi
# spesifik aramalar genel feed'lerde bulunmuyor — Google News herhangi bir terimi
# yakalar, ücretsiz, API key gerektirmez. TTL aynı (15 dk).
_query_cache: dict[str, dict] = {}
_GOOGLE_NEWS_RSS = "https://news.google.com/rss/search"

# Sembol-bazlı haber bölgesi: BIST hisseleri Türk basınından (hl=tr) — ABD/kripto/
# döviz/emtia İngilizce orijinalden (hl=en). Sebep: ABD/kripto sorgusu TR baskıya
# gidince makine-çevirisi agregatör (Coinfomania, Investing TR) dönüyordu → VADER
# okuyamıyor (hep "Nötr 0.00") + kaynak kalitesiz. İngilizce orijinal → VADER
# gerçek skor verir + Reuters/Bloomberg/CNBC kalitesi. Sorgu önekle gelir
# ("en|apple", "tr|THYAO ..."); öneksiz/eski sorgu TR varsayılır.
_REGION_PARAMS = {
    "tr": {"hl": "tr", "gl": "TR", "ceid": "TR:tr"},
    "en": {"hl": "en-US", "gl": "US", "ceid": "US:en"},
}

# Finans niteleyicisi: ham sembol/şirket sorgusu ("apple", "nvidia") ürün/oyun/
# etkinlik haberlerini de döndürüyordu (iPhone fiyatı, oyun sürümü). Sorguyu
# "(şirket) VE (finansal terim)" biçimine sokarak kaynakta finansal içeriğe
# yönlendiriyoruz. Niteleyici bölgenin diline göre seçilir.
_FINANCE_QUALIFIER = {
    "tr": "(hisse OR borsa OR finans OR bilanço OR kâr OR temettü OR şirket OR "
          "yatırım OR analiz OR sermaye OR ralli OR düşüş OR yükseliş)",
    "en": "(stock OR shares OR earnings OR market OR revenue OR crypto OR "
          "investor OR analyst OR profit OR forecast OR rally OR guidance)",
}

# Toplu (Portföyüm/İzleme) ham çekimde sembol başına en yeni N haber → her
# sembolden pay + makul hacim. (LLM enrich artık ARKA PLANDA olduğundan bu cap
# enrich batch'ini değil, ilk-açılışta gösterilen hacmi belirler; dar tutulursa
# liste seyrekleşir → 10.)
_PER_SYMBOL_CAP = 10

# Haber tazelik penceresi (gün). Google News RSS, dar sorgularda (örn. küçük
# bir BIST hissesi) YENİ haber bulamayınca AYLAR ÖNCESİNİ döndürüyor; sembol
# başına kota da bunlarla doluyordu. Canlı ölçüm (2 Eyl 2026): portföy
# haberinin %19'u bir aydan eskiydi, en eskisi 11 Şubat — ekranda bugünkü
# haberin yanında "haber" gibi duruyordu. Pencere dışı haber ELENİR; o
# sembolün güncel haberi yoksa hiç göstermemek, eskiyi güncel gibi
# göstermekten dürüsttür.
_MAX_NEWS_AGE_DAYS = 30

# Portföy/İzleme haberinde kaç sembol sorgulanır. 12 "demo üst sınırı"ydı;
# 51 pozisyonlu bir portföyde 39 hissenin haberi HİÇ çekilmiyordu ("haber
# sayısı az"). 24 de yetmiyordu: 38 pozisyonlu canlı portföyde 14 sembol
# kapsam dışı kalıyordu. Artık sınır sembol SAYISINDA değil, tur başına
# yapılan ÇEKİM sayısında (_FETCH_BUDGET) — kapsam dışı kalan sembol bir
# sonraki turda çekilir, o ana kadar cache'ten gelir.
_MAX_SYMBOLS = 40

# Bir istekte Google News'e atılacak EN FAZLA sorgu. Neden gerekli: Google News
# RSS kısıtlamayı 429 ile değil, **HTTP 200 + BOŞ feed** ile yapıyor (3 Eylül
# 2026 ölçümü: aynı IP'den arka arkaya ~30 sorgudan sonra spesifik sorgular boş
# dönmeye başladı, Google'ın kendi cache'indeki popüler sorgular dönmeye devam
# etti). Backend bunu "haber yok" sanıp sessizce boş liste veriyordu — canlıda
# 24 sembol sorulup yalnız 4 sembolün haberi geliyordu. Bütçe + sorgu cache'i
# birlikte istek hacmini düşürür.
_FETCH_BUDGET = 24

# Eşzamanlı RSS isteği. 16'ydı: tek seferde 48 sorgu (dil ikizleriyle) atmak
# kısıtlamayı tetikleyen desenin ta kendisiydi.
_FETCH_CONCURRENCY = 6

# Toplu haberin üst sınırı. Genel akışın _POOL_LIMIT'inden (40) ayrı: burada
# çok daha fazla sembol var, 40'ta kesmek listeyi seyrekleştiriyordu.
_SYMBOL_POOL_LIMIT = 90

# Sorgu-başına HAM haber cache'i (LLM'siz, dil ikizleri dahil her sorgu ayrı).
# İki işi var:
#   1) Aynı sembol tekrar tekrar çekilmez — toplu yol (portföy) ve tekil yol
#      (hisse detayı) aynı havuzu paylaşır.
#   2) **Kısıtlama kalkanı**: yeni çekim BOŞ dönerse (Google'ın 200+boş yanıtı)
#      eldeki sonuç _RAW_STALE_MAX_MINUTES kadar korunur → sembolün haberi
#      ekrandan kaybolmaz. Boş yanıt "haber yok" demek DEĞİL.
_raw_cache: dict[str, dict] = {}
_RAW_STALE_MAX_MINUTES = 360
_RAW_CACHE_MAX_ENTRIES = 400

# ABD/kripto sembolleri için haber HEM İngilizce HEM Türkçe kaynaktan çekilir.
# Yalnız İngilizce çekmek Türk kullanıcıya "Türk haberi yok" hissi veriyordu;
# yalnız Türkçe çekmek ise makine-çevirisi agregatörleri getirip skoru
# bozuyordu. İkisi birlikte: Reuters/Bloomberg kalitesi + Türk basını.
_BILINGUAL = True


def _expand_bilingual(queries: list[str]) -> list[str]:
    """`en|...` sorgularına `tr|...` ikizini ekler (BIST zaten `tr|`).
    Sıra korunur: her sembolün iki dili yan yana kalır."""
    if not _BILINGUAL:
        return queries
    out: list[str] = []
    for q in queries:
        out.append(q)
        region, clean = _split_region(q)
        if region == "en":
            out.append(f"tr|{clean}")
    return out


def _split_region(query: str) -> tuple[str, str]:
    """'en|apple' → ('en', 'apple'). Etiketsiz/eski sorgu → ('tr', query)."""
    q = (query or "").strip()
    if len(q) > 3 and q[2] == "|" and q[:2] in _REGION_PARAMS:
        return q[:2], q[3:].strip()
    return "tr", q


# Türkçe finansal duygu sözlüğü — VADER yalnızca İngilizce anladığından, TR
# feed'lerinin (BloombergHT, Investing TR, AA, Google News hl=tr) başlıkları
# neredeyse hep "Nötr" dönüyordu. Aşağıdaki köklerle başlık+açıklama taranır;
# net skor VADER ile harmanlanır. Köklerin uzun/spesifik seçilmesi yanlış-pozitifi
# azaltır (örn "kar" yerine "kâr"/"kârlı" — kar/karar/kara karışmasın diye).
# NOT: bare "arttı/artış" bilerek YOK — bağlama göre olumlu (kâr arttı) ya da
# olumsuz (endişe arttı) olabiliyor; yön bildiren köklere + sonuç isimlerine
# güveniyoruz. Gerçekten olumlu artışlar "talep arttı / ihracat arttı / kâr"
# gibi açık ifadelerle yakalanıyor.
# Türkçe finans sözlüğü. Kapsam neden geniş: ABD hisseleri için de Türk
# basınından haber çekiliyor ve VADER Türkçe okuyamıyor → sözlük tutmazsa
# haber "Nötr 0.00" olarak geçiyor. Kökler ("yüksel") çekim eklerini de
# yakalasın diye kasten kısa; çakışan gündelik kelimeler (kar/kâr ayrımı,
# "hat", "ses") dışarıda bırakıldı.
_TR_POS = (
    # NOT: "kazanç" TEK BAŞINA yok — nötr bir bilanço terimi ("kazancı
    # açıklandı"). Pozitif saymak "kazancı beklentilerin altında kaldı"
    # başlığını sıfırlıyordu. Yön belirten biçimler aşağıda.
    "yüksel", "rekor", "kazandı", "ralli", "güçlen", "toparlan",
    "prim yap", "primli", "zirve", "büyüme", "büyüdü", "olumlu", "müjde",
    "değer kazan", "yükseliş", "sıçra", "fırla", "rekor kır", "kâr", "kârlı",
    "kâr açıkla", "anlaşma", "destek buldu", "talep arttı", "beklenti aştı",
    "yatırım çek", "ihracat arttı", "güçlü bilanço",
    # ── genişletme: analist/hedef/sözleşme dili ──
    "hedef fiyat yüksel", "hedef fiyatı artır", "tavsiyesini yükselt",
    "not artır", "yükseltti", "al tavsiye", "endeks üstü", "alım öner",
    "beklentiyi aştı", "beklentileri aştı", "beklentinin üzerinde",
    # Türkçe yumuşama: "kazanç" ekli halde "kazancı/kazancın" olur → ç'li
    # biçim eşleşmez. Aynı sebeple çoğul "beklentilerin üzerinde" ayrı yazıldı.
    "beklentilerin üzerinde", "beklentiler üzerinde",
    "tahminlerin üzerinde", "tahminin üzerinde",
    "kazanç artt", "kazancı artt", "kazanç büyü", "kâr artt",
    "tahminleri aştı", "güçlü talep", "sipariş aldı", "ihale kazan",
    "sözleşme imzala", "sözleşme aldı", "yeni sipariş", "kontrat kazan",
    "satın al", "birleşme", "ortaklık", "iş birliği", "stratejik anlaşma",
    "temettü", "hisse geri alım", "bedelsiz",
    "yatırım kararı", "kapasite artır", "üretime başla", "onay aldı",
    "ruhsat aldı", "lisans aldı", "izin aldı", "patent",
    "gelir artış", "ciro artış", "satışları arttı", "marj iyileş",
    "borç azalt", "nakit akış güçlü", "halka arz talep",
    "primle kapat", "tavan yaptı", "değerlendi",
    "iyimser", "olumlu ayrıştı", "pozitif ayrıştı", "moral buldu",
)
_TR_NEG = (
    "düşüş", "düştü", "düşüyor", "geriled", "geriliyor", "kayıp", "zarar",
    "çöküş", "çöktü", "kriz", "iflas", "satış baskı", "eridi", "çakıl",
    "daralma", "daraldı", "resesyon", "küçülme", "küçüldü", "olumsuz", "endişe",
    "panik", "soruşturma", "dava açıl", "ceza", "batış", "döküldü", "sert düşüş",
    "değer kaybı", "kaybetti", "azaldı", "tahsis edilemedi", "zayıf bilanço",
    "beklentiyi karşılamadı", "temerrüt", "iflas başvuru",
    # ── genişletme: analist/hedef/operasyon dili ──
    "hedef fiyat düşür", "hedef fiyatı indir", "tavsiyesini düşür",
    "not indir", "düşürdü", "sat tavsiye", "endeks altı", "sat öner",
    "beklentinin altında", "beklentilerin altında", "beklentiler altında",
    "tahminlerin altında", "tahminin altında",
    "beklentileri karşılamadı", "tahminleri ıskaladı",
    "talep zayıf", "sipariş iptal", "sözleşme iptal", "ihaleyi kaybet",
    "anlaşma bozul", "görüşmeler tıkandı", "ortaklık sona er",
    "üretimi durdur", "üretime ara", "fabrika kapat", "işten çıkar",
    "istifa", "görevden al", "ceo ayrıl", "yönetim değişik",
    "geri çağır", "toplatma", "kazası", "kaza geçir", "arıza", "güvenlik sorunu",
    "veri ihlali", "siber saldırı", "hack",
    "ruhsat iptal", "lisans iptal", "onay alamadı", "reddedildi",
    "para cezası", "yaptırım", "inceleme başlat", "usulsüzlük",
    "gelir azal", "ciro düş", "satışları düştü", "marj daral",
    "borç arttı", "nakit sıkıntı", "sermaye artırım",  # sulanma sinyali
    "taban yaptı", "sert satış", "kâr satış",
    "kötümser", "olumsuz ayrıştı", "negatif ayrıştı", "baskı altında",
    "rekor düşüş", "rekor kayıp", "rekor zarar", "kazanç düş", "kâr düş",
)

# Tek bir TR anahtar kelime eşiği (±0.05) geçsin ama uçlara savrulmasın diye katsayı.
_TR_WORD_WEIGHT = 0.35


# Anahtarlar UZUNDAN KISAYA denenir ve eşleşen aralık TÜKETİLİR. İki sebep:
#   • "kâr satışı" (negatif) içindeki "kâr" (pozitif) ayrıca sayılıp skoru
#     sıfırlıyordu; "anlaşma bozuldu" / "ortaklık sona erdi" da öyle.
#   • Uzun ifade her zaman daha spesifik → o kazanmalı.
_TR_LEXICON = tuple(sorted(
    [(w, +1) for w in _TR_POS] + [(w, -1) for w in _TR_NEG],
    key=lambda kv: len(kv[0]), reverse=True))

# Anahtar KELİME BAŞINDA eşleşmeli. Türkçe çekim ekleri sona geldiği için sağ
# taraf serbest ("yüksel" → "yükseldi"), ama sol tarafta harf olmamalı — yoksa
# kelime ortasında yakalanır. (Ölçülen gerçek hata: "kaza" negatifi "kazancı"
# içinde eşleşiyordu → HER bilanço haberi negatif çıkıyordu.)
_TR_LETTER = "a-zçğıöşü0-9"


def _tr_matches(text_low: str) -> tuple[int, int]:
    """(pozitif, negatif) eşleşme sayısı — aralık tüketmeli, uzun-önce."""
    consumed = [False] * len(text_low)
    pos = neg = 0
    for word, polarity in _TR_LEXICON:
        for m in re.finditer(
                rf"(?<![{_TR_LETTER}]){re.escape(word)}", text_low):
            a, b = m.start(), m.end()
            if any(consumed[a:b]):
                continue        # daha uzun (daha spesifik) bir anahtar aldı
            for i in range(a, b):
                consumed[i] = True
            if polarity > 0:
                pos += 1
            else:
                neg += 1
    return pos, neg


def _turkish_sentiment(text_low: str):
    """Türkçe sözlük net skoru (-1..+1). Sinyal yoksa None döner (VADER'a düşülür)."""
    pos, neg = _tr_matches(text_low)
    if pos == 0 and neg == 0:
        return None
    score = (pos - neg) * _TR_WORD_WEIGHT
    return max(-1.0, min(1.0, score))


def analyze_sentiment(text: str) -> dict:
    """Hibrit duygu skoru: İngilizce için VADER + Türkçe finansal sözlük.
    İki kaynakta da sinyal varsa ortalanır; yalnız biri varsa o kullanılır."""
    if not text:
        return {"label": "Nötr", "score": 0.0}

    compound = analyzer.polarity_scores(text)["compound"]  # İngilizce
    tr = _turkish_sentiment(text.lower())  # Türkçe (yoksa None)

    if tr is None:
        score = compound
    elif abs(compound) >= 0.05:
        score = (compound + tr) / 2  # iki dil de sinyal verdi → harmanla
    else:
        score = tr  # VADER nötr kaldı, Türkçe sözlüğe güven

    if score >= 0.05:
        label = "Pozitif"
    elif score <= -0.05:
        label = "Negatif"
    else:
        label = "Nötr"
    return {"label": label, "score": round(score, 4)}


def _label_for(score: float) -> str:
    if score >= 0.05:
        return "Pozitif"
    if score <= -0.05:
        return "Negatif"
    return "Nötr"


# Deterministik yabancı-dil backstop'u: LLM dil filtresine güvenilmez (prompt'a
# rağmen Almanca/Fransızca/Rusça başlıkları relevant=true bırakıyor). Aşağıdaki
# işaretler TR/EN başlıklarda PRATİKTE asla görünmez → kesin ele. Türkçe ile
# çakışan kelimeler (hat, ses, kar, der→? ) bilerek dışarıda; yalnız yüksek-kesinlikli
# damgalar. LLM'in açık `lang` alanı bunu tamamlar (listede olmayan diller için).
_NON_TREN_CHARS = re.compile(r"[Ѐ-ӿ]|[ýňžä]")  # Kiril + Türkmence/Azerice
_FOREIGN_TOKENS = re.compile(
    r"\b("
    # Almanca
    r"wird|ihren|ihre|einen|eine|für|und|der|verzeichnete|verkehrsreichsten"
    r"|rückgang|geschichte|passagierzahlen|passagierlounge|inland|ihrer|seine"
    # Fransızca
    r"|maintenant|augmente|nouvelle|compagnie|aérienne|vols|entre|aujourd"
    # Rusça (latin transliterasyon)
    r"|izvestny|aviakompanii|otkrylsya|prodazh|novye|reisy|goroda|tseny"
    r")\b",
    re.IGNORECASE,
)
_FOREIGN_PHRASES = ("il y a", "ya budet", "ofis prodazh")


def _looks_foreign(title: str) -> bool:
    """TR/EN dışı bir başlık mı? Yüksek-kesinlikli deterministik kontrol."""
    if not title:
        return False
    if _NON_TREN_CHARS.search(title):
        return True
    low = title.lower()
    if any(p in low for p in _FOREIGN_PHRASES):
        return True
    return bool(_FOREIGN_TOKENS.search(title))


_VERDICT_RE = re.compile(r"\{[^{}]*\"i\"\s*:\s*\d+[^{}]*\}")


def _salvage_verdicts(raw: str) -> list[dict]:
    """Kesik/bozuk JSON'daki TAM yazılmış karar nesnelerini toplar.
    (Model çıktısı max_tokens'a takılırsa son kayıt yarım kalır; öncekiler
    sağlamdır — hepsini birden çöpe atmak gereksiz.)"""
    out: list[dict] = []
    for m in _VERDICT_RE.finditer(raw or ""):
        try:
            v = json.loads(m.group(0))
        except ValueError:
            continue
        if isinstance(v, dict) and "i" in v:
            out.append(v)
    return out


def _log_enrich(query: str, incoming: int, gate_dropped: int,
                lang_dropped: int, irrelevant: int, kept: int) -> None:
    """Enrich'in eleme oranını HER turda log'a bas (katman katman).

    Neden: haber sayısı ikinci açılışta gözle görülür düşüyordu ve hangi
    katmanın yediği log'dan okunamıyordu — yalnız %50 üstü eleme uyarı
    basıyordu, altındaki sessiz kayıp ölçülemiyordu. Üç katman ayrı sayılır:
    deterministik dil kapısı (LLM'e hiç gitmeyen), LLM'in dil kararı, LLM'in
    alaka kararı. %50 ve üstü eleme WARNING'e yükselir (filtre fazla agresif
    ya da LLM konuyu yanlış anlamış olabilir).
    """
    if not incoming:
        return
    dropped = incoming - kept
    pct = dropped * 100 // incoming
    line = (f"Haber enrich [{query}]: {incoming} ham -> {kept} kaldi "
            f"(%{pct} elendi; dil kapisi {gate_dropped} - LLM dil {lang_dropped} "
            f"- alaka {irrelevant})")
    (logger.warning if pct >= 50 else logger.info)(line)


def _llm_enrich(items: list[dict], query: str) -> list[dict]:
    """Sadece TR/EN + hisse-fiyatı-etkili materyal haber bırakır, gerçek (çok-dil
    okunabilen) duygu skoru verir. İki katman:
      1) Deterministik dil kapısı (_looks_foreign): Kiril/Türkmence harf + yüksek-
         kesinlikli yabancı damga → LLM'den ÖNCE kesin ele (LLM düşse de geçerli).
      2) Tek batch LLM çağrısı: her haber için lang (dil) + relevant (materyal mi)
         + score. lang ∉ {tr,en} → ele; alakasız → ele; kalanlar gerçek skor alır.
    Quota dostu: sorgu başına TEK çağrı (sonuç _query_cache'te 15 dk). MODEL_LITE:
    flash günlük-20 kotasını yakmamak için. LLM düşerse en az dil kapısı uygular."""
    if not items:
        return items
    incoming = len(items)
    # 1) Deterministik dil kapısı — LLM'e gitmeden yabancıları at.
    items = [it for it in items if not _looks_foreign(it.get("title") or "")]
    gate_dropped = incoming - len(items)
    if not items:
        _log_enrich(query, incoming, gate_dropped, 0, 0, 0)
        return items

    listing = "\n".join(f"{i}: {it['title']}" for i, it in enumerate(items))
    subject = (query or "ilgili hisse").strip()
    system = (
        "Sen bir hisse senedi yatırım analistisin. Sana numaralı haber başlıkları "
        "verilir. Her başlık için ÜÇ alan döndür: lang (başlığın dili, ISO 2-harf: "
        "tr, en, de, fr, ru, az, pt ...), relevant (bool), score (-1.0..+1.0 duygu).\n"
        "relevant=true SADECE şu İKİ koşul birlikte sağlanıyorsa:\n"
        "  1) lang KESİNLİKLE 'tr' veya 'en' (Türkçe ya da İngilizce). Türkmence/"
        "Azerice 'tr' DEĞİLDİR (ý, ň, ä, ž harfleri ya da 'gatnaw, howa, şäher, "
        "ýyl' → lang='tk'/'az', relevant=false).\n"
        "  2) Haber hisse FİYATINI etkileyebilecek MATERYAL bir gelişme: finansal "
        "sonuç/bilanço, kâr-zarar, beklenti, yönetim/CEO/kurul değişikliği, satın "
        "alma/birleşme, büyük sözleşme/sipariş, düzenleme/ceza/dava, kaza/güvenlik "
        "olayı, analist notu, talep/maliyet değişimi, stratejik karar. Rutin "
        "operasyon (yeni hat/sefer, bilet iadesi, tarife), reklam/sponsorluk, spor "
        "turnuvası, sergi/fuar, etkinlik, magazin, bölgesel PR → relevant=false.\n"
        "score: olumsuz negatif, olumlu pozitif, gerçekten nötr ise 0'a yakın.\n"
        'SADECE şu biçimde geçerli JSON döndür: '
        '{"items":[{"i":0,"lang":"en","relevant":true,"score":-0.4}, ...]}'
    )
    user = f"Yatırım konusu: {subject}\n\nBaşlıklar:\n{listing}"
    raw = ""
    try:
        raw = complete(
            [{"role": "system", "content": system},
             {"role": "user", "content": user}],
            temperature=0.0,
            # Öğe başına yaklaşık 26 token ({"i":12,"lang":"en","relevant":
            # true,"score":-0.4},). Sabit 1800 idi ve toplu yol 90 öğeye kadar
            # çıkabiliyor → JSON ortasından kesiliyor, parse patlıyor ve enrich
            # HİÇ uygulanmıyordu (sessiz kayıp, kotası da yanıyordu).
            max_tokens=min(4000, 200 + 26 * len(items)),
            json_mode=True,
            model=MODEL_LITE,
        )
        if not raw:
            # complete() boş dönerse LLM zinciri komple düşmüştür (kota/404) →
            # haber listesi enrich'siz kalıyor demektir, sessiz geçmesin.
            logger.warning(
                "Haber LLM enrich BOŞ yanıt döndü → yalnız dil kapısı uygulandı")
            _log_enrich(query, incoming, gate_dropped, 0, 0, len(items))
            return items
        raw = raw.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip()
        verdicts = json.loads(raw).get("items", [])
    except Exception as e:
        # Kesik JSON'dan kurtarılabileni kurtar: tam yazılmış kayıtlar geçerli,
        # eksik kalanlar zaten "LLM atladı" dalına düşer (haber KAYBOLMAZ).
        verdicts = _salvage_verdicts(raw if isinstance(raw, str) else "")
        if verdicts:
            logger.warning(
                f"Haber LLM enrich JSON'ı kesildi ({type(e).__name__}) → "
                f"{len(verdicts)}/{len(items)} karar kurtarıldı")
        else:
            logger.warning(
                f"Haber LLM enrich düştü ({type(e).__name__}: {e}) → dil kapısı "
                "uygulandı, VADER skoru korunuyor")
            _log_enrich(query, incoming, gate_dropped, 0, 0, len(items))
            return items

    by_idx = {v["i"]: v for v in verdicts if isinstance(v, dict) and "i" in v}
    enriched: list[dict] = []
    lang_dropped = irrelevant = 0
    for i, it in enumerate(items):
        v = by_idx.get(i)
        if v is None:
            enriched.append(it)  # LLM bu başlığı atladı → dil kapısını geçti, kalsın
            continue
        lang = str(v.get("lang", "")).lower()
        if lang and lang not in ("tr", "en"):
            lang_dropped += 1
            continue  # TR/EN dışı → ele
        if v.get("relevant") is False:
            irrelevant += 1
            continue  # yatırımla alakasız → ele
        try:
            score = max(-1.0, min(1.0, float(v["score"])))
        except (KeyError, TypeError, ValueError):
            enriched.append(it)
            continue
        it = {**it, "sentiment_score": round(score, 4), "sentiment_label": _label_for(score)}
        enriched.append(it)
    # Dil kapısından geçenlerden LLM hepsini alakasız bulduysa, dil-filtreli
    # (yabancısız) listeyi koru — boş ekran yerine en azından TR/EN haber.
    out = enriched or items
    _log_enrich(query, incoming, gate_dropped, lang_dropped, irrelevant, len(out))
    return out


def _strip_html(s: str) -> str:
    return _TAG_RE.sub("", s or "").strip()


def _entry_date(entry) -> datetime:
    parsed = entry.get("published_parsed") or entry.get("updated_parsed")
    if parsed:
        try:
            return datetime.fromtimestamp(calendar.timegm(parsed), tz=timezone.utc)
        except (ValueError, OverflowError):
            pass
    return datetime.now(timezone.utc)


# Çıplak ticker sorgusu ("LMT", "PLTR", "NXE"): istemci ABD sembolleri için
# ŞİRKET ADINI bilmiyor (portföy ucu ad döndürmüyor), sorgu tek başına ticker
# oluyor. Google News'te "LMT" araması "Lockheed Martin" başlıklarının bir
# kısmını kaçırıyor. Sunucuda ad zaten cache'te (fiyat çekiminde çözülüyor) →
# sorguyu AĞ İSTEMEDEN genişletiyoruz.
_BARE_TICKER_RE = re.compile(r"^[A-Z]{1,6}(\.[A-Z]{2,3})?$")
_LEGAL_SUFFIX_RE = re.compile(
    r"\b(inc|inc\.|incorporated|corp|corp\.|corporation|company|co|co\.|ltd|"
    r"ltd\.|limited|plc|holdings?|group|nv|sa|se|ag|a\.ş\.|as|aş)\b\.?",
    re.IGNORECASE,
)


def _company_name_for(ticker: str) -> str | None:
    """Bilinen şirket adı (yalnız cache/katalog — AĞ İSTEĞİ ATMAZ)."""
    try:
        from app.services.market_data_service import _known_name
    except Exception:  # pragma: no cover - import döngüsü/servis yoksa
        return None
    try:
        name = _known_name(ticker)
    except Exception:
        return None
    if not name or name.upper() == ticker.upper():
        return None
    name = _LEGAL_SUFFIX_RE.sub("", name.split(",")[0]).strip(" .-")
    words = name.split()
    if not words:
        return None
    return " ".join(words[:4])


def _expand_with_company_name(clean: str) -> str:
    """'LMT' → 'LMT OR "Lockheed Martin"'. Ticker olmayan sorgu değişmez."""
    q = (clean or "").strip()
    if not _BARE_TICKER_RE.match(q):
        return q  # zaten adlı ya da serbest metin sorgusu
    name = _company_name_for(q)
    return f'{q} OR "{name}"' if name else q


def _fetch_feed(item: tuple[str, str]) -> list:
    _, url = item
    try:
        r = requests.get(url, headers={"User-Agent": _UA}, timeout=8)
        if r.status_code != 200:
            return []
        return feedparser.parse(r.content).entries or []
    except Exception:
        return []  # tek feed çökerse diğerleri akmaya devam etsin


def _fetch_google_raw(query: str) -> list[dict]:
    """Spesifik bir sorgu (örn 'turkish airlines') için Google News RSS → pool
    formatı (VADER + affected_assets). Genel piyasa feed'leri büyük BIST
    hisselerini (THYAO, AKBNK) çoğu kez atlar; Google News kapsayıcı.
    LLM enrich YOK — çağıran karar verir (tek sorgu kendi enrich'ini yapar,
    toplu yol tüm sorguları TEK batch enrich'ler)."""
    region, clean = _split_region(query)
    qualifier = _FINANCE_QUALIFIER.get(region, _FINANCE_QUALIFIER["tr"])
    subject = _expand_with_company_name(clean)
    try:
        r = requests.get(
            _GOOGLE_NEWS_RSS,
            params={"q": f"({subject}) {qualifier}",
                    **_REGION_PARAMS.get(region, _REGION_PARAMS["tr"])},
            headers={"User-Agent": _UA},
            timeout=6,
        )
        if r.status_code != 200:
            logger.warning(
                f"Google News {r.status_code} ({clean[:40]}) → bu sembol için haber yok")
            return []
        entries = feedparser.parse(r.content).entries or []
    except Exception:
        return []

    if not entries:
        # 200 + boş feed: ya gerçekten haber yok ya da kısıtlama. Ayırt
        # edemiyoruz; çağıran (_fetch_google_cached) eldeki eski sonucu korur.
        logger.debug(f"Google News boş feed ({clean[:40]})")

    out: list[dict] = []
    seen: set[str] = set()
    for e in entries[:20]:  # Google ilk 20 yeterli
        title = _strip_html(e.get("title", "")).strip()
        if not title or title.lower() in seen:
            continue
        if _NOISE_RE.search(title):  # insider filing ("X yetkilisi $Y hisse sattı") vb. → ele
            continue
        seen.add(title.lower())
        desc = _strip_html(e.get("summary", e.get("description", "")))[:500]
        text = f"{title} {desc}"
        sentiment = analyze_sentiment(text)
        out.append({
            "title": title,
            "description": desc,
            "url": e.get("link", ""),
            "published_at": _entry_date(e),
            "sentiment_label": sentiment["label"],
            "sentiment_score": sentiment["score"],
            "affected_assets": extract_affected_assets(text),
            # Haberi HANGİ sembol sorgusu getirdi. İstemci portföy haberini
            # buna göre eşliyor: `affected_assets` elle yazılmış ~100 şirketlik
            # bir sözlük (LMT, PLTR, GLRMK gibi semboller içinde yok) ve
            # başlıkta "Lockheed Martin" yazıp "LMT" yazmıyor → istemcideki
            # metin eşlemesi doğru haberlerin YARISINI eliyordu (canlıda
            # 34 haberin 16'sı).
            "matched_query": clean,
        })
    return out


def _prune_raw_cache(now: datetime) -> None:
    """Cache şişerse kullanılamayacak kadar eski kayıtları at."""
    if len(_raw_cache) <= _RAW_CACHE_MAX_ENTRIES:
        return
    limit = timedelta(minutes=_RAW_STALE_MAX_MINUTES)
    for key in [k for k, v in _raw_cache.items() if now - v["timestamp"] > limit]:
        _raw_cache.pop(key, None)


def _fetch_google_cached(query: str, force_refresh: bool = False) -> list[dict]:
    """`_fetch_google_raw` + sorgu cache'i. Boş yanıt eldeki sonucu SİLMEZ."""
    now = datetime.now(timezone.utc)
    key = (query or "").strip().lower()
    hit = _raw_cache.get(key)
    if (
        not force_refresh
        and hit is not None
        and now - hit["timestamp"] < timedelta(minutes=_NEWS_CACHE_TTL_MINUTES)
    ):
        return hit["data"]

    items = _fetch_google_raw(query)
    if items:
        _raw_cache[key] = {"data": items, "timestamp": now}
        _prune_raw_cache(now)
        return items
    if hit is not None and now - hit["timestamp"] < timedelta(
            minutes=_RAW_STALE_MAX_MINUTES):
        # Kısıtlama olasılığı: sembolün haberini ekrandan düşürme.
        return hit["data"]
    return []


def _is_fresh(item: dict, now: datetime | None = None) -> bool:
    """Haber tazelik penceresinde mi? (bkz. _MAX_NEWS_AGE_DAYS)"""
    published = item.get("published_at")
    if not isinstance(published, datetime):
        return True  # tarihi çözülemeyen haberi elemiyoruz (RSS bazen vermiyor)
    now = now or datetime.now(timezone.utc)
    if published.tzinfo is None:
        published = published.replace(tzinfo=timezone.utc)
    return (now - published) <= timedelta(days=_MAX_NEWS_AGE_DAYS)


def _drop_stale(items: list[dict]) -> list[dict]:
    now = datetime.now(timezone.utc)
    fresh = [i for i in items if _is_fresh(i, now)]
    dropped = len(items) - len(fresh)
    if dropped:
        logger.debug(f"Bayat haber elendi: {dropped}/{len(items)}")
    return fresh


def _fetch_google_news(query: str, force_refresh: bool = False) -> list[dict]:
    """Tek sorgu: ham çek + o sorguya özel LLM enrich (alaka + dil + skor).
    Ham çekim sorgu cache'inden gelir (toplu yol ile paylaşımlı) → hisse
    detayına girip sonra portföy haberine bakmak Google'ı iki kez dövmez."""
    _, clean = _split_region(query)  # enrich konusu öneksiz olsun
    return _llm_enrich(
        _drop_stale(_fetch_google_cached(query, force_refresh)), clean)


def _is_relevant(text: str, assets: list) -> bool:
    if assets:
        return True
    low = text.lower()
    return any(kw in low for kw in _FINANCE_KEYWORDS)


def _build_pool() -> list[dict]:
    """Tüm feed'leri paralel çek, dedupe et, alaka filtrele, tarihe göre sırala."""
    entries: list = []
    with ThreadPoolExecutor(max_workers=len(_FEEDS)) as ex:
        for res in ex.map(_fetch_feed, _FEEDS):
            entries.extend(res)

    seen: set[str] = set()
    pool: list[dict] = []
    for e in entries:
        title = _strip_html(e.get("title", "")).strip()
        if not title:
            continue
        if _NOISE_RE.search(title):
            continue
        key = title.lower()
        if key in seen:
            continue
        seen.add(key)

        desc = _strip_html(e.get("summary", e.get("description", "")))[:500]
        text = f"{title} {desc}"
        assets = extract_affected_assets(text)
        if not _is_relevant(text, assets):
            continue
        sentiment = analyze_sentiment(text)
        pool.append(
            {
                "title": title,
                "description": desc,
                "url": e.get("link", ""),
                "published_at": _entry_date(e),
                "sentiment_label": sentiment["label"],
                "sentiment_score": sentiment["score"],
                "affected_assets": assets,
            }
        )

    pool = _drop_stale(pool)
    pool.sort(key=lambda n: n["published_at"], reverse=True)
    return pool[:_POOL_LIMIT]


_GENERIC_QUERIES = {"", "stock market", "finance", "markets", "borsa", "piyasa"}


def _filter_for_query(pool: list[dict], query: str) -> list[dict]:
    """Genel sorgu → tüm havuz. Belirli sorgu (hisse/şirket) → eşleşenler;
    çok az eşleşirse (<3) havuzun tamamına düş (ekran boş kalmasın, istemci
    affected_assets ile zaten daraltıyor)."""
    q = (query or "").strip().lower()
    if q in _GENERIC_QUERIES:
        return pool
    terms = [t for t in re.split(r"[^\wğüşıöçĞÜŞİÖÇ]+", q) if len(t) > 2]
    if not terms:
        return pool
    matched = [
        n for n in pool
        if any(t in f"{n['title']} {n['description']}".lower() for t in terms)
        or any(t in a["symbol"].lower() or t in a["name"].lower()
               for a in n["affected_assets"] for t in terms)
    ]
    return matched if len(matched) >= 3 else pool


def _get_google_for_query(query: str, force_refresh: bool, now: datetime) -> list[dict]:
    """Google News'i sorgu başına cache'le; 15 dk içinde aynı sorgu gelirse RSS'i
    tekrar çağırma."""
    q = (query or "").strip().lower()
    if not q or q in _GENERIC_QUERIES:
        return []
    cached = _query_cache.get(q)
    if (
        not force_refresh
        and cached is not None
        and now - cached["timestamp"] < timedelta(minutes=_NEWS_CACHE_TTL_MINUTES)
    ):
        return cached["data"]
    items = _fetch_google_news(query, force_refresh)
    if items:  # boş gelirse cache'leme (geçici hata olabilir)
        _query_cache[q] = {"data": items, "timestamp": now}
    return items


_pool_refreshing = False


def _refresh_pool_bg():
    """Bayat havuzu arka planda yeniler (stale-while-revalidate); kullanıcı beklemez."""
    global _pool_refreshing
    try:
        pool = _build_pool()
        if pool:
            _news_cache["data"] = pool
            _news_cache["timestamp"] = datetime.now(timezone.utc)
    finally:
        _pool_refreshing = False


def get_financial_news(query: str = "stock market", force_refresh: bool = False):
    global _pool_refreshing
    now = datetime.now(timezone.utc)
    # 1) Genel piyasa havuzu (tüm sorgular için ortak). Stale-while-revalidate:
    #    elde veri varsa HEMEN döner; bayatsa arka planda yenilenir (kullanıcı
    #    beklemez). Yalnız ilk-ever yükleme (veri yok) veya force senkron bekler.
    cached = _news_cache["data"]
    ts = _news_cache["timestamp"]
    fresh = (
        cached is not None
        and ts is not None
        and now - ts < timedelta(minutes=_NEWS_CACHE_TTL_MINUTES)
    )
    if not force_refresh and cached is not None:
        pool = cached
        if not fresh and not _pool_refreshing:
            _pool_refreshing = True
            threading.Thread(target=_refresh_pool_bg, daemon=True).start()
    else:
        pool = _build_pool()
        if pool:  # boş havuzu cache'leme (geçici ağ hatası tüm feed'leri düşürmüş olabilir)
            _news_cache["data"] = pool
            _news_cache["timestamp"] = now

    # 2) Spesifik sorgu varsa Google News ile genişlet (THYAO, AKBNK, vb. büyük
    #    BIST hisseleri genel feed'lerde yok; Google News kapsayıcı). Dedupe edip
    #    Google sonuçlarını ÖNE al (alakalı, taze).
    google = _get_google_for_query(query, force_refresh, now)
    _, clean_query = _split_region(query)  # terim eşleşmesi öneksiz sorguyla
    if google:
        seen = {n["title"].lower() for n in google}
        merged = google + [n for n in pool if n["title"].lower() not in seen]
        return _filter_for_query(merged, clean_query)
    return _filter_for_query(pool, clean_query)


# Toplu haber (Portföyüm / İzleme): birden çok sembol sorgusunu SUNUCUDA paralel
# çek + TEK batch LLM enrich. Eski yol istemcide sembol-başına ayrı /latest
# çağırıyordu → N HTTP + N LLM çağrısı (Gemini free-tier throttle → ilk açılış
# yavaş). Burada 1 HTTP + 1 LLM; sonuç sorgu-kümesi başına 15 dk cache'lenir.
_multi_cache: dict[str, dict] = {}
_multi_refreshing: set[str] = set()


def _plan_fetches(queries: list[str], now: datetime,
                  force_refresh: bool) -> tuple[list[str], list[list[dict]]]:
    """Sorguları ikiye ayırır: bu turda ÇEKİLECEKLER + cache'ten gelenler.

    Bütçe (_FETCH_BUDGET) dolduğunda geri kalanlar cache'teki (bayat da olsa)
    sonuçla temsil edilir; hiç çekilmemiş sorgular öncelikli, sonra en eskiler.
    Böylece 40 sembollük bir portföy tek turda Google'ı dövmeden, birkaç turda
    tamamen kapsanır."""
    fetch_now: list[str] = []
    from_cache: list[list[dict]] = []
    candidates: list[tuple[int, datetime, str]] = []

    for q in queries:
        hit = _raw_cache.get((q or "").strip().lower())
        if (
            not force_refresh
            and hit is not None
            and now - hit["timestamp"] < timedelta(minutes=_NEWS_CACHE_TTL_MINUTES)
        ):
            from_cache.append(hit["data"])  # taze — çekmeye gerek yok
            continue
        # (0) hiç çekilmemiş → önce o; (1) bayat → tarihi eskiden yeniye
        candidates.append((0 if hit is None else 1,
                           hit["timestamp"] if hit else now, q))

    candidates.sort(key=lambda c: (c[0], c[1]))
    for rank, (_, _, q) in enumerate(candidates):
        if rank < _FETCH_BUDGET:
            fetch_now.append(q)
        else:
            hit = _raw_cache.get((q or "").strip().lower())
            if hit is not None:
                from_cache.append(hit["data"])
    return fetch_now, from_cache


def _collect_raw_for_symbols(clean: list[str],
                             force_refresh: bool = False) -> list[dict]:
    """Sorgu kümesini SUNUCUDA çek + dedupe + tarihe sırala — LLM YOK.
    Hızlı: yalnız RSS + bölge-yönlendirmeli VADER/TR skoru + deterministik
    filtreler (gürültü/yabancı/finans niteleyici). İlk açılış bunu HEMEN döner.

    Çekim bütçelidir (bkz. _FETCH_BUDGET): Google News kısıtlaması sessizdir
    (200 + boş feed), tek turda 48 sorgu atmak sembollerin çoğunu boş
    bırakıyordu."""
    now = datetime.now(timezone.utc)
    # Birincil sorgular ÖNCE, dil ikizleri sonra: bütçe kısıtlıysa her sembol
    # en azından kendi ana dilinden bir kez sorulur.
    primary = list(clean)
    twins = [q for q in _expand_bilingual(clean) if q not in primary]
    fetch_now, cached_lists = _plan_fetches(primary + twins, now, force_refresh)

    fetched: list[list[dict]] = []
    if fetch_now:
        with ThreadPoolExecutor(
                max_workers=min(len(fetch_now), _FETCH_CONCURRENCY)) as ex:
            fetched = list(ex.map(
                lambda q: _fetch_google_cached(q, force_refresh), fetch_now))
        empty = sum(1 for items in fetched if not items)
        if empty and empty >= len(fetch_now) // 2:
            logger.warning(
                f"Google News: {empty}/{len(fetch_now)} sorgu boş döndü — "
                "kısıtlama olabilir (eldeki cache'ten servis ediliyor)")

    raw: list[dict] = []
    seen: set[str] = set()
    for items in fetched + cached_lists:
        # Bayatı kotadan ÖNCE ele: yoksa sembolün 10'luk payı aylar
        # öncesinin haberleriyle doluyor ve taze haberler dışarıda kalıyor.
        for it in _drop_stale(items)[:_PER_SYMBOL_CAP]:
            k = it["title"].lower()
            if k and k not in seen:
                seen.add(k)
                raw.append(it)
    raw.sort(key=lambda n: n["published_at"], reverse=True)
    return _fair_share(raw)


def _fair_share(items: list[dict]) -> list[dict]:
    """Havuz tavanını (_SYMBOL_POOL_LIMIT) semboller arasında SIRAYLA paylaştırır.

    Ölçüm (4 Eyl, canlı, 38 pozisyonlu gerçek portföy): tavan saf tarih
    sırasıyla doluyordu ve 90 haberin 72'si ABD sembollerine gidiyordu — oysa
    portföyde 13 BIST/fon + 25 ABD var. ABD kaynakları çok daha sık yayın
    yaptığı için BIST haberleri tavanın altında kalıyordu; kullanıcı "Türk
    haberleri az geldi" dedi. Bir sembol tek başına 10 haber alırken bir
    diğeri 1 haberde kalıyordu.

    Round-robin: önce her sembolün EN YENİ haberi, sonra ikincileri… Bol
    haberli sembol yine çoğunluğu alır ama tavanı tek başına yiyemez.
    Sıralama sonunda yine tarihe göredir (ekran en yeniyi üstte gösterir).
    """
    if len(items) <= _SYMBOL_POOL_LIMIT:
        return items
    by_symbol: dict[str, list[dict]] = {}
    for it in items:  # items zaten tarihe göre azalan sıralı
        by_symbol.setdefault(it.get("matched_query") or "", []).append(it)
    picked: list[dict] = []
    round_index = 0
    while len(picked) < _SYMBOL_POOL_LIMIT:
        added = False
        for bucket in by_symbol.values():
            if round_index < len(bucket):
                picked.append(bucket[round_index])
                added = True
                if len(picked) >= _SYMBOL_POOL_LIMIT:
                    break
        if not added:  # her sembolün haberi tükendi
            break
        round_index += 1
    picked.sort(key=lambda n: n["published_at"], reverse=True)
    return picked


def _restore_silenced_symbols(raw: list[dict], enriched: list[dict]) -> list[dict]:
    """Enrich bir sembolün BÜTÜN haberlerini elediyse o sembolün en yeni
    haberini geri koyar.

    Ölçüm (4 Eyl 2026, 24 sorgu, gerçek RSS + gerçek LLM): ham 90 haberin 32'si
    (%36) enrich'te eleniyor ve 16 sembolün 5'i (AAPL · THYAO · TUPRS · KCHOL ·
    KARCL) listeden TAMAMEN kayboluyordu. Kullanıcı ilk açılışta ham listeyi
    (bol), ikinci açılışta enrich'liyi (az) görüyor → hem sayı düşüyor hem de
    portföyündeki hisse için "hiç haber yok" sanıyor.

    Alaka filtresi korunur: yalnız SESSİZLEŞEN sembol için ve yalnız BİR haber
    geri gelir; kalabalık sembollerde eleme aynen uygulanır."""
    kept = {it.get("matched_query") for it in enriched}
    restored: list[dict] = []
    for q in dict.fromkeys(it.get("matched_query") for it in raw):
        if q is None or q in kept:
            continue
        # raw yayın tarihine göre azalan sıralı → ilk eşleşen en yenisi.
        newest = next((it for it in raw if it.get("matched_query") == q), None)
        if newest is not None:
            restored.append(newest)
    if restored:
        logger.debug(
            f"Haber enrich {len(restored)} sembolü tamamen susturmuştu → "
            "her biri için en yeni haber geri konuldu")
    return enriched + restored


def _build_news_for_symbols(clean: list[str]) -> list[dict]:
    """Ham çekim + TEK batch LLM enrich (dil/alaka filtresi + rafine skor).
    ARKA PLANDA koşar (kullanıcı beklemez); sonucu sonraki açılış görür. Raw
    zaten _POOL_LIMIT'e kapalı → enrich JSON'ı max_tokens'a rahat sığar."""
    raw = _collect_raw_for_symbols(clean)
    enriched = _llm_enrich(raw, "portföydeki ve izlemedeki hisseler")
    filtered = len(enriched)
    enriched = _restore_silenced_symbols(raw, enriched)
    enriched.sort(key=lambda n: n["published_at"], reverse=True)
    out = enriched[:_SYMBOL_POOL_LIMIT]
    # Uçtan uca hat özeti: ham çekim → enrich → susturulan sembol telafisi →
    # ekrana giden. Katman kırılımı `_log_enrich` satırında; bu satır "kullanıcı
    # kaç haber görüyor" sorusunu tek bakışta yanıtlar.
    if raw:
        pct = (len(raw) - filtered) * 100 // len(raw)
        line = (f"Haber hatti ({len(clean)} sembol): {len(raw)} ham -> enrich "
                f"{filtered} (%{pct} elendi) -> telafi +{len(enriched) - filtered} "
                f"-> servis {len(out)}")
        (logger.warning if pct >= 50 else logger.info)(line)
    return out


def _refresh_multi_bg(key: str, clean: list[str]):
    """Bayat toplu-haber kümesini arka planda yeniler (kullanıcı beklemez)."""
    try:
        result = _build_news_for_symbols(clean)
        if result:
            _multi_cache[key] = {
                "data": result,
                "timestamp": datetime.now(timezone.utc),
            }
    finally:
        _multi_refreshing.discard(key)


def get_news_for_symbols(queries: list[str], force_refresh: bool = False) -> list[dict]:
    now = datetime.now(timezone.utc)
    clean = [q.strip() for q in (queries or []) if q and q.strip()][:_MAX_SYMBOLS]
    if not clean:
        return []
    key = "|".join(sorted({q.lower() for q in clean}))
    cached = _multi_cache.get(key)
    # Stale-while-revalidate: cache varsa HEMEN dön; bayatsa arka planda yenile.
    # Yalnız ilk-ever yükleme (cache yok) ya da force senkron bekler → tekrar
    # açılışlar anında gelir (tekil get_financial_news ile aynı kalıp).
    if not force_refresh and cached is not None:
        fresh = now - cached["timestamp"] < timedelta(minutes=_NEWS_CACHE_TTL_MINUTES)
        if not fresh and key not in _multi_refreshing:
            _multi_refreshing.add(key)
            threading.Thread(
                target=_refresh_multi_bg, args=(key, clean), daemon=True
            ).start()
        return cached["data"]

    # İlk yükleme (cache yok) ya da force: HAM sonucu HEMEN dön (hızlı + bol) →
    # LLM enrich'i ARKA PLANDA yap (skor/alaka rafine olur, sonraki açılış görür).
    # Eskiden enrich senkron bekleniyordu → ilk açılış yavaştı + LLM alaka filtresi
    # haber sayısını çok düşürüyordu (kullanıcı "13 Mayıs'a iniyor" dedi).
    raw = _collect_raw_for_symbols(clean, force_refresh=force_refresh)
    if raw:  # boş sonucu cache'leme (geçici ağ hatası olabilir)
        _multi_cache[key] = {"data": raw, "timestamp": now}
        if key not in _multi_refreshing:
            _multi_refreshing.add(key)
            threading.Thread(
                target=_refresh_multi_bg, args=(key, clean), daemon=True
            ).start()
    return raw
