"""Kurum-bağımsız ekstre okuma — Midas profili tutmadığında son deterministik çare.

Neden var: her aracı kurumun kendi PDF düzeni var ve hepsine profil yazmak
mümkün değil. Bu modül, sütun adlarını BİLMEDEN bir işlem satırını tanımaya
çalışır. AI YOK — iki kademeli düz mantık:

  1. BAŞLIK EŞLEME (güvenilir): satırda "Tarih ... Adet ... Fiyat ... Tutar"
     gibi bir başlık varsa sütun sırası oradan öğrenilir ve alttaki satırlara
     konumla uygulanır. Kurumların çoğu böyle bir başlık basar.

  2. ÇARPIM SEZGİSİ (yedek): başlık yoksa, satırdaki sayılar arasında
     a × b ≈ c olan bir üçlü aranır. Bir ekstre satırında bu üçlü neredeyse
     her zaman adet × fiyat = tutar'dır; komisyon/stopaj tutarı biraz
     kaydırabildiği için %2 tolerans verilir. Bu, "en büyük sayı tutardır"
     gibi kırılgan varsayımlardan çok daha sağlam.

Sonuçlar `source: "generic"` ile işaretlenir; UI bunları "tahmini okuma"
olarak gösterip kullanıcıya kontrol ettirir. Midas profili tuttuğunda bu
modül HİÇ çalışmaz — aynı satırlar iki kez sayılmasın.

Bilinen sınırı: iptal/gerçekleşmemiş emir sütununu bilemez. Bu yüzden
satırda iptal/red ifadesi geçiyorsa satır atlanır (Midas'ta bu tuzağın
portföyü tamamen bozduğu görüldü).
"""

import re
from datetime import datetime

from loguru import logger

from app.services.bist_catalog import CATALOG as BIST_CATALOG
from app.services import fund_catalog

_BUY = {"ALIŞ", "ALIS", "AL", "ALIM", "ALINAN", "BUY", "ALIŞ İŞLEMİ"}
_SELL = {"SATIŞ", "SATIS", "SAT", "SATIM", "SATILAN", "SELL", "SATIŞ İŞLEMİ"}

# Gerçekleşmemiş emirler işlem DEĞİL. Sütununu bilemediğimiz için
# satırda geçen ifadeye bakılır.
_NOT_EXECUTED = re.compile(
    r"iptal|red(?:dedild)?|gerçekleşmedi|gerceklesmedi|bekliyor|beklemede|"
    r"kısmi\s*iptal|expired|cancel",
    re.IGNORECASE,
)

# Başlık/dipnot/toplam satırları — işlem sanılmamalı.
_NOISE = re.compile(
    r"sayfa\s*\d|toplam|bakiye|devir|müşteri|musteri|hesap\s+no|tckn|vergi\s+no|"
    r"adres|telefon|e-?posta|imza|ekstre\s+dönem|iban|mersis|ticaret\s+sicil",
    re.IGNORECASE,
)

_DATE_RE = re.compile(
    r"\b(\d{1,2})[./](\d{1,2})[./](\d{4}|\d{2})\b|\b(\d{4})-(\d{2})-(\d{2})\b"
)
_NUM_RE = re.compile(r"-?\d[\d.,]*")
_SYMBOL_RE = re.compile(r"\b([A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ0-9.]{1,9})\b")

_CURRENCIES = {"TL", "TRY", "USD", "EUR", "GBP", "$", "₺", "€"}

# Sütun başlığı ipuçları. Kurumlar aynı kavrama farklı ad veriyor.
_HDR = {
    "date": ("tarih", "işlem tarihi", "islem tarihi", "valör", "valor"),
    "symbol": ("kıymet", "kiymet", "sembol", "hisse", "menkul", "enstrüman",
               "enstruman", "sermaye piyasası aracı", "kod"),
    "side": ("işlem", "islem", "işlem tipi", "islem tipi", "işlem türü",
             "alım/satım", "alim/satim", "yön", "yon"),
    "quantity": ("adet", "nominal", "miktar", "lot", "pay adedi"),
    "price": ("fiyat", "birim fiyat", "ortalama fiyat", "kur"),
    "total": ("tutar", "toplam", "işlem tutarı", "islem tutari", "net tutar"),
}


