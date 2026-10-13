"""Temettü cevapları için açık sözleşme (C2).

get_dividend_overview ve collect_virtual_dividends eskiden gevşek dict
döndürüyordu. Açık model → frontend tip üretebilir, sözleşme görünür.

`extra = "allow"`: yeni alanlar model güncellenene dek SESSİZCE
silinmesin (round-10 *_try hatası sınıfı).
"""

from pydantic import BaseModel, ConfigDict


class DividendItem(BaseModel):
    symbol: str
    name: str
    currency: str
    quantity: float
    last_amount: float
    last_date: str
    ttm_per_share: float
    est_annual_income: float
    next_payout: float
    next_ex_date: str | None = None
    next_ex_estimated: bool = True
    collected_try: float = 0.0
    auto_collect: bool = True

    model_config = ConfigDict(extra="allow")


class DividendRecent(BaseModel):
    symbol: str
    date: str
    amount_try: float


class DividendCollectEvent(BaseModel):
    symbol: str
    date: str
    per_share: float
    amount: float


class DividendOverviewResponse(BaseModel):
    has_data: bool
    items: list[DividendItem] = []
    est_annual_try: float = 0.0
    est_annual_usd: float = 0.0
    collected_total_try: float = 0.0
    collected_count: int = 0
    collected_recent: list[DividendRecent] = []
    # Şu an tahsil edilebilir kesin tutar/olaylar (gömülü dry-run) —
    # eskiden ayrı /dividends/preview round-trip'iydi.
    claimable: float = 0.0
    claim_events: list[DividendCollectEvent] = []

    model_config = ConfigDict(extra="allow")


class DividendCollectResponse(BaseModel):
    credited: float
    events: list[DividendCollectEvent] = []

    model_config = ConfigDict(extra="allow")
