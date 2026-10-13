"""Midas hesap ekstresi (PDF) → yapılandırılmış işlem satırları + pozisyonlar.

Neden PDF: Midas'ın public API'si yok ve ekstreyi yalnız PDF veriyor. Ama
PDF METİN katmanı taşıyor — görüntü değil. Bu yüzden ekran görüntüsü OCR'ının
(`screenshot_import_service`, Gemini vision) aksine burada LLM YOK: parse
deterministik, AI kotası yanmıyor, ekranda görünmeyen tarih/komisyon da geliyor.

EKSTRE YAPISI (gerçek dosyadan doğrulandı, Haziran+Temmuz 2026):

  PORTFÖY ÖZETİ (gg/aa/yy)
    Sermaye Piyasası Aracı | Adet | Hisse Başı Ortalama Maliyet | Kar/Zarar | Toplam Değeri
    LHX - L3Harris  0,802980132  362,40 USD  -55,37 USD  235,63 USD

  YATIRIM İŞLEMLERİ (gg/aa/yy - gg/aa/yy)      ← ASIL İŞLEM GEÇMİŞİ
    Tarih | İşlem Türü | Sembol | İşlem Tipi | İşlem Durumu | Para Birimi |
    Emir Adedi | Emir Tutarı | Gerçekleşen Adet | Ortalama İşlem Fiyatı |
    İşlem Ücreti | İşlem Tutarı
    01/06/26 21:31:38 Piyasa Emri NBIS Satış Gerçekleşti USD 3,885486563 - 3,885486563 271,98 1,50 1056,76

  HESAP İŞLEMLERİ    → yalnız nakit/döviz (Döviz Alış/Satış, Nema) — pivot
                       sonrası nakit tutulmadığı için KULLANILMIYOR
  TEMETTÜ İŞLEMLERİ  → ödeme tarihi + brüt/stopaj/net
  HİSSE TRANSFERLERİ

İKİ TUZAK (ikisi de gerçek ekstrede var):
  1. İPTAL EDİLEN EMİRLER de listeleniyor ("İptal Edildi"). Bunlar işlem
     DEĞİL — kaydedilirse portföy tamamen yanlış çıkar.
  2. Adet iki sütunda: "Emir Adedi" (talep edilen) ve "Gerçekleşen Adet".
     Kısmi dolan emirlerde ikisi FARKLI; doğru olan Gerçekleşen Adet.
     Tutar bazlı emirlerde ("5,00 dolarlık al") Emir Adedi boş ('-') gelir.

Bu servis HİÇBİR ŞEY KAYDETMEZ — yalnız ayrıştırır. Kullanıcı önizlemede
düzeltip onaylar, kayıt `order_service.apply_statement_rows` ile yapılır.
"""

import re
from datetime import datetime
from io import BytesIO

from loguru import logger

from app.services import statement_generic
from app.services.bist_catalog import CATALOG as BIST_CATALOG
from app.services import fund_catalog

MAX_PDF_BYTES = 10 * 1024 * 1024  # 10 MB
MAX_PAGES = 60

# Bölüm başlıkları — satırlar bölüm bağlamında ayrıştırılır, serbest
# tahminle değil (HESAP İŞLEMLERİ'ndeki döviz alışı hisse alışı sanılmasın).
_SEC_PORTFOLIO = re.compile(r"PORTFÖY\s+ÖZET[İI]")
_SEC_TRADES = re.compile(r"YATIRIM\s+İŞLEMLER[İI]")
_SEC_CASH = re.compile(r"HESAP\s+İŞLEMLER[İI]")
_SEC_DIVIDEND = re.compile(r"TEMETTÜ\s+İŞLEMLER[İI]")
_SEC_TRANSFER = re.compile(r"H[İI]SSE\s+TRANSFERLER[İI]")
_SEC_ANY = re.compile(
    r"PORTFÖY\s+ÖZET|YATIRIM\s+İŞLEMLER|HESAP\s+İŞLEMLER|"
    r"TEMETTÜ\s+İŞLEMLER|H[İI]SSE\s+TRANSFERLER"
)

