"""Şirket adı gösterimi: ham unvan ("Inc.", "Corporation", "A.S.") atılır.

Canlıda (16 Kas 2026) katalogda olmayan her hisse Yahoo/Finnhub'ın resmî
unvanıyla görünüyordu: "Apple Inc.", "NVIDIA Corporation", "Kardemir Celik
Sanayi AS", "SDT Uzay ve Savunma Teknolojileri Anonim Sirketi". Aşağıdaki
girdilerin çoğu o gün canlı `/market/prices` yanıtından alındı (KRDMD Yahoo
aramasından; KOZAL ve ALTN örnek).

Çalıştırma:  cd backend && python -m pytest tests/test_company_name.py -q
"""

import pytest

from app.utils.company_name import clean


@pytest.mark.parametrize("raw, symbol, expected", [
    ("Apple Inc.", "AAPL", "Apple"),
    ("NVIDIA Corporation", "NVDA", "NVIDIA"),
    ("Micron Technology, Inc.", "MU", "Micron Technology"),
    ("Meta Platforms, Inc.", "META", "Meta Platforms"),
    ("Alphabet Inc.", "GOOG", "Alphabet"),
    ("Palantir Technologies Inc.", "PLTR", "Palantir Technologies"),
    ("Centrus Energy Corp.", "LEU", "Centrus Energy"),
    ("NexGen Energy Ltd.", "NXE", "NexGen Energy"),
    ("Frontline plc", "FRO", "Frontline"),
    ("Mobilicom Limited", "MOB", "Mobilicom"),
    ("The Boeing Company", "BA", "Boeing"),
    ("Boeing Co", "BA", "Boeing"),                      # Finnhub biçimi
    ("JPMorgan Chase & Co.", "JPM", "JPMorgan Chase"),
    ("Procter & Gamble Co", "PG", "Procter & Gamble"),
    ("RTX Corporation", "RTX", "RTX"),
    ("Ondas Inc.", "ONDS", "Ondas"),
    # ETF ve fon adları olduğu gibi kalır
    ("Global X Uranium ETF", "URA", "Global X Uranium ETF"),
    ("Roundhill Memory ETF", "DRAM", "Roundhill Memory ETF"),
    # BIST: unvan + "ve Ticaret" atılır, Türkçe karakter geri gelir
    ("Kardemir Celik Sanayi AS", "KARCL.IS", "Kardemir Çelik Sanayi"),
    ("Papilon Savunma Teknoloji ve Ticaret A.S.", "PAPIL.IS",
     "Papilon Savunma Teknoloji"),
    ("SDT Uzay ve Savunma Teknolojileri Anonim Sirketi", "SDTTR.IS",
     "SDT Uzay ve Savunma Teknolojileri"),
    ("Kardemir Karabük Demir Çelik Sanayi Ve Ticaret A.S.", "KRDMD.IS",
     "Kardemir Karabük Demir Çelik"),
    ("Koza Altin Isletmeleri AS", "KOZAL.IS", "Koza Altın İşletmeleri"),
    # Zaten temiz ad değişmez
    ("Türk Hava Yolları", "THYAO.IS", "Türk Hava Yolları"),
    ("Altın (ons)", "GC=F", "Altın (ons)"),
])
def test_unvan_atilir(raw, symbol, expected):
    assert clean(raw, symbol) == expected


def test_turkce_duzeltme_yalniz_bist_te():
    # ABD hissesinde "Celik" gibi bir kelime olsa da dokunulmaz
    assert clean("Altin Corp.", "ALTN") == "Altin"


@pytest.mark.parametrize("raw", [None, "", "AAPL"])
def test_bos_ya_da_sembol_aynen_doner(raw):
    assert clean(raw, "AAPL") == raw


def test_yalniz_unvandan_olusan_ad_bozulmaz():
    assert clean("Inc.", "X") == "Inc."
