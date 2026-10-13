from sqlalchemy import Column, DateTime, Integer, String
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.core.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String, nullable=True)
    # Risk profili: Muhafazakar / Dengeli / Agresif (nullable — test yapılmamış olabilir)
    risk_profile = Column(String, nullable=True)
    # Kolon sonradan eklendi (göç a7c3e5b19d40) → eski hesaplarda NULL,
    # yani "kayıt tarihi bilinmiyor". Uydurma tarih yazılmadı.
    created_at = Column(DateTime(timezone=True), server_default=func.now(),
                        nullable=True)

    transactions = relationship("Transaction", back_populates="user", cascade="all, delete-orphan")
    portfolio = relationship("Portfolio", back_populates="user", cascade="all, delete-orphan")
    chat_messages = relationship("ChatMessage", back_populates="user", cascade="all, delete-orphan")