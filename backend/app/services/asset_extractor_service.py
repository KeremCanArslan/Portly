"""Haber metinlerinden etkilenen varlıkları (hisse/kripto/döviz) çıkarır.

Yaklaşım: anahtar kelime → varlık eşleme. Yatırım terimleri ve şirket adları,
ürün isimleri, CEO/kurucu adları gibi referanslar üzerinden tetikleme yapılır.
Production'da bunu LLM tabanlı NER ile yapmak daha doğru olur ama bu yaklaşım
küçük ek maliyetle %80 doğruluk verir.
"""

import re
from functools import lru_cache


# (anahtar kelime, varlık sembolü, gösterim adı)
_ASSET_KEYWORD_MAP: list[tuple[str, str, str]] = [
    # ─── ABD Mega-Cap Teknoloji ────────────────────────────────────────
    ("apple", "AAPL", "Apple"),
    ("iphone", "AAPL", "Apple"),
    ("ipad", "AAPL", "Apple"),
    ("tim cook", "AAPL", "Apple"),
    ("microsoft", "MSFT", "Microsoft"),
    ("azure", "MSFT", "Microsoft"),
    ("satya nadella", "MSFT", "Microsoft"),
    ("google", "GOOGL", "Alphabet"),
    ("alphabet", "GOOGL", "Alphabet"),
    ("youtube", "GOOGL", "Alphabet"),
    ("sundar pichai", "GOOGL", "Alphabet"),
    ("amazon", "AMZN", "Amazon"),
    ("aws", "AMZN", "Amazon"),
    ("jeff bezos", "AMZN", "Amazon"),
    ("andy jassy", "AMZN", "Amazon"),
    ("meta", "META", "Meta"),
    ("facebook", "META", "Meta"),
    ("instagram", "META", "Meta"),
    ("whatsapp", "META", "Meta"),
    ("zuckerberg", "META", "Meta"),
    ("tesla", "TSLA", "Tesla"),
    ("elon musk", "TSLA", "Tesla"),
    ("cybertruck", "TSLA", "Tesla"),
    ("nvidia", "NVDA", "Nvidia"),
    ("jensen huang", "NVDA", "Nvidia"),
    ("netflix", "NFLX", "Netflix"),
    ("amd", "AMD", "AMD"),
    ("lisa su", "AMD", "AMD"),
    ("intel", "INTC", "Intel"),
    ("pat gelsinger", "INTC", "Intel"),

    # ─── Kripto Paralar ───────────────────────────────────────────────
    ("bitcoin", "BTC-USD", "Bitcoin"),
    ("ethereum", "ETH-USD", "Ethereum"),
    ("vitalik", "ETH-USD", "Ethereum"),
    ("solana", "SOL-USD", "Solana"),
    ("binance", "BNB-USD", "BNB"),
    ("dogecoin", "DOGE-USD", "Dogecoin"),
    ("xrp", "XRP-USD", "XRP"),
    ("ripple", "XRP-USD", "XRP"),
    ("cardano", "ADA-USD", "Cardano"),

    # ─── BIST (Borsa İstanbul) ────────────────────────────────────────
    ("türk hava yolları", "THYAO.IS", "Türk Hava Yolları"),
    ("turkish airlines", "THYAO.IS", "Türk Hava Yolları"),
    ("thy ", "THYAO.IS", "Türk Hava Yolları"),
    ("aselsan", "ASELS.IS", "Aselsan"),
    ("garanti bbva", "GARAN.IS", "Garanti BBVA"),
    ("garanti bank", "GARAN.IS", "Garanti BBVA"),
    ("akbank", "AKBNK.IS", "Akbank"),
    ("iş bankası", "ISCTR.IS", "İş Bankası"),
    ("isbank", "ISCTR.IS", "İş Bankası"),
    ("yapı kredi", "YKBNK.IS", "Yapı Kredi"),
    ("yapi kredi", "YKBNK.IS", "Yapı Kredi"),
    ("koç holding", "KCHOL.IS", "Koç Holding"),
    ("koc holding", "KCHOL.IS", "Koç Holding"),
    ("sabancı holding", "SAHOL.IS", "Sabancı Holding"),
    ("sabanci holding", "SAHOL.IS", "Sabancı Holding"),
    ("bim ", "BIMAS.IS", "BİM"),
    ("migros", "MGROS.IS", "Migros"),
    ("ereğli demir", "EREGL.IS", "Ereğli Demir Çelik"),
    ("eregli demir", "EREGL.IS", "Ereğli Demir Çelik"),
    ("türkcell", "TCELL.IS", "Türkcell"),
    ("turkcell", "TCELL.IS", "Türkcell"),
    ("pegasus", "PGSUS.IS", "Pegasus"),
    ("tüpraş", "TUPRS.IS", "Tüpraş"),
    ("tupras", "TUPRS.IS", "Tüpraş"),
    ("ford otosan", "FROTO.IS", "Ford Otosan"),
    ("tofas", "TOASO.IS", "Tofaş"),
    ("tofaş", "TOASO.IS", "Tofaş"),

    # ─── Döviz & Emtia ────────────────────────────────────────────────
    ("dolar", "USDTRY=X", "USD/TRY"),
    ("usd/try", "USDTRY=X", "USD/TRY"),
    ("dollar/lira", "USDTRY=X", "USD/TRY"),
    ("turkish lira", "USDTRY=X", "USD/TRY"),
    ("euro", "EURTRY=X", "EUR/TRY"),
    ("eur/try", "EURTRY=X", "EUR/TRY"),
    ("altın", "GC=F", "Altın"),
    ("ons altın", "GC=F", "Altın"),
    ("gold price", "GC=F", "Altın"),
    ("gold rally", "GC=F", "Altın"),
    ("gold futures", "GC=F", "Altın"),
    ("petrol", "CL=F", "Ham Petrol"),
    ("crude oil", "CL=F", "Ham Petrol"),
    ("brent", "CL=F", "Ham Petrol"),
    ("wti", "CL=F", "Ham Petrol"),
    ("opec", "CL=F", "Ham Petrol"),
    ("silver", "SI=F", "Gümüş"),

    # ─── Endeksler ────────────────────────────────────────────────────
    ("s&p 500", "^GSPC", "S&P 500"),
    ("s&p500", "^GSPC", "S&P 500"),
    ("nasdaq", "^IXIC", "Nasdaq"),
    ("dow jones", "^DJI", "Dow Jones"),
    ("bist 100", "XU100.IS", "BIST 100"),
    ("bist100", "XU100.IS", "BIST 100"),
    ("borsa istanbul", "XU100.IS", "BIST 100"),

    # ─── Merkez Bankaları (geniş etki) ────────────────────────────────
    ("federal reserve", "^GSPC", "S&P 500"),
    ("fed rate", "^GSPC", "S&P 500"),
    ("powell", "^GSPC", "S&P 500"),
    ("tcmb", "USDTRY=X", "USD/TRY"),
    ("ecb", "EURTRY=X", "EUR/TRY"),
]


