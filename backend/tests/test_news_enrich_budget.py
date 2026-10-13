"""LLM enrich'in kesilmeye dayanıklılığı + haberin hangi sorgudan geldiğinin
etiketlenmesi (3 Eylül 2026, 5. tur).

İki ölçülen sorun:
 1. `max_tokens` SABİT 1800'dü, toplu yol ise 90 öğeye kadar çıkabiliyor
    (~26 token/öğe) → model JSON'ı ortasından kesiliyor, `json.loads` patlıyor
    ve enrich HİÇ uygulanmıyordu. Sessiz kayıp: kota yanıyor, sonuç yok.
 2. Haberi hangi sembolün getirdiği yanıtta yoktu; istemci portföy haberini
    başlıkta ticker arayarak eşliyordu. "Lockheed Martin ... " başlığında
    "LMT" geçmediği için canlıda 34 haberin 16'sı ekrana HİÇ çıkmıyordu.

Çalıştırma:  cd backend && python -m pytest tests/test_news_enrich_budget.py -q
"""

import json

from app.services import nlp_sentiment_service as nls


def _items(n: int) -> list[dict]:
    return [{
        "title": f"Haber {i}",
        "description": "",
        "url": "",
        "published_at": "2026-09-02T00:00:00",
        "sentiment_label": "Nötr",
        "sentiment_score": 0.0,
        "affected_assets": [],
    } for i in range(n)]


# ── 1) Kesik JSON ────────────────────────────────────────────────────────────

def test_max_tokens_scales_with_batch_size(monkeypatch):
    seen = {}

    def fake_complete(messages, **kw):
        seen.update(kw)
        return json.dumps({"items": [
            {"i": i, "lang": "en", "relevant": True, "score": 0.1}
            for i in range(90)]})

    monkeypatch.setattr(nls, "complete", fake_complete)
    nls._llm_enrich(_items(90), "portföy")

    # 90 öğelik JSON 1800 token'a sığmıyordu — sınır öğe sayısıyla büyümeli.
    assert seen["max_tokens"] > 1800


def test_truncated_json_still_applies_what_was_written(monkeypatch):
    """Kesik yanıt: yazılmış kararlar uygulanır, yarım kalan öğe DOKUNULMADAN
    listede kalır (haber kaybolmaz)."""
    truncated = (
        '{"items":[{"i":0,"lang":"en","relevant":true,"score":0.8},'
        '{"i":1,"lang":"en","relevant":false,"score":0.0},'
        '{"i":2,"lang":"en","rele'  # burada kesildi
    )
    monkeypatch.setattr(nls, "complete", lambda messages, **kw: truncated)

    out = nls._llm_enrich(_items(3), "portföy")
    titles = [n["title"] for n in out]

    assert "Haber 0" in titles          # relevant=true → kaldı
    assert "Haber 1" not in titles      # relevant=false → elendi
    assert "Haber 2" in titles          # kararı gelmedi → dokunulmadı
    assert out[0]["sentiment_score"] == 0.8   # kurtarılan skor uygulandı


def test_completely_broken_json_keeps_all_items(monkeypatch):
    """Kurtarılacak bir şey yoksa eski davranış: dil kapısı + VADER skoru."""
    monkeypatch.setattr(nls, "complete", lambda messages, **kw: "çöp yanıt")
    out = nls._llm_enrich(_items(4), "portföy")
    assert len(out) == 4


def test_salvage_reads_only_complete_records():
    raw = '{"items":[{"i":0,"lang":"en","relevant":true,"score":-0.5},{"i":1,"la'
    verdicts = nls._salvage_verdicts(raw)
    assert verdicts == [{"i": 0, "lang": "en", "relevant": True, "score": -0.5}]


# ── 2) Haberi getiren sorgunun etiketlenmesi ────────────────────────────────

