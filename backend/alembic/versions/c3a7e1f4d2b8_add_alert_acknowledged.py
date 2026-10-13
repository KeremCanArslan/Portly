"""add acknowledged to price_alerts

Tetiklenen alarmın kullanıcı tarafından uygulama içinde görülüp görülmediğini
izler. Uygulama-içi "okunmamış alarm" rozeti bunu sayar → e-posta teslimatı
(SMTP) yapılandırılmamış olsa bile tetiklenen alarm görünür olur.

Mevcut satırlar için server_default=false (eski tetiklenmiş alarmlar
"okunmamış" görünmesin diye sonradan UPDATE ile True'ya çekilebilir; demoda
önemsiz — varsayılan güvenli).

Revision ID: c3a7e1f4d2b8
Revises: a1d4c7f2b9e0
Create Date: 2026-06-05 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c3a7e1f4d2b8'
down_revision: Union[str, None] = 'a1d4c7f2b9e0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'price_alerts',
        sa.Column('acknowledged', sa.Boolean(), nullable=False,
                  server_default=sa.false()),
    )


def downgrade() -> None:
    op.drop_column('price_alerts', 'acknowledged')
