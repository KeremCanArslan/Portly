"""Makro takvim: olaylar GERÇEK kaynaklardan, uydurma yok.

Eskiden (16 Kas 2026'ya kadar) olaylar tarih ve saatleriyle LLM'e
ürettiriliyordu; LLM yokken her gün aynı iki sabit "örnek" olay dönüyordu.
Artık kaynak ForexFactory haftalık akışı (küresel) + TCMB resmî takvim sayfası
(Türkiye). Kaynak çökerse o kaynaktan olay gelmez — yerine bir şey uydurulmaz.
Ağ çağrılmaz: iki çekici de mock'lanır.

Çalıştırma:  cd backend && python -m pytest tests/test_macro_calendar.py -q
"""

from datetime import datetime

from app.services import macro_calendar_service as mcs

_NOW = datetime(2026, 11, 16, 9, 0, tzinfo=mcs._IST)   # Pazartesi 09:00 TR

_FF = [
    # ABD saatiyle 08:30 → TR 16:30; yüksek etki
    {"title": "CPI m/m", "country": "USD", "date": "2026-11-18T08:30:00-05:00",
     "impact": "High", "forecast": "0.3%", "previous": "0.1%"},
    # düşük etki → elenir
    {"title": "Crude Oil Inventories", "country": "USD",
     "date": "2026-11-18T10:30:00-05:00", "impact": "Low",
     "forecast": "", "previous": ""},
    # kapsam dışı para birimi → elenir
    {"title": "CPI q/q", "country": "NZD", "date": "2026-11-17T16:45:00-05:00",
     "impact": "High", "forecast": "", "previous": ""},
    # geçmiş olay → elenir
    {"title": "Retail Sales m/m", "country": "USD",
     "date": "2026-11-15T08:30:00-05:00", "impact": "High",
     "forecast": "", "previous": ""},
    # Avro Bölgesi, beklentisiz
    {"title": "German ifo Business Climate", "country": "EUR",
     "date": "2026-11-17T04:00:00-05:00", "impact": "High",
     "forecast": "", "previous": "88.4"},
]

_TCMB_HTML = """
<h2>PARA POLİTİKASI KURULU TOPLANTILARI VE RAPOR TAKVİMİ</h2>
<table id="midTable"><thead><tr>
<td><h3>Para Politikası Kurulu Toplantı Kararı</h3></td>
<td><h3>Para Politikası Kurulu Toplantı Özeti</h3></td>
<td><h3>Enflasyon Raporu</h3></td>
<td><h3>Finansal İstikrar Raporu</h3></td>
</tr></thead><tbody>
<tr><td>22 Ekim 2026</td><td>30 Ekim 2026</td><td>12 Kasım 2026</td><td>27 Kasım 2026</td></tr>
<tr><td>19 Kasım 2026</td><td>26 Kasım 2026</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>10 Aralık 2026</td><td>17 Aralık 2026</td><td>&nbsp;</td><td>&nbsp;</td></tr>
</tbody></table>
"""


def _patch(monkeypatch, ff=_FF, tcmb=_TCMB_HTML):
    monkeypatch.setattr(mcs, "_fetch_ff", lambda: ff)
    monkeypatch.setattr(mcs, "_fetch_tcmb_html", lambda: tcmb)
    monkeypatch.setattr(mcs, "_now", lambda: _NOW)
    mcs._cache.clear()


def test_ff_olayi_tr_saatine_cevrilir_ve_suzulur(monkeypatch):
    _patch(monkeypatch, tcmb=None)
    events = mcs.get_upcoming_events()
    titles = [e["title"] for e in events]
    assert titles == ["Almanya ifo iş ortamı endeksi", "ABD TÜFE (aylık)"]
    cpi = events[1]
    assert (cpi["date"], cpi["time"]) == ("2026-11-18", "16:30")
    assert cpi["country"] == "USA"
    assert cpi["importance"] == "high"
    assert cpi["impact"] == "Beklenti %0,3 · Önceki %0,1"
    assert cpi["source"] == "ForexFactory"
    assert events[0]["impact"] == "Önceki 88,4"


def test_tcmb_takvimi_okunur(monkeypatch):
    _patch(monkeypatch, ff=None)
    events = mcs.get_upcoming_events()
    ppk = [e for e in events if e["title"] == "TCMB faiz kararı (PPK)"]
    assert len(ppk) == 1                         # 7 gün içindeki tek karar
    assert (ppk[0]["date"], ppk[0]["time"]) == ("2026-11-19", "14:00")
    assert ppk[0]["country"] == "TUR" and ppk[0]["importance"] == "high"
    assert ppk[0]["source"] == "TCMB"
    # 7 günden sonraki (26 Kas özet, 27 Kas FİR) ve geçmiş (12 Kas) gelmez
    assert all(e["date"] <= "2026-11-23" for e in events)