_RSS = """<?xml version="1.0"?><rss version="2.0"><channel>
<item><title>Lockheed Martin wins $1B missile contract</title>
<link>https://x/1</link><description>d</description></item>
</channel></rss>"""


class _Resp:
    status_code = 200
    content = _RSS.encode()


def test_item_is_tagged_with_the_query_that_found_it(monkeypatch):
    monkeypatch.setattr(nls.requests, "get", lambda *a, **k: _Resp())
    out = nls._fetch_google_raw("en|LMT")
    assert out and out[0]["matched_query"] == "LMT"
    # Başlıkta "LMT" GEÇMİYOR — istemcinin metin eşlemesi bu haberi eliyordu.
    assert "LMT" not in out[0]["title"]


# ── 3) Çıplak ticker sorgusunun şirket adıyla genişletilmesi ───────────────

def test_bare_ticker_query_is_expanded_with_known_company_name(monkeypatch):
    from app.services import market_data_service as mds
    monkeypatch.setitem(mds._name_cache, "LMT", "Lockheed Martin Corporation")

    # Tüzel kişilik eki ("Corporation") atılır, sorgu OR ile genişler.
    assert nls._expand_with_company_name("LMT") == 'LMT OR "Lockheed Martin"'


def test_unknown_ticker_query_is_left_alone(monkeypatch):
    from app.services import market_data_service as mds
    mds._name_cache.pop("ZZZZ", None)
    assert nls._expand_with_company_name("ZZZZ") == "ZZZZ"


def test_non_ticker_query_is_left_alone():
    # İstemci BIST'te zaten ad gönderiyor — dokunma.
    q = 'ASELS OR "Aselsan"'
    assert nls._expand_with_company_name(q) == q
    assert nls._expand_with_company_name("gold price") == "gold price"


def test_expanded_query_reaches_google_but_tag_stays_the_symbol(monkeypatch):
    from app.services import market_data_service as mds
    monkeypatch.setitem(mds._name_cache, "PLTR", "Palantir Technologies Inc.")
    sent = {}

    class _R:
        status_code = 200
        content = _RSS.encode()

    def fake_get(url, params=None, **kw):
        sent.update(params or {})
        return _R()

    monkeypatch.setattr(nls.requests, "get", fake_get)
    out = nls._fetch_google_raw("en|PLTR")

    assert "Palantir Technologies" in sent["q"]
    # Etiket ham sembol kalır: istemci eşlemesi bunu kullanıyor.
    assert out[0]["matched_query"] == "PLTR"


# ─────────────────────── enrich sembolü tamamen susturmasın (6. tur)
#
# Ölçüm (4 Eyl 2026, 24 sorgu, gerçek RSS + gerçek LLM): 90 ham haberin 32'si
# (%36) enrich'te elendi ve 16 sembolün 5'i (AAPL · THYAO · TUPRS · KCHOL ·
# KARCL) listeden TAMAMEN kayboldu. İlk açılış ham listeyi, ikinci açılış
# enrich'liyi gösterdiği için kullanıcı hem sayının düştüğünü görüyor hem de
# portföyündeki hisse için "haber yok" sanıyor.

def _haber(baslik: str, sorgu: str, tarih: str) -> dict:
    return {
        "title": baslik,
        "description": "",
        "url": "",
        "published_at": tarih,
        "sentiment_label": "Nötr",
        "sentiment_score": 0.0,
        "affected_assets": [],
        "matched_query": sorgu,
    }


def test_tamamen_elenen_sembolun_en_yeni_haberi_geri_gelir():
    raw = [
        _haber("THYAO yeni sefer", "THYAO", "2026-09-04T10:00:00"),
        _haber("THYAO tarife", "THYAO", "2026-09-03T10:00:00"),
        _haber("GOOG bilanço", "GOOG", "2026-09-04T09:00:00"),
    ]
    enriched = [raw[2]]  # LLM iki THYAO haberini de "alakasız" buldu

    out = nls._restore_silenced_symbols(raw, enriched)

    basliklar = [i["title"] for i in out]
    assert "GOOG bilanço" in basliklar
    # Sembol sessizleşmesin diye TEK haber — en yenisi.
    assert "THYAO yeni sefer" in basliklar
    assert "THYAO tarife" not in basliklar


