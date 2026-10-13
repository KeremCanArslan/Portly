"""Sembol gösterim adı (4 Eylül 2026, 6. tur).

Kerem sohbette "GC=F" görünce "bu altın demek, hiçbir yerde karşıma çıkmasın"
dedi. Arayüzdeki `SymbolDisplay` LLM çıktısını düzeltemez (serbest metin) →
modele ham sembol HİÇ verilmiyor. Bu testler frontend `compact()` ile aynı
sözleşmeyi backend'de sabitler.
"""

import pytest

from app.utils.symbol_display import compact


@pytest.mark.parametrize("ham,beklenen", [
    ("GC=F", "Altın"),
    ("SI=F", "Gümüş"),
    ("USDTRY=X", "USD/TRY"),
    ("BTC-USD", "Bitcoin"),
    ("THYAO.IS", "Türk Hava Yolları"),
    ("TUPRS.IS", "Tüpraş"),
])
def test_bilinen_sembol_turkce_ada_donusur(ham, beklenen):
    assert compact(ham) == beklenen


@pytest.mark.parametrize("ham,beklenen", [
    ("KARCL.IS", "KARCL"),      # haritada yok → yalnız sonek kırpılır
    ("TLY.FON", "TLY"),
    ("GLRMK.IS", "GLRMK"),
    ("ZM=F", "ZM"),
    ("HYPE32196-USD", "HYPE"),  # Yahoo'nun eklediği sayısal id atılır
])
def test_bilinmeyen_sembolde_sonek_kirpilir(ham, beklenen):
    assert compact(ham) == beklenen


def test_abd_hissesi_dokunulmaz():
    # LMT/GOOG zaten okunabilir; değiştirmek modeli yanıltırdı.
    assert compact("LMT") == "LMT"
    assert compact("GOOG") == "GOOG"


def test_bos_ve_kucuk_harf():
    assert compact("") == ""
    assert compact("gc=f") == "Altın"
