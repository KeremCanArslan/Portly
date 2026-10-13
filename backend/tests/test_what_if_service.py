"""C6 — 'Eğer almış olsaydım' (what-if) + DCA matematiği.

calculate sembol-native (FX yok): adet = tutar/baş_fiyat, değer = adet×son_fiyat,
CAGR yıllıklandırılmış. calculate_dca her ay alım + lump-sum kıyası. yfinance
mock'lanır (kontrollü pandas DataFrame).

Çalıştırma:  cd backend && pytest -q
"""

import pandas as pd
import pytest

from app.services import what_if_service


class _FakeTicker:
    def __init__(self, hist):
        self._hist = hist

    def history(self, *args, **kwargs):
        return self._hist


def _patch_hist(monkeypatch, hist):
    monkeypatch.setattr(
        "app.services.what_if_service.yf.Ticker",
        lambda sym: _FakeTicker(hist))


# ── calculate (tek seferlik) ──────────────────────────────────────────────

def test_what_if_basic_return(monkeypatch):
    """2 yılda 100→200 (×2): 1000₺ → 10 adet → 2000₺, %100 kâr; CAGR < toplam."""
    idx = pd.DatetimeIndex(["2024-01-01", "2026-01-01"])
    _patch_hist(monkeypatch, pd.DataFrame({"Close": [100.0, 200.0]}, index=idx))

    res = what_if_service.calculate("AAPL", amount=1000.0, years_back=2)

    assert "error" not in res
    assert res["quantity"] == pytest.approx(10.0)
    assert res["current_value"] == pytest.approx(2000.0)
    assert res["profit_pct"] == pytest.approx(100.0)
    assert 0 < res["cagr_pct"] < res["profit_pct"]   # yıllık < kümülatif


def test_what_if_loss(monkeypatch):
    """Düşen fiyat negatif kâr vermeli."""
    idx = pd.DatetimeIndex(["2025-01-01", "2026-01-01"])
    _patch_hist(monkeypatch, pd.DataFrame({"Close": [200.0, 100.0]}, index=idx))

    res = what_if_service.calculate("AAPL", amount=1000.0, years_back=1)

    assert res["profit"] == pytest.approx(-500.0)     # 1000 → 500
    assert res["profit_pct"] == pytest.approx(-50.0)


def test_what_if_insufficient_data(monkeypatch):
    """Tek satır geçmiş → hata (bölme/hesap yapılmaz, patlamaz)."""
    idx = pd.DatetimeIndex(["2026-01-01"])
    _patch_hist(monkeypatch, pd.DataFrame({"Close": [100.0]}, index=idx))

    res = what_if_service.calculate("AAPL", 1000.0, 1)

    assert "error" in res


def test_what_if_end_date_truncates(monkeypatch):
    """Bitiş tarihi verilince o tarihe (dahil) kadarki son fiyat baz alınır:
    100→150→300, bitiş 2025-06-01 → son satır 2025-01-01 (150), bugünkü 300 DEĞİL."""
    idx = pd.DatetimeIndex(["2024-01-01", "2025-01-01", "2026-01-01"])
    _patch_hist(monkeypatch,
                pd.DataFrame({"Close": [100.0, 150.0, 300.0]}, index=idx))

    res = what_if_service.calculate("AAPL", 1000.0, 5,
                                    end_date_str="2025-06-01")

    assert res["end_date"] == "2025-01-01"
    assert res["end_price"] == pytest.approx(150.0)
    assert res["current_value"] == pytest.approx(1500.0)  # 10 adet × 150
    assert res["profit_pct"] == pytest.approx(50.0)


# ── calculate_dca (maliyet ortalaması) ────────────────────────────────────

def test_dca_accumulates_and_beats_by_lump_in_rising_market(monkeypatch):
    """Aylık ilk-gün fiyatları 100/200/400, son 400. Aylık 1000₺:
    adet 10+5+2.5=17.5, yatırılan 3000, değer 7000 (%133). Lump-sum aynı 3000'i
    ilk ay 100'den alsaydı 30 adet → 12000 (%300) → yükselen piyasada lump kazanır."""
    dates = pd.date_range("2026-01-01", "2026-03-31", freq="D")
    close = [{1: 100.0, 2: 200.0, 3: 400.0}[d.month] for d in dates]
    _patch_hist(monkeypatch, pd.DataFrame({"Close": close}, index=dates))

    res = what_if_service.calculate_dca("AAPL", monthly_amount=1000.0, years_back=1)

    assert res["months"] == 3
    assert res["total_invested"] == pytest.approx(3000.0)
    assert res["quantity"] == pytest.approx(17.5)
    assert res["current_value"] == pytest.approx(7000.0)
    assert res["profit_pct"] == pytest.approx(133.33, abs=0.01)
    assert res["lump_sum_profit_pct"] == pytest.approx(300.0)
    assert res["lump_sum_profit_pct"] > res["profit_pct"]


def test_dca_respects_date_window(monkeypatch):
    """Başlangıç+bitiş penceresi aydan ayı kırpar: Oca/Şub/Mar/Nis fiyatları
    100/200/400/800; pencere Şub başı–Mar ortası → yalnız Şub(200) ve Mar(400):
    adet 1000/200+1000/400=7.5, yatırılan 2000, son fiyat 400 → değer 3000 (%50)."""
    dates = pd.date_range("2026-01-01", "2026-04-30", freq="D")
    close = [{1: 100.0, 2: 200.0, 3: 400.0, 4: 800.0}[d.month] for d in dates]
    _patch_hist(monkeypatch, pd.DataFrame({"Close": close}, index=dates))

    res = what_if_service.calculate_dca(
        "AAPL", monthly_amount=1000.0, years_back=1,
        start_date_str="2026-02-01", end_date_str="2026-03-15")

    assert res["months"] == 2
    assert res["start_date"] == "2026-02-01"
    assert res["total_invested"] == pytest.approx(2000.0)
    assert res["quantity"] == pytest.approx(7.5)
    assert res["current_value"] == pytest.approx(3000.0)
    assert res["profit_pct"] == pytest.approx(50.0)
