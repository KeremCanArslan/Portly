"""NaN/inf'e karşı güvenli global JSON yanıtı.

Starlette'in varsayılan `JSONResponse`'u gövdeyi `allow_nan=False` ile render
eder → yanıtta NaN/inf görürse `ValueError: Out of range float values are not
JSON compliant` fırlatır → HTTP 500. yfinance sık sık NaN döndürür (yarım/eksik
bar, boş finansal alan); TEK bir NaN bütün ucu çökertir — bu projede tekrar eden
bir sınıf (fear-greed, grafik geçmişi, vb.).

Bu yanıt sınıfı render'dan ÖNCE içeriği derinlemesine gezip NaN/inf'i `None`'a
(JSON `null`) indirir → uç ASLA NaN yüzünden 500 atmaz. `null` Dart/Flutter
tarafında zaten güvenli (alanlar nullable). `allow_nan=False` bilinçli korunur:
sanitize sonrası (teorik) non-finite kalırsa sessizce geçersiz JSON üretmek
yerine hata versin.

Not: Bu son savunmadır. Veri-doğruluğu (ör. grafikte NaN satırı atlamak) yine
kaynakta yapılır; bu sınıf yalnız "hiçbir uç çökmesin" garantisidir.
"""

import json
import math
from typing import Any

from starlette.responses import JSONResponse


def sanitize_nan(value: Any) -> Any:
    """NaN/inf'i None'a indirip dict/list'i derinlemesine temizler."""
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if isinstance(value, dict):
        return {k: sanitize_nan(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [sanitize_nan(v) for v in value]
    return value


class SafeJSONResponse(JSONResponse):
    """Starlette JSONResponse + render öncesi NaN/inf → null sanitizasyonu."""

    def render(self, content: Any) -> bytes:
        return json.dumps(
            sanitize_nan(content),
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
        ).encode("utf-8")
