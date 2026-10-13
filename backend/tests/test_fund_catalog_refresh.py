"""Fon kataloğunun canlı tazelenmesi.

Bağlam: katalog (`app/data/tefas_funds.json`) elle üretilip commit'leniyordu;
arada kurulan bir fon deploy'a kadar "bulunamadı" görünüyordu. Arka plan
işçisi artık günde bir TEFAS'ın liste ucundan YENİ kodları ekliyor.

Kural: tazeleme yalnız EKLER. Dosya gözden geçirilmiş kaynak; canlı uç bir
gün yarım liste dönerse doğrulanmış adı kaybetmeyelim.

Testler ağa ÇIKMAZ.
"""

import pytest

from app.services import fund_catalog as fc
from app.services import fund_source_service as fss
from app.services import market_refresh_service as mrs


@pytest.fixture(autouse=True)
def _izole(monkeypatch):
    # CATALOG modül düzeyinde ve paylaşılıyor → testler birbirini kirletmesin.
    monkeypatch.setattr(fc, "CATALOG", dict(fc.CATALOG))
    monkeypatch.setattr(fc, "_last_refresh", 0.0)
    yield


def test_merge_yalniz_yeni_kod_ekler():
    fc.CATALOG["TLY"] = ("ESKİ AMA DOĞRULANMIŞ UNVAN", "Serbest")
    added = fc.merge({"TLY": ("BOZUK UNVAN", ""), "ZZZ": ("YENİ FON", "Hisse")})
    assert added == 1
    assert fc.CATALOG["TLY"][0] == "ESKİ AMA DOĞRULANMIŞ UNVAN"
    assert fc.CATALOG["ZZZ"] == ("YENİ FON", "Hisse")


def test_merge_adsiz_kaydi_almaz():
    assert fc.merge({"QQQ": ("", "Hisse"), "": ("AD", "")}) == 0


def test_refresh_gunde_bir_calisir(monkeypatch):
    cagri = []
    monkeypatch.setattr(fss, "fetch_catalog",
                        lambda: cagri.append(1) or {"YNI": ("YENİ FON", "")})
    assert fc.refresh_if_due() == 1
    assert fc.refresh_if_due() == 0      # sayaç dolmadı → ağa çıkmaz
    assert len(cagri) == 1
    assert fc.is_known_code("YNI")


def test_uc_dusukse_katalog_bozulmaz(monkeypatch):
    onceki = dict(fc.CATALOG)
    monkeypatch.setattr(fss, "fetch_catalog", lambda: {})
    assert fc.refresh_if_due() == 0
    assert fc.CATALOG == onceki


def test_uc_patlarsa_sessiz_gecer(monkeypatch):
    def _patla():
        raise RuntimeError("TEFAS düştü")
    monkeypatch.setattr(fss, "fetch_catalog", _patla)
    assert fc.refresh_if_due() == 0


def test_kisa_liste_zehirlemez(monkeypatch):
    """fetch_catalog kendi eşiğini uygular: yarım liste → boş döner."""
    class _Resp:
        status_code = 200

        def json(self):
            return {"resultList": [{"fonKodu": "AAA", "fonUnvan": "A FONU"}]}

    class _Client:
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def post(self, *a, **k): return _Resp()

    monkeypatch.setattr(fss.httpx, "Client", lambda *a, **k: _Client())
    monkeypatch.setattr(fss, "available", lambda: True)
    assert fss.fetch_catalog() == {}


def test_devre_kesik_ise_istek_atilmaz(monkeypatch):
    monkeypatch.setattr(fss, "available", lambda: False)
    monkeypatch.setattr(fss.httpx, "Client",
                        lambda *a, **k: pytest.fail("ağa çıkılmamalıydı"))
    assert fss.fetch_catalog() == {}


def test_isci_turunda_katalog_iSi_var(monkeypatch):
    monkeypatch.setattr(fss, "fetch_catalog", lambda: {"YNI": ("YENİ FON", "")})
    monkeypatch.setattr(mrs.market_data_service, "prewarm_symbols",
                        lambda symbols: None)
    monkeypatch.setattr(mrs.market_data_service, "refresh_daily_closes",
                        lambda symbols: {})
    monkeypatch.setattr(mrs.market_data_service, "refresh_daily_ohlcv",
                        lambda symbols, period: {})
    res = mrs.refresh(["THYAO.IS"])
    assert res.new_funds == 1
    assert not res.errors
