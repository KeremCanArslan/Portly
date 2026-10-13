"""TEFAS fon kodlarını .IS'ten .FON'a taşı (TLY.IS → TLY.FON)

Ekstre içe aktarımı, kur TRY olduğu için HER sembole ".IS" ekliyordu; TEFAS
yatırım fonu kodları (TLY, LTL) da böyle BIST hissesi sanılıp Yahoo'da
aranıyor, bulunamıyordu → pozisyon "Fiyat —" görünüyor, sinyal taramasında
başarısızlar listesine düşüyor, portföy değeri maliyetle sayılıyordu.
Fonun fiyat kaynağı artık TEFAS (`fund_source_service`) ve sembol biçimi
".FON" (`fund_catalog`).

Göç AĞA ÇIKMAZ: fon kodları yerel katalogdan (app/data/tefas_funds.json)
okunur. Yalnız ÜÇ harfli kodlara dokunur — TEFAS fon kodları daima 3 harf,
BIST pay kodları 4-5 harftir, çakışma yok. Çıplak (soneksiz) kodlara ASLA
dokunmaz: "URA" hem bir TEFAS fonu hem Global X Uranium ETF'idir.

Revision ID: b7d1f4c2e8a9
Revises: a7c3e9f1b5d2
Create Date: 2026-09-02

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b7d1f4c2e8a9'
down_revision: Union[str, None] = 'a7c3e9f1b5d2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Sembol taşıyan tablolar. `dividend_cache` KASTEN yok: orası salt cache,
# üstelik symbol birincil anahtar → çakışma riski var; fonun temettüsü de
# olmadığı için satır zaten anlamsız, kendiliğinden bayatlar.
_TABLES = ("portfolios", "transactions", "watchlist_items",
           "price_alerts", "notes", "chart_drawings")


def _fund_codes() -> set[str]:
    from app.services import fund_catalog
    return {c for c in fund_catalog.CATALOG if len(c) == 3}


def _table_exists(bind, name: str) -> bool:
    return sa.inspect(bind).has_table(name)


def _move(old_suffix: str, new_suffix: str) -> None:
    bind = op.get_bind()
    codes = _fund_codes()
    if not codes:
        return
    for table in _TABLES:
        if not _table_exists(bind, table):
            continue
        rows = bind.execute(sa.text(
            f"SELECT DISTINCT symbol FROM {table} WHERE symbol LIKE :pat"
        ), {"pat": f"___{old_suffix}"}).fetchall()
        for (symbol,) in rows:
            base = symbol[:3].upper()
            if base not in codes:
                continue
            bind.execute(
                sa.text(f"UPDATE {table} SET symbol = :new WHERE symbol = :old"),
                {"new": f"{base}{new_suffix}", "old": symbol})


def upgrade() -> None:
    _move(".IS", ".FON")


def downgrade() -> None:
    _move(".FON", ".IS")
