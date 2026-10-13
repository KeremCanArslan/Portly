"""₺ maliyet ALIŞ kuruyla — kur kazancının K/Z'ye girmesi.

Yabancı (USD) varlıkların ₺ maliyeti bugünkü kurla hesaplanırken kurdan gelen
reel kâr K/Z'de HİÇ görünmüyordu: kur yükselince maliyet de aynı oranda büyüyüp
farkı sıfırlıyordu. Pozisyon artık maliyetin oluştuğu andaki kuru
(`fx_rate_at_cost`, lotların NATIVE maliyetiyle ağırlıklı) taşıyor.

Kilitlenen davranış:
- alış kuru kaydedilir (TRY varlıkta anlamsız → NULL),
- iki lot birleşince kur native maliyetle ağırlıklanır,
- ₺ K/Z = değer − (alış kuruyla) maliyet,
- `fx_gain_try` + varlık kazancı = ₺ K/Z (ayrıştırma tutarlı),
- kur BİLİNMİYORSA eski davranış (canlı kur) aynen sürer — regresyon yok.

Ağ yok: geçmiş kur conftest'te kapalı, testler kendi serisini verir.

Çalıştırma:  cd backend && python -m pytest tests/test_fx_cost_basis.py -q
"""
from datetime import datetime

import pytest

from app.models.portfolio import Portfolio
from app.services import fx_service, order_service, portfolio_service


class _Req:
    """import_manual_position'ın beklediği gövde (şema yerine hafif nesne)."""

    def __init__(self, user_id, symbol, quantity, avg_cost, acquired_at=None):
        self.user_id = user_id
        self.symbol = symbol
        self.quantity = quantity
        self.avg_cost = avg_cost
        self.acquired_at = acquired_at


@pytest.fixture
def history(monkeypatch):
    """Tarih → kur sözlüğü kuran yardımcı."""
    def _set(mapping: dict):
        monkeypatch.setattr(
            fx_service, "usdtry_rate_on",
            lambda day: mapping.get(str(day)[:10]))
    return _set


# ── kaydetme ─────────────────────────────────────────────────────────────

def test_try_asset_has_no_cost_rate(db, make_user, market):
    """BIST/.FON ₺ ile kote — kur alanı anlamsız, NULL kalır."""
    user = make_user()
    order_service.import_manual_position(
        db, _Req(user.id, "THYAO.IS", 100, 300))
    row = db.query(Portfolio).filter(Portfolio.symbol == "THYAO.IS").first()
    assert row.fx_rate_at_cost is None


def test_manual_import_records_acquisition_day_rate(
        db, make_user, market, history):
    """Geçmiş tarihli pozisyon O GÜNÜN kuruyla işaretlenir (bugünkü ile değil)."""
    market.set_usdtry(48.0)
    history({"2025-06-02": 39.0})
    user = make_user()
    order_service.import_manual_position(
        db, _Req(user.id, "AAPL", 10, 100, datetime(2025, 6, 2, 10, 0)))
    row = db.query(Portfolio).filter(Portfolio.symbol == "AAPL").first()
    assert row.fx_rate_at_cost == pytest.approx(39.0)


def test_merged_lots_weight_rate_by_native_cost(db, make_user, market, history):
    """İki lot birleşince kur, lotların NATIVE maliyetiyle ağırlıklanır.

    1000$ @39 + 2000$ @45 → (1000*39 + 2000*45)/3000 = 43.0
    Böylece `native_maliyet × kur` her zaman gerçek ₺ maliyeti verir.
    """
    market.set_usdtry(48.0)
    history({"2025-06-02": 39.0, "2026-02-02": 45.0})
    user = make_user()
    order_service.import_manual_position(
        db, _Req(user.id, "AAPL", 10, 100, datetime(2025, 6, 2)))
    order_service.import_manual_position(
        db, _Req(user.id, "AAPL", 10, 200, datetime(2026, 2, 2)))
    row = db.query(Portfolio).filter(Portfolio.symbol == "AAPL").first()
    assert row.quantity == pytest.approx(20)
    assert row.average_cost == pytest.approx(150)
    assert row.fx_rate_at_cost == pytest.approx(43.0)


# ── değerleme ────────────────────────────────────────────────────────────

