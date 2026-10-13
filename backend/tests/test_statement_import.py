"""Ekstre (PDF) içe aktarma — ağsız birim testleri.

Parser'ın gerçek Midas formatıyla doğrulanması için örnek PDF gerekiyor
(bkz. CIHAZ_DOGRULAMA.md). Buradaki testler formattan BAĞIMSIZ çekirdeği
kilitler: sayı/tarih ayrıştırma, sembol çözümleme, satır tanıma ve
kronolojik AL/SAT replay'inin ortalama maliyeti doğru kurması.
"""

import pytest

from app.services import statement_import_service as sis


def _pdf(lines: list[str]) -> bytes:
    """Test için metin katmanlı sahte ekstre PDF'i üretir.

    Vera fontu ŞART: reportlab'ın varsayılan Helvetica'sı Türkçe karakterleri
    bozuyor ('İŞLEMLERİ' → 'nnLEMLERn'), o zaman bölüm başlıkları eşleşmiyor
    ve test parser'ı değil kendi kurgusunu ölçmüş oluyor. Vera reportlab ile
    birlikte geliyor (ek dosya/indirme yok).
    """
    import os
    from io import BytesIO

    import reportlab
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen import canvas

    if "Vera" not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(TTFont(
            "Vera", os.path.join(os.path.dirname(reportlab.__file__),
                                 "fonts", "Vera.ttf")))

    buf = BytesIO()
    c = canvas.Canvas(buf)
    c.setFont("Vera", 9)
    for i, line in enumerate(lines):
        c.drawString(40, 790 - i * 15, line)
    c.save()
    return buf.getvalue()


# --------------------------------------------------------------------------
# Sayı ayrıştırma — TR (1.234,56) ve US (1,234.56) biçimleri karışık gelebilir
# --------------------------------------------------------------------------
@pytest.mark.parametrize("raw,expected", [
    ("1.234,56", 1234.56),
    ("1,234.56", 1234.56),
    ("1234.56", 1234.56),
    ("1234,56", 1234.56),
    ("1.234", 1234.0),      # sondaki grup 3 hane → binlik
    ("1,234", 1234.0),
    ("1.23", 1.23),         # sondaki grup 2 hane → ondalık
    ("12", 12.0),
    ("₺6.802,48", 6802.48),
    ("$187.50", 187.50),
    ("", None),
    ("abc", None),
])
def test_parse_tr_number(raw, expected):
    assert sis.parse_amount(raw) == expected


# --------------------------------------------------------------------------
# Kayıt adımı — kronolojik replay, ortalama maliyet, çift yükleme
# --------------------------------------------------------------------------
def _rows():
    return [
        # Kasıtlı olarak ters sırada verildi: servis kronolojik sıralamalı
        {"date": "2026-03-10T00:00:00", "symbol": "THYAO.IS", "side": "BUY",
         "quantity": 10, "price": 400.0},
        {"date": "2026-01-05T00:00:00", "symbol": "THYAO.IS", "side": "BUY",
         "quantity": 10, "price": 300.0},
    ]


def test_apply_rows_builds_weighted_average(db, make_user):
    user = make_user()
    from app.services import order_service
    from app.models.portfolio import Portfolio

    res = order_service.apply_statement_rows(db, user.id, _rows())
    assert res["imported"] == 2

    pos = db.query(Portfolio).filter(
        Portfolio.user_id == user.id, Portfolio.symbol == "THYAO.IS"
    ).first()
    assert pos.quantity == 20
    assert pos.average_cost == pytest.approx(350.0)  # (10*300 + 10*400) / 20


def test_apply_rows_is_idempotent(db, make_user):
    """Aynı ekstre iki kez yüklenirse işlemler çiftlenmemeli."""
    user = make_user()
    from app.services import order_service
    from app.models.portfolio import Portfolio

    order_service.apply_statement_rows(db, user.id, _rows())
    second = order_service.apply_statement_rows(db, user.id, _rows())

    assert second["imported"] == 0
    assert second["duplicates"] == 2
    pos = db.query(Portfolio).filter(
        Portfolio.user_id == user.id, Portfolio.symbol == "THYAO.IS"
    ).first()
    assert pos.quantity == 20  # ikiye katlanmadı


