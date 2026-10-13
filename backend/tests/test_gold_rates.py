"""Banka Altın ekranı — kaynak veri kusurlarına karşı savunma testleri.

Kaynak (truncgil) iki şekilde yanıltıyor, ikisi de gerçek ekranda görüldü:

1. Türev ürünlerin (çeyrek/tam/ata/bilezik) "Değişim" alanını doldurmayıp
   '%0,00' döndürüyor — üstelik o ürünlerin FİYATI da güncellenmemiş oluyor.
   Ekranda "bugün hiç değişmedi" diye göstermek yanlış bilgiydi.
2. Bağlantıyı yanıtsız kapatıyor (ölçüm: tek denemede ~%40 başarı). Boş
   sonuç 5 dk cache'lenince "Altın Ürünleri" bölümü ekrandan tamamen
   kayboluyordu.
"""

from datetime import datetime

import pytest

from app.services import gold_rates_service as g


@pytest.mark.parametrize("raw,expected", [
    ("%-1,42", -1.42),
    ("%0,00", 0.0),
    ("%3,51", 3.51),
    ("", None),
    (None, None),
    ("abc", None),
])
def test_pct_from_change(raw, expected):
    assert g._pct_from_change(raw) == expected


def test_fake_zero_change_is_hidden_when_gram_moved():
    """Gram %-1,42 iken ürün '%0,00' diyorsa bu veri yok demektir."""
    text, stale = g._clean_change("%0,00", -1.42)
    assert text == "" and stale is True


def test_real_zero_change_is_kept_when_gram_also_flat():
    """Gram da yatay ise '%0,00' GERÇEKTİR — gizlenmemeli."""
    text, stale = g._clean_change("%0,00", 0.0)
    assert text == "%0,00" and stale is False


def test_real_change_always_kept():
    assert g._clean_change("%-0,23", -1.42) == ("%-0,23", False)
    assert g._clean_change("%1,10", -1.42) == ("%1,10", False)


def test_missing_change_is_not_marked_stale():
    """Alan hiç yoksa 'bayat' iddiasında bulunma — yalnız boş göster."""
    assert g._clean_change(None, -1.42) == ("", False)
    assert g._clean_change("", -1.42) == ("", False)


def test_no_reference_means_no_hiding():
    """Gram değişimi bilinmiyorsa ürün verisini yargılayamayız."""
    assert g._clean_change("%0,00", None) == ("%0,00", False)


def test_truncgil_retries_before_giving_up(monkeypatch):
    calls = {"n": 0}

    def flaky(*a, **k):
        calls["n"] += 1
        raise ConnectionError("Remote end closed connection")

    monkeypatch.setattr(g.requests, "get", flaky)
    monkeypatch.setattr(g.time, "sleep", lambda _s: None)

    assert g._fetch_truncgil(attempts=3) is None
    assert calls["n"] == 3


def test_truncgil_succeeds_on_second_attempt(monkeypatch):
    calls = {"n": 0}

    class Resp:
        status_code = 200

        @staticmethod
        def json():
            return {"gram-altin": {"Alış": "1", "Satış": "2"}}

    def flaky(*a, **k):
        calls["n"] += 1
        if calls["n"] == 1:
            raise ConnectionError("Remote end closed connection")
        return Resp()

    monkeypatch.setattr(g.requests, "get", flaky)
    monkeypatch.setattr(g.time, "sleep", lambda _s: None)

    assert g._fetch_truncgil(attempts=3) is not None
    assert calls["n"] == 2


def test_empty_products_do_not_evict_cached_list(monkeypatch):
    """Kaynak patlarsa bölüm ekrandan SİLİNMEMELİ — son iyi liste korunur."""
    g._cache.clear()
    g._cache["data"] = (
        {
            "extra_products": [{"name": "Çeyrek Altın", "buy": 1, "sell": 2,
                                "change": "%-0,71", "stale": False}],
            "reference_change": "%-1,38",
        },
        datetime.now(),
    )

    # HER İKİ kaynak da erişilemez; banka scrape'i de kapalı → tahminî fiyat.
    monkeypatch.setattr(g, "_fetch_canlidoviz_gold", lambda *a, **k: None)
    monkeypatch.setattr(g, "_fetch_truncgil", lambda *a, **k: None)
    monkeypatch.setattr(g, "_gram_gold_in_try", lambda: 6800.0)
    monkeypatch.setattr(g, "_fetch_canlidoviz_bank", lambda slug: None)
    # TTL'i aşmış gibi davran ki cache'ten dönmesin.
    g._cache["data"] = (g._cache["data"][0],
                        datetime.now() - g.timedelta(minutes=10))

    res = g.get_bank_gold_rates()
    assert res["products_stale"] is True
    assert len(res["extra_products"]) == 1
    assert res["extra_products"][0]["name"] == "Çeyrek Altın"
    assert res["reference_change"] == "%-1,38"
    g._cache.clear()


# --------------------------------------------------------------------------
# Kaynak değişimi: canlidoviz birincil, truncgil yedek
#
# truncgil iki ayrı şekilde yanıltıyordu: türev ürünlerin değişimini
# doldurmuyor VE Python istemcisiyle bağlantıyı sık kapatıyordu (ölçüm:
# requests 1-2/6, curl 5/5, curl_cffi 0/5). canlidoviz aynı ölçümde 5/5,
# her ürün için gerçek değişim veriyor ve banka fiyatları için zaten
# kullanıldığından Render'dan çalıştığı kanıtlı.
# --------------------------------------------------------------------------
def test_canlidoviz_is_primary_and_truncgil_not_called(monkeypatch):
    called = {"truncgil": 0}

    def fake_cd():
        return {
            "GA": {"buy": 6800.0, "sell": 6801.0, "change": "%-1,56"},
            "C": {"buy": 11000.0, "sell": 11180.0, "change": "%-1,49"},
        }

    def fake_truncgil(*a, **k):
        called["truncgil"] += 1
        return None

    g._cache.clear()
    monkeypatch.setattr(g, "_fetch_canlidoviz_gold", fake_cd)
    monkeypatch.setattr(g, "_fetch_truncgil", fake_truncgil)
    monkeypatch.setattr(g, "_fetch_canlidoviz_bank", lambda slug: None)

    res = g.get_bank_gold_rates()
    assert res["products_source"] == "canlidoviz"
    assert called["truncgil"] == 0          # yedek boşuna çağrılmadı
    assert res["reference_change"] == "%-1,56"
    names = [p["name"] for p in res["extra_products"]]
    assert "Çeyrek Altın" in names
    g._cache.clear()


def test_falls_back_to_truncgil_when_canlidoviz_down(monkeypatch):
    g._cache.clear()
    monkeypatch.setattr(g, "_fetch_canlidoviz_gold", lambda *a, **k: None)
    monkeypatch.setattr(g, "_fetch_truncgil", lambda *a, **k: {
        "gram-altin": {"Alış": "6.800,00", "Satış": "6.801,00",
                       "Değişim": "%-1,42"},
        "ceyrek-altin": {"Alış": "11.000,00", "Satış": "11.180,00",
                         "Değişim": "%0,00"},
    })
    monkeypatch.setattr(g, "_fetch_canlidoviz_bank", lambda slug: None)

    res = g.get_bank_gold_rates()
    assert res["products_source"] == "truncgil"
    # Yedek yoldayken sahte %0,00 koruması HÂLÂ geçerli olmalı.
    ceyrek = [p for p in res["extra_products"] if p["name"] == "Çeyrek Altın"][0]
    assert ceyrek["change"] == "" and ceyrek["stale"] is True
    g._cache.clear()