def test_haberi_kalan_sembole_dokunulmaz():
    raw = [
        _haber("MU bilanço", "MU", "2026-09-04T10:00:00"),
        _haber("MU reklam", "MU", "2026-09-03T10:00:00"),
    ]
    enriched = [raw[0]]  # biri elendi ama sembol susmadı

    out = nls._restore_silenced_symbols(raw, enriched)

    assert [i["title"] for i in out] == ["MU bilanço"]


def test_etiketsiz_haber_geri_konmaz():
    # matched_query yoksa hangi sembolü temsil ettiği bilinmiyor.
    raw = [_haber("kaynağı belirsiz", None, "2026-09-04T10:00:00")]
    assert nls._restore_silenced_symbols(raw, []) == []


def test_hicbir_sey_elenmediyse_liste_degismez():
    raw = [_haber("A", "AAPL", "2026-09-04T10:00:00")]
    assert nls._restore_silenced_symbols(raw, list(raw)) == raw


# ─────────────────────── havuz tavanı adil paylaşılsın (6. tur)
#
# Ölçüm (4 Eyl, canlı, 38 pozisyonlu gerçek portföy): havuz tavanı (90) saf
# tarih sırasıyla doluyordu; 90 haberin 72'si ABD sembollerine gidiyor, 13
# BIST/fon pozisyonuna yalnız 18 haber kalıyordu (bir sembol 10 alırken bir
# diğeri 1). Kullanıcı "Türk haberleri az geldi" dedi. Round-robin sonrası
# aynı veriyle: TR 36 / ABD 54, temsil edilen sembol 18 → 23.

def _n(sorgu: str, tarih: str) -> dict:
    return _haber(f"{sorgu} haberi {tarih}", sorgu, tarih)


def test_bol_haberli_sembol_tavani_tek_basina_yemez(monkeypatch):
    monkeypatch.setattr(nls, "_SYMBOL_POOL_LIMIT", 6)
    # ABD sembolü 10 haberle geliyor, iki BIST sembolünde 2'şer haber var.
    items = [_n("PLTR", f"2026-09-04T{10 - i:02d}:00:00") for i in range(10)]
    items += [_n("ASELS", "2026-09-03T09:00:00"), _n("ASELS", "2026-09-03T08:00:00")]
    items += [_n("THYAO", "2026-09-03T07:00:00"), _n("THYAO", "2026-09-03T06:00:00")]
    items.sort(key=lambda x: x["published_at"], reverse=True)

    out = nls._fair_share(items)

    assert len(out) == 6
    kaynaklar = {i["matched_query"] for i in out}
    # Eskiden yalnız PLTR dönerdi (en yeni 6 haber onundu).
    assert kaynaklar == {"PLTR", "ASELS", "THYAO"}


def test_tavanin_altindaysa_liste_aynen_kalir(monkeypatch):
    monkeypatch.setattr(nls, "_SYMBOL_POOL_LIMIT", 50)
    items = [_n("MU", "2026-09-04T10:00:00"), _n("MU", "2026-09-04T09:00:00")]
    assert nls._fair_share(items) == items


def test_sonuc_tarihe_gore_sirali_doner(monkeypatch):
    monkeypatch.setattr(nls, "_SYMBOL_POOL_LIMIT", 3)
    items = [
        _n("A", "2026-09-04T12:00:00"),
        _n("B", "2026-09-04T11:00:00"),
        _n("A", "2026-09-04T10:00:00"),
        _n("B", "2026-09-04T09:00:00"),
    ]
    out = nls._fair_share(items)
    tarihler = [i["published_at"] for i in out]
    assert tarihler == sorted(tarihler, reverse=True)
