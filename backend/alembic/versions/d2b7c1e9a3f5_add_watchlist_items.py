"""add watchlist_items

Kullanıcının izleme listesini (sıralı sembol listesi) hesaba bağlı kalıcı saklar
→ izleme listesi cihaz/tarayıcı değişince veya PWA cache temizlenince kaybolmaz
(önceden yalnız frontend SharedPreferences'taydı).

Revision ID: d2b7c1e9a3f5
Revises: f1a2c9d4e6b8
Create Date: 2026-06-14 20:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd2b7c1e9a3f5'
down_revision: Union[str, None] = 'f1a2c9d4e6b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'watchlist_items',
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('symbol', sa.String(), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False, server_default='0'),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('user_id', 'symbol'),
    )


def downgrade() -> None:
    op.drop_table('watchlist_items')
