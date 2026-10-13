"""Fiyat cache'i: kullanıcı isteği kaynağı BEKLEMEZ (4 Eylül 2026, 6. tur).

Ölçüm (canlı, 38 pozisyonlu gerçek portföy): `/portfolio/1` ardışık üç çağrıda
1,2 / **5,8** / 0,3 sn sürdü. Kerem "portföy hâlâ geç yükleniyor" dedi.

Kök sebep: fiyat kaydı cache'e `_STALE_TTL_SECONDS` (10 dk) ile yazılıyordu →
10 dakika sonra kayıt SİLİNİYOR, sonraki istek "missing" sayılıp bloklayan
çekime düşüyordu. Arka plan işçisi boştayken durduğu için (Neon kotası) bu
sık oluyordu.

Sözleşme: kayıt `_KEEP_TTL_SECONDS` boyunca elde tutulur; yaşı 10 dakikayı
geçmişse bayat-ama-GERÇEK fiyat ANINDA döner ve tazeleme arka plana gider.
"""

import time

from app.services import market_data_service as mds


def _kur_cache(monkeypatch, yas_saniye: float):
    """Cache'te verilen yaşta bir fiyat kaydı varmış gibi davran."""
    kayit = {"symbol": "AAPL", "company_name": "Apple", "current_price": 200.0,
             "change_percent": 1.0}
    monkeypatch.setattr(mds, "_cache_get",
                        lambda key: (kayit, time.time() - yas_saniye))
    monkeypatch.setattr(mds, "_cache_set", lambda *a, **k: None)
    return kayit


def test_bayat_kayit_bloklamadan_servis_edilir(monkeypatch):
    _kur_cache(monkeypatch, mds._STALE_TTL_SECONDS + 60)  # 11 dakikalık
    cagrildi = []
    monkeypatch.setattr(mds, "_fetch_many",
                        lambda syms: cagrildi.append(syms) or {})
    arka_plan = []
    monkeypatch.setattr(mds, "_schedule_batch_refresh", arka_plan.append)

    out = mds.get_stock_prices(["AAPL"])

    assert out["AAPL"]["current_price"] == 200.0
    assert cagrildi == [], "kullanıcı isteği kaynağı BEKLEMEMELİ"
    assert arka_plan == [["AAPL"]], "tazeleme arka plana gitmeli"


def test_taze_kayitta_arka_plan_tazelemesi_de_yok(monkeypatch):
    _kur_cache(monkeypatch, 5)  # 5 saniyelik
    arka_plan = []
    monkeypatch.setattr(mds, "_schedule_batch_refresh", arka_plan.append)
    monkeypatch.setattr(mds, "_fetch_many", lambda syms: {})

    out = mds.get_stock_prices(["AAPL"])

    assert out["AAPL"]["current_price"] == 200.0
    assert arka_plan == []


def test_gercekten_eski_kayit_icin_cekim_yapilir(monkeypatch):
    _kur_cache(monkeypatch, mds._KEEP_TTL_SECONDS + 60)  # 6 saatten eski
    cagrildi = []

    def _fetch(syms):
        cagrildi.append(syms)
        return {"AAPL": {"symbol": "AAPL", "current_price": 250.0,
                         "change_percent": 2.0}}

    monkeypatch.setattr(mds, "_fetch_many", _fetch)
    monkeypatch.setattr(mds, "_recently_failed", lambda *a: False)

    out = mds.get_stock_prices(["AAPL"])

    assert cagrildi == [["AAPL"]]
    assert out["AAPL"]["current_price"] == 250.0


def test_kayit_saklama_suresi_stale_penceresinden_uzun():
    # Kayıt stale penceresi kadar yaşasaydı, bayat servis etme yolu hiç
    # çalışmazdı (kayıt zaten silinmiş olurdu) — regresyon nöbetçisi.
    assert mds._KEEP_TTL_SECONDS > mds._STALE_TTL_SECONDS
