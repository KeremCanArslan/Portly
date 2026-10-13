"""pivot: sanal borsa katmanını kaldır (pending_orders + users.balance)

Uygulama sanal borsa simülatöründen portföy takip + haber + sinyal
asistanına dönüştü (49. tur pivot). Sanal emir motoru (pending_orders:
limit/SL/TP/OCO/bracket) ve sanal nakit (users.balance) kaldırıldı.
İşlem kayıtları (transactions) KALIR — kayıt defteri semantiği.

Revision ID: a7c3e9f1b5d2
Revises: f4a9c2b7d1e3
Create Date: 2026-07-04

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a7c3e9f1b5d2'
down_revision: Union[str, None] = 'f4a9c2b7d1e3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_index('ix_pending_status_symbol', table_name='pending_orders')
    op.drop_index(op.f('ix_pending_orders_user_id'), table_name='pending_orders')
    op.drop_index(op.f('ix_pending_orders_symbol'), table_name='pending_orders')
    op.drop_index(op.f('ix_pending_orders_id'), table_name='pending_orders')
    op.drop_table('pending_orders')
    op.drop_column('users', 'balance')


def downgrade() -> None:
    op.add_column('users', sa.Column('balance', sa.Float(), nullable=True,
                                     server_default='100000.0'))
    op.create_table(
        'pending_orders',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('symbol', sa.String(), nullable=False),
        sa.Column('side', sa.String(), nullable=False),
        sa.Column('quantity', sa.Float(), nullable=False),
        sa.Column('limit_price', sa.Float(), nullable=False),
        sa.Column('status', sa.String(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=True),
        sa.Column('filled_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('filled_price', sa.Float(), nullable=True),
        # b48806822728 + f4a9c2b7d1e3 kolonları (order_kind + bracket/OCO)
        sa.Column('order_kind', sa.String(), nullable=False,
                  server_default='LIMIT'),
        sa.Column('sl_price', sa.Float(), nullable=True),
        sa.Column('tp_price', sa.Float(), nullable=True),
        sa.Column('parent_order_id', sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_pending_orders_id'), 'pending_orders', ['id'], unique=False)
    op.create_index(op.f('ix_pending_orders_symbol'), 'pending_orders', ['symbol'], unique=False)
    op.create_index(op.f('ix_pending_orders_user_id'), 'pending_orders', ['user_id'], unique=False)
    op.create_index('ix_pending_status_symbol', 'pending_orders', ['status', 'symbol'], unique=False)
