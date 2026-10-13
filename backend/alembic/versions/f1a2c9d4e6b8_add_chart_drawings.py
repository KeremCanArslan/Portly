"""add chart_drawings

Kullanıcı+sembol başına grafik çizim setini (tek JSON blob, timestamp-bazlı)
kalıcı saklar → çizimler uygulama/cihaz değişince kaybolmaz, hesaba bağlı kalır.

Revision ID: f1a2c9d4e6b8
Revises: c3a7e1f4d2b8
Create Date: 2026-06-13 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f1a2c9d4e6b8'
down_revision: Union[str, None] = 'c3a7e1f4d2b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'chart_drawings',
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('symbol', sa.String(), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False),
        sa.Column(
            'updated_at',
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('user_id', 'symbol'),
    )


def downgrade() -> None:
    op.drop_table('chart_drawings')
