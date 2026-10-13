# =============================================================================
# Sembol Kanonikleştirme
#
# Kullanıcı "THY" veya "THYAO" yazdığında Yahoo bunu Türk Hava Yolları
# (THYAO.IS) yerine alakasız bir ABD enstrümanına çözebiliyor (örn. "THY"
# = Toews Agility Shares ETF). Bu modül, bilinen BIST şirketlerinin çıplak
# kodlarını / yaygın takma adlarını kanonik ".IS" sembolüne sabitler.
# =============================================================================

# Yaygın takma ad → kanonik sembol.
_ALIASES = {
    "THY": "THYAO.IS",
    "TURKISH AIRLINES": "THYAO.IS",
    "TURK HAVA YOLLARI": "THYAO.IS",
    "TÜRK HAVA YOLLARI": "THYAO.IS",
}

# .IS soneki olmadan yazılabilen, Yahoo'da yabancı enstrümana çözülme
# riski olan BIST çıplak kodları.
_BIST_BARE = {
    "THYAO", "ASELS", "GARAN", "AKBNK", "ISCTR", "YKBNK", "KCHOL",
    "SAHOL", "BIMAS", "MGROS", "EREGL", "TCELL", "PGSUS", "TUPRS",
    "FROTO", "TOASO",
}


def canonical(symbol: str) -> str:
    """Sembolü kanonik biçime getirir; tanınmayan semboller değişmeden döner."""
    if not symbol:
        return symbol
    s = symbol.strip().upper()
    if s in _ALIASES:
        return _ALIASES[s]
    # Çıplak BIST kodu (nokta/parite/endeks değil) → .IS ekle.
    if s in _BIST_BARE and "." not in s and "=" not in s and not s.startswith("^"):
        return f"{s}.IS"
    fund = _fund_from_bist_suffix(s)
    if fund:
        return fund
    return s


def _fund_from_bist_suffix(s: str) -> str | None:
    """'TLY.IS' → 'TLY.FON'. Ekstre içe aktarımı, kur TRY diye HER sembole
    ".IS" ekliyordu; TEFAS fon kodları da öyle BIST hissesi sanılıp Yahoo'da
    aranıyor ve bulunamıyordu. Eski satırlar veri göçüyle düzeltildi, bu kural
    kalanları (elle yazılmış/bayat istemci cache'i) çalışma anında yakalar.

    Yalnız ÜÇ harfli kodlar: TEFAS fon kodları daima 3 harf, BIST pay kodları
    4-5 harf → çakışma yok. Çıplak koda DOKUNMAZ: "URA" hem bir TEFAS fonu hem
    Global X Uranium ETF'i; kur bilgisi olmadan hangisi olduğu bilinemez."""
    if not s.endswith(".IS"):
        return None
    base = s[:-3]
    if len(base) != 3:
        return None
    from app.services import fund_catalog
    return fund_catalog.to_symbol(base) if fund_catalog.is_known_code(base) \
        else None
