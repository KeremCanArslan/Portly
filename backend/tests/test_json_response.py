"""Global NaN-güvenli JSON yanıtı (SafeJSONResponse) birim testleri.

Sözleşme: NaN/inf → null (JSON), geçerli değerler aynen, TR karakterler korunur
(ensure_ascii=False). Bu, yfinance NaN'ının tek başına bir ucu 500'lemesini
önleyen son savunmadır.
"""

import json

from app.core.json_response import SafeJSONResponse, sanitize_nan


def test_sanitize_nan_recursive():
    out = sanitize_nan({
        "a": float("nan"),
        "b": [1.0, float("inf")],
        "c": {"d": float("-inf")},
        "e": 3.14,
        "f": None,
        "g": True,        # bool int alt-sınıfı → değişmemeli
        "h": "metin",
        "i": 5,
    })
    assert out == {
        "a": None, "b": [1.0, None], "c": {"d": None},
        "e": 3.14, "f": None, "g": True, "h": "metin", "i": 5,
    }


def test_render_converts_nan_to_null():
    body = {"x": float("nan"), "y": 1.5}
    assert json.loads(SafeJSONResponse(body).render(body)) == {"x": None, "y": 1.5}


def test_render_preserves_valid_and_unicode():
    body = {"tr": "şğüöçİı", "n": 42, "f": 3.14, "list": [1, 2, 3], "nested": {"k": "v"}}
    # ensure_ascii=False → Türkçe karakter bozulmadan döner; veri aynı kalır.
    assert json.loads(SafeJSONResponse(body).render(body)) == body
