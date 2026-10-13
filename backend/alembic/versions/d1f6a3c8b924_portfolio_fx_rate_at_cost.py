"""portfolios.fx_rate_at_cost + mevcut pozisyonların alış kuruyla doldurulması

Yabancı (USD) varlıkların ₺ maliyeti BUGÜNKÜ kurla hesaplanıyordu. Kur
yükselince maliyet de aynı oranda büyüdüğü için kurdan gelen reel kâr ₺ K/Z'de
HİÇ görünmüyordu: bir yıl önce alınmış 100$'lık hisse, kur 39'dan 48'e çıksa
bile "kur kazancı yok" gibi raporlanıyordu.

Kolon, maliyetin oluştuğu andaki USDTRY kurunu (lotların native maliyetiyle
ağırlıklı ortalaması) tutar. TRY varlıkta (BIST/.FON) anlamsız → NULL.

Backfill: her USD pozisyonu için kullanıcının o sembboldeki BUY işlemleri
(`transactions`) okunur, her işlemin GÜNÜNDEKİ kur `fx_service.usdtry_rate_on`
ile alınır ve native maliyetle ağırlıklandırılır. Kaynak frankfurter (ECB,
anahtarsız) — Yahoo bilerek kullanılmaz, Render IP'si zaten kısıtlı.

Ağ erişilemezse migration ÇÖKMEZ: kur alınamayan pozisyon NULL kalır ve eski
davranışa (canlı kur) düşer. Kolon eklendikten sonra `alembic upgrade head`
tekrar koşturulmaz; eksik kalanlar için `scripts` yerine yeni bir alış kaydı
ya da elle güncelleme gerekir (pratikte tümü doluyor).

Revision ID: d1f6a3c8b924
Revises: c9e4b1a8f7d2
Create Date: 2026-09-03

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd1f6a3c8b924'
down_revision: Union[str, None] = 'c9e4b1a8f7d2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _backfill(bind) -> None:
    from loguru import logger
    from app.services import fx_service

    rows = bind.execute(sa.text(
        "SELECT id, user_id, symbol, quantity, average_cost FROM portfolios"
    )).fetchall()

    filled = skipped = 0
    for pid, user_id, symbol, quantity, average_cost in rows:
        if fx_service.currency_of(symbol) == "TRY":
            continue  # ₺ varlıkta kur anlamsız

        buys = bind.execute(sa.text(
            "SELECT quantity, price, timestamp FROM transactions "
            "WHERE user_id = :u AND symbol = :s AND transaction_type = 'BUY' "
            "ORDER BY timestamp"
        ), {"u": user_id, "s": symbol}).fetchall()

        weighted = native = 0.0
        for qty, price, ts in buys:
            lot = float(qty or 0) * float(price or 0)
            if lot <= 0 or ts is None:
                continue
            rate = fx_service.usdtry_rate_on(ts)
            if not rate:
                continue
            weighted += lot * rate
            native += lot

        if native <= 0:
            # Alış kaydı yok (kolon öncesi elle yazılmış satır) ya da kur
            # alınamadı → NULL bırak, eski davranış sürsün.
            skipped += 1
            continue

        bind.execute(sa.text(
            "UPDATE portfolios SET fx_rate_at_cost = :r WHERE id = :i"
        ), {"r": weighted / native, "i": pid})
        filled += 1

    logger.info(f"fx_rate_at_cost backfill: dolduruldu={filled} atlandı={skipped}")


def upgrade() -> None:
    op.add_column("portfolios",
                  sa.Column("fx_rate_at_cost", sa.Float(), nullable=True))
    try:
        _backfill(op.get_bind())
    except Exception as exc:  # ağ/kaynak hatası deploy'u düşürmesin
        from loguru import logger
        logger.warning(f"fx_rate_at_cost backfill atlandı: {exc}")


def downgrade() -> None:
    op.drop_column("portfolios", "fx_rate_at_cost")
