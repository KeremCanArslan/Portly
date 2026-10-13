"""Kullanıcıya bağlı 8 tabloda ON DELETE CASCADE

Uygulamada "hesabımı sil" yolu yoktu ve veritabanı da silmeye izin vermiyordu:
`users`'a bakan 8 yabancı anahtarın hepsi NO ACTION'dı → bir kullanıcı satırını
silmek yabancı anahtar hatası veriyordu. Artık dışarıdan gerçek kullanıcılar
var; KVKK'da silme hakkı zorunlu.

ORM tarafında `cascade="all, delete-orphan"` YALNIZ üç ilişkide (transactions,
portfolio, chat_messages) tanımlı; kalan beş tablo (notes, price_alerts,
watchlist_items, chart_drawings, refresh_tokens) uygulama silse bile yetim
kalırdı. Kural veritabanına yazılıyor ki hangi yoldan silinirse silinsin
(servis, psql, ileride bir yönetim aracı) artık kayıt kalmasın.

Servis yine de alt satırları AÇIKÇA siliyor (`account_service.delete_account`)
— bu göç savunmanın ikinci katmanı, tek dayanak değil.

Revision ID: b8d4f6c2a713
Revises: a7c3e5b19d40
Create Date: 2026-09-07

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'b8d4f6c2a713'
down_revision: Union[str, None] = 'a7c3e5b19d40'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# (kısıt adı, tablo)
_FKS = [
    ("chart_drawings_user_id_fkey", "chart_drawings"),
    ("chat_messages_user_id_fkey", "chat_messages"),
    ("notes_user_id_fkey", "notes"),
    ("portfolios_user_id_fkey", "portfolios"),
    ("price_alerts_user_id_fkey", "price_alerts"),
    ("refresh_tokens_user_id_fkey", "refresh_tokens"),
    ("transactions_user_id_fkey", "transactions"),
    ("watchlist_items_user_id_fkey", "watchlist_items"),
]


def upgrade() -> None:
    for name, table in _FKS:
        op.drop_constraint(name, table, type_="foreignkey")
        op.create_foreign_key(name, table, "users", ["user_id"], ["id"],
                              ondelete="CASCADE")


def downgrade() -> None:
    for name, table in _FKS:
        op.drop_constraint(name, table, type_="foreignkey")
        op.create_foreign_key(name, table, "users", ["user_id"], ["id"])
