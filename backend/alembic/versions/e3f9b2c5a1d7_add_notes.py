"""add notes

Yatırımcı günlüğü: kullanıcının hisseye bağlı veya serbest (genel) notları. Bir
hisseye zaman içinde birden çok not yazılabildiği için notun kendi `id` PK'si var
(watchlist/chart_drawings'in 'kullanıcı+sembol tek satır' kalıbından farklı).
`symbol` NULL → genel günlük girdisi. `(user_id, symbol)` indeksi hisseye-özel ve
genel listeleri (leftmost prefix) hızlandırır.

Revision ID: e3f9b2c5a1d7
Revises: d2b7c1e9a3f5
Create Date: 2026-06-15 13:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e3f9b2c5a1d7'
down_revision: Union[str, None] = 'd2b7c1e9a3f5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'notes',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('symbol', sa.String(), nullable=True),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=True,
        ),
        sa.Column(
            'updated_at',
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=True,
        ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_notes_user_symbol', 'notes', ['user_id', 'symbol'])


def downgrade() -> None:
    op.drop_index('ix_notes_user_symbol', table_name='notes')
    op.drop_table('notes')
