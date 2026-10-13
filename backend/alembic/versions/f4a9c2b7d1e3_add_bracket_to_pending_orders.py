"""add bracket (sl/tp/parent) to pending_orders

44. tur — LIMIT BUY bracket: emir dolunca otomatik koruma. Parent LIMIT emirde
`sl_price`/`tp_price` hedefleri tutulur; emir dolunca bunlardan STOP_LOSS/
TAKE_PROFIT SELL çocuk emirleri kurulur ve `parent_order_id` ile bağlanır
(OCO: biri dolunca kardeşi iptal edilir). Üç kolon da nullable → additive,
mevcut satırları etkilemez, güvenli.

Revision ID: f4a9c2b7d1e3
Revises: e3f9b2c5a1d7
Create Date: 2026-06-18 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f4a9c2b7d1e3'
down_revision: Union[str, None] = 'e3f9b2c5a1d7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('pending_orders', sa.Column('sl_price', sa.Float(), nullable=True))
    op.add_column('pending_orders', sa.Column('tp_price', sa.Float(), nullable=True))
    op.add_column('pending_orders', sa.Column('parent_order_id', sa.Integer(), nullable=True))
    op.create_index(
        'ix_pending_orders_parent_order_id', 'pending_orders', ['parent_order_id'])
    op.create_foreign_key(
        'fk_pending_orders_parent_order_id', 'pending_orders', 'pending_orders',
        ['parent_order_id'], ['id'], ondelete='SET NULL')


def downgrade() -> None:
    op.drop_constraint(
        'fk_pending_orders_parent_order_id', 'pending_orders', type_='foreignkey')
    op.drop_index('ix_pending_orders_parent_order_id', table_name='pending_orders')
    op.drop_column('pending_orders', 'parent_order_id')
    op.drop_column('pending_orders', 'tp_price')
    op.drop_column('pending_orders', 'sl_price')
