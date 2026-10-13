from sqlalchemy import (
    Column, String, Integer, Text, DateTime, ForeignKey, Index
)
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.core.database import Base


class Note(Base):
    """Kullanıcının yatırımcı günlüğü notu — bir hisseye bağlı ya da serbest.

    `symbol` NULL → genel günlük girdisi; dolu → o hisseye ait not (hisse detay +
    behavior ekranına bağlanır). watchlist/chart_drawings'in 'kullanıcı+sembol TEK
    satır' kalıbından FARKLI: bir hisseye zaman içinde BİRDEN ÇOK not yazılabilir
    (günlük/timeline), bu yüzden notun kendi `id` PK'si var. Sembol kanonik (UPPER,
    strip; boş → NULL), price_alert/watchlist/chart_drawing servisleriyle tutarlı.

    `(user_id, symbol)` indeksi hem hisseye-özel listeyi (`symbol=...`) hem genel
    listeyi (yalnız `user_id` — leftmost prefix) hızlandırır.
    """

    __tablename__ = "notes"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    symbol = Column(String, nullable=True)  # canonical UPPER; NULL = genel günlük
    content = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    __table_args__ = (Index("ix_notes_user_symbol", "user_id", "symbol"),)

    user = relationship("User")
