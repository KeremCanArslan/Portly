"""Şirket adını kullanıcıya gösterilecek kısa biçime getirir.

Yahoo ve Finnhub resmî unvanı veriyor ("Apple Inc.", "NVIDIA Corporation",
"Kardemir Celik Sanayi AS"); izleme listesi ve portföy bu unvanla doluyordu
(16 Kas 2026). Burada yalnız sondaki hukuki ek atılır, ad uydurulmaz:
- ABD/Avrupa: Inc., Corporation, Corp., Ltd., Limited, plc, N.V., S.A., AG, SE.
  "The X Company" → "X".
- BIST (.IS): A.S., AS, A.Ş., Anonim Şirketi ve sondaki "(Sanayi) ve Ticaret".
  Yahoo bu adları çoğunlukla Türkçe karaktersiz veriyor → yaygın kelimeler
  sözlükle düzeltilir (Celik → Çelik). Sözlükte olmayan kelime olduğu gibi kalır.
Yerel kataloglardaki adlar zaten temiz; bu fonksiyon onlara dokunmaz.
"""

import re

_SUFFIX = re.compile(
    r"(?:,?\s+(?:"
    r"(?i:inc\.?|incorporated|corporation|corp\.?|co\.|ltd\.?|limited|plc|"
    r"l\.p\.|n\.v\.|s\.a\.|s\.p\.a\.|a\.s\.|a\.ş\.|t\.a\.s\.|anonim\s+[sş]irketi)"
    r"|AS|AŞ|AG|SE|NV|SA))+\s*$"
)
_THE_COMPANY = re.compile(r"^The\s+(.+?)\s+Company$")
_TR_TRADE = re.compile(r"\s+(?:Sanayi\s+)?[vV]e\s+Tic(?:aret|\.)?$")

# Yahoo'nun ASCII'ye katladığı yaygın unvan kelimeleri → Türkçe yazım.
_TR_WORDS = {
    "Agir": "Ağır", "Akaryakit": "Akaryakıt", "Altin": "Altın",
    "Bankasi": "Bankası", "Bilisim": "Bilişim", "Celik": "Çelik",
    "Cimento": "Çimento", "Dagitim": "Dağıtım", "Dis": "Dış",
    "Dokum": "Döküm", "Egitim": "Eğitim", "Gayrimenkul": "Gayrimenkul",
    "Gelistirme": "Geliştirme", "Gida": "Gıda", "Gubre": "Gübre",
    "Ihracat": "İhracat", "Ilac": "İlaç", "Iletisim": "İletişim",
    "Insaat": "İnşaat", "Isletmeleri": "İşletmeleri", "Ithalat": "İthalat",
    "Kagit": "Kağıt", "Katilim": "Katılım", "Magazacilik": "Mağazacılık",
    "Muhendislik": "Mühendislik", "Ortakligi": "Ortaklığı", "Ozel": "Özel",
    "Saglik": "Sağlık", "Seker": "Şeker", "Sigortasi": "Sigortası",
    "Sise": "Şişe", "Tarim": "Tarım", "Tasimacilik": "Taşımacılık",
    "Turk": "Türk", "Turkiye": "Türkiye", "Urunleri": "Ürünleri",
    "Uretim": "Üretim", "Yatirim": "Yatırım", "Yazilim": "Yazılım",
}


def clean(name: str | None, symbol: str) -> str | None:
    if not name or name == symbol:
        return name
    out = name.strip()
    m = _THE_COMPANY.match(out)
    if m:
        out = m.group(1)
    out = _SUFFIX.sub("", out).rstrip(" ,")
    if symbol.upper().endswith(".IS"):
        out = _TR_TRADE.sub("", out)
        out = " ".join(_TR_WORDS.get(w, w) for w in out.split())
    return out or name
