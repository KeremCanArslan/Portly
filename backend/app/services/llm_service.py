"""Birleşik LLM katmanı — tüm AI servislerinin tek kapısı.

Birincil: Google Gemini Flash (`gemini-flash-latest` takma adı; `thinking` kapalı
→ hızlı + token tasarrufu). `grounding=True` ile Google Search'e bağlanıp GÜNCEL
bilgi çekebilir (Groq'ta olmayan şey).

Yedek: Groq Llama 3.3 70B. Gemini rate-limit (429) / hata / boş yanıt verirse
otomatik buna düşülür → free-tier limit sorunu için güvenlik ağı.

Mesaj formatı OpenAI-stili `[{role, content}]`; Gemini'ye uygun hâle burada
çevrilir, böylece çağıran servisler sağlayıcıyı hiç bilmez.
"""

from collections.abc import Iterator

from loguru import logger

from app.core.config import settings

# Premium (chat grounding + vision OCR) vs hafif (yüksek hacimli JSON analiz).
# İkisi AYRI free kotaya sahip → yükü bölmek chat'in flash bütçesini boşaltır
# ve toplam tavanı yükseltir. [[project_llm_provider_arch]]
#
# ⚠️ SÜRÜM DEĞİL TAKMA AD kullan (4 Eyl 2026 dersi): sabitlenmiş
# `gemini-2.5-flash` ve `gemini-2.5-flash-lite` bir gün "no longer available to
# new users" (404) demeye başladı ve TÜM AI özellikleri (sohbet · haber enrich ·
# piyasa etkisi · temel analiz · makro takvim) aynı anda sessizce düştü — Groq
# yedeği de erişimsizdi. `-latest` takma adları model kullanımdan kalkınca
# kendiliğinden bir sonraki sürüme geçer, yani bu arıza tekrar etmez.
MODEL_FLASH = "gemini-flash-latest"
MODEL_LITE = "gemini-flash-lite-latest"
_GEMINI_MODEL = MODEL_FLASH  # varsayılan (chat/stream/vision)
# Groq yedeği — SIRALI adaylar. Canlıda (3 Eyl 2026) `llama-3.3-70b-versatile`
# 404 "does not exist or you do not have access to it" döndü: model Groq'un
# üretim listesinde duruyor ama HESABIN erişimi yok. Gemini o sırada 429/503
# olduğu için TÜM AI özellikleri (sohbet, haber analizi, makro takvim) birden
# düştü — tek modele bağlı olmak tek nokta arızasıydı.
# Sıra: env > 70B > gpt-oss > 8B (en dar erişimden en yaygına).
# Erişilemeyen model işaretlenip bir daha DENENMEZ (süreç ömrü boyunca).
_GROQ_MODELS = [m for m in (
    settings.GROQ_MODEL,
    "llama-3.3-70b-versatile",
    "openai/gpt-oss-120b",
    "openai/gpt-oss-20b",
    "llama-3.1-8b-instant",
) if m]
_groq_dead: set[str] = set()


def _groq_candidates() -> list[str]:
    """Denenecek Groq modelleri (ölü işaretlenenler hariç, sıra korunur)."""
    seen: set[str] = set()
    out = []
    for m in _GROQ_MODELS:
        if m in seen or m in _groq_dead:
            continue
        seen.add(m)
        out.append(m)
    return out


def _is_model_missing(e: Exception) -> bool:
    """Groq "model_not_found" / 404 — model yok ya da hesabın erişimi yok."""
    txt = str(e).lower()
    return "model_not_found" in txt or "does not exist" in txt

# ── Client'lar (anahtar yoksa None; o sağlayıcı atlanır) ──────────────────
try:
    from groq import Groq

    _groq = Groq(api_key=settings.GROQ_API_KEY) if settings.GROQ_API_KEY else None
except Exception as e:  # pragma: no cover
    logger.warning(f"Groq init edilemedi: {e}")
    _groq = None

try:
    from google import genai
    from google.genai import types

    _gemini = (
        genai.Client(api_key=settings.GEMINI_API_KEY)
        if settings.GEMINI_API_KEY
        else None
    )
except Exception as e:  # pragma: no cover
    logger.warning(f"Gemini init edilemedi: {e}")
    _gemini = None