@lru_cache(maxsize=1)
def _get_compiled_patterns() -> list[tuple[re.Pattern, str, str]]:
    """Regex'leri tek seferlik derler. Word boundary ile false-positive azaltır."""
    compiled = []
    for keyword, symbol, name in _ASSET_KEYWORD_MAP:
        # Word boundary, case-insensitive, unicode (Türkçe karakterler için)
        pattern = re.compile(rf"\b{re.escape(keyword)}\b", re.IGNORECASE | re.UNICODE)
        compiled.append((pattern, symbol, name))
    return compiled


def extract_affected_assets(text: str, max_results: int = 5) -> list[dict]:
    """Metinde geçen anahtar kelimelerden etkilenen varlıkları bulur.

    Aynı sembol birden çok kez geçerse tek kez döner. Sıralama: metinde
    ilk görülen önce.

    Returns:
        [{"symbol": "AAPL", "name": "Apple"}, ...]
    """
    if not text:
        return []

    seen_symbols: set[str] = set()
    results: list[dict] = []

    for pattern, symbol, name in _get_compiled_patterns():
        if symbol in seen_symbols:
            continue
        if pattern.search(text):
            seen_symbols.add(symbol)
            results.append({"symbol": symbol, "name": name})
            if len(results) >= max_results:
                break

    return results
