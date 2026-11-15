"""Haberden etkilenen varlık çıkarımı (`extract_affected_assets`).

Canlıda (16 Kas 2026) iki yanlış etiket görüldü: tutar bildiren "milyon dolar"
haberi USD/TRY, "Silver Lake" (yatırım fonu) haberi Gümüş sayılıyordu. USD/TRY
izleme listesinde olunca alakasız haber "İzleme Listem"e düşüyordu.

Çalıştırma:  cd backend && python -m pytest tests/test_asset_extractor.py -q
"""

import pytest

from app.services.asset_extractor_service import extract_affected_assets


def _symbols(text: str) -> list[str]:
    return [a["symbol"] for a in extract_affected_assets(text)]


@pytest.mark.parametrize("text", [
    "Şirket 250 milyon dolar yatırım yapacak",
    "Anlaşmanın değeri 1,5 milyar dolar",
    "Hisse başına 12 dolar temettü",
    "Avrupa'ya 40 milyon euro ihracat",
])
def test_amount_in_currency_is_not_fx_news(text):
    assert "USDTRY=X" not in _symbols(text)
    assert "EURTRY=X" not in _symbols(text)


@pytest.mark.parametrize("text, symbol", [
    ("Dolar rekor kırdı, kur 42 lirayı aştı", "USDTRY=X"),
    ("Dolar/TL güne yükselişle başladı", "USDTRY=X"),
    ("Euro haftaya düşüşle başladı", "EURTRY=X"),
])
def test_currency_news_still_tagged(text, symbol):
    assert symbol in _symbols(text)


@pytest.mark.parametrize("text", [
    "Silver Lake takes Electronic Arts private",
    "Every cloud has a silver lining for investors",
])
def test_silver_word_alone_is_not_silver_news(text):
    assert "SI=F" not in _symbols(text)


@pytest.mark.parametrize("text", [
    "Silver prices jump as dollar weakens",
    "Gümüş ons başına 50 doları aştı",
    "Spot silver hits record",
])
def test_silver_news_still_tagged(text):
    assert "SI=F" in _symbols(text)


def test_gold_prices_plural_tagged():
    assert "GC=F" in _symbols("Gold prices hit record high")


def test_order_follows_text():
    text = "Bitcoin rallies while Apple shares slip"
    assert _symbols(text)[:2] == ["BTC-USD", "AAPL"]
