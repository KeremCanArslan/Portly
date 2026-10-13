from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.core.database import Base


class PriceAlert(Base):
    """Kullanıcı fiyat alarmı.

    direction='ABOVE': fiyat threshold'un üstüne çıkınca tetiklenir.
    direction='BELOW': fiyat threshold'un altına düşünce tetiklenir.
    notify_email=True ise SMTP üzerinden mail gider.
    """

    __tablename__ = "price_alerts"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    symbol = Column(String, nullable=False, index=True)
    threshold_price = Column(Float, nullable=False)
    direction = Column(String, nullable=False)  # ABOVE / BELOW
    notify_email = Column(Boolean, default=True, nullable=False)
    active = Column(Boolean, default=True, nullable=False)
    # Tetiklenen alarmı kullanıcı uygulama içinde gördü mü? Tetik anında False
    # kalır → uygulama-içi "okunmamış" rozeti bunu sayar (e-posta teslimatından
    # bağımsız). Kullanıcı alarm ekranını açınca True yapılır.
    acknowledged = Column(Boolean, default=False, nullable=False)
    triggered_at = Column(DateTime(timezone=True), nullable=True)
    triggered_price = Column(Float, nullable=True)
    note = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User")