# En az bir sağlayıcı varsa AI kullanılabilir (servisler bu bayrakla guard yapar).
available = (_gemini is not None) or (_groq is not None)


def _thinking_config():
    """Düşünmeyi en aza indir: yanıt tokenı düşünmeye gitmesin, gecikme artmasın.

    ⚠️ `thinking_budget=0` KULLANMA (4 Eyl 2026): güncel Gemini Flash modelleri
    sıfır bütçeyi **400 INVALID_ARGUMENT** ile reddediyor — istek hiç kurulmuyor,
    dolayısıyla model adı doğru olsa bile tüm AI çağrıları düşerdi. Yeni API
    karşılığı `thinking_level`; kabul edilmezse `_gemini_generate` çağrıyı
    düşünme ayarı OLMADAN bir kez daha dener (AI ayakta kalsın)."""
    return types.ThinkingConfig(thinking_level="low")


def _alt_model(model: str) -> str:
    """flash ↔ lite. İki modelin de free kotası ayrı; biri dolunca öbürü kullanılır."""
    return MODEL_LITE if model == MODEL_FLASH else MODEL_FLASH


def _is_quota_error(e: Exception) -> bool:
    """429 / RESOURCE_EXHAUSTED (günlük free-tier kota) tespiti."""
    if getattr(e, "code", None) == 429 or getattr(e, "status", None) == "RESOURCE_EXHAUSTED":
        return True
    s = str(e)
    return "RESOURCE_EXHAUSTED" in s or "429" in s


def _is_model_gone(e: Exception) -> bool:
    """404 / NOT_FOUND — model kullanımdan kalktı ya da hesap erişemiyor.
    Kotadan farkı: KENDİ KENDİNE düzelmez, kod (model adı) değişmeli."""
    if getattr(e, "code", None) == 404 or getattr(e, "status", None) == "NOT_FOUND":
        return True
    s = str(e)
    return "NOT_FOUND" in s or "no longer available" in s


def _is_overloaded(e: Exception) -> bool:
    """503 / UNAVAILABLE — modelde anlık yoğunluk (geçici)."""
    if getattr(e, "code", None) == 503 or getattr(e, "status", None) == "UNAVAILABLE":
        return True
    s = str(e)
    return "UNAVAILABLE" in s or "503" in s or "high demand" in s


def _is_invalid_argument(e: Exception) -> bool:
    """400 / INVALID_ARGUMENT — istek gövdesinde modelin kabul etmediği alan."""
    if getattr(e, "code", None) == 400 or getattr(e, "status", None) == "INVALID_ARGUMENT":
        return True
    return "INVALID_ARGUMENT" in str(e)


def _should_try_alt_model(e: Exception) -> str | None:
    """Diğer Gemini modeline düşmeye değer mi? Değerse sebebi döner.
    Üç durum da tek modele bağlı kalmayı anlamsız kılar: kota dolu (429),
    model yok (404), model yoğun (503). Eskiden yalnız 429 düşüyordu; 3 Eylül
    canlı arızası 503 + 404 ile geldi ve zincir hiç denenmeden Groq'a düştü."""
    if _is_quota_error(e):
        return "kotası doldu (429)"
    if _is_model_gone(e):
        return "yok/erişilemiyor (404)"
    if _is_overloaded(e):
        return "yoğun (503)"
    return None


def _gemini_generate(model: str, contents, config) -> str:
    """Gemini çağrısı; model kota/yokluk/yoğunluk verirse diğer modele BİR kez
    düşer. İkisi de düşerse hata yükselir (çağıran Groq'a/boşa düşürür)."""
    try:
        resp = _gemini.models.generate_content(
            model=model, contents=contents, config=config
        )
        return (resp.text or "").strip()
    except Exception as e:
        if _is_invalid_argument(e) and getattr(config, "thinking_config", None):
            # Model bu düşünme ayarını tanımıyor (alan adı/kabul edilen değerler
            # sürümle değişiyor) → ayarı düşürüp bir kez daha dene. AI'yı bir
            # config alanı yüzünden komple kaybetmek en kötü sonuç olurdu.
            logger.warning(
                f"{model} düşünme ayarını reddetti (400) → ayarsız tekrar deneniyor")
            resp = _gemini.models.generate_content(
                model=model, contents=contents,
                config=config.model_copy(update={"thinking_config": None}),
            )
            return (resp.text or "").strip()
        sebep = _should_try_alt_model(e)
        if not sebep:
            raise
        if _is_model_gone(e):
            # Kotadan farklı: beklemekle geçmez, model adı güncellenmeli.
            logger.error(
                f"Gemini modeli {model} {sebep} — model adı güncellenmeli "
                "(takma ad kullanılmıyorsa sürüm kalkmış olabilir)")
        alt = _alt_model(model)
        logger.warning(f"{model} {sebep} → {alt}'a düşülüyor")
        resp = _gemini.models.generate_content(
            model=alt, contents=contents, config=config
        )
        return (resp.text or "").strip()