# 01/06/26 21:31:38 ... USD <6 alan>
_TRADE_RE = re.compile(
    r"^(?P<date>\d{2}/\d{2}/\d{2})\s+(?P<time>\d{2}:\d{2}:\d{2})\s+"
    r"(?P<mid>.+?)\s+(?P<currency>USD|TRY|EUR|TL)\s+(?P<tail>.+)$"
)
_SIDE_RE = re.compile(r"\b(Alış|Alis|Satış|Satis)\b")

# LHX - L3Harris 0,802980132 362,40 USD -55,37 USD 235,63 USD
_POSITION_RE = re.compile(
    r"^(?P<symbol>[A-Z][A-Z0-9.]{0,9})\s+-\s+(?P<name>.+?)\s+"
    r"(?P<qty>[\d.,]+)\s+(?P<cost>[\d.,]+)\s+(?P<cur>USD|TRY|EUR|TL)\s+"
    r"(?P<pnl>-?[\d.,]+)\s+(?:USD|TRY|EUR|TL)\s+"
    r"(?P<total>-?[\d.,]+)\s+(?:USD|TRY|EUR|TL)\s*$"
)


# Desteklenen kurumlar. Anahtar = ekstrede geçen kurum adı parçası.
_KNOWN_BROKERS = {
    "midas menkul": "Midas",
}

# Türk aracı kurum adları neredeyse hep bu kalıplarla biter. Tanımadığımız
# bir kurumun ekstresi geldiğinde kullanıcıya ADINI söyleyebilmek için
# ilk sayfadan çekilir — böylece "okuyamadım" değil, "bu X ekstresi, henüz
# desteklemiyorum" diyebiliriz.
_ISSUER_RE = re.compile(
    r"([A-ZÇĞİÖŞÜ0-9][\w İÇĞÖŞÜçğıöşü.&-]{2,60}?"
    r"(?:Menkul\s+Değerler|Yatırım\s+Menkul|Menkul\s+Kıymetler|"
    r"Yatırım\s+Menkul\s+Değerler|Portföy\s+Yönetimi)"
    r"(?:\s+A\.?Ş\.?)?)",
    re.IGNORECASE,
)


def detect_issuer(lines: list[str]) -> tuple[str | None, str | None]:
    """Ekstreyi kimin düzenlediğini bulur.

    Döner: (desteklenen_kurum_adı, ekstrede_okunan_ham_ad). İlki None ise
    kurum tanınmıyor demektir; ikincisi doluysa kullanıcıya adıyla
    söylenebilir.
    """
    head = "\n".join(lines[:40])
    low = head.lower()
    for marker, name in _KNOWN_BROKERS.items():
        if marker in low:
            return name, name
    m = _ISSUER_RE.search(head)
    return None, (" ".join(m.group(1).split()) if m else None)


def parse_amount(raw: str | None) -> float | None:
    """'1.234,56' → 1234.56 · '1,234.56' → 1234.56 · '-' → None.

    Ayracı sondaki gruba bakarak seçer: son ayraçtan sonra tam 3 hane varsa
    o ayraç BİNLİK'tir, değilse ONDALIK. Midas hem '3,885486563' (9 haneli
    ondalık, küsuratlı lot) hem '1056,76' üretiyor.
    """
    if raw is None:
        return None
    s = str(raw).strip().replace(" ", "").replace("₺", "").replace("$", "")
    if not s or s == "-" or not any(ch.isdigit() for ch in s):
        return None

    neg = s.startswith("-")
    s = s.lstrip("+-")
    last_dot, last_comma = s.rfind("."), s.rfind(",")
    if last_dot == -1 and last_comma == -1:
        val = s
    else:
        sep = max(last_dot, last_comma)
        tail = s[sep + 1:]
        if len(tail) == 3 and tail.isdigit():
            val = s.replace(".", "").replace(",", "")   # binlik ayracı
        else:
            val = f"{s[:sep].replace('.', '').replace(',', '')}.{tail}"
    try:
        out = float(val)
    except ValueError:
        return None
    return -out if neg else out


