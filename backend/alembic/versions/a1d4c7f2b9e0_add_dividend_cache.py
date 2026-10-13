"""add dividend_cache

Sembol başına temettü serisini DB'ye kalıcı yazar → süreç restart/sleep
sonrası temettü ekranı soğuk yfinance çekmeden anında açılır.

Revision ID: a1d4c7f2b9e0
Revises: e8f8c8611151
Create Date: 2026-06-03 19:20:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1d4c7f2b9e0'
down_revision: Union[str, None] = 'e8f8c8611151'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'dividend_cache',
        sa.Column('symbol', sa.String(), nullable=False),
        sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=False),
        sa.PrimaryKeyConstraint('symbol'),
    )


def downgrade() -> None:
    op.drop_table('dividend_cache')