def test_kaynaklar_coker_ise_uydurma_olay_donmez(monkeypatch):
    _patch(monkeypatch, ff=None, tcmb=None)
    assert mcs.get_upcoming_events() == []
    assert not hasattr(mcs, "llm_service")       # LLM'e olay ürettirilmez


def test_olaylar_tarih_saatine_gore_siralanir(monkeypatch):
    _patch(monkeypatch)
    events = mcs.get_upcoming_events()
    keys = [(e["date"], e["time"] or "99:99") for e in events]
    assert keys == sorted(keys)
    assert {e["source"] for e in events} == {"ForexFactory", "TCMB"}


def test_sayilar_turkce_yazilir():
    assert mcs._tr_number("-0.4%") == "−%0,4"
    assert mcs._tr_number("199K") == "199 bin"
    assert mcs._tr_number("-1.2B") == "−1,2 milyar"
    assert mcs._tr_number("52.1") == "52,1"
    assert mcs._tr_number("") == ""


def test_cachete_saati_gecen_olay_duser(monkeypatch):
    _patch(monkeypatch)
    morning = datetime(2026, 11, 19, 13, 0, tzinfo=mcs._IST)
    monkeypatch.setattr(mcs, "_now", lambda: morning)
    first = mcs.get_upcoming_events()
    assert any(e["title"] == "TCMB faiz kararı (PPK)" for e in first)

    def no_fetch():
        raise AssertionError("cache'ten dönmeliydi")
    monkeypatch.setattr(mcs, "_fetch_ff", no_fetch)
    monkeypatch.setattr(mcs, "_fetch_tcmb_html", no_fetch)
    later = datetime(2026, 11, 19, 14, 30, tzinfo=mcs._IST)   # TTL içinde
    monkeypatch.setattr(mcs, "_now", lambda: later)
    after = mcs.get_upcoming_events()
    assert all(e["title"] != "TCMB faiz kararı (PPK)" for e in after)


def test_tekrar_eden_konusma_listeyi_doldurmaz(monkeypatch):
    speech = {"title": "BOE Gov Bailey Speaks", "country": "GBP",
              "impact": "High", "forecast": "", "previous": ""}
    ff = [dict(speech, date=f"2026-11-1{d}T05:00:00-05:00") for d in (7, 8, 9)]
    ff.append({"title": "FOMC Meeting Minutes", "country": "USD",
               "date": "2026-11-19T14:00:00-05:00", "impact": "High",
               "forecast": "", "previous": ""})
    _patch(monkeypatch, ff=ff, tcmb=None)
    titles = [e["title"] for e in mcs.get_upcoming_events()]
    assert titles == ["BoE Başkanı Bailey konuşuyor", "FOMC toplantı tutanakları"]


def test_baslik_turkcelestirilir():
    assert mcs._ff_title("Core Retail Sales m/m", "USD") == (
        "ABD çekirdek perakende satışlar (aylık)", "USA")
    assert mcs._ff_title("Unemployment Rate", "USD")[0] == "ABD işsizlik oranı"
    assert mcs._ff_title("ISM Services PMI", "USD")[0] == "ABD ISM hizmet PMI"
    assert mcs._ff_title("Fed Chairman Warsh Speaks", "USD")[0] == \
        "Fed Başkanı Warsh konuşuyor"
    # haritada yoksa İngilizce kalır, uydurma çeviri yok
    assert mcs._ff_title("Foo Index", "JPY")[0] == "Japonya Foo Index"


def test_force_bes_dakikada_bir_kaynaga_gider(monkeypatch):
    _patch(monkeypatch, tcmb=None)
    calls = []
    monkeypatch.setattr(mcs, "_fetch_ff", lambda: calls.append(1) or _FF)
    mcs.get_upcoming_events()
    mcs.get_upcoming_events(force_refresh=True)          # hemen ardından
    assert len(calls) == 1
    soon = datetime(2026, 11, 16, 9, 6, tzinfo=mcs._IST)
    monkeypatch.setattr(mcs, "_now", lambda: soon)
    mcs.get_upcoming_events(force_refresh=True)          # 6 dk sonra
    assert len(calls) == 2
