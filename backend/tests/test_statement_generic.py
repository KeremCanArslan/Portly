"""Kurum-bağımsız ekstre okuma (statement_generic) testleri.

Bu katman Midas profili tutmadığında devreye giren SON deterministik çaredir
— AI yok. İki kademesi ayrı ayrı kilitlenir:
  1. Başlık eşleme ("Tarih Kıymet İşlem Adet Fiyat Tutar")
  2. Çarpım sezgisi (a × b ≈ c → adet × fiyat = tutar)

Ayrıca en kritik davranış: Midas profili TUTTUĞUNDA bu katman hiç
çalışmamalı, yoksa aynı satırlar iki kez sayılır.
"""

import pytest

from app.services import statement_generic as g


# --------------------------------------------------------------------------
# Sayı biçimi ve ondalık tespiti
# --------------------------------------------------------------------------
@pytest.mark.parametrize("raw,expected", [
    ("1.234,56", 1234.56),
    ("1,234.56", 1234.56),
    ("1234.56", 1234.56),
    ("40", 40.0),
    ("50.000,00", 50000.0),
    ("₺300,50", 300.50),
    ("", None),
    ("abc", None),
])
def test_to_float(raw, expected):
    assert g._to_float(raw) == expected


@pytest.mark.parametrize("raw,expected", [
    ("1.250,00", True),    # kuruşlu → fiyat sinyali
    ("300,50", True),
    ("40", False),         # çıplak tam sayı → adet sinyali
    ("1.250", False),      # sondaki 3 hane BİNLİK ayracı, ondalık değil
    ("50.000", False),
])
def test_has_decimals(raw, expected):
    assert g._has_decimals(raw) is expected


def test_order_qty_price_uses_decimal_signal():
    """Çarpım her iki sırada aynı; ayırt eden tek şey ondalık yazım.

    '1.250,00' kuruşlu → fiyat, '40' çıplak → adet. Sıra ters olsa bile
    doğru eşleşmeli; yanlış eşleşme pozisyonu tamamen ters çevirirdi.
    """
    assert g._order_qty_price((1250.0, "1.250,00"), (40.0, "40")) == (40.0, 1250.0)
    assert g._order_qty_price((40.0, "40"), (1250.0, "1.250,00")) == (40.0, 1250.0)


def test_order_qty_price_falls_back_to_common_order():
    """İkisi de (ya da hiçbiri) ondalıklıysa yaygın sıra: önce adet."""
    assert g._order_qty_price((100.0, "100"), (50.0, "50")) == (100.0, 50.0)
    assert g._order_qty_price((10.5, "10,50"), (20.5, "20,50")) == (10.5, 20.5)


# --------------------------------------------------------------------------
# Başlık eşleme
# --------------------------------------------------------------------------
def test_detect_header():
    hdr = g.detect_header("Tarih Kıymet İşlem Adet Fiyat Tutar")
    assert hdr is not None
    assert hdr["quantity"] == 3 and hdr["price"] == 4


def test_detect_header_requires_quantity_and_amount():
    """Rastgele bir metin başlık sanılmamalı."""
    assert g.detect_header("Sayın müşterimiz, ekstreniz ektedir") is None
    assert g.detect_header("Tarih Açıklama") is None


def test_header_layout_parsed():
    rows, cancelled = g.parse_lines([
        "Tarih Kıymet İşlem Adet Fiyat Tutar",
        "05.06.2026 THYAO Alış 100 300,50 30050,00",
        "12.06.2026 GARAN Satış 50 118,20 5910,00",
    ])
    assert cancelled == 0 and len(rows) == 2
    assert rows[0]["symbol"] == "THYAO.IS"      # BIST kodu → .IS
    assert rows[0]["quantity"] == 100 and rows[0]["price"] == 300.50
    assert rows[1]["side"] == "SELL"
    assert all(r["source"] == "generic" for r in rows)


# --------------------------------------------------------------------------
# Çarpım sezgisi (başlıksız)
# --------------------------------------------------------------------------
def test_product_heuristic_reversed_columns():
    """Fiyat sütunu önce gelse bile adet/fiyat doğru ayrılmalı."""
    rows, _ = g.parse_lines([
        "20/06/2026  SATIŞ  EREGL  1.250,00  40  50.000,00",
    ])
    assert len(rows) == 1
    assert rows[0]["quantity"] == 40 and rows[0]["price"] == 1250.0


def test_product_heuristic_tolerates_commission():
    """Tutar komisyonla hafif kayabilir — %2 tolerans."""
    rows, _ = g.parse_lines(["01.07.2026 ALIŞ TUPRS 10 180,50 1.809,00"])
    assert len(rows) == 1
    assert rows[0]["quantity"] == 10 and rows[0]["price"] == 180.50


# --------------------------------------------------------------------------
# Gerçekleşmemiş emirler — Midas'ta bu tuzağın portföyü bozduğu görüldü
# --------------------------------------------------------------------------
def test_cancelled_rows_skipped_and_counted():
    rows, cancelled = g.parse_lines([
        "Tarih Sembol İşlem Adet Fiyat Tutar Durum",
        "01.07.2026 BIMAS Alış 30 512,00 15360,00 Gerçekleşti",
        "02.07.2026 BIMAS Satış 30 520,00 15600,00 İptal Edildi",
        "03.07.2026 BIMAS Satış 30 520,00 15600,00 Beklemede",
    ])
    assert len(rows) == 1 and rows[0]["side"] == "BUY"
    assert cancelled == 2


def test_noise_lines_ignored():
    rows, _ = g.parse_lines([
        "Sayfa 1 / 4",
        "Hesap No: 12345678",
        "TOPLAM 01.07.2026 Alış 30 512,00 15360,00",
        "Müşteri Adı Soyadı : TEST",
    ])
    assert rows == []


def test_line_without_date_or_side_is_not_a_trade():
    rows, _ = g.parse_lines([
        "THYAO 100 300,50 30050,00",        # tarih yok
        "05.06.2026 THYAO 100 300,50",      # AL/SAT yok
    ])
    assert rows == []


def test_duplicate_lines_counted_once():
    line = "05.06.2026 THYAO Alış 100 300,50 30050,00"
    rows, _ = g.parse_lines([line, line])
    assert len(rows) == 1


# --------------------------------------------------------------------------
# EN KRİTİK: Midas profili tuttuğunda sezgisel HİÇ çalışmamalı
# --------------------------------------------------------------------------
def test_generic_does_not_run_when_midas_profile_matches():
    from app.services import statement_import_service as sis
    from tests.test_statement_import import _pdf

    pdf = _pdf([
        "Midas Menkul Değerler A.Ş.",
        "YATIRIM İŞLEMLERİ (01/06/26 - 30/06/26)",
        "05/06/26 10:00:00 Piyasa Emri AAPL Alış Gerçekleşti USD "
        "3 - 3 187,50 1,50 562,50",
    ])
    res = sis.parse_statement(pdf)
    assert res["generic"] is False
    assert len(res["rows"]) == 1          # iki kez sayılmadı
    assert res["rows"][0]["symbol"] == "AAPL"
