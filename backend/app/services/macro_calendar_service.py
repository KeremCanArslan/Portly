"""Makro ekonomik takvim — bugünün ve yaklaşan önemli olayları.

Production'da economic calendar API (Trading Economics, Investing.com) entegrasyonu
yapılır. Bu MVP versiyonunda LLM ile o anki tarihe uygun olaylar üretiyoruz —
gerçek piyasa verilerine dayalı genel takvim bilgisi (US CPI, FED toplantı, TCMB
PPK, vb.) modelden çıkıyor.
"""

import json
from datetime import datetime, timedelta
from loguru import logger
from app.services import llm_service

_cache: dict[str, tuple[list, datetime]] = {}
_CACHE_TTL_HOURS = 6


def _build_prompt(today: datetime) -> str:
    return f"""Bugünün tarihi: {today.strftime('%d %B %Y, %A')}. Önümüzdeki 7 gün içindeki önemli ekonomik takvim olaylarını listele.

ÇIKTI: Yalnızca geçerli JSON, başka metin yok. 5-7 olay döndür.

{{
  "events": [
    {{
      "date": "YYYY-MM-DD",
      "time": "14:30",
      "title": "ABD TÜFE (Yıllık)",
      "country": "USA",
      "importance": "high" | "medium" | "low",
      "impact": "S&P 500, USD/TRY, altın üzerinde dalgalanma yaratabilir"
    }}
  ]
}}

Tipik olaylar: FED faiz kararı, TCMB PPK, ABD TÜFE/ÜFE, Tarım Dışı İstihdam, Türkiye TÜFE, Almanya IFO, Çin imalat PMI."""


def get_upcoming_events(force_refresh: bool = False) -> list[dict]:
    now = datetime.now()
    cache_key = now.strftime("%Y-%m-%d")
    if not force_refresh and cache_key in _cache:
        data, ts = _cache[cache_key]
        if now - ts < timedelta(hours=_CACHE_TTL_HOURS):
            return data

    if not llm_service.available:
        return _fallback_events(now)

    try:
        raw = llm_service.complete(
            [
                {"role": "system", "content": "Finansal ekonomik takvim uzmanı. Yalnızca geçerli JSON dön."},
                {"role": "user", "content": _build_prompt(now)},
            ],
            temperature=0.3,
            max_tokens=600,
            json_mode=True,
            model=llm_service.MODEL_LITE,
        )
        parsed = json.loads(raw)
        events = parsed.get("events", [])
        _cache[cache_key] = (events, now)
        return events
    except Exception as exc:
        logger.warning(f"Macro calendar LLM hata: {exc}")
        return _fallback_events(now)


def _fallback_events(now: datetime) -> list[dict]:
    """LLM kullanılamazsa generic örnek olaylar."""
    return [
        {
            "date": (now + timedelta(days=1)).strftime("%Y-%m-%d"),
            "time": "15:30",
            "title": "ABD Haftalık İşsizlik Başvuruları",
            "country": "USA",
            "importance": "medium",
            "impact": "S&P 500 ve USD üzerinde kısa vadeli oynaklık",
        },
        {
            "date": (now + timedelta(days=3)).strftime("%Y-%m-%d"),
            "time": "10:00",
            "title": "TCMB Aylık Fiyat Gelişmeleri",
            "country": "TUR",
            "importance": "high",
            "impact": "BIST ve TL üzerinde belirleyici",
        },
    ]