def _to_float(raw: str) -> float | None:
    """'1.234,56' / '1,234.56' / '1234.56' → float."""
    s = raw.strip().replace(" ", "")
    for c in ("₺", "$", "€", "TL", "TRY", "USD", "EUR"):
        s = s.replace(c, "")
    if not s or not any(ch.isdigit() for ch in s):
        return None
    neg = s.startswith("-")
    s = s.lstrip("+-")
    d, c = s.rfind("."), s.rfind(",")
    if d == -1 and c == -1:
        val = s
    else:
        sep = max(d, c)
        tail = s[sep + 1:]
        if len(tail) == 3 and tail.isdigit():
            val = s.replace(".", "").replace(",", "")
        else:
            val = f"{s[:sep].replace('.', '').replace(',', '')}.{tail}"
    try:
        out = float(val)
    except ValueError:
        return None
    return -out if neg else out


def _parse_date(line: str) -> datetime | None:
    m = _DATE_RE.search(line)
    if not m:
        return None
    try:
        if m.group(1):
            day, month, yr = int(m.group(1)), int(m.group(2)), m.group(3)
            year = int(yr) if len(yr) == 4 else (
                2000 + int(yr) if int(yr) < 80 else 1900 + int(yr))
            return datetime(year, month, day)
        return datetime(int(m.group(4)), int(m.group(5)), int(m.group(6)))
    except ValueError:
        return None


def _detect_side(line: str) -> str | None:
    tokens = set(re.findall(r"[A-ZÇĞİÖŞÜ]+", line.upper()))
    if tokens & _SELL:
        return "SELL"
    if tokens & _BUY:
        return "BUY"
    return None


def _detect_symbol(line: str) -> str | None:
    """Satırdaki sembol adayı. BIST kataloğundakiler önceliklidir."""
    skip = _BUY | _SELL | _CURRENCIES | {
        "ADET", "LOT", "TUTAR", "FIYAT", "TARIH", "NOMINAL", "MIKTAR",
        "GERCEKLESTI", "GERÇEKLEŞTİ", "PIYASA", "LIMIT", "EMRI", "EMİR",
    }
    cands = [c for c in _SYMBOL_RE.findall(line.upper()) if c not in skip]
    for c in cands:
        if c in BIST_CATALOG:
            return f"{c}.IS"
    # TEFAS yatırım fonu (TLY, LTL …): genel ekstreler TL hesabından gelir,
    # 3 harfli kod orada hisseden çok fon demektir. Katalogda yoksa dokunma.
    for c in cands:
        if len(c) == 3 and fund_catalog.is_known_code(c):
            return fund_catalog.to_symbol(c)
    for c in cands:
        if 2 <= len(c) <= 6 and not c.isdigit():
            return c
    return None


def detect_header(line: str) -> dict[str, int] | None:
    """Sütun başlığı satırını çözer → {alan: token_index}.

    En az adet + fiyat (ya da adet + tutar) bulunmalı; yoksa bu satır
    başlık sayılmaz.
    """
    tokens = line.split()
    if len(tokens) < 3:
        return None
    low = [t.lower().strip(":()") for t in tokens]
    found: dict[str, int] = {}
    for field, hints in _HDR.items():
        for i, tok in enumerate(low):
            if field in found:
                break
            if any(tok == h or tok.startswith(h.split()[0]) for h in hints
                   if " " not in h):
                found[field] = i
    if "quantity" in found and ("price" in found or "total" in found):
        return found
    return None


def _from_header(line: str, hdr: dict[str, int]) -> dict | None:
    tokens = line.split()
    date = _parse_date(line)
    side = _detect_side(line)
    if date is None or side is None:
        return None

    def num_at(field: str) -> float | None:
        i = hdr.get(field)
        if i is None or i >= len(tokens):
            return None
        return _to_float(tokens[i])

    qty, price = num_at("quantity"), num_at("price")
    if price is None:
        total = num_at("total")
        if qty and total and qty > 0:
            price = total / qty
    if not qty or not price or qty <= 0 or price <= 0:
        return None

    symbol = None
    si = hdr.get("symbol")
    if si is not None and si < len(tokens):
        symbol = _detect_symbol(tokens[si])
    symbol = symbol or _detect_symbol(line)
    if not symbol:
        return None

    return {"date": date.isoformat(), "symbol": symbol, "side": side,
            "quantity": qty, "price": price, "commission": 0.0,
            "currency": "TRY", "source": "generic", "raw": line.strip()}



