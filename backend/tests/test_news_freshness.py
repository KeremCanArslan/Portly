"""Haber tazelik filtresi — bayat haberi güncel gibi gösterme.

Canlı ölçüm (2 Eyl 2026): portföy haberinin %19'u bir aydan eskiydi
(en eskisi 11 Şubat). Google News RSS dar sorgularda yeni haber
bulamayınca aylar öncesini döndürüyor, sembol başına kota da onlarla
doluyordu → taze haberler dışarıda kalıyordu.
"""
from datetime import datetime, timedelta, timezone

from app.services import nlp_sentiment_service as nlp


def _item(days_ago: float, title: str = "haber"):
    return {"title": title,
            "published_at": datetime.now(timezone.utc) - timedelta(days=days_ago)}


def test_fresh_items_pass():
    assert nlp._is_fresh(_item(0))
    assert nlp._is_fresh(_item(29))


def test_stale_items_dropped():
    assert not nlp._is_fresh(_item(31))
    assert not nlp._is_fresh(_item(203))   # canlıda görülen 11 Şubat vakası


def test_undated_item_is_kept():
    """RSS bazen tarih vermiyor → tarihi çözülemeyeni elemek haber sayısını
    sebepsiz düşürür; şüphede kalanı tut."""
    assert nlp._is_fresh({"title": "x", "published_at": None})


def test_drop_stale_keeps_order_and_fresh_only():
    items = [_item(1, "taze"), _item(120, "bayat"), _item(5, "yeni")]
    out = nlp._drop_stale(items)
    assert [i["title"] for i in out] == ["taze", "yeni"]


def test_naive_datetime_does_not_crash():
    """tz'siz datetime gelirse UTC varsayılır (karşılaştırma patlamasın)."""
    naive = {"title": "x", "published_at": datetime.utcnow() - timedelta(days=1)}
    assert nlp._is_fresh(naive)