def parse_short_date(raw: str, time_part: str = "") -> datetime | None:
    """'01/06/26' (+'21:31:38') → datetime. İki haneli yıl: 00-79 → 2000'ler."""
    m = re.match(r"^(\d{2})/(\d{2})/(\d{2})$", raw.strip())
    if not m:
        return None
    day, month, yy = int(m.group(1)), int(m.group(2)), int(m.group(3))
    year = 2000 + yy if yy < 80 else 1900 + yy
    hour = minute = sec = 0
    tm = re.match(r"^(\d{2}):(\d{2}):(\d{2})$", (time_part or "").strip())
    if tm:
        hour, minute, sec = int(tm.group(1)), int(tm.group(2)), int(tm.group(3))
    try:
        return datetime(year, month, day, hour, minute, sec)
    except ValueError:
        return None


def resolve_symbol(symbol: str, currency: str) -> str:
    """Para birimine göre kanonikleştirir.

    Kur sütunu sembolün hangi borsaya ait olduğunu kesin söyler: TRY/TL →
    BIST → '.IS' soneki şart (çıplak 'THYAO' Yahoo'da alakasız bir ABD
    enstrümanına çözülüyor). USD → ABD sembolü, sone EKLENMEZ — aksi halde
    BIST kodlarıyla çakışan ABD tickerları yanlış hisseye bağlanırdı.
    """
    s = symbol.strip().upper()
    if currency in ("TRY", "TL"):
        if "." not in s:
            # TEFAS yatırım fonu mu? (TLY, LTL …) Fon kodları 3 harflidir ve
            # BIST'te karşılığı yoktur → ".IS" eklenirse Yahoo'da aranıp
            # bulunamıyor, pozisyon fiyatsız kalıyordu.
            if s not in BIST_CATALOG and fund_catalog.is_known_code(s):
                return fund_catalog.to_symbol(s)
            return f"{s}.IS"
        return s
    if currency == "USD" and s in BIST_CATALOG:
        # Katalogda BIST kodu olarak geçse bile kur USD → ABD hissesi.
        return s
    return s


def parse_trade_line(line: str) -> dict | None:
    """YATIRIM İŞLEMLERİ satırı → işlem. Gerçekleşmeyen emirlerde None."""
    m = _TRADE_RE.match(line.strip())
    if not m:
        return None

    mid = m.group("mid")
    sm = _SIDE_RE.search(mid)
    if not sm:
        return None

    # Sembol, İşlem Tipi'nden hemen önceki tokendir. İşlem Türü değişken
    # uzunlukta ("Piyasa Emri" / "Kar Al ve Zarar Durdur Emri") → konumla
    # değil, Alış/Satış çıpasıyla bulunur.
    before = mid[:sm.start()].split()
    if not before:
        return None
    symbol = before[-1]
    if not re.fullmatch(r"[A-Z][A-Z0-9.]{0,9}", symbol):
        return None

    status = mid[sm.end():].strip()
    # TUZAK 1: iptal edilen emirler de listede. İşlem DEĞİL.
    if "Gerçekleş" not in status or "İptal" in status:
        return None

    side = "SELL" if sm.group(1).lower().startswith("sat") else "BUY"
    currency = m.group("currency")

    fields = m.group("tail").split()
    if len(fields) < 6:
        return None
    # Emir Adedi | Emir Tutarı | Gerçekleşen Adet | Ort. Fiyat | Ücret | Tutar
    # TUZAK 2: adet iki sütunda; doğrusu GERÇEKLEŞEN adet.
    quantity = parse_amount(fields[2])
    price = parse_amount(fields[3])
    commission = parse_amount(fields[4]) or 0.0

    if not quantity or not price or quantity <= 0 or price <= 0:
        return None

    dt = parse_short_date(m.group("date"), m.group("time"))
    if dt is None:
        return None

    return {
        "date": dt.isoformat(),
        "symbol": resolve_symbol(symbol, currency),
        "side": side,
        "quantity": quantity,
        "price": price,
        "commission": commission,
        "currency": currency,
        "raw": line.strip(),
    }


def parse_position_line(line: str, currency_hint: str = "USD") -> dict | None:
    """PORTFÖY ÖZETİ satırı → pozisyon (adet + hisse başı ortalama maliyet)."""
    m = _POSITION_RE.match(line.strip())
    if not m:
        return None
    qty = parse_amount(m.group("qty"))
    cost = parse_amount(m.group("cost"))
    if qty is None or qty <= 0:
        return None
    return {
        "symbol": resolve_symbol(m.group("symbol"), m.group("cur")),
        "name": m.group("name").rstrip(". "),
        "quantity": qty,
        "avg_cost": cost or 0.0,
        "currency": m.group("cur"),
    }


