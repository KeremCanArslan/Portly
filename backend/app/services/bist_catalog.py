# =============================================================================
# Yerel BIST Kataloğu + Türkçe-normalize arama
#
# Sorun: Yahoo (yf.Search) Türkçe karakterli sorguları ("gülermak", "türk
# hava", "şişe") boş döndürüyor; ASCII'de ("gulermak") çalışıyor ama o zaman
# da çoğu BIST hissesi `.IS` yerine alakasız .F/.SG enstrümanına düşüyor
# ("garanti", "bim", "koç" → yabancı çöp). Çözüm: (1) sorguyu Türkçe→ASCII
# katla, (2) bu doğrulanmış yerel katalogda eşleşeni Yahoo sonuçlarının
# ÖNÜNE koy. Her ticker yfinance ile doğrulandı (geçersizler elendi).
# =============================================================================

# Türkçe diakritik → ASCII (Yahoo araması bunları tanımıyor).
_TR_FOLD = str.maketrans("ıİşŞçÇöÖüÜğĞâÂîÎûÛ", "iissccoouuggaaiiuu")


def tr_fold(s: str) -> str:
    """'Gülermak Ağır' → 'gulermak agir'. Arama karşılaştırması için."""
    return s.translate(_TR_FOLD).lower().strip()


# Çıplak BIST kodu → resmi Türkçe ad. Tümü yfinance'te doğrulandı.
CATALOG = {
    "THYAO": "Türk Hava Yolları", "ASELS": "Aselsan", "GARAN": "Garanti BBVA",
    "AKBNK": "Akbank", "ISCTR": "İş Bankası", "YKBNK": "Yapı Kredi Bankası",
    "KCHOL": "Koç Holding", "SAHOL": "Sabancı Holding",
    "BIMAS": "BİM Birleşik Mağazalar", "MGROS": "Migros Ticaret",
    "EREGL": "Ereğli Demir Çelik", "TCELL": "Turkcell",
    "PGSUS": "Pegasus Hava Yolları", "TUPRS": "Tüpraş",
    "FROTO": "Ford Otosan", "TOASO": "Tofaş Oto", "TTKOM": "Türk Telekom",
    "SISE": "Şişe Cam", "PETKM": "Petkim", "SASA": "Sasa Polyester",
    "HEKTS": "Hektaş", "KRDMD": "Kardemir D", "GUBRF": "Gübre Fabrikaları",
    "VESTL": "Vestel", "ARCLK": "Arçelik", "ENKAI": "Enka İnşaat",
    "TKFEN": "Tekfen Holding", "DOHOL": "Doğan Holding",
    "ALARK": "Alarko Holding", "GLRMK": "Gülermak Ağır Sanayi",
    "ODAS": "Odaş Elektrik", "ZOREN": "Zorlu Enerji", "AYGAZ": "Aygaz",
    "TAVHL": "TAV Havalimanları", "HALKB": "Halkbank", "VAKBN": "Vakıfbank",
    "SKBNK": "Şekerbank", "ASTOR": "Astor Enerji",
    "SMRTG": "Smart Güneş Enerjisi", "KONTR": "Kontrolmatik",
    "REEDR": "Reeder Teknoloji", "OYAKC": "Oyak Çimento", "CIMSA": "Çimsa",
    "AKCNS": "Akçansa", "BRSAN": "Borusan Boru", "EKGYO": "Emlak Konut GYO",
    "ISGYO": "İş GYO", "TRGYO": "Torunlar GYO", "MAVI": "Mavi Giyim",
    "BIZIM": "Bizim Toptan", "SOKM": "Şok Marketler", "ULKER": "Ülker Bisküvi",
    "CCOLA": "Coca-Cola İçecek", "AEFES": "Anadolu Efes",
    "TTRAK": "Türk Traktör", "OTKAR": "Otokar", "KARSN": "Karsan Otomotiv",
    "DOAS": "Doğuş Otomotiv", "LOGO": "Logo Yazılım", "NETAS": "Netaş Telekom",
    "ARDYZ": "ARD Bilişim", "ALTNY": "Altınay Savunma", "KLSER": "Kaleseramik",
    "EGEEN": "Ege Endüstri", "BRYAT": "Borusan Yatırım", "ISMEN": "İş Yatırım",
    "GWIND": "Galata Wind", "ENJSA": "Enerjisa", "AKSEN": "Aksa Enerji",
    "AKSA": "Aksa Akrilik", "KORDS": "Kordsa", "BAGFS": "Bagfaş",
    "ECILC": "Eczacıbaşı İlaç", "DEVA": "Deva Holding", "SELEC": "Selçuk Ecza",
    "TMSN": "Tümosan", "KAYSE": "Kayseri Şeker", "PENTA": "Penta Teknoloji",
    "EUPWR": "Europower", "CWENE": "CW Enerji", "BINHO": "Bien Yapı",
    "TABGD": "TAB Gıda", "CANTE": "Çan2 Termik", "MIATK": "Mia Teknoloji",
    "PASEU": "Pasifik GYO", "FENER": "Fenerbahçe Futbol",
    "GSRAY": "Galatasaray Sportif", "BJKAS": "Beşiktaş Futbol",
    "YEOTK": "Yeo Teknoloji", "ESEN": "Esenboğa Elektrik",
    "IZENR": "İzdemir Enerji", "HUNER": "Hun Yenilenebilir",
}

# Önceden katlanmış indeks: (ticker, ad, folded_ticker, folded_ad).
_INDEX = [
    (t, n, t.lower(), tr_fold(n)) for t, n in CATALOG.items()
]


def search_catalog(query: str, limit: int = 10):
    """Yerel BIST kataloğunda Türkçe-duyarsız arama.

    market_data_service.search_symbols ile aynı sözlük biçimini döndürür:
    {symbol, name, market, type}. Skor: ticker tam > ticker baş > ad kelime
    başı > geçiş. Eşleşme yoksa boş liste.
    """
    fq = tr_fold(query)
    if not fq:
        return []
    out = []
    for ticker, name, ft, fn in _INDEX:
        score = -1
        if ft == fq:
            score = 100
        elif ft.startswith(fq):
            score = 90
        elif any(w.startswith(fq) for w in fn.split()):
            score = 80
        elif fq in fn or fq in ft:
            score = 60
        if score >= 0:
            out.append((score, ticker, name))
    out.sort(key=lambda x: (-x[0], x[1]))
    return [
        {
            "symbol": f"{t}.IS",
            "name": n,
            "market": "BIST",
            "type": "EQUITY",
        }
        for _, t, n in out[:limit]
    ]