def test_currency_gain_reaches_try_pnl(db, make_user, market, history):
    """Fiyat HİÇ değişmese bile kur yükselmişse ₺ kâr vardır.

    10 adet @100$ = 1000$ maliyet, kur 39 → ₺39.000.
    Fiyat yine 100$, kur 48 → değer ₺48.000. Gerçek ₺ kâr ₺9.000.
    Eski hesapta maliyet de 48 ile çevrildiğinden K/Z ₺0 görünüyordu.
    """
    market.set_usdtry(48.0)
    market.set_price("AAPL", 100.0)
    history({"2025-06-02": 39.0})
    user = make_user()
    order_service.import_manual_position(
        db, _Req(user.id, "AAPL", 10, 100, datetime(2025, 6, 2)))

    row = portfolio_service.get_user_portfolio(db, user.id)[0]
    assert row["total_cost_try"] == pytest.approx(39_000)
    assert row["total_value_try"] == pytest.approx(48_000)
    assert row["pnl_try"] == pytest.approx(9_000)
    assert row["fx_gain_try"] == pytest.approx(9_000)
    assert row["pnl"] == pytest.approx(0)      # native K/Z değişmedi


def test_fx_gain_plus_asset_gain_equals_try_pnl(
        db, make_user, market, history):
    """Ayrıştırma tutarlı: kur kazancı + varlık kazancı = ₺ K/Z."""
    market.set_usdtry(48.0)
    market.set_price("AAPL", 150.0)            # 100$ → 150$
    history({"2025-06-02": 39.0})
    user = make_user()
    order_service.import_manual_position(
        db, _Req(user.id, "AAPL", 10, 100, datetime(2025, 6, 2)))

    row = portfolio_service.get_user_portfolio(db, user.id)[0]
    asset_gain = (150 - 100) * 10 * 48.0       # varlığın kendi kazancı, canlı kurla
    assert row["fx_gain_try"] == pytest.approx(1000 * (48.0 - 39.0))
    assert row["pnl_try"] == pytest.approx(asset_gain + row["fx_gain_try"])


def test_unknown_cost_rate_keeps_old_behaviour(db, make_user, market):
    """Kur bilinmeyen (kolon öncesi) satırda eski davranış aynen sürer."""
    market.set_usdtry(48.0)
    market.set_price("AAPL", 150.0)
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=10,
                     average_cost=100, fx_rate_at_cost=None))
    db.commit()

    row = portfolio_service.get_user_portfolio(db, user.id)[0]
    assert row["total_cost_try"] == pytest.approx(1000 * 48.0)
    assert row["pnl_try"] == pytest.approx(500 * 48.0)
    assert row["fx_gain_try"] == pytest.approx(0)


def test_try_asset_valuation_untouched(db, make_user, market):
    """₺ varlıkta kur yolu hiç devreye girmez (BIST/.FON regresyon nöbetçisi)."""
    market.set_usdtry(48.0)
    market.set_price("THYAO.IS", 350.0)
    user = make_user()
    order_service.import_manual_position(
        db, _Req(user.id, "THYAO.IS", 100, 300))

    row = portfolio_service.get_user_portfolio(db, user.id)[0]
    assert row["total_cost_try"] == pytest.approx(30_000)
    assert row["total_value_try"] == pytest.approx(35_000)
    assert row["pnl_try"] == pytest.approx(5_000)
    assert row["fx_gain_try"] == pytest.approx(0)


def test_bare_bist_code_is_treated_as_try(db, make_user, market, history):
    """Çıplak BIST kodu ('THYAO') da ₺ sayılır — kur damgalanmaz.

    Kayıt ham sembolle yazılıyor ama portfolio_service okurken
    canonical('THYAO')='THYAO.IS' üzerinden ₺ diyor; iki taraf aynı sembolü
    görmezse ₺ varlığa boşuna kur işlenirdi.
    """
    market.set_usdtry(48.0)
    history({"2025-06-02": 39.0})
    user = make_user()
    order_service.import_manual_position(
        db, _Req(user.id, "THYAO", 100, 300, datetime(2025, 6, 2)))
    row = db.query(Portfolio).filter(Portfolio.user_id == user.id).first()
    assert row.fx_rate_at_cost is None
