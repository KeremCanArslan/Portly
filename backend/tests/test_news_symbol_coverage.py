"""Portföy/İzleme haberi — kapsam ve dil.

İki ölçülen şikâyet:
 1. "Haber sayısı az": sembol listesi 12'de kesiliyordu ("demo üst sınırı").
    51 pozisyonlu portföyde 39 hissenin haberi HİÇ çekilmiyordu.
 2. "Türk haberi yok": ABD sembolleri yalnız İngilizce basından çekiliyordu.
    Artık hem İngilizce (Reuters/Bloomberg kalitesi) hem Türkçe çekilir.

Ağ yok: RSS çekimi monkeypatch'lenir.
"""

from datetime import timedelta

import pytest

from app.services import nlp_sentiment_service as nls


@pytest.fixture(autouse=True)
def _clear():
    nls._multi_cache.clear()
    nls._multi_refreshing.clear()
    yield
    nls._multi_cache.clear()
    nls._multi_refreshing.clear()


@pytest.fixture
def captured(monkeypatch):
    """Çekilen sorguları toplar, her sorgu için tek sahte haber döndürür."""
    seen: list[str] = []

    def fake(query):
        seen.append(query)
        return [{
            "title": f"haber {query}",
            "description": "", "url": "", "published_at": "2026-09-02T00:00:00",
            "sentiment_label": "Nötr", "sentiment_score": 0.0,
            "affected_assets": [],
        }]

    monkeypatch.setattr(nls, "_fetch_google_raw", fake)
    # Arka plan LLM enrich thread'i testte çalışmasın
    monkeypatch.setattr(nls, "_refresh_multi_bg", lambda key, clean: None)
    return seen


# ── Dil genişletmesi ──────────────────────────────────────────────────────

def test_us_symbol_is_fetched_in_both_languages():
    out = nls._expand_bilingual(["en|Lockheed Martin"])
    assert out == ["en|Lockheed Martin", "tr|Lockheed Martin"]


def test_bist_symbol_is_not_duplicated():
    """BIST zaten Türk basınından geliyor — ikinci sorgu israf olurdu."""
    assert nls._expand_bilingual(["tr|THYAO"]) == ["tr|THYAO"]


def test_mixed_portfolio_expansion():
    out = nls._expand_bilingual(["en|Boeing", "tr|ASELS", "en|Micron"])
    assert out == ["en|Boeing", "tr|Boeing", "tr|ASELS",
                   "en|Micron", "tr|Micron"]


def test_collect_actually_queries_both_languages(captured):
    nls._collect_raw_for_symbols(["en|Boeing", "tr|ASELS"])
    assert sorted(captured) == ["en|Boeing", "tr|ASELS", "tr|Boeing"]


# ── Sembol kapsamı ────────────────────────────────────────────────────────

def test_symbol_cap_covers_a_real_portfolio(captured):
    """12 sınırı gerçek portföyler için çok dardı; 24 de yetmiyordu (canlı
    portföy 38 pozisyon)."""
    assert nls._MAX_SYMBOLS >= 40

    queries = [f"en|SYM{i}" for i in range(40)]
    nls.get_news_for_symbols(queries)

    # Tek turda Google'a atılan sorgu sayısı BÜTÇEYLE sınırlı (kısıtlama
    # kalkanı) — sembol sayısıyla değil.
    assert len(captured) == nls._FETCH_BUDGET
    # Bütçe önce BİRİNCİL sorgulara gider: her sembol en azından kendi
    # dilinden bir kez sorulsun, dil ikizleri sonra.
    assert all(q.startswith("en|") for q in captured)


def test_second_round_covers_the_remaining_symbols(captured):
    """Bütçe dışı kalan sembol kaybolmuyor: sonraki tur onları çekiyor."""
    queries = [f"en|SYM{i}" for i in range(40)]
    nls.get_news_for_symbols(queries)
    first_round = set(captured)

    captured.clear()
    nls._multi_cache.clear()          # sonraki açılış / arka plan tazeleme
    nls.get_news_for_symbols(queries)

    # İlk turda çekilenler cache'te taze → tekrar çekilmez, sıra yenilere gelir.
    assert not (set(captured) & first_round)
    assert len(captured) == nls._FETCH_BUDGET


def test_cached_symbols_are_not_refetched(captured):
    nls.get_news_for_symbols(["en|Boeing"])
    fetched_once = list(captured)
    captured.clear()
    nls._multi_cache.clear()
    nls.get_news_for_symbols(["en|Boeing"])
    assert fetched_once and captured == []


def test_empty_response_keeps_previous_news(monkeypatch):
    """Google News kısıtlamayı 200 + BOŞ feed ile yapıyor → boş yanıt eldeki
    haberi SİLMEMELİ (yoksa sembol ekrandan kayboluyor)."""
    monkeypatch.setattr(nls, "_refresh_multi_bg", lambda key, clean: None)
    item = {
        "title": "Boeing haberi", "description": "", "url": "",
        "published_at": "2026-09-02T00:00:00",
        "sentiment_label": "Nötr", "sentiment_score": 0.0,
        "affected_assets": [],
    }
    monkeypatch.setattr(nls, "_fetch_google_raw", lambda q: [item])
    first = nls._collect_raw_for_symbols(["en|Boeing"])
    assert len(first) == 1

    # Cache'i bayatlat + kaynağı sustur (kısıtlama)
    for entry in nls._raw_cache.values():
        entry["timestamp"] -= timedelta(minutes=nls._NEWS_CACHE_TTL_MINUTES + 1)
    monkeypatch.setattr(nls, "_fetch_google_raw", lambda q: [])

    assert [n["title"] for n in nls._collect_raw_for_symbols(["en|Boeing"])] \
        == ["Boeing haberi"]


def test_more_symbols_yield_more_news(captured):
    few = nls.get_news_for_symbols([f"en|A{i}" for i in range(3)])
    nls._multi_cache.clear()
    many = nls.get_news_for_symbols([f"en|B{i}" for i in range(20)])
    assert len(many) > len(few)


def test_pool_limit_is_larger_than_general_feed():
    """Toplu haber çok daha fazla sembol içeriyor → genel akışın 40'lık
    sınırında kesilirse liste seyrekleşiyordu."""
    assert nls._SYMBOL_POOL_LIMIT > nls._POOL_LIMIT


def test_result_is_capped(captured):
    out = nls.get_news_for_symbols([f"en|S{i}" for i in range(30)])
    assert len(out) <= nls._SYMBOL_POOL_LIMIT


def test_empty_query_list(captured):
    assert nls.get_news_for_symbols([]) == []
    assert captured == []


def test_duplicate_titles_are_deduped(monkeypatch):
    monkeypatch.setattr(nls, "_refresh_multi_bg", lambda key, clean: None)
    monkeypatch.setattr(nls, "_fetch_google_raw", lambda q: [{
        "title": "aynı başlık", "description": "", "url": "",
        "published_at": "2026-09-02T00:00:00",
        "sentiment_label": "Nötr", "sentiment_score": 0.0,
        "affected_assets": [],
    }])
    out = nls._collect_raw_for_symbols(["en|A", "en|B", "tr|C"])
    assert len(out) == 1