def _split_messages(messages: list[dict]):
    """OpenAI-stili mesajları (system_instruction, gemini_contents) ikilisine böler."""
    system_parts: list[str] = []
    contents: list[dict] = []
    for m in messages:
        role = m.get("role")
        content = m.get("content", "") or ""
        if role == "system":
            system_parts.append(content)
        else:
            g_role = "model" if role == "assistant" else "user"
            contents.append({"role": g_role, "parts": [{"text": content}]})
    return "\n\n".join(system_parts).strip(), contents


def _gemini_config(
    system: str,
    temperature: float,
    max_tokens: int,
    grounding: bool,
    json_mode: bool,
):
    # Gemini'de JSON modu (response_mime_type) ile araç (grounding) BİRLİKTE
    # kullanılamaz; çağıran ikisini birden istemez ama güvenlik için JSON öncelikli.
    tools = (
        [types.Tool(google_search=types.GoogleSearch())]
        if grounding and not json_mode
        else None
    )
    return types.GenerateContentConfig(
        system_instruction=system or None,
        temperature=temperature,
        max_output_tokens=max_tokens,
        tools=tools,
        response_mime_type="application/json" if json_mode else None,
        # "Düşünme" tokenı: en aza indirilir, yoksa yanıt bütçesini yer.
        thinking_config=_thinking_config(),
    )


def complete(
    messages: list[dict],
    *,
    temperature: float = 0.4,
    max_tokens: int = 800,
    grounding: bool = False,
    json_mode: bool = False,
    model: str | None = None,
) -> str:
    """Tek-seferlik yanıt. Gemini birincil, hata/boşta Groq'a düşer.

    json_mode=True → model yalnız geçerli JSON döndürür (yapısal çıktı isteyen
    analiz servisleri için). model=MODEL_LITE → hafif/cömert-kotalı modele yönlendir."""
    if _gemini is not None:
        try:
            system, contents = _split_messages(messages)
            text = _gemini_generate(
                model or _GEMINI_MODEL,
                contents,
                _gemini_config(
                    system, temperature, max_tokens, grounding, json_mode
                ),
            )
            if text:
                return text
            logger.warning("Gemini boş yanıt → Groq'a düşülüyor")
        except Exception as e:
            logger.warning(f"Gemini hatası ({type(e).__name__}: {e}) → Groq'a düşülüyor")
    return _groq_complete(messages, temperature, max_tokens, json_mode)


def _groq_complete(
    messages: list[dict], temperature: float, max_tokens: int, json_mode: bool
) -> str:
    if _groq is None:
        logger.error("Groq yedeği de yok — boş yanıt")
        return ""
    kwargs = {}
    if json_mode:
        kwargs["response_format"] = {"type": "json_object"}
    last: Exception | None = None
    for model in _groq_candidates():
        try:
            resp = _groq.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                **kwargs,
            )
            return (resp.choices[0].message.content or "").strip()
        except Exception as e:
            last = e
            if not _is_model_missing(e):
                raise
            _groq_dead.add(model)
            logger.warning(
                f"Groq modeli kullanılamıyor ({model}) → sıradaki aday deneniyor")
    logger.error(f"Groq'ta erişilebilir model bulunamadı: {last}")
    return ""


