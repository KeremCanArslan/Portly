"""Türkçe finansal duygu analizi — regresyon korpusu.

Neden var: ABD hisseleri için de Türk basınından haber çekiliyor ve VADER
Türkçe okuyamıyor. Sözlük yanlış çalışırsa haberler ya "Nötr 0.00" kalır ya
da TERS etiketlenir.

Ölçülen gerçek hata (bu testler yazılmadan önce): negatif sözlükteki "kaza"
kelimesi "kazancı" İÇİNDE eşleşiyordu → HER bilanço haberi negatif çıkıyordu.
Bu yüzden eşleştirme artık kelime başı sınırlı ve uzun-anahtar-önce
(aralık tüketmeli).
"""

import pytest

from app.services.nlp_sentiment_service import (
    _tr_matches, _turkish_sentiment, analyze_sentiment,
)

POSITIVE = [
    "RTX Corp kazancı beklentilerin üzerinde geldi",
    "Şirket bu çeyrekte rekor kazanç açıkladı",
    "BofA hedef fiyatı yükseltti: THYAO için al tavsiyesi",
    "Aselsan yeni sipariş aldı, 500 milyon dolarlık sözleşme imzalandı",
    "Şirket ihaleyi kazandı, üretime başlıyor",
    "Temettü ödemesi açıklandı, hisse primle kapattı",
    "Gelir artışı sürüyor, marj iyileşti",
    "Yatırım kararı onaylandı, kapasite artırılıyor",
]

NEGATIVE = [
    "Şirketin kazancı beklentilerin altında kaldı",
    "Şirket üretimi durdurdu, fabrika kapatılıyor",
    "Boeing hisseleri baskı altında: analistler not indirdi",
    "Hisse kâr satışlarıyla geriledi",
    "Anlaşma bozuldu, görüşmeler tıkandı",
    "Uçak kazası soruşturması başlatıldı",
    "Şirkete para cezası verildi, inceleme başlatıldı",
    "CEO istifa etti, yönetim değişikliğe gidiyor",
    "Sipariş iptal edildi, ciro düştü",
    "Veri ihlali sonrası siber saldırı doğrulandı",
]

NEUTRAL = [
    "Şirket olağan genel kurul toplantısını yaptı",
    "Yapay zeka tabanlı yeni ürün tanıtıldı",
    "Genel müdür bugün bir konferansta konuştu",
    "Şirket merkezini yeni binaya taşıdı",
]


@pytest.mark.parametrize("text", POSITIVE)
def test_positive_headlines(text):
    assert analyze_sentiment(text)["label"] == "Pozitif", text


@pytest.mark.parametrize("text", NEGATIVE)
def test_negative_headlines(text):
    assert analyze_sentiment(text)["label"] == "Negatif", text


@pytest.mark.parametrize("text", NEUTRAL)
def test_neutral_headlines(text):
    assert analyze_sentiment(text)["label"] == "Nötr", text


# ── Alt-dize çakışması (asıl yakalanan hata) ──────────────────────────────

@pytest.mark.parametrize("text,inside", [
    ("kazancı arttı", "kaza"),        # kaza(negatif) ⊄ kazanç
    ("kazandı", "kaza"),
    ("yapay zeka tabanlı ürün", "taban"),   # taban(negatif) ⊄ tabanlı
])
def test_keyword_does_not_match_inside_another_word(text, inside):
    """Kelime ORTASINDA eşleşme olmamalı."""
    pos, neg = _tr_matches(text)
    assert neg == 0, f"'{inside}' yanlışlıkla '{text}' içinde eşleşti"


def test_earnings_word_is_not_negative():
    """En kritik regresyon: bilanço haberi negatif çıkmamalı."""
    assert _turkish_sentiment("kazancı açıklandı") is None or \
        _turkish_sentiment("kazancı açıklandı") >= 0


# ── Uzun ifade kısa olanı yutmalı ─────────────────────────────────────────

@pytest.mark.parametrize("text", [
    "kâr satışı görüldü",        # "kâr"(+) ⊂ "kâr satış"(−) → net negatif
    "anlaşma bozuldu",           # "anlaşma"(+) ⊂ "anlaşma bozul"(−)
    "ortaklık sona erdi",        # "ortaklık"(+) ⊂ "ortaklık sona er"(−)
])
def test_longer_phrase_wins(text):
    pos, neg = _tr_matches(text)
    assert neg > 0 and pos == 0, f"{text}: pos={pos} neg={neg}"


def test_no_signal_returns_none_so_vader_can_decide():
    """Türkçe sinyal yoksa None → İngilizce metinde VADER devreye girsin."""
    assert _turkish_sentiment("apple announces new iphone") is None


def test_english_headline_still_scored_by_vader():
    r = analyze_sentiment("Lockheed Martin profit beats estimates, shares surge")
    assert r["label"] == "Pozitif"


def test_record_word_does_not_flip_negative_headline():
    """'rekor' tek başına pozitif ama 'rekor düşüş' negatiftir — uzun ifade
    kazanmalı, yoksa iki sinyal birbirini götürüp Nötr çıkıyordu."""
    assert analyze_sentiment("Hisse rekor düşüş yaşadı")["label"] == "Negatif"


def test_bare_earnings_word_is_not_a_signal():
    """'kazanç' nötr bir bilanço terimi: tek başına yön bildirmez."""
    assert _turkish_sentiment("şirketin kazancı açıklandı") is None
