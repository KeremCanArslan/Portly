"""Toplu (Portföyüm/İzleme) haber: çok sorguyu SUNUCUDA paralel çek + TEK batch
LLM enrich. Eski yol istemcide sembol-başına ayrı çağrıydı → N HTTP + N LLM.

Sözleşme: her sorgu için ham çekim 1 kez; enrich TÜM havuz için TEK kez; örtüşen
başlıklar tekilleşir; en yeni önce; aynı sorgu-kümesi (sıra fark etmez) cache'lenir.
Ağ + LLM mock'lu (ağ ÇAĞRILMAZ).

Çalıştırma:  cd backend && python -m pytest tests/test_news_aggregate.py -q
"""

from datetime import datetime, timedelta, timezone

from app.services import nlp_sentiment_service as ns


def _item(title: str, day: int) -> dict:
    """`day` yalnız SIRALAMA için: büyük gün = daha yeni.

    Tarihler artık MUTLAK değil, bugüne göreli. Sebep: haber toplama yolunda
    tazelik filtresi var (_MAX_NEWS_AGE_DAYS) — sabit 2026-06 tarihleri zamanla
    pencerenin dışına düşüp bu testleri sahte biçimde kırıyordu. Buradaki konu
    tazelik değil, birleştirme/sıralama/cache davranışı."""
    return {
        "title": title,
        "description": "",
        "url": f"https://x/{title}",
        "published_at": datetime.now(timezone.utc) - timedelta(days=20 - day),
        "sentiment_label": "Nötr",
        "sentiment_score": 0.0,
        "affected_assets": [],
    }


def test_first_load_returns_raw_without_blocking_enrich(monkeypatch):
    """İlk açılış: ham sonucu HEMEN döner (LLM enrich'i BEKLEMEZ → hızlı).
    Dedupe + en-yeni-önce korunur. Enrich arka planda (burada devre dışı)."""
    ns._multi_cache.clear()
    ns._multi_refreshing.clear()
    calls = {"raw": 0, "enrich": 0}

    def fake_raw(q):
        calls["raw"] += 1
        # iki sorgu da ortak başlığı + kendi özel başlığını döndürsün
        return [_item("Ortak haber", 17), _item(f"{q} özel", 16)]

    def fake_enrich(items, subject):
        calls["enrich"] += 1
        return items

    monkeypatch.setattr(ns, "_fetch_google_raw", fake_raw)
    monkeypatch.setattr(ns, "_llm_enrich", fake_enrich)
    # arka plan enrich thread'ini devre dışı bırak → deterministik senkron test
    monkeypatch.setattr(ns, "_refresh_multi_bg", lambda *a, **k: None)

    res = ns.get_news_for_symbols(["THYAO", "AKBNK"])

    assert calls["raw"] == 2       # her sorgu için ham çekim
    assert calls["enrich"] == 0    # ilk açılış enrich'i BEKLEMEZ (arka planda)
    titles = [n["title"] for n in res]
    assert titles.count("Ortak haber") == 1          # dedupe
    assert "THYAO özel" in titles and "AKBNK özel" in titles
    assert titles[0] == "Ortak haber"                # en yeni (17) önce


def test_background_build_single_batch_enrich(monkeypatch):
    """Arka plan tam-build: ham çek + TEK batch enrich (sorgu başına değil)."""
    calls = {"raw": 0, "enrich": 0}

    def fake_raw(q):
        calls["raw"] += 1
        return [_item("Ortak haber", 17), _item(f"{q} özel", 16)]

    def fake_enrich(items, subject):
        calls["enrich"] += 1
        return items

    monkeypatch.setattr(ns, "_fetch_google_raw", fake_raw)
    monkeypatch.setattr(ns, "_llm_enrich", fake_enrich)

    res = ns._build_news_for_symbols(["THYAO", "AKBNK"])

    assert calls["raw"] == 2
    assert calls["enrich"] == 1                       # TEK batch
    titles = [n["title"] for n in res]
    assert titles.count("Ortak haber") == 1
    assert titles[0] == "Ortak haber"


def test_aggregate_empty_queries(monkeypatch):
    ns._multi_cache.clear()
    monkeypatch.setattr(ns, "_fetch_google_raw", lambda q: [])
    monkeypatch.setattr(ns, "_llm_enrich", lambda items, s: items)
    assert ns.get_news_for_symbols([]) == []
    assert ns.get_news_for_symbols(["  ", ""]) == []


def test_aggregate_caches_by_query_set(monkeypatch):
    ns._multi_cache.clear()
    ns._multi_refreshing.clear()
    calls = {"raw": 0}

    def fake_raw(q):
        calls["raw"] += 1
        return [_item("H", 17)]

    monkeypatch.setattr(ns, "_fetch_google_raw", fake_raw)
    monkeypatch.setattr(ns, "_llm_enrich", lambda items, s: items)
    # arka plan thread'ini kapat → ham çekim sayımı deterministik kalsın
    monkeypatch.setattr(ns, "_refresh_multi_bg", lambda *a, **k: None)

    ns.get_news_for_symbols(["THYAO", "AKBNK"])
    after_first = calls["raw"]
    # aynı küme, sıra farklı → cache hit, ağ tekrar çekilmez
    ns.get_news_for_symbols(["AKBNK", "THYAO"])
    assert calls["raw"] == after_first
