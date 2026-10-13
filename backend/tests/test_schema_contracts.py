"""C1 — API sözleşmesi regresyon testi.

Round-10'da total_value_try/total_cost_try/pnl_try backend'de hesaplanıp
şemada TANIMLI OLMADIĞI için FastAPI response_model bunları cevaptan
SESSİZCE siliyordu → frontend USD+₺'yi ham topluyordu. Bu test o hata
sınıfının nöbetçisi: kritik *_try alanları ve A4 dürüstlük alanları
sözleşmede kalmalı.

Çalıştırma (kullanıcı doğrularken):  cd backend && pytest -q
"""

from app.schemas.portfolio_schema import PortfolioItemResponse
from app.schemas.benchmark_schema import BenchmarkResponse, BenchmarkPortfolio
from app.schemas.dividend_schema import (
    DividendOverviewResponse,
    DividendCollectResponse,
)


def test_portfolio_item_has_try_fields():
    """USD pozisyonların ₺ karşılığı sözleşmede OLMAK ZORUNDA."""
    fields = set(PortfolioItemResponse.model_fields)
    for required in ("total_value_try", "total_cost_try", "pnl_try"):
        assert required in fields, (
            f"{required} PortfolioItemResponse'tan düşmüş — "
            f"FastAPI bunu cevaptan siler, round-10 hatası geri gelir."
        )


def test_portfolio_item_has_change_percent():
    """40. tur regresyonu (Round-10 *_try hatasının aynı sınıfı): pozisyonun
    BUGÜNKÜ % değişimi servis (portfolio_service) tarafından üretiliyordu ama
    şemada TANIMLI DEĞİLDİ → FastAPI response_model cevaptan SİLDİ → frontend
    dailyChangePct=0 → ana sayfa 'Bugün' K/Z'si ₺0 göründü."""
    fields = set(PortfolioItemResponse.model_fields)
    assert "change_percent" in fields, (
        "change_percent PortfolioItemResponse'tan düşmüş — FastAPI bunu "
        "cevaptan siler, ana sayfa 'Bugün' K/Z'si ₺0 görünür (40. tur hatası)."
    )


def test_benchmark_portfolio_surfaces_exclusions():
    """A4: dürüstlük alanları (dahil/dışlanan sembol) sözleşmede."""
    fields = set(BenchmarkPortfolio.model_fields)
    assert "symbols_included" in fields
    assert "symbols_excluded" in fields
    # Üst düzey sözleşme de bütünlüğünü korumalı.
    top = set(BenchmarkResponse.model_fields)
    assert {"period", "portfolio", "benchmarks"} <= top


def test_dividend_contracts_complete():
    """Temettü genel görünüm + tahsil alanları sözleşmede."""
    ov = set(DividendOverviewResponse.model_fields)
    assert {"has_data", "items", "collected_total_try"} <= ov
    co = set(DividendCollectResponse.model_fields)
    assert {"credited", "events"} <= co


def test_response_models_allow_extra():
    """extra='allow' → ileride eklenen alan SESSİZCE silinmesin."""
    for model in (BenchmarkResponse, DividendOverviewResponse,
                  DividendCollectResponse):
        assert model.model_config.get("extra") == "allow", (
            f"{model.__name__} extra='allow' kaybetti — yeni alanlar "
            f"sessizce düşebilir (round-10 hatası sınıfı)."
        )
