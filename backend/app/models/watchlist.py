from sqlalchemy import (
    Column, String, Integer, DateTime, ForeignKey, PrimaryKeyConstraint
)
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.core.database import Base


class WatchlistItem(Base):
    """Kullanıcının izleme listesindeki bir sembol (sıralı).

    İzleme listesi önceden YALNIZ frontend SharedPreferences'ta
    ('watchlist_<userId>') tutuluyordu → cihaz/tarayıcı değişince ya da PWA
    cache temizlenince kayboluyordu. Bu tablo listeyi kullanıcıya bağlar
    (cihazlar arası senkron; [[chart_drawings]] ile aynı gerekçe).

    Sembol başına TEK satır: PK (user_id, symbol) doğal tekillik sağlar → aynı
    sembol iki kez eklenemez (idempotent add). `position` listedeki sırayı korur
    (drag-to-reorder); okuma position'a göre sıralanır. Sembol kanonik (UPPER),
    chart_drawing/price_alert servisleriyle tutarlı.
    """

    __tablename__ = "watchlist_items"

    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    symbol = Column(String, nullable=False)  # canonical, UPPER
    position = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (PrimaryKeyConstraint("user_id", "symbol"),)

    user = relationship("User")