def _extract_lines(pdf_bytes: bytes) -> list[str]:
    import pdfplumber

    lines: list[str] = []
    with pdfplumber.open(BytesIO(pdf_bytes)) as pdf:
        if len(pdf.pages) > MAX_PAGES:
            raise ValueError(
                f"Ekstre çok uzun ({len(pdf.pages)} sayfa, en fazla {MAX_PAGES})"
            )
        for page in pdf.pages:
            lines.extend((page.extract_text() or "").splitlines())
    return lines


def parse_statement(pdf_bytes: bytes) -> dict:
    """Tek ekstre PDF'i → işlemler + kapanış pozisyonları. KAYDETMEZ."""
    if not pdf_bytes:
        raise ValueError("Boş dosya")
    if len(pdf_bytes) > MAX_PDF_BYTES:
        raise ValueError("Dosya 10 MB sınırını aşıyor")
    if not pdf_bytes.startswith(b"%PDF"):
        raise ValueError("Dosya PDF değil")

    lines = _extract_lines(pdf_bytes)
    if not lines:
        raise ValueError(
            "PDF'ten metin çıkarılamadı — ekstre taranmış görüntü olabilir. "
            "Midas uygulamasından indirilen orijinal PDF'i kullanın."
        )

    broker, issuer = detect_issuer(lines)

    section = None
    rows: list[dict] = []
    positions: list[dict] = []
    cancelled = 0
    period = ""
    as_of = ""

    for line in lines:
        stripped = line.strip()
        if _SEC_ANY.search(stripped):
            if _SEC_PORTFOLIO.search(stripped):
                section = "portfolio"
                dm = re.search(r"\((\d{2}/\d{2}/\d{2})\)", stripped)
                if dm:
                    as_of = dm.group(1)
            elif _SEC_TRADES.search(stripped):
                section = "trades"
                pm = re.search(r"\((\d{2}/\d{2}/\d{2} - \d{2}/\d{2}/\d{2})\)",
                               stripped)
                if pm:
                    period = pm.group(1)
            elif _SEC_CASH.search(stripped):
                section = "cash"       # nakit/döviz — pivot sonrası kullanılmıyor
            elif _SEC_DIVIDEND.search(stripped):
                section = "dividend"
            elif _SEC_TRANSFER.search(stripped):
                section = "transfer"
            continue

        if section == "trades":
            parsed = parse_trade_line(stripped)
            if parsed:
                rows.append(parsed)
            elif _SIDE_RE.search(stripped) and "İptal" in stripped:
                cancelled += 1
        elif section == "portfolio":
            pos = parse_position_line(stripped)
            if pos:
                positions.append(pos)

    rows.sort(key=lambda r: r["date"])

    # Midas profili tutmadıysa kurum-bağımsız sezgisele düş. Profil TUTTUYSA
    # çalıştırma — aynı satırlar iki kez sayılır.
    generic_used = False
    if not rows and not positions:
        rows, generic_cancelled = statement_generic.parse_lines(lines)
        if rows:
            generic_used = True
            cancelled += generic_cancelled

    # Hiçbir şey çıkmadıysa SESSİZ KALMA. Üç ayrı durum var ve kullanıcının
    # hangisi olduğunu bilmesi gerekiyor:
    #   1) Tanınmayan kurum  → format desteklenmiyor, adıyla söyle
    #   2) Midas ama boş     → o dönemde işlem yok; bu meşru olabilir
    #   3) Ekstre bile değil → başka bir PDF yüklenmiş
    if not rows and not positions:
        if broker is None:
            if issuer:
                raise ValueError(
                    f"Bu '{issuer}' ekstresi gibi görünüyor. Şu an yalnız "
                    f"{', '.join(_KNOWN_BROKERS.values())} ekstresi okunabiliyor."
                )
            raise ValueError(
                "Bu dosya bir aracı kurum ekstresine benzemiyor. Midas "
                "uygulamasından indirdiğin PDF ekstreyi yükle."
            )
        raise ValueError(
            f"{broker} ekstresi okundu ama içinde işlem veya pozisyon yok — "
            "bu dönemde hareket olmamış olabilir. Başka bir ay dene."
        )

    logger.info(
        f"Ekstre parse ({broker or issuer or 'bilinmeyen'}"
        f"{', GENEL SEZGİSEL' if generic_used else ''}): {len(rows)} "
        f"gerçekleşen işlem, {cancelled} iptal edilen emir atlandı, "
        f"{len(positions)} pozisyon"
    )

    return {
        "broker": broker,
        "issuer": issuer,
        "generic": generic_used,
        "rows": rows,
        "positions": positions,
        "cancelled_orders": cancelled,
        "period": period,
        "positions_as_of": as_of,
        "symbols": sorted({r["symbol"] for r in rows}),
        "note": (
            "Satırlar okundu ama HENÜZ KAYDEDİLMEDİ. Ekstrendeki işlem "
            "sayısıyla karşılaştır, hatalıları düzelt, sonra onayla."
        ),
    }


