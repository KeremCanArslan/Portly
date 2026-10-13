"""Gemini model dayanıklılığı (4 Eylül 2026, 6. tur).

Ölçülen canlı arıza: `gemini-2.5-flash` ve `gemini-2.5-flash-lite` bir gün
404 "This model is no longer available to new users" demeye başladı. Kodda
sabitlenmiş İKİ model de aynı anda öldüğü için sohbet · haber enrich · piyasa
etkisi · temel analiz · makro takvim hep birden sustu; Groq yedeği de erişimsizdi.
İkinci tuzak: yeni Flash modelleri `thinking_budget=0`'ı **400 INVALID_ARGUMENT**
ile reddediyor — model adı düzeltilse bile istek kurulamıyordu.

Sabitlenen sözleşme:
 1. Model adları SÜRÜM değil TAKMA AD (`-latest`) → sürüm kalkınca kendiliğinden
    bir sonrakine geçer.
 2. Alternatif modele düşme yalnız kotada (429) değil; model yok (404) ve
    yoğunluk (503) da düşürür.
 3. Düşünme ayarı reddedilirse (400) çağrı ayarsız BİR KEZ tekrarlanır.

Çalıştırma:  cd backend && python -m pytest tests/test_llm_model_resilience.py -q
"""

import pytest

from app.services import llm_service as llm


class _Err(Exception):
    """google-genai ClientError'ın testte taklidi (code/status taşır)."""

    def __init__(self, message, code=None, status=None):
        super().__init__(message)
        self.code = code
        self.status = status


# ───────────────────────────── model adları

def test_model_adlari_takma_ad_kullanir():
    # Sabit sürüm ("gemini-2.5-flash") kalkınca TÜM AI birden ölüyordu.
    for name in (llm.MODEL_FLASH, llm.MODEL_LITE):
        assert name.endswith("-latest"), name


def test_flash_ve_lite_farkli_modeller():
    # Aynı olurlarsa cross-model fallback sahte bir güvenlik ağına dönerdi.
    assert llm.MODEL_FLASH != llm.MODEL_LITE
    assert llm._alt_model(llm.MODEL_FLASH) == llm.MODEL_LITE
    assert llm._alt_model(llm.MODEL_LITE) == llm.MODEL_FLASH


# ───────────────────────────── hata sınıflandırması

@pytest.mark.parametrize("exc", [
    _Err("429 RESOURCE_EXHAUSTED", code=429),
    _Err("RESOURCE_EXHAUSTED: quota"),
])
def test_kota_hatasi_alternatif_modele_dusurur(exc):
    assert "429" in llm._should_try_alt_model(exc)


@pytest.mark.parametrize("exc", [
    _Err("404 NOT_FOUND", code=404),
    _Err("This model models/gemini-2.5-flash is no longer available to new users"),
])
def test_model_yoksa_alternatif_modele_dusurur(exc):
    assert llm._is_model_gone(exc)
    assert "404" in llm._should_try_alt_model(exc)


@pytest.mark.parametrize("exc", [
    _Err("503 UNAVAILABLE", code=503),
    _Err("This model is currently experiencing high demand"),
])
def test_yogunluk_alternatif_modele_dusurur(exc):
    assert "503" in llm._should_try_alt_model(exc)


def test_alakasiz_hata_model_degistirmez():
    # Prompt/ağ hatasında model değiştirmek arızayı gizler, çözmez.
    assert llm._should_try_alt_model(_Err("PERMISSION_DENIED", code=403)) is None
    assert llm._should_try_alt_model(_Err("bağlantı koptu")) is None


def test_gecersiz_argüman_tespiti():
    assert llm._is_invalid_argument(_Err("400 INVALID_ARGUMENT", code=400))
    assert llm._is_invalid_argument(_Err("Request contains an invalid argument. INVALID_ARGUMENT"))
    assert not llm._is_invalid_argument(_Err("429 RESOURCE_EXHAUSTED", code=429))


# ───────────────────────────── düşünme ayarı

def test_dusunme_ayari_sifir_butce_kullanmaz():
    # thinking_budget=0 güncel Flash modellerinde 400 veriyor → thinking_level.
    cfg = llm._thinking_config()
    assert getattr(cfg, "thinking_budget", None) is None
    assert getattr(cfg, "thinking_level", None)


# ───────────────────────────── _gemini_generate davranışı

class _FakeModels:
    def __init__(self, plan):
        self.plan = plan          # [(model, thinking_var_mi) -> sonuç|hata]
        self.calls = []

    def generate_content(self, *, model, contents, config):
        thinking = getattr(config, "thinking_config", None) is not None
        self.calls.append((model, thinking))
        out = self.plan[(model, thinking)]
        if isinstance(out, Exception):
            raise out
        return type("R", (), {"text": out})()


class _FakeGemini:
    def __init__(self, plan):
        self.models = _FakeModels(plan)


def _cfg(thinking=True):
    from google.genai import types
    return types.GenerateContentConfig(
        temperature=0,
        max_output_tokens=64,
        thinking_config=llm._thinking_config() if thinking else None,
    )


def test_404_alan_model_alternatife_duser(monkeypatch):
    fake = _FakeGemini({
        (llm.MODEL_FLASH, True): _Err("404 NOT_FOUND", code=404),
        (llm.MODEL_LITE, True): "ikinci model cevapladı",
    })
    monkeypatch.setattr(llm, "_gemini", fake)
    out = llm._gemini_generate(llm.MODEL_FLASH, [], _cfg())
    assert out == "ikinci model cevapladı"
    assert fake.models.calls == [(llm.MODEL_FLASH, True), (llm.MODEL_LITE, True)]


def test_dusunme_ayari_reddedilirse_ayarsiz_tekrarlanir(monkeypatch):
    fake = _FakeGemini({
        (llm.MODEL_LITE, True): _Err("400 INVALID_ARGUMENT", code=400),
        (llm.MODEL_LITE, False): "ayarsız çalıştı",
    })
    monkeypatch.setattr(llm, "_gemini", fake)
    out = llm._gemini_generate(llm.MODEL_LITE, [], _cfg())
    assert out == "ayarsız çalıştı"
    # AYNI model, düşünme ayarı düşürülerek — model DEĞİŞTİRİLMEDİ.
    assert fake.models.calls == [(llm.MODEL_LITE, True), (llm.MODEL_LITE, False)]


def test_alakasiz_hata_yukselir(monkeypatch):
    fake = _FakeGemini({(llm.MODEL_LITE, True): _Err("PERMISSION_DENIED", code=403)})
    monkeypatch.setattr(llm, "_gemini", fake)
    with pytest.raises(_Err):
        llm._gemini_generate(llm.MODEL_LITE, [], _cfg())
    assert len(fake.models.calls) == 1