def complete_vision(
    prompt: str,
    image_bytes: bytes,
    mime_type: str,
    *,
    temperature: float = 0.2,
    max_tokens: int = 1200,
    json_mode: bool = True,
    model: str | None = None,
) -> str:
    """Görsel + metin → yanıt. SADECE Gemini (Groq mevcut modeli text-only).
    Screenshot'tan portföy okuma gibi OCR işleri için. Gemini yoksa/hata verirse
    boş döner — çağıran 'okunamadı' diye ele alır.

    Varsayılan MODEL_LITE: flash free-tier günlük 20 istekle sınırlı ve chat onu
    tüketiyor; lite ayrı + cömert kotalı, vision'da da yetkin (OCR için yeterli)."""
    if _gemini is None:
        logger.error("Vision için Gemini yok")
        return ""
    try:
        config = types.GenerateContentConfig(
            temperature=temperature,
            max_output_tokens=max_tokens,
            response_mime_type="application/json" if json_mode else None,
            thinking_config=_thinking_config(),
        )
        return _gemini_generate(
            model or MODEL_LITE,
            [
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                prompt,
            ],
            config,
        )
    except Exception as e:
        logger.warning(f"Gemini vision hatası ({type(e).__name__}: {e})")
        return ""


def stream(
    messages: list[dict],
    *,
    temperature: float = 0.4,
    max_tokens: int = 800,
    grounding: bool = False,
) -> Iterator[str]:
    """Token token üretir. Gemini birincil; ilk token gelmeden hata/boş olursa
    Groq'a düşer. Token akmaya başladıysa yarıda hata olsa bile Groq'a DÜŞMEZ
    (yinelenmesin)."""
    if _gemini is not None:
        system, contents = _split_messages(messages)
        cfg = _gemini_config(system, temperature, max_tokens, grounding, False)
        cfg_plain = cfg.model_copy(update={"thinking_config": None})
        # İlk token gelmeden hata olursa sırayla: aynı model düşünme ayarsız
        # (400 INVALID_ARGUMENT), sonra diğer model (429 kota / 404 model yok /
        # 503 yoğunluk). Eskiden YALNIZ 429 diğer modele geçiyordu → 4 Eylül'de
        # birincil model 404 verince sohbet doğrudan Groq'a (yani boşluğa) düştü.
        for attempt, attempt_cfg in (
            (_GEMINI_MODEL, cfg),
            (_GEMINI_MODEL, cfg_plain),
            (_alt_model(_GEMINI_MODEL), cfg),
        ):
            any_token = False
            try:
                gen = _gemini.models.generate_content_stream(
                    model=attempt, contents=contents, config=attempt_cfg
                )
                for chunk in gen:
                    tok = chunk.text
                    if tok:
                        any_token = True
                        yield tok
                if any_token:
                    return
                logger.warning(f"Gemini stream boş ({attempt}) → Groq'a düşülüyor")
                break
            except Exception as e:
                if any_token:
                    logger.warning(
                        f"Gemini stream hatası ({type(e).__name__}), kısmi yanıt gönderildi — Groq atlanıyor"
                    )
                    return
                if _is_invalid_argument(e) and attempt_cfg is cfg:
                    logger.warning(
                        f"{attempt} düşünme ayarını reddetti (400) → ayarsız stream deneniyor"
                    )
                    continue
                reason = _should_try_alt_model(e)
                if reason and attempt == _GEMINI_MODEL:
                    logger.warning(
                        f"{attempt} {reason} → {_alt_model(_GEMINI_MODEL)} stream deneniyor"
                    )
                    continue
                logger.warning(
                    f"Gemini stream hatası ({type(e).__name__}: {e}) → Groq'a düşülüyor"
                )
                break

    if _groq is None:
        logger.error("Groq yedeği de yok — stream boş")
        return
    gstream = None
    for model in _groq_candidates():
        try:
            gstream = _groq.chat.completions.create(
                model=model,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
                stream=True,
            )
            break
        except Exception as e:
            if not _is_model_missing(e):
                raise
            _groq_dead.add(model)
            logger.warning(
                f"Groq modeli kullanılamıyor ({model}) → sıradaki aday deneniyor")
    if gstream is None:
        logger.error("Groq'ta erişilebilir model bulunamadı — stream boş")
        return
    for chunk in gstream:
        delta = chunk.choices[0].delta
        if delta and delta.content:
            yield delta.content
