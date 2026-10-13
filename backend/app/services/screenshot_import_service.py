"""Portföy ekran görüntüsü → yapılandırılmış pozisyonlar (Gemini vision OCR).

Akış: görsel → Gemini 2.5 Flash vision JSON çıkarımı → her okunan ad/sembol
`market_data_service.search_symbols` ile kanonik sembole eşlenir (THYAO→THYAO.IS,
Apple→AAPL). Sonuç frontend'de TOPLU EDİTÖRE dökülür; kullanıcı onaylar/düzeltir,
hiçbir şey otomatik kaydedilmez (OCR yanılabilir).
"""

import hashlib
import json
from datetime import datetime, timedelta
from io import BytesIO

from loguru import logger
from PIL import Image, UnidentifiedImageError

from app.services import llm_service, market_data_service

# Görsel-içerik hash'iyle OCR sonucu cache'i: aynı screenshot tekrar yüklenince
# LLM'e GİTMEZ (flash/lite günlük free kotası kıt — [[project_llm_provider_arch]]).
# Anahtar = sha256(bytes); içerik değişmedikçe sonuç aynı → uzunca TTL güvenli.
_cache: dict[str, tuple[dict, datetime]] = {}
_CACHE_TTL_MINUTES = 30

# Pillow format adı → kabul edilen görsel tipleri (content_type'tan BAĞIMSIZ;
# asıl kanıt baytların gerçekten decode olması).
_PIL_ALLOWED_FORMATS = {"PNG", "JPEG", "WEBP"}


def verify_image(image_bytes: bytes) -> str:
    """Baytları GERÇEKTEN decode ederek görsel olduğunu doğrular.

    content_type başlığı client'tan gelir ve sahtelenebilir → güvenlik kararını
    baytlara dayandırırız. Geçerliyse Pillow'un format adını ("PNG"/"JPEG"/
    "WEBP") döner; aksi halde kullanıcıya gösterilebilir bir ValueError fırlatır.
    Decompression-bomb'a karşı Pillow'un MAX_IMAGE_PIXELS koruması devrede
    (aşırı pikselli görsel DecompressionBombError verir).
    """
    try:
        with Image.open(BytesIO(image_bytes)) as img:
            fmt = (img.format or "").upper()
            img.verify()  # yapısal bütünlük; bozuk/eksik dosyada patlar
    except Image.DecompressionBombError as exc:
        raise ValueError("Görsel çözünürlüğü çok yüksek") from exc
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError) as exc:
        raise ValueError("Geçerli bir görsel dosyası değil") from exc
    if fmt not in _PIL_ALLOWED_FORMATS:
        raise ValueError("Yalnızca PNG/JPEG/WebP desteklenir")
    return fmt

_PROMPT = """Bu bir yatırım/borsa portföy ekran görüntüsü (Midas, aracı kurum app'i vb.).
Görseldeki TÜM açık pozisyonları oku.

Yalnızca şu formatta GEÇERLİ JSON döndür, başka hiçbir şey yazma:
{"positions":[{"name":"<görünen hisse sembolü veya şirket adı>","quantity":<sahip olunan lot/adet sayısı>,"avg_cost":<ortalama birim maliyet/alış fiyatı>}]}

Kurallar:
- Sayılarda binlik ayracı (nokta/virgül) ve ondalık virgülü olabilir; avg_cost ve quantity'yi sade ondalık sayıya çevir (ondalık ayraç NOKTA olsun). Örn "1.297,50" → 1297.50
- avg_cost = ortalama maliyet / alış fiyatı (güncel/piyasa fiyatı DEĞİL). Ekranda "maliyet", "ort.", "alış" gibi etiketli sütunu seç.
- Toplam değer, kâr/zarar, yüzde gibi alanları YOK SAY.
- Bir alan okunamıyorsa o pozisyonu yine ekle ama bilinmeyen sayıyı 0 yap.
- Hiç pozisyon yoksa {"positions":[]} döndür."""


def _num(v) -> float:
    if isinstance(v, (int, float)):
        return float(v)
    if not v:
        return 0.0
    s = str(v).strip().replace(" ", "")
    # "1.297,50" → "1297.50" ; "297,75" → "297.75"
    if "," in s and "." in s:
        s = s.replace(".", "").replace(",", ".")
    elif "," in s:
        s = s.replace(",", ".")
    try:
        return float("".join(ch for ch in s if ch.isdigit() or ch == "."))
    except ValueError:
        return 0.0


def _resolve(name: str):
    """Okunan ad/sembolü kanonik sembole eşler. (symbol, display_name, matched)."""
    try:
        res = market_data_service.search_symbols(name, limit=1)
    except Exception as e:
        logger.warning(f"Sembol arama hatası ({name}): {e}")
        res = []
    if res:
        return res[0]["symbol"], res[0].get("name", name), True
    return "", name, False


def parse_screenshot(image_bytes: bytes, mime_type: str) -> dict:
    key = hashlib.sha256(image_bytes).hexdigest()
    now = datetime.now()
    hit = _cache.get(key)
    if hit and now - hit[1] < timedelta(minutes=_CACHE_TTL_MINUTES):
        logger.info("Screenshot OCR cache HIT (LLM atlandı)")
        return hit[0]

    raw = llm_service.complete_vision(
        _PROMPT, image_bytes, mime_type, json_mode=True, max_tokens=1500
    )
    if not raw:
        # AI başarısız (kota/down) — cache'LEME, geçici durum; çağıran ayırt etsin.
        return {"positions": [], "error": "Görsel okunamadı (AI yanıt vermedi)"}
    try:
        data = json.loads(raw)
    except (ValueError, TypeError) as e:
        logger.warning(f"Vision JSON çözümlenemedi: {e} | raw={raw[:200]}")
        return {"positions": [], "error": "Ekran görüntüsü çözümlenemedi"}

    items = data.get("positions", []) if isinstance(data, dict) else []
    out = []
    for it in items:
        if not isinstance(it, dict):
            continue
        name = str(it.get("name", "")).strip()
        if not name:
            continue
        symbol, disp, matched = _resolve(name)
        out.append(
            {
                "symbol": symbol,
                "name": disp,
                "raw_name": name,
                "quantity": _num(it.get("quantity")),
                "avg_cost": _num(it.get("avg_cost")),
                "matched": matched,
            }
        )
    result = {"positions": out, "matched_count": sum(1 for p in out if p["matched"])}
    _cache[key] = (result, now)  # başarılı OCR'ı cache'le (tekrar yüklemede LLM yok)
    return result
