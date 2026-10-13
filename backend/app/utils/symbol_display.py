"""Sembolleri kullanıcıya gösterilecek ada çevirir (frontend
`lib/utils/symbol_display.dart` `compact()` ile aynı sözleşme).

Neden backend'de de gerekli: AI'ya giden bağlamda HAM sembol yazıyorduk
("GC=F: 5 lot, ..."), model de cevabında birebir onu tekrarlıyordu — kullanıcı
sohbette "GC=F" görüyordu. Arayüzdeki `SymbolDisplay` bunu düzeltemez: LLM
çıktısı serbest metindir. Çözüm, modele ham sembolü HİÇ göstermemek.

Kayıt/sorgu/filtre HAM sembolde kalır; bu yalnız gösterim (ve modele verilen
metin) içindir.
"""

import re

_LABELS = {
    "GC=F": "Altın",
    "SI=F": "Gümüş",
    "CL=F": "Ham Petrol",
    "USDTRY=X": "USD/TRY",
    "EURTRY=X": "EUR/TRY",
    "GBPTRY=X": "GBP/TRY",
    "BTC-USD": "Bitcoin",
    "ETH-USD": "Ethereum",
    "SOL-USD": "Solana",
    "BNB-USD": "BNB",
    "DOGE-USD": "Dogecoin",
    "XRP-USD": "XRP",
    "^GSPC": "S&P 500",
    "^IXIC": "Nasdaq",
    "^DJI": "Dow Jones",
    "XU100.IS": "BIST 100",
    "THYAO.IS": "Türk Hava Yolları",
    "ASELS.IS": "Aselsan",
    "GARAN.IS": "Garanti BBVA",
    "AKBNK.IS": "Akbank",
    "ISCTR.IS": "İş Bankası",
    "YKBNK.IS": "Yapı Kredi",
    "KCHOL.IS": "Koç Holding",
    "SAHOL.IS": "Sabancı Holding",
    "BIMAS.IS": "BİM",
    "MGROS.IS": "Migros",
    "EREGL.IS": "Ereğli Demir Çelik",
    "TCELL.IS": "Türkcell",
    "PGSUS.IS": "Pegasus",
    "TUPRS.IS": "Tüpraş",
    "FROTO.IS": "Ford Otosan",
    "TOASO.IS": "Tofaş",
}

_TRAILING_DIGITS = re.compile(r"\d+$")


def compact(symbol: str) -> str:
    """Ham sembol → kullanıcı dostu ad. Bilinmeyen sembolde sonek kırpılır."""
    if not symbol:
        return ""
    s = symbol.upper()
    mapped = _LABELS.get(s)
    if mapped:
        return mapped
    # Haritasız kripto: Yahoo "HYPE32196-USD" gibi sembole sayısal id ekliyor.
    if s.endswith("-USD"):
        base = _TRAILING_DIGITS.sub("", s[:-4])
        if base:
            return base
    for suffix in (".IS", ".TR", ".FON"):
        if s.endswith(suffix):
            return s[: -len(suffix)]
    # Yahoo emtia/parite soneki ("=F"/"=X") kullanıcıya anlamsız.
    if s.endswith(("=X", "=F")):
        return s[:-2]
    return s
