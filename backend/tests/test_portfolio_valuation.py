"""C3 — Portföy değerleme (*_try) regresyon testleri.

Şema testi (test_schema_contracts) yalnız *_try alanlarının SÖZLEŞMEDE
kaldığını korur; bu dosya o alanların DEĞERLERİNİ korur. Round-10'daki kök
hata: USD + ₺ pozisyonlar ham toplanıyordu (TSLA $1266 ≈ ₺1266) → portföy
toplamı/donut/sektör yüzdeleri yanlıştı. get_user_portfolio artık her satırın
total_value_try/total_cost_try/pnl_try'sini fx_service ile üretir; toplayan
taraf MUTLAKA *_try okur. Bkz. [[feedback_fx_single_source]].

Çalıştırma:  cd backend && pytest -q
"""

import pytest

from app.services import portfolio_service
from app.models.portfolio import Portfolio


def _add_position(db, user, symbol, quantity, avg_cost):
    db.add(Portfolio(user_id=user.id, symbol=symbol,
                     quantity=quantity, average_cost=avg_cost))
    db.commit()


def _row(rows, symbol):
    return next(r for r in rows if r["symbol"] == symbol)


# ── Tek pozisyon değerleme ────────────────────────────────────────────────

def test_usd_position_value_in_try(db, market, make_user):
    """USD pozisyon: *_try canlı kurla çevrilir, native alanlar USD kalır."""
    market.set_usdtry(40.0)
    market.set_price("AAPL", 200.0)
    user = make_user()
    _add_position(db, user, "AAPL", 2, 150.0)

    row = _row(portfolio_service.get_user_portfolio(db, user.id), "AAPL")

    assert row["currency"] == "USD"
    assert row["average_cost"] == pytest.approx(150.0)     # native USD
    assert row["total_value"] == pytest.approx(400.0)      # native 2×200
    assert row["pnl"] == pytest.approx(100.0)              # 400 − 300
    assert row["total_value_try"] == pytest.approx(16000.0)  # 400×40
    assert row["total_cost_try"] == pytest.approx(12000.0)   # 300×40
    assert row["pnl_try"] == pytest.approx(4000.0)           # 100×40


def test_bist_position_no_fx(db, market, make_user):
    """BIST (₺) pozisyon: *_try == native (kur uygulanmaz)."""
    market.set_usdtry(40.0)
    market.set_price("THYAO.IS", 100.0)
    user = make_user()
    _add_position(db, user, "THYAO.IS", 10, 80.0)

    row = _row(portfolio_service.get_user_portfolio(db, user.id), "THYAO.IS")

    assert row["currency"] == "TRY"
    assert row["total_value"] == pytest.approx(1000.0)
    assert row["total_value_try"] == pytest.approx(1000.0)   # FX yok
    assert row["total_cost_try"] == pytest.approx(800.0)


# ── Karışık portföy: ham-toplama bug'ının nöbetçisi ───────────────────────

def test_mixed_portfolio_try_is_summable(db, market, make_user):
    """USD+BIST karışık portföyde total_value_try TOPLANABİLİR olmalı.
    Ham toplama bug'ı olsaydı: 100+500 = 600. Doğrusu: 100×40 + 500 = 4500."""
    market.set_usdtry(40.0)
    market.set_price("AAPL", 100.0)       # USD
    market.set_price("THYAO.IS", 50.0)    # TRY
    user = make_user()
    _add_position(db, user, "AAPL", 1, 100.0)
    _add_position(db, user, "THYAO.IS", 10, 50.0)

    rows = portfolio_service.get_user_portfolio(db, user.id)
    total_try = sum(r["total_value_try"] for r in rows)

    assert total_try == pytest.approx(4500.0)


# ── Sağlamlık: bozuk/eksik veri ───────────────────────────────────────────

def test_zero_quantity_position_skipped(db, market, make_user):
    """Adet ~0 pozisyon toplamlara/bölmelere sızmadan elenir (boş liste döner)."""
    market.set_price("AAPL", 100.0)
    user = make_user()
    _add_position(db, user, "AAPL", 0.0, 100.0)

    assert portfolio_service.get_user_portfolio(db, user.id) == []


def test_missing_quote_falls_back_to_avg_cost(db, market, make_user):
    """Batch'te fiyat dönmeyen sembol → current_price = avg_cost (pnl 0),
    'boş portföy' yerine makul satır. Render'da Yahoo boş dönerse demoyu korur."""
    market.set_usdtry(40.0)
    user = make_user()
    _add_position(db, user, "AAPL", 2, 150.0)   # AAPL fiyatı set EDİLMEDİ

    row = _row(portfolio_service.get_user_portfolio(db, user.id), "AAPL")

    assert row["current_price"] == pytest.approx(150.0)        # avg_cost'a düştü
    assert row["pnl"] == pytest.approx(0.0)
    assert row["total_value_try"] == pytest.approx(2 * 150 * 40)  # 12000