def test_apply_rows_sell_reduces_quantity_not_cost(db, make_user):
    user = make_user()
    from app.services import order_service
    from app.models.portfolio import Portfolio

    rows = _rows() + [
        {"date": "2026-04-01T00:00:00", "symbol": "THYAO.IS", "side": "SELL",
         "quantity": 5, "price": 500.0},
    ]
    order_service.apply_statement_rows(db, user.id, rows)

    pos = db.query(Portfolio).filter(
        Portfolio.user_id == user.id, Portfolio.symbol == "THYAO.IS"
    ).first()
    assert pos.quantity == 15
    assert pos.average_cost == pytest.approx(350.0)  # satış maliyeti değiştirmez


def test_apply_rows_skips_unbacked_sell(db, make_user):
    """Elde olmayan lotun satışı hata değil — atlanır, kalanlar işlenir."""
    user = make_user()
    from app.services import order_service

    rows = [
        {"date": "2026-01-05T00:00:00", "symbol": "ASELS.IS", "side": "SELL",
         "quantity": 100, "price": 50.0},
        {"date": "2026-01-06T00:00:00", "symbol": "ASELS.IS", "side": "BUY",
         "quantity": 10, "price": 60.0},
    ]
    res = order_service.apply_statement_rows(db, user.id, rows)
    assert res["imported"] == 1
    assert len(res["skipped"]) == 1
    assert "ASELS.IS" in res["skipped"][0]


def test_apply_rows_rejects_invalid_side(db, make_user):
    user = make_user()
    from app.services import order_service

    rows = [{"date": "2026-01-05T00:00:00", "symbol": "THYAO.IS",
             "side": "TRANSFER", "quantity": 1, "price": 1.0}]
    res = order_service.apply_statement_rows(db, user.id, rows)
    assert res["imported"] == 0
    assert len(res["skipped"]) == 1


# --------------------------------------------------------------------------
# Midas satır ayrıştırma — GERÇEK ekstre formatı (Haziran/Temmuz 2026 ile
# doğrulandı). Sütunlar:
#   Tarih | İşlem Türü | Sembol | İşlem Tipi | İşlem Durumu | Para Birimi |
#   Emir Adedi | Emir Tutarı | Gerçekleşen Adet | Ort. Fiyat | Ücret | Tutar
# --------------------------------------------------------------------------
def test_trade_line_market_order():
    r = sis.parse_trade_line(
        "01/06/26 21:31:38 Piyasa Emri NBIS Satış Gerçekleşti USD "
        "3,885486563 - 3,885486563 271,98 1,50 1056,76")
    assert r["symbol"] == "NBIS" and r["side"] == "SELL"
    assert r["quantity"] == pytest.approx(3.885486563)
    assert r["price"] == 271.98 and r["commission"] == 1.50
    assert r["date"] == "2026-06-01T21:31:38"


def test_trade_line_cancelled_order_is_skipped():
    """TUZAK: iptal edilen emirler de ekstrede listeleniyor — işlem DEĞİL."""
    assert sis.parse_trade_line(
        "10/06/26 11:29:11 Limit Emri BCHT Alış İptal Edildi USD "
        "82 - 0 - - 0,00") is None
    assert sis.parse_trade_line(
        "02/06/26 10:12:02 Kar Al ve Zarar Durdur Emri NASA Satış "
        "İptal Edildi USD 78 - 0 - - 0,00") is None


def test_trade_line_uses_executed_quantity_not_requested():
    """TUZAK: adet iki sütunda; doğrusu 'Gerçekleşen Adet'.

    Tutar bazlı emirde Emir Adedi boş ('-'), Emir Tutarı dolu; gerçekleşen
    adet üçüncü alandır.
    """
    r = sis.parse_trade_line(
        "05/06/26 21:40:04 Piyasa Emri CEG Alış Gerçekleşti USD "
        "- 2,73 0,010662896 256,03 0,00 2,73")
    assert r["quantity"] == pytest.approx(0.010662896)  # 2,73 DEĞİL
    assert r["price"] == 256.03 and r["commission"] == 0.0


def test_trade_line_multiword_order_type():
    """İşlem Türü değişken uzunlukta → sembol konumla bulunamaz."""
    r = sis.parse_trade_line(
        "03/06/26 01:03:35 Zarar Durdur Emri NASA Satış Gerçekleşti USD "
        "19 - 19 35,01 1,50 665,19")
    assert r["symbol"] == "NASA" and r["side"] == "SELL" and r["quantity"] == 19


