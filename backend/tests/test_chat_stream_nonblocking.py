"""AI Koç akışı olay döngüsünü bloklamamalı (4 Eylül 2026, 8. tur).

`chat_service.stream_chat_response` baştan sona SENKRON: DB yazar, RAG
bağlamını kurar, LLM akışını bloklayarak okur. `async def event_generator`
içinde düz `for` ile dönmek onu olay döngüsünde çalıştırıyordu → sohbet
sürerken aynı uvicorn işçisindeki diğer bütün istekler (portföy, fiyat,
sinyal) sıraya giriyordu. Render ücretsiz katmanında işçi sayısı az olduğu
için bu, "AI yazarken uygulama donuyor" demektir.

İkinci konu: istemci sekmeyi kapatınca senkron üretecin KAPANMASI
(LLM kotası arkada tükenmesin).

Not: projede pytest-asyncio yok → testler `asyncio.run` ile sürülüyor.
"""

import asyncio
import time

from app.api.v1 import chat as chat_api


class _SayacliKaynak:
    """Bloklayan (senkron) LLM akışı taklidi; kapanışı da kaydeder."""

    def __init__(self, token_sayisi=5, blok_saniye=0.02):
        self.token_sayisi = token_sayisi
        self.blok_saniye = blok_saniye
        self.uretilen = 0
        self.kapandi = False

    def __iter__(self):
        try:
            for i in range(self.token_sayisi):
                time.sleep(self.blok_saniye)  # ağ/LLM beklemesi
                self.uretilen += 1
                yield f"t{i}"
        except GeneratorExit:
            self.kapandi = True
            raise


def _sahte_stream(kaynak):
    def _fn(db=None, user_id=None, user_message=None):
        yield from kaynak

    return _fn


async def _olaylari_topla(response, sinir=None):
    olaylar = []
    async for item in response.body_iterator:
        olaylar.append(item)
        if sinir is not None and len(olaylar) >= sinir:
            break
    return olaylar


def test_akis_olay_dongusunu_bloklamaz(monkeypatch):
    """Ölçüt: olay döngüsünün EN UZUN duraksaması.

    "Yan görev toplam kaç kez döndü" yetmiyor — blokta biriken zamanlayıcılar
    blok bitince arka arkaya ateşleniyor ve toplam sayı tutuyor. Bloklanmanın
    imzası, ardışık iki tik ARASINDAKİ en büyük boşluktur: bloklayan sürümde
    bu, tek bir token beklemesi kadar (50 ms+) olur.
    """
    kaynak = _SayacliKaynak(token_sayisi=4, blok_saniye=0.05)
    monkeypatch.setattr(
        chat_api.chat_service, "stream_chat_response", _sahte_stream(kaynak)
    )

    async def senaryo():
        anlar = []
        bitti = False

        async def _diger_istek():
            while not bitti:
                anlar.append(time.monotonic())
                await asyncio.sleep(0.001)

        response = chat_api._stream_response(db=None, user_id=1, message="merhaba")
        yan_gorev = asyncio.create_task(_diger_istek())
        olaylar = await _olaylari_topla(response)
        bitti = True
        await yan_gorev
        return anlar, olaylar

    anlar, olaylar = asyncio.run(senaryo())

    # Yan görev hiç dönemediyse döngü baştan sona bloke demektir.
    assert len(anlar) >= 2, (
        "eş zamanlı görev akış boyunca HİÇ çalışamadı — olay döngüsü tamamen "
        "bloklanmış"
    )
    en_uzun = max(b - a for a, b in zip(anlar, anlar[1:]))
    # Bloklayan sürümde en uzun boşluk ≈ 50 ms (bir token beklemesi).
    # Threadpool'a taşınmış sürümde ~1 ms. Eşik ikisinin ortasında.
    assert en_uzun < 0.02, (
        f"olay döngüsü {en_uzun * 1000:.0f} ms duraksadı — LLM akışı döngüyü "
        "blokluyor, sohbet sürerken diğer istekler sıraya girer"
    )

    tipler = [o["event"] for o in olaylar]
    assert tipler[0] == "thinking"
    assert tipler[-1] == "done"
    assert tipler.count("token") == 4


def test_istemci_koparsa_senkron_uretec_kapanir(monkeypatch):
    kaynak = _SayacliKaynak(token_sayisi=50, blok_saniye=0.005)
    monkeypatch.setattr(
        chat_api.chat_service, "stream_chat_response", _sahte_stream(kaynak)
    )

    async def senaryo():
        response = chat_api._stream_response(db=None, user_id=1, message="merhaba")
        # İki olay al (thinking + ilk token), sonra istemci kopmuş gibi kapat.
        await _olaylari_topla(response, sinir=2)
        await response.body_iterator.aclose()

    asyncio.run(senaryo())

    assert kaynak.kapandi is True, "üreteç kapanmadı → LLM arkada üretmeye devam eder"
    assert kaynak.uretilen < 50, "kopmadan sonra da token üretilmiş"