def parse_statements(files: list[tuple[str, bytes]]) -> dict:
    """Birden çok ekstre PDF'ini TEK sonuçta birleştirir.

    Midas ekstreyi yalnız AYLIK veriyor; bir yıllık geçmiş 12 dosya demek.
    Dosyalar burada birleştirilir: işlemler kronolojik sıralanır, aynı işlem
    iki ekstrede birden geçiyorsa (dönemler örtüşebiliyor — Haziran ekstresi
    01/06-08/07 arasını kapsıyor) bir kez sayılır.

    Pozisyonlar EN SON tarihli ekstreden alınır; eskisi güncelini ezmemeli.

    Bir dosya bozuksa diğerleri işlenir; hata `failed_files`'a yazılır.
    """
    all_rows: list[dict] = []
    failed: list[dict] = []
    brokers: set[str] = set()
    generic_any = False
    seen: set[tuple] = set()
    cancelled = 0
    best_positions: list[dict] = []
    best_as_of = ""
    best_file = ""

    for name, data in files:
        try:
            res = parse_statement(data)
        except ValueError as exc:
            failed.append({"file": name, "error": str(exc)})
            continue
        except Exception as exc:
            logger.warning(f"{name} ayrıştırılamadı: {exc}")
            failed.append({"file": name, "error": "Dosya okunamadı"})
            continue

        if res.get("broker"):
            brokers.add(res["broker"])
        if res.get("generic"):
            generic_any = True
        for row in res["rows"]:
            key = (row["date"], row["symbol"], row["side"],
                   row["quantity"], row["price"])
            if key in seen:
                continue
            seen.add(key)
            row["source_file"] = name
            all_rows.append(row)
        cancelled += res["cancelled_orders"]

        # En güncel portföy özeti kazanır (as_of gg/aa/yy → karşılaştırılabilir
        # anahtara çevrilir).
        as_of = res["positions_as_of"]
        if res["positions"]:
            dt = parse_short_date(as_of) if as_of else None
            best_dt = parse_short_date(best_as_of) if best_as_of else None
            if best_dt is None or (dt is not None and dt > best_dt):
                best_positions = res["positions"]
                best_as_of = as_of
                best_file = name

    all_rows.sort(key=lambda r: r["date"])
    logger.info(
        f"Toplu ekstre: {len(files)} dosya → {len(all_rows)} işlem, "
        f"{cancelled} iptal atlandı, {len(failed)} okunamayan dosya"
    )

    return {
        "brokers": sorted(brokers),
        "generic": generic_any,
        "rows": all_rows,
        "positions": best_positions,
        "positions_as_of": best_as_of,
        "positions_source": best_file,
        "cancelled_orders": cancelled,
        "failed_files": failed,
        "file_count": len(files),
        "symbols": sorted({r["symbol"] for r in all_rows}),
        "date_range": (
            [all_rows[0]["date"][:10], all_rows[-1]["date"][:10]]
            if all_rows else []
        ),
        "note": (
            "Satırlar okundu ama HENÜZ KAYDEDİLMEDİ. Ekstrendeki işlem "
            "sayısıyla karşılaştır, hatalıları düzelt, sonra onayla."
        ),
    }
