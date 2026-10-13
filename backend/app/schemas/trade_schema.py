from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.services.symbol_alias import canonical


class TradeRequest(BaseModel):
    user_id: int = Field(..., gt=0)
    symbol: str = Field(..., min_length=1, max_length=20)
    quantity: float = Field(..., gt=0)
    transaction_type: Literal["BUY", "SELL"]

    @field_validator("symbol")
    @classmethod
    def _normalize_symbol(cls, v: str) -> str:
        return canonical(v)


class ManualPositionRequest(BaseModel):
    """Manuel pozisyon içe aktarma: kullanıcının GERÇEKTE sahip olduğu bir
    pozisyonu maliyet + lot ile portföye tanımlar (kayıt defteri).
    `avg_cost` sembolün kendi para biriminde birim maliyettir. `acquired_at`
    verilmezse şimdi kabul edilir; temettü mutabakatı bunu edinim tarihi
    cutoff'u olarak kullanır."""

    user_id: int = Field(..., gt=0)
    symbol: str = Field(..., min_length=1, max_length=20)
    quantity: float = Field(..., gt=0)
    avg_cost: float = Field(..., gt=0)
    acquired_at: datetime | None = None

    @field_validator("symbol")
    @classmethod
    def _normalize_symbol(cls, v: str) -> str:
        return canonical(v)


class TradeResponse(BaseModel):
    id: int
    symbol: str
    transaction_type: str
    quantity: float
    price: float
    timestamp: datetime

    model_config = ConfigDict(from_attributes=True)


class StatementRow(BaseModel):
    """Ekstreden okunmuş TEK işlem satırı (kullanıcı önizlemede düzeltebilir)."""
    date: datetime
    symbol: str = Field(..., min_length=1, max_length=20)
    side: Literal["BUY", "SELL"]
    quantity: float = Field(..., gt=0)
    price: float = Field(..., gt=0)
    commission: float = Field(default=0.0, ge=0)


class StatementPosition(BaseModel):
    """Ekstrenin PORTFÖY ÖZETİ'nden okunmuş tek pozisyon."""
    symbol: str = Field(..., min_length=1, max_length=20)
    quantity: float = Field(..., gt=0)
    avg_cost: float = Field(..., gt=0)


class StatementCommitRequest(BaseModel):
    """Önizlemede onaylananların portföye işlenmesi. İKİ MOD:

    - `positions` (varsayılan): ekstrenin PORTFÖY ÖZETİ'ni yazar. Aracı
      kurumun kendi adet + ortalama maliyet kaydı olduğu için portföy tek
      dosyayla DOĞRU kurulur. Hesap yıllar önce açılmış ve elde yalnız son
      birkaç ayın ekstresi varsa doğru seçim budur.
    - `trades`: YATIRIM İŞLEMLERİ'ni kronolojik oynatır. Ancak hesap
      açılışından itibaren TÜM ekstreler yüklendiyse portföyü doğru kurar;
      eksik dönemde maliyet yanlış çıkar. Davranış analizi için işlem
      geçmişi isteniyorsa kullanılır.
    """
    user_id: int = Field(..., gt=0)
    mode: Literal["positions", "trades"] = "positions"
    rows: list[StatementRow] = Field(default_factory=list, max_length=2000)
    positions: list[StatementPosition] = Field(default_factory=list,
                                               max_length=500)
    positions_as_of: datetime | None = None