def _has_decimals(raw: str) -> bool:
    """'1.250,00' → True · '40' → False · '1.250' → False (binlik ayracı)."""
    r = raw.strip()
    d, c = r.rfind("."), r.rfind(",")
    if d == -1 and c == -1:
        return False
    sep = max(d, c)
    tail = r[sep + 1:]
    # Sondaki grup 3 haneyse bu binlik ayracıdır, ondalık değil.
    return not (len(tail) == 3 and tail.isdigit())


def _order_qty_price(a: tuple[float, str],
                     b: tuple[float, str]) -> tuple[float, float]:
    """Çarpımı doğrulanmış iki sayıdan hangisi adet, hangisi fiyat?

    Çarpım her iki sırada da aynı olduğu için sıra tek başına yetmez ve
    kurumlar sütunları farklı diziyor ("Adet Fiyat" ya da "Fiyat Adet").
    Ayırt edici sinyal ondalık: Türk ekstrelerinde fiyat kuruşuyla
    ('300,50' / '1.250,00') yazılır, BIST adedi ise tam sayıdır ('40').
    Yalnız biri ondalıklıysa o FİYATTIR. İkisi de (ya da hiçbiri)
    ondalıklıysa yaygın sıraya düşülür: önce adet, sonra fiyat.
    """
    (av, ar), (bv, br) = a, b
    ad, bd = _has_decimals(ar), _has_decimals(br)
    if ad and not bd:
        return bv, av
    if bd and not ad:
        return av, bv
    return av, bv


def _from_product(line: str) -> dict | None:
    """Başlık yoksa: a × b ≈ c olan üçlüyü ara (adet × fiyat = tutar)."""
    date = _parse_date(line)
    side = _detect_side(line)
    if date is None or side is None:
        return None
    symbol = _detect_symbol(line)
    if not symbol:
        return None

    stripped = _DATE_RE.sub(" ", line)
    # Ham metni de sakla: ondalık yazılıp yazılmadığı adet/fiyat ayrımında
    # tek güvenilir ipucu (çarpım her iki sırada da aynı sonucu verir).
    pairs = [(v, m.group()) for m in _NUM_RE.finditer(stripped)
             if (v := _to_float(m.group())) is not None and v > 0]
    if len(pairs) < 2:
        return None
    nums = [v for v, _ in pairs]

    best: tuple[int, int] | None = None
    for i in range(len(nums)):
        for j in range(i + 1, len(nums)):
            for k in range(len(nums)):
                if k in (i, j):
                    continue
                if nums[k] > 0 and abs(nums[i] * nums[j] - nums[k]) / nums[k] <= 0.02:
                    best = (i, j)
                    break
            if best:
                break
        if best:
            break

    i, j = best if best else (0, 1)
    qty, price = _order_qty_price(pairs[i], pairs[j])
    if qty <= 0 or price <= 0:
        return None

    return {"date": date.isoformat(), "symbol": symbol, "side": side,
            "quantity": qty, "price": price, "commission": 0.0,
            "currency": "TRY", "source": "generic", "raw": line.strip()}


def parse_lines(lines: list[str]) -> tuple[list[dict], int]:
    """Kurum-bağımsız işlem çıkarımı. Döner: (satırlar, atlanan_iptal_sayısı)."""
    rows: list[dict] = []
    header: dict[str, int] | None = None
    skipped_cancelled = 0
    seen: set[tuple] = set()

    for line in lines:
        s = line.strip()
        if not s or len(s) < 10:
            continue
        if _NOISE.search(s):
            continue

        hdr = detect_header(s)
        if hdr:
            header = hdr
            continue

        # Gerçekleşmemiş emir: sütununu bilemeyiz, ifadeye bakarız.
        if _NOT_EXECUTED.search(s):
            if _detect_side(s) and _parse_date(s):
                skipped_cancelled += 1
            continue

        row = (_from_header(s, header) if header else None) or _from_product(s)
        if not row:
            continue
        key = (row["date"], row["symbol"], row["side"], row["quantity"],
               row["price"])
        if key in seen:
            continue
        seen.add(key)
        rows.append(row)

    rows.sort(key=lambda r: r["date"])
    logger.info(
        f"Genel sezgisel: {len(rows)} işlem çıkarıldı, "
        f"{skipped_cancelled} gerçekleşmemiş emir atlandı"
    )
    return rows, skipped_cancelled
