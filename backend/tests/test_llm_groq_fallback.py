"""Groq yedeğinde model aday zinciri.

Bağlam (Render log'u, 3 Eyl 2026 10:58): Gemini 429/503 verince Groq'a
düşülüyordu ama Groq `llama-3.3-70b-versatile` için 404 döndü —
"does not exist or you do not have access to it". Model Groq'un üretim
listesinde duruyor; erişim HESAP tarafında yok. Sonuç: sohbet, haber analizi
ve makro takvim AYNI ANDA çöktü (tek modele bağlılık = tek nokta arıza).

Kural: erişilemeyen model bir kez işaretlenir ve sıradaki aday denenir;
model dışı hatalar (kota, ağ) YUTULMAZ — çağırana gider.
"""

import pytest

from app.services import llm_service as llm


class _Msg:
    def __init__(self, content):
        self.content = content


class _Choice:
    def __init__(self, content):
        self.message = _Msg(content)


class _Resp:
    def __init__(self, content):
        self.choices = [_Choice(content)]


class _FakeGroq:
    """`model_not_found` döndüren modelleri taklit eder."""

    def __init__(self, calisan: str | None):
        self.calisan = calisan
        self.denenen: list[str] = []
        self.chat = self

    @property
    def completions(self):
        return self

    def create(self, model, **kw):
        self.denenen.append(model)
        if model != self.calisan:
            raise RuntimeError(
                "Error code: 404 - {'error': {'message': \"The model "
                f"`{model}` does not exist or you do not have access to it.\", "
                "'code': 'model_not_found'}}")
        return _Resp("cevap")


@pytest.fixture(autouse=True)
def _temiz(monkeypatch):
    monkeypatch.setattr(llm, "_groq_dead", set())
    monkeypatch.setattr(llm, "_GROQ_MODELS", [
        "llama-3.3-70b-versatile", "openai/gpt-oss-120b",
        "llama-3.1-8b-instant"])
    yield


def _mesaj():
    return [{"role": "user", "content": "merhaba"}]


def test_erisilemeyen_model_atlanir_sonraki_denenir(monkeypatch):
    fake = _FakeGroq("openai/gpt-oss-120b")
    monkeypatch.setattr(llm, "_groq", fake)
    assert llm._groq_complete(_mesaj(), 0.4, 100, False) == "cevap"
    assert fake.denenen == ["llama-3.3-70b-versatile", "openai/gpt-oss-120b"]


def test_olu_model_bir_daha_denenmez(monkeypatch):
    fake = _FakeGroq("llama-3.1-8b-instant")
    monkeypatch.setattr(llm, "_groq", fake)
    llm._groq_complete(_mesaj(), 0.4, 100, False)
    fake.denenen.clear()
    llm._groq_complete(_mesaj(), 0.4, 100, False)
    assert fake.denenen == ["llama-3.1-8b-instant"]  # ilk ikisi ölü işaretli


def test_hicbiri_erisilebilir_degilse_bos_doner(monkeypatch):
    fake = _FakeGroq(None)
    monkeypatch.setattr(llm, "_groq", fake)
    assert llm._groq_complete(_mesaj(), 0.4, 100, False) == ""
    assert len(fake.denenen) == 3


def test_model_disi_hata_yutulmaz(monkeypatch):
    class _Patlak(_FakeGroq):
        def create(self, model, **kw):
            self.denenen.append(model)
            raise RuntimeError("Error code: 429 - rate limit exceeded")

    fake = _Patlak(None)
    monkeypatch.setattr(llm, "_groq", fake)
    with pytest.raises(RuntimeError, match="429"):
        llm._groq_complete(_mesaj(), 0.4, 100, False)
    assert fake.denenen == ["llama-3.3-70b-versatile"]  # zincire devam etmez


def test_stream_de_aday_zincirini_kullanir(monkeypatch):
    class _StreamGroq(_FakeGroq):
        def create(self, model, **kw):
            self.denenen.append(model)
            if model != self.calisan:
                raise RuntimeError("404 ... 'code': 'model_not_found'}}")

            class _D:
                content = "tok"

            class _C:
                delta = _D()

            class _Chunk:
                choices = [_C()]

            return [_Chunk()]

    fake = _StreamGroq("llama-3.1-8b-instant")
    monkeypatch.setattr(llm, "_groq", fake)
    monkeypatch.setattr(llm, "_gemini", None)
    assert list(llm.stream(_mesaj())) == ["tok"]
    assert fake.denenen[-1] == "llama-3.1-8b-instant"


def test_env_modeli_once_denenir(monkeypatch):
    monkeypatch.setattr(llm, "_GROQ_MODELS",
                        ["ozel/model", "llama-3.1-8b-instant"])
    fake = _FakeGroq("llama-3.1-8b-instant")
    monkeypatch.setattr(llm, "_groq", fake)
    llm._groq_complete(_mesaj(), 0.4, 100, False)
    assert fake.denenen[0] == "ozel/model"
