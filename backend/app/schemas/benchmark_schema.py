"""Benchmark cevabı için açık sözleşme (C2).

Eskiden /portfolio/{id}/benchmark gevşek bir dict döndürüyordu; A4'te
eklenen symbols_included/symbols_excluded gibi alanlar sözleşmede görünmez,
frontend tip üretemezdi. Burada her alan açıkça modellenir.

`extra = "allow"`: ileride servise yeni bir alan eklenirse FastAPI bunu
SESSİZCE SİLMESİN (round-10 *_try hatası sınıfının kökü buydu) — model
genişletilene kadar alan yine de cevapta kalır.
"""

from pydantic import BaseModel, ConfigDict


class BenchmarkComponent(BaseModel):
    symbol: str
    weight: float
    return_pct: float


class BenchmarkPortfolio(BaseModel):
    return_pct: float
    has_holdings: bool
    sharpe: float | None = None
    components: list[BenchmarkComponent] = []
    # A4: getiri yalnız dönem verisi OLAN pozisyonlardan; dürüst rapor.
    symbols_included: int = 0
    symbols_excluded: list[str] = []

    model_config = ConfigDict(extra="allow")


class BenchmarkEntry(BaseModel):
    return_pct: float | None = None
    symbol: str
    sharpe: float | None = None
    approx: bool | None = None

    model_config = ConfigDict(extra="allow")


class BenchmarkResponse(BaseModel):
    period: str
    days: int
    portfolio: BenchmarkPortfolio
    benchmarks: dict[str, BenchmarkEntry]
    generated_at: str

    model_config = ConfigDict(extra="allow")
