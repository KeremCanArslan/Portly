"""Haber akışı çöp filtresi (`_NOISE_RE`).

TR tarafı (TradingView kullanıcı analizleri, insider bildirimleri) zaten
eleniyordu; İNGİLİZCE tarafta kumar/promosyon listeleri sızıyordu — canlıda
`en|bitcoin` sonucunda "Best Crypto Casinos 2026 …" başlığı iki kez geldi.

Filtrenin İKİ yönü de sınanır: çöp elenmeli AMA gerçek haber (kumar sektörü
şirketleri dahil: Las Vegas Sands, DraftKings, Flutter) akışta KALMALI —
"casino" kelimesini görünce elemek haber kaybettirirdi.

Çalıştırma:  cd backend && python -m pytest tests/test_news_noise_filter.py -q
"""

import pytest

from app.services.nlp_sentiment_service import _NOISE_RE


@pytest.mark.parametrize("title", [
    "Best Crypto Casinos 2026: Top 10 Bitcoin Gambling Sites Ranked",
    "Top 5 Crypto Casinos for US Players",
    "New Bitcoin Casino Offers No Deposit Bonus to Players",
    "Best Crypto to Buy Now: 3 Presales That Could Explode",
    "Top 10 meme coins to buy before 2027",
    "Best online casino sites for slots and free spins",
    # TR tarafı (regresyon: eski kalıplar bozulmadı)
    "BIST:THYAO için 2 saatlik teknik ve temel analizi - TradingView",
    "Şirket yöneticisi 1,2 milyon dolarlık hisse sattı",
])
def test_promotional_noise_is_filtered(title):
    assert _NOISE_RE.search(title), f"çöp elenmedi: {title}"


@pytest.mark.parametrize("title", [
    "Bitcoin ETF inflows hit record as investors pile in",
    "DraftKings stock jumps after online betting ruling in Missouri",
    "Las Vegas Sands casino revenue beats estimates on Macau rebound",
    "Flutter Entertainment sportsbook revenue rises 22%",
    "Casino operator Wynn Resorts posts higher quarterly profit",
    "Coinbase launches staking service for institutional clients",
    "MicroStrategy adds 5,000 BTC to its treasury",
    "Gold price hits record high as dollar weakens",
    "Aselsan yeni savunma ihracat sözleşmesi imzaladı",
    "Crypto exchange Kraken files for IPO",
])
def test_real_news_survives(title):
    assert not _NOISE_RE.search(title), f"gerçek haber elendi: {title}"
