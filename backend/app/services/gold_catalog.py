# =============================================================================
# Fiziki Altın/Gümüş Kataloğu (yerel, ağsız)
#
# Neden: kullanıcıların önemli bir kısmı altını KÂĞITTA değil elinde tutuyor
# ("ben altınımı somut tutuyorum, portföye onu da ekleyebilsek"). Uygulamada
# fiziki altın yalnız "Banka Altın Karşılaştırma" ekranında İZLENEBİLİYORDU;
# portföye giremediği için "toplam birikimim ne kadar" sorusu eksik cevap
# veriyordu — ki uygulamanın tek vaadi bu ("tüm birikimi tek yerde görmek").
#
# Çeyrek/tam/bilezik Yahoo'da YOKTUR (GC=F ons cinsinden VADELİ altındır,
# Türkiye serbest piyasa fiyatı değil). Bu yüzden fon (.FON) deseninin aynısı:
# sembol soneki + yerel katalog + kendi fiyat kaynağı.
#
#   GRAM.ALTIN · CEYREK.ALTIN · TAM.ALTIN · BILEZIK22.ALTIN · GRAM.GUMUS …
#
# Sonek neden iki tane: "GUMUS.ALTIN" saçma olurdu; sonek varlığın CİNSİ,
# kod ise BİÇİMİ (gram/çeyrek/tam). Portföyde okunur duruyor.
#
# Fiyat: `gold_rates_service` (canlidoviz birincil, truncgil yedek) — ürün
# adıyla eşlenir. Değerleme ALIŞ (bozdurma) fiyatıyla yapılır: kullanıcının
# sorusu "hepsini satsam ne kadar gelir", satarken alınan fiyat alıştır.
# =============================================================================

SUFFIXES = (".ALTIN", ".GUMUS")

# Portly sembolü → (gösterilen ad, gold_rates_service ürün adı).
# Ürün adı `get_bank_gold_rates()["extra_products"]` içindeki `name` ile
# birebir aynı olmalı; "Gram Altın" orada YOK (referans alanlarından gelir).
CATALOG: dict[str, tuple[str, str]] = {
    "GRAM.ALTIN": ("Gram Altın", "Gram Altın"),
    "HAS.ALTIN": ("Gram Has Altın", "Gram Has Altın"),
    "CEYREK.ALTIN": ("Çeyrek Altın", "Çeyrek Altın"),
    "YARIM.ALTIN": ("Yarım Altın", "Yarım Altın"),
    "TAM.ALTIN": ("Tam Altın", "Tam Altın"),
    "CUMHURIYET.ALTIN": ("Cumhuriyet Altını", "Cumhuriyet Altını"),
    "ATA.ALTIN": ("Ata Altın", "Ata Altın"),
    "BILEZIK22.ALTIN": ("22 Ayar Bilezik", "22 Ayar Bilezik"),
    "AYAR18.ALTIN": ("18 Ayar Altın", "18 Ayar Altın"),
    "AYAR14.ALTIN": ("14 Ayar Altın", "14 Ayar Altın"),
    "GRAM.GUMUS": ("Gram Gümüş", "Gümüş"),
}

# Aramada eşleşsin diye ek anahtar kelimeler (ad zaten aranıyor).
_KEYWORDS: dict[str, str] = {
    "GRAM.ALTIN": "fiziki altin gram kulce",
    "HAS.ALTIN": "fiziki altin has 24 ayar",
    "CEYREK.ALTIN": "fiziki altin ceyrek",
    "YARIM.ALTIN": "fiziki altin yarim",
    "TAM.ALTIN": "fiziki altin tam ziynet",
    "CUMHURIYET.ALTIN": "fiziki altin cumhuriyet",
    "ATA.ALTIN": "fiziki altin ata",
    "BILEZIK22.ALTIN": "fiziki altin bilezik 22 ayar takı",
    "AYAR18.ALTIN": "fiziki altin 18 ayar",
    "AYAR14.ALTIN": "fiziki altin 14 ayar",
    "GRAM.GUMUS": "fiziki gumus gram",
}

_TR_FOLD = str.maketrans("ıİşŞçÇöÖüÜğĞâÂîÎûÛ", "iissccoouuggaaiiuu")


def _fold(s: str) -> str:
    return (s or "").translate(_TR_FOLD).lower().strip()


def is_gold_symbol(symbol: str) -> bool:
    """'CEYREK.ALTIN' → True. Katalogda olmayan uydurma sonek kabul EDİLMEZ:
    fiyat kaynağı ürün adına bağlı, tanımadığımızı fiyatlayamayız."""
    return (symbol or "").upper() in CATALOG


def is_gold_suffix(symbol: str) -> bool:
    """Sonek kontrolü (katalogda olmasa bile) — Yahoo'ya sorulmasın diye."""
    return (symbol or "").upper().endswith(SUFFIXES)


def name_of(symbol: str) -> str | None:
    row = CATALOG.get((symbol or "").upper())
    return row[0] if row else None


def product_of(symbol: str) -> str | None:
    """Sembol → `gold_rates_service` ürün adı."""
    row = CATALOG.get((symbol or "").upper())
    return row[1] if row else None


def is_silver(symbol: str) -> bool:
    return (symbol or "").upper().endswith(".GUMUS")


def search(query: str, limit: int = 10) -> list[dict]:
    """Ad ya da anahtar kelimeye göre arar → sembol arama sözleşmesi.

    "çeyrek", "ceyrek altin", "fiziki", "bilezik" hepsi eşleşir."""
    q = _fold(query)
    if len(q) < 2:
        return []
    words = [w for w in q.split() if w]

    out: list[tuple[int, dict]] = []
    for symbol, (name, _product) in CATALOG.items():
        hay = f"{_fold(name)} {_KEYWORDS.get(symbol, '')} {_fold(symbol)}"
        if not all(w in hay for w in words):
            continue
        rank = 0 if _fold(name).startswith(q) else 1
        out.append((rank, {
            "symbol": symbol,
            "name": name,
            "market": "FİZİKİ",
            "type": "Fiziki Altın" if not is_silver(symbol) else "Fiziki Gümüş",
        }))

    out.sort(key=lambda x: (x[0], x[1]["name"]))
    return [item for _rank, item in out[:limit]]
