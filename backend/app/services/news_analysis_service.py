"""Haber için derin LLM analizi.

Verilen başlık + açıklamaya bakıp:
- Hangi sektörleri etkiler?
- Hangi hisselerde ne yönde hareket beklenir? (yüzde oranlı)
- Kısa, orta, uzun vade için yorum
- Olası ters sinyaller / belirsizlikler
"""

import json
from datetime import datetime, timedelta
from loguru import logger
from app.services import llm_service

_cache: dict[str, tuple[dict, datetime]] = {}
_CACHE_TTL_HOURS = 24


def _cache_key(title: str) -> str:
    # Title'a göre cache — aynı haber tekrar gelirse aynı analiz dönsün
    return title.strip().lower()[:100]


def _build_prompt(title: str, description: str) -> str:
    return f"""Aşağıdaki finans haberini analiz et. Etkilenebilecek varlıkları ve yön/yüzde tahmini ver.

BAŞLIK: {title}
AÇIKLAMA: {description}

ÇIKTI: Yalnızca geçerli JSON, başka metin yok.

{{
  "summary_tr": "1-2 cümle Türkçe özet — neden önemli",
  "affected": [
    {{
      "symbol": "AAPL",
      "name": "Apple",
      "direction": "UP" | "DOWN" | "NEUTRAL",
      "expected_impact_pct": -5'ten +5'e kadar tahmini etki yüzdesi,
      "rationale": "Neden bu etki, 1 kısa cümle"
    }}
  ],
  "sectors": ["teknoloji", "bankacılık", "enerji" gibi etkilenen sektörler],
  "horizons": {{
    "short": "Kısa vade (1-2 hafta) etki yorumu",
    "medium": "Orta vade (1-3 ay) etki yorumu",
    "long": "Uzun vade (6+ ay) etki yorumu"
  }},
  "risks": ["bu analizi geçersiz kılabilecek 1-2 belirsizlik"]
}}

Önemli: Etkilenen varlıklar listesi 2-5 sembol içersin. Sembol formatları: BIST için "THYAO.IS", kripto için "BTC-USD", ABD için "AAPL"."""


def analyze(title: str, description: str = "") -> dict:
    key = _cache_key(title)
    now = datetime.now()
    if key in _cache:
        data, ts = _cache[key]
        if now - ts < timedelta(hours=_CACHE_TTL_HOURS):
            return data

    if not llm_service.available:
        return {"error": "AI sağlayıcı (Gemini/Groq) ayarlı değil"}

    try:
        raw = llm_service.complete(
            [
                {"role": "system", "content": "Finansal haber analisti. Yalnızca geçerli JSON dön."},
                {"role": "user", "content": _build_prompt(title, description)},
            ],
            temperature=0.4,
            # 800 yetersizdi: 2-5 etkilenen sembol (rationale'lı) + 3 vade
            # cümlesi + sektör + risk (Türkçe) çoğu haberde 800'e sığmıyor →
            # yanıt yarıda kesilip JSON bozuluyordu ("Unterminated string").
            # 1500 ile tam JSON sığar (bkz. technical_analysis_service aynı sorun).
            max_tokens=1500,
            json_mode=True,
            model=llm_service.MODEL_LITE,
        )
        parsed = json.loads(raw)
        _cache[key] = (parsed, now)
        return parsed
    except Exception as exc:
        # Ham JSONDecodeError mesajını ("Unterminated string starting at...")
        # kullanıcıya GÖSTERME — kibar Türkçe mesaj dön, gerçeği log'a yaz.
        logger.warning(f"News analysis hata: {exc}")
        return {"error": "AI analizi şu an üretilemedi, lütfen tekrar deneyin."}
