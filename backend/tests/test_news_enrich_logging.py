"""Haber enrich eleme oranının canlı log'da izlenebilmesi (4 Eylül 2026, 9. tur).

Neden: haber sayısı ikinci açılışta gözle görülür düşüyordu (ölçüm: 90 ham →
63 servis) ama Render log'unda yalnız %50 üstü eleme uyarı basıyordu; altındaki
kayıp ve — daha önemlisi — hangi KATMANIN yediği (deterministik dil kapısı mı,
LLM'in dil kararı mı, alaka kararı mı) görülemiyordu. Ayrıca LLM zinciri komple
düşüp boş yanıt verdiğinde enrich sessizce atlanıyordu (6. turda tüm AI'ın
ölü olduğunun aylarca fark edilmemesinin aynı deseni).

Çalıştırma:  cd backend && python -m pytest tests/test_news_enrich_logging.py -q
"""

import json
import logging
from contextlib import contextmanager

from app.services import nlp_sentiment_service as nls


@contextmanager
def _captured_logs(caplog):
    """(seviye, mesaj) çiftleri — bu modül stdlib logging kullanıyor."""
    records: list[tuple[str, str]] = []
    with caplog.at_level(logging.DEBUG, logger=nls.__name__):
        caplog.clear()
        yield records
        records.extend((r.levelname, r.getMessage()) for r in caplog.records)


def _items(titles: list[str]) -> list[dict]:
    return [{
        "title": t,
        "description": "",
        "url": "",
        "published_at": "2026-09-04T00:00:00",
        "sentiment_label": "Nötr",
        "sentiment_score": 0.0,
        "affected_assets": [],
    } for t in titles]


def _verdicts(**by_index) -> str:
    return json.dumps({"items": [
        {"i": i, "lang": v[0], "relevant": v[1], "score": 0.1}
        for i, v in sorted((int(k[1:]), v) for k, v in by_index.items())]})


def test_enrich_logs_layer_breakdown(monkeypatch, caplog):
    """Tek satırda: kaç ham geldi, kaç kaldı, hangi katman kaç tane eledi."""
    # 4 başlık: biri Kiril (dil kapısı), biri LLM'e göre Almanca, biri alakasız.
    items = _items(["Apple bilanço", "Новости рынка", "Messe Termin", "Reklam kampanyası"])
    monkeypatch.setattr(nls, "complete", lambda messages, **kw: _verdicts(
        i0=("en", True), i1=("de", True), i2=("tr", False)))

    with _captured_logs(caplog) as records:
        out = nls._llm_enrich(items, "portföy")

    assert len(out) == 1, "yalnız alakalı TR/EN haber kalmalı"
    line = next(m for lvl, m in records if m.startswith("Haber enrich [portföy]"))
    assert "4 ham -> 1 kaldi" in line
    assert "dil kapisi 1" in line, "Kiril başlık deterministik kapıda elenmeli"
    assert "LLM dil 1" in line
    assert "alaka 1" in line


def test_heavy_drop_escalates_to_warning(monkeypatch, caplog):
    """%50 ve üstü eleme WARNING olmalı — filtre fazla agresif olabilir."""
    items = _items([f"Haber {i}" for i in range(4)])
    monkeypatch.setattr(nls, "complete", lambda messages, **kw: _verdicts(
        i0=("en", True), i1=("tr", False), i2=("tr", False), i3=("tr", False)))

    with _captured_logs(caplog) as records:
        nls._llm_enrich(items, "portföy")

    levels = [lvl for lvl, m in records if m.startswith("Haber enrich")]
    assert "WARNING" in levels


def test_empty_llm_response_is_not_silent(monkeypatch, caplog):
    """LLM zinciri düşüp BOŞ dönerse enrich sessizce atlanmasın (kota/404)."""
    monkeypatch.setattr(nls, "complete", lambda messages, **kw: "")

    with _captured_logs(caplog) as records:
        out = nls._llm_enrich(_items(["Apple bilanço", "Ford satış"]), "portföy")

    assert len(out) == 2, "LLM yoksa dil kapısını geçenler korunur"
    assert any(lvl == "WARNING" and "BOŞ yanıt" in m for lvl, m in records)


def test_pipeline_summary_counts_restore(monkeypatch, caplog):
    """Uçtan uca satır: ham → enrich → susturulan sembol telafisi → servis."""
    raw = _items(["AAPL bilanço", "THYAO reklam"])
    raw[0]["matched_query"] = "AAPL"
    raw[1]["matched_query"] = "THYAO"
    monkeypatch.setattr(nls, "_collect_raw_for_symbols", lambda clean: raw)
    # Enrich THYAO'yu tamamen eliyor → telafi devreye girmeli.
    monkeypatch.setattr(nls, "_llm_enrich", lambda items, query: [items[0]])

    with _captured_logs(caplog) as records:
        out = nls._build_news_for_symbols(["AAPL", "THYAO"])

    assert len(out) == 2, "susturulan sembolün en yeni haberi geri gelmeli"
    line = next(m for lvl, m in records if m.startswith("Haber hatti"))
    assert "2 ham -> enrich 1" in line
    assert "telafi +1" in line
    assert "servis 2" in line
