"""portfolios(user_id, symbol) benzersiz kısıtı + mevcut çift satırların birleştirilmesi

Bir kullanıcının bir sembolden TEK pozisyon satırı olmalı; lotlar ağırlıklı
ortalama maliyetle birleşir. Uygulama katmanı bunu zaten varsayıyordu ama
veritabanı garanti etmiyordu: satır henüz YOKKEN aynı anda gelen iki alış
isteği (yavaş bağlantıda çift dokunuş) iki ayrı satır yaratabiliyordu →
portföyde aynı sembol iki kez, toplam değer ve ağırlıklar bozuk.

Kısıt eklenmeden ÖNCE varsa mevcut çiftler birleştirilir; aksi halde
migration canlıda hata verir ve konteyner hiç ayağa kalkmaz (Dockerfile
`alembic upgrade head && uvicorn` zincirini koşuyor). Birleştirme kayıpsız:
adetler toplanır, maliyet adetle ağırlıklandırılır, fazla satırlar silinir.

Revision ID: c9e4b1a8f7d2
Revises: b7d1f4c2e8a9
Create Date: 2026-09-03

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c9e4b1a8f7d2'
down_revision: Union[str, None] = 'b7d1f4c2e8a9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_CONSTRAINT = "uq_portfolio_user_symbol"


def _merge_duplicates(bind) -> None:
    """Aynı (user_id, symbol) satırlarını en küçük id'de birleştirir."""
    dupes = bind.execute(sa.text(
        "SELECT user_id, symbol FROM portfolios "
        "GROUP BY user_id, symbol HAVING COUNT(*) > 1"
    )).fetchall()
    for user_id, symbol in dupes:
        rows = bind.execute(sa.text(
            "SELECT id, quantity, average_cost FROM portfolios "
            "WHERE user_id = :u AND symbol = :s ORDER BY id"
        ), {"u": user_id, "s": symbol}).fetchall()
        total_qty = sum(float(r[1] or 0) for r in rows)
        # Ağırlıklı ortalama maliyet; adet toplamı sıfırsa (bozuk kayıt)
        # ilk satırın maliyeti korunur, satır kullanıcıda kalır.
        if total_qty > 0:
            avg_cost = sum(float(r[1] or 0) * float(r[2] or 0)
                           for r in rows) / total_qty
        else:
            avg_cost = float(rows[0][2] or 0)
        keep_id = rows[0][0]
        bind.execute(sa.text(
            "UPDATE portfolios SET quantity = :q, average_cost = :c "
            "WHERE id = :i"
        ), {"q": total_qty, "c": avg_cost, "i": keep_id})
        for row in rows[1:]:
            bind.execute(sa.text("DELETE FROM portfolios WHERE id = :i"),
                         {"i": row[0]})


def upgrade() -> None:
    bind = op.get_bind()
    _merge_duplicates(bind)
    with op.batch_alter_table("portfolios") as batch:
        batch.create_unique_constraint(_CONSTRAINT, ["user_id", "symbol"])


def downgrade() -> None:
    with op.batch_alter_table("portfolios") as batch:
        batch.drop_constraint(_CONSTRAINT, type_="unique")