def test_empty_portfolio_returns_empty(db, market, make_user):
    user = make_user()
    assert portfolio_service.get_user_portfolio(db, user.id) == []


# ── Sektör dağılımı (donut): ₺ tabanlı ────────────────────────────────────

def test_sector_breakdown_uses_try(db, market, make_user, monkeypatch):
    """Donut/sektör USD+₺'yi ham toplamamalı; total_value_try kullanır +
    yüzdeler 100'e tamamlanır (round-25 donut + ham-toplama dersi).
    Pivot sonrası sanal nakit YOK → 'Nakit' dilimi de yok."""
    market.set_usdtry(40.0)
    market.set_price("AAPL", 100.0)       # USD → 1×100×40 = ₺4000
    market.set_price("THYAO.IS", 50.0)    # TRY → 10×50   = ₺500
    monkeypatch.setattr(
        "app.services.portfolio_service._resolve_sector",
        lambda sym: {"AAPL": "Teknoloji", "THYAO.IS": "Ulaştırma"}.get(
            sym.upper(), "Diğer"))
    user = make_user()
    _add_position(db, user, "AAPL", 1, 100.0)
    _add_position(db, user, "THYAO.IS", 10, 50.0)

    out = portfolio_service.get_sector_breakdown(db, user.id)
    sectors = {s["name"]: s for s in out["sectors"]}

    assert out["total_value"] == pytest.approx(4000 + 500)  # ₺4500
    assert sectors["Teknoloji"]["value"] == pytest.approx(4000.0)  # USD→₺
    assert sectors["Ulaştırma"]["value"] == pytest.approx(500.0)
    assert "Nakit" not in sectors
    assert sum(s["percent"] for s in out["sectors"]) == pytest.approx(100.0, abs=0.1)


# ── Fiyat alınamadığında dürüstlük ────────────────────────────────────────

def test_unpriced_position_is_flagged_not_silently_zero(db, market, make_user):
    """Fiyat gelmeyince maliyet fiyat yerine geçiyor ve K/Z 0 çıkıyor.

    Canlıda (2 Eyl 2026) Yahoo BIST'i 429'ladığı için TÜM BIST satırları
    "Fiyat ₺35,00 · Maliyet ₺35,00 · +%0,00 · Bugün +%0,00" görünüyordu —
    kullanıcı bunu "hiç değişmemiş" diye okur. Sayı aynı kalır (toplamlar
    bozulmasın) ama satır `price_available: False` ile işaretlenir; ekran
    "—" gösterir.
    """
    market.set_usdtry(40.0)
    # KARCL.IS bilerek fiyatlanmıyor (fixture yalnız set edilenleri döndürür).
    market.set_price("THYAO.IS", 120.0)
    user = make_user()
    _add_position(db, user, "KARCL.IS", 94, 35.0)
    _add_position(db, user, "THYAO.IS", 10, 100.0)

    rows = portfolio_service.get_user_portfolio(db, user.id)
    unpriced = _row(rows, "KARCL.IS")
    priced = _row(rows, "THYAO.IS")

    assert unpriced["price_available"] is False
    assert unpriced["current_price"] == pytest.approx(35.0)   # maliyete düştü
    assert unpriced["pnl"] == pytest.approx(0.0)              # matematik 0
    assert priced["price_available"] is True
    assert priced["pnl"] == pytest.approx(200.0)


def test_price_available_survives_response_model(db, market, make_user, client=None):
    """Bayrak ŞEMADA olmalı — yoksa response_model cevaptan siler (40. turdaki
    change_percent regresyonunun aynısı)."""
    from app.schemas.portfolio_schema import PortfolioItemResponse
    assert "price_available" in PortfolioItemResponse.model_fields


def test_change_unavailable_when_price_missing(db, make_user, monkeypatch):
    """Kotasyonu HİÇ dönmeyen pozisyon 'bugün %0' demez.

    Fiyat gelmeyince değer maliyetten hesaplanıyor; oradaki 0 değişim gerçek
    bir ölçüm değildir. `change_available` False olmazsa portföyün günlük
    yüzdesi bu sahte 0'la seyrelirdi (dürüst boş-durum kuralı).
    """
    from app.models.portfolio import Portfolio
    from app.services import portfolio_service

    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="ZZZZ.IS",
                     quantity=10, average_cost=100))
    db.commit()

    monkeypatch.setattr(portfolio_service, "get_stock_prices",
                        lambda symbols: {})
    rows = portfolio_service.get_user_portfolio(db, user.id)
    assert len(rows) == 1
    assert rows[0]["price_available"] is False
    assert rows[0]["change_available"] is False