def test_trade_line_try_gets_is_suffix():
    """Para birimi borsayı kesin söyler: TRY → BIST → '.IS' şart."""
    r = sis.parse_trade_line(
        "03/06/26 16:50:06 Piyasa Emri THYAO Alış Gerçekleşti TRY "
        "6 - 6 68,40 1,50 410,43")
    assert r["symbol"] == "THYAO.IS"


def test_trade_line_usd_symbol_never_gets_is_suffix():
    """ABD tickerı BIST koduyla çakışsa bile USD ise sone ALMAZ."""
    r = sis.parse_trade_line(
        "03/06/26 16:50:06 Piyasa Emri MP Satış Gerçekleşti USD "
        "6 - 6 68,40 1,50 410,43")
    assert r["symbol"] == "MP"


def test_two_digit_year():
    assert sis.parse_short_date("01/06/26").year == 2026
    assert sis.parse_short_date("01/06/99").year == 1999
    assert sis.parse_short_date("gecersiz") is None


def test_position_line():
    p = sis.parse_position_line(
        "LHX - L3Harris 0,802980132 362,40 USD -55,37 USD 235,63 USD")
    assert p["symbol"] == "LHX"
    assert p["quantity"] == pytest.approx(0.802980132)
    assert p["avg_cost"] == 362.40


def test_cash_section_rows_are_not_trades():
    """HESAP İŞLEMLERİ'ndeki döviz alışı hisse alışı sanılmamalı."""
    assert sis.parse_trade_line(
        "07/07/26 17:00:44 07/07/26 17:00:44 Döviz Alış 47,27 USD/TRY "
        "kurundan 455,00 dolar alış Gerçekleşti 455,00 USD") is None


# --------------------------------------------------------------------------
# Portföy özeti (snapshot) kaydı
# --------------------------------------------------------------------------
def test_apply_positions_replaces_not_adds(db, make_user):
    """Ekstre anlık görüntüdür: mevcut pozisyonun ÜSTÜNE eklenmez."""
    from app.services import order_service
    from app.models.portfolio import Portfolio
    user = make_user()

    order_service.apply_statement_positions(
        db, user.id, [{"symbol": "LHX", "quantity": 5, "avg_cost": 300.0}])
    order_service.apply_statement_positions(
        db, user.id, [{"symbol": "LHX", "quantity": 8, "avg_cost": 362.40}])

    rows = db.query(Portfolio).filter(Portfolio.user_id == user.id,
                                      Portfolio.symbol == "LHX").all()
    assert len(rows) == 1                       # ikinci satır açılmadı
    assert rows[0].quantity == 8                # 13 DEĞİL
    assert rows[0].average_cost == pytest.approx(362.40)


def test_apply_positions_idempotent(db, make_user):
    from app.services import order_service
    user = make_user()
    pos = [{"symbol": "LHX", "quantity": 8, "avg_cost": 362.40}]

    order_service.apply_statement_positions(db, user.id, pos)
    second = order_service.apply_statement_positions(db, user.id, pos)
    assert second["imported"] == 0 and second["unchanged"] == 1


def test_apply_positions_skips_zero_cost(db, make_user):
    """Bedelsiz/rüçhan kaydı (ekstrede maliyet 0,00) portföy değerini bozar."""
    from app.services import order_service
    user = make_user()
    res = order_service.apply_statement_positions(
        db, user.id, [{"symbol": "EOSER", "quantity": 18.55, "avg_cost": 0.0}])
    assert res["imported"] == 0 and len(res["skipped"]) == 1


# --------------------------------------------------------------------------
# Tanınmayan kurum — SESSİZ KALMA
#
# Parser Midas'ın bölüm başlıklarına ve sütun düzenine kilitli. Başka bir
# aracı kurumun ekstresinde hiçbir şey bulamaz; eskiden bunu hata olarak
# değil BOŞ SONUÇ olarak döndürüyordu → kullanıcı boş bir önizleme
# ekranında kalıp nedenini anlayamıyordu.
# --------------------------------------------------------------------------
def test_detect_issuer_known_broker():
    lines = ["Midas Menkul Değerler A.Ş.", "Mersis Numarası: 0621096943000001"]
    broker, issuer = sis.detect_issuer(lines)
    assert broker == "Midas" and issuer == "Midas"


