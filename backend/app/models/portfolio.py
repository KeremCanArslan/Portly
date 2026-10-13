from sqlalchemy import Column, Integer, String, Float, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from app.core.database import Base

class Portfolio(Base):
    __tablename__ = "portfolios"

    # Bir kullanıcının bir sembolden TEK satırı olur (lotlar ağırlıklı ortalama
    # maliyetle birleşir). Kısıt veritabanı seviyesinde: eşzamanlı iki alış
    # isteği satır henüz yokken yarışırsa ikinci INSERT reddedilir ve
    # order_service birleştirmeye düşer (bkz. _merge_buy_lot).
    __table_args__ = (
        UniqueConstraint("user_id", "symbol", name="uq_portfolio_user_symbol"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    symbol = Column(String, index=True, nullable=False)
    quantity = Column(Float, default=0.0)
    average_cost = Column(Float, default=0.0)
    # Maliyetin oluştuğu ANDAKİ USDTRY kuru (native maliyetle ağırlıklı
    # ortalaması). ₺ maliyet bununla hesaplanır; canlı kurla değil — yoksa
    # kurdan gelen reel kâr K/Z'de hiç görünmez (maliyet de kurla birlikte
    # büyüyüp farkı sıfırlar). TRY varlıkta (BIST/.FON) anlamsız → NULL.
    # NULL = kur bilinmiyor → eski davranış (canlı kur) uygulanır.
    fx_rate_at_cost = Column(Float, nullable=True)

    user = relationship("User", back_populates="portfolio")
