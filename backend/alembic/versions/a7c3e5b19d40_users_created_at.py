"""users.created_at — hesabın ne zaman açıldığı

Tablo bugüne kadar kayıt tarihi tutmuyordu. "Kim ne zaman katıldı" sorusu
ancak `refresh_tokens`'ın en eski satırından TAHMİN edilebiliyordu (rotation
eski satırları iptal ediyor ama silmiyor, yine de tahmin).

MEVCUT satırlar NULL kalır — bilinmeyen bir tarihi uydurmaktansa "bilinmiyor"
demek dürüst. Yeni kayıtlar sunucu saatiyle dolar.

Revision ID: a7c3e5b19d40
Revises: d1f6a3c8b924
Create Date: 2026-09-07

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'a7c3e5b19d40'
down_revision: Union[str, None] = 'd1f6a3c8b924'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.text("now()"), nullable=True),
    )
    # server_default yeni satırları doldurur; eski satırlar Postgres'te
    # varsayılanla DOLDURULUR (ALTER TABLE ... DEFAULT geriye yazar), o yüzden
    # onları açıkça NULL'a çekiyoruz: göç anını "kayıt tarihi" diye göstermek
    # yanlış veri olurdu.
    op.execute("UPDATE users SET created_at = NULL")


def downgrade() -> None:
    op.drop_column("users", "created_at")