def test_detect_issuer_unknown_broker_is_named():
    """Tanımasak da kurumun ADINI söyleyebilmeliyiz."""
    lines = ["ORNEK YATIRIM MENKUL DEGERLER A.S.", "MUSTERI HESAP EKSTRESI"]
    broker, issuer = sis.detect_issuer(lines)
    assert broker is None
    assert issuer is not None and "MENKUL" in issuer.upper()


def test_detect_issuer_not_a_statement():
    broker, issuer = sis.detect_issuer(["Fatura", "Toplam: 100 TL"])
    assert broker is None and issuer is None


def test_unknown_broker_falls_back_to_generic_and_is_flagged():
    """Tanınmayan kurum artık kurtarılıyor — ama TAHMİNİ olarak işaretlenerek.

    Genel sezgisel (statement_generic) devreye girip satırı okur; UI bunu
    "kesin değil, kontrol et" uyarısıyla gösterir.
    """
    pdf = _pdf([
        "ORNEK YATIRIM MENKUL DEGERLER A.S.",
        "MUSTERI HESAP EKSTRESI  01.06.2026 - 30.06.2026",
        "HISSE SENEDI HAREKETLERI",
        "05.06.2026  THYAO    ALIS   100       300,50   30050,00",
    ])
    res = sis.parse_statement(pdf)
    assert res["generic"] is True
    assert res["broker"] is None
    assert "MENKUL" in (res["issuer"] or "").upper()
    assert len(res["rows"]) == 1
    assert res["rows"][0]["symbol"] == "THYAO.IS"
    assert res["rows"][0]["quantity"] == 100 and res["rows"][0]["price"] == 300.50


def test_unknown_broker_with_nothing_readable_still_raises_with_name():
    """Sezgisel de bir şey bulamazsa kurumun adıyla açık hata ver."""
    pdf = _pdf([
        "ORNEK YATIRIM MENKUL DEGERLER A.S.",
        "MUSTERI HESAP EKSTRESI  01.06.2026 - 30.06.2026",
        "Sayin musterimiz, ekstreniz ektedir.",
    ])
    with pytest.raises(ValueError) as exc:
        sis.parse_statement(pdf)
    msg = str(exc.value)
    assert "MENKUL" in msg.upper()   # kurumun adı mesajda
    assert "Midas" in msg            # neyin desteklendiği mesajda


def test_non_statement_pdf_raises_generic_message():
    pdf = _pdf(["Alışveriş Fişi", "Ekmek 15,00", "Süt 42,50"])
    with pytest.raises(ValueError, match="aracı kurum ekstresine benzemiyor"):
        sis.parse_statement(pdf)


def test_midas_statement_with_no_activity_raises_distinct_message():
    """Tanınan kurum ama boş dönem → 'desteklenmiyor' DEME, 'hareket yok' de."""
    pdf = _pdf([
        "Midas Menkul Değerler A.Ş.",
        "01/09/26 - 30/09/26 HESAP EKSTRESİ",
        "YATIRIM İŞLEMLERİ (01/09/26 - 30/09/26)",
        "Kayıt bulunmamaktadır.",
    ])
    with pytest.raises(ValueError) as exc:
        sis.parse_statement(pdf)
    msg = str(exc.value)
    assert "hareket olmamış" in msg
    assert "desteklenmiyor" not in msg and "okunabiliyor" not in msg


def test_parse_statements_reports_unknown_broker_per_file():
    """Karışık yüklemede tanınmayan dosya diğerlerini çöpe atmaz."""
    good = _pdf([
        "Midas Menkul Değerler A.Ş.",
        "YATIRIM İŞLEMLERİ (01/06/26 - 30/06/26)",
        "05/06/26 10:00:00 Piyasa Emri AAPL Alış Gerçekleşti USD 3 - 3 187,50 1,50 562,50",
    ])
    other = _pdf(["ORNEK YATIRIM MENKUL DEGERLER A.S.", "HESAP EKSTRESI"])

    res = sis.parse_statements([("midas.pdf", good), ("baska.pdf", other)])
    assert len(res["rows"]) == 1
    assert res["brokers"] == ["Midas"]
    assert len(res["failed_files"]) == 1
    assert res["failed_files"][0]["file"] == "baska.pdf"
    assert "MENKUL" in res["failed_files"][0]["error"].upper()
