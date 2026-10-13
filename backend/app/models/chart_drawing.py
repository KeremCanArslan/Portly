from sqlalchemy import (
    Column, String, Integer, DateTime, JSON, ForeignKey, PrimaryKeyConstraint
)
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.core.database import Base


class ChartDrawing(Base):
    """Kullanıcının bir sembol için kaydettiği grafik çizimleri (tek JSON blob).

    Çizimler (trend/fib/dikdörtgen/yatay-ışın/dikey/not/kanal/pozisyon + yatay
    destek-direnç) önceden YALNIZ PriceChart State'inde BELLEKTE tutuluyordu →
    uygulama kapanınca veya cihaz değişince kayboluyordu. Bu tablo çizim setini
    kullanıcı+sembol başına KALICI saklar (hesaba bağlı; cihazlar arası taşınır).

    payload zamana-dayalı (timestamp) saklanır, bar-INDEX değil: index veri
    penceresine bağlıdır (farklı timeframe/aralık → çizim kayar). Frontend
    kaydederken index→timestamp, yüklerken timestamp→en-yakın-index çevirir
    (PriceChart._remapDrawings ile aynı en-yakın eşleme). Şema (v1):
      {"v":1, "hlines":[fiyat,..],
       "trends":[{ta,pa,tb,pb}], "fibs":[..], "rects":[..],
       "hrays":[{t,p}], "vlines":[ts,..], "notes":[{t,p,text}],
       "channels":[{ta,pa,tb,pb,off}], "positions":[{ta,entry,tb,target,stop}]}
    ta/tb/t = bar timestamp (epoch), p/pa/pb/.. = fiyat.

    Sembol başına TEK satır: frontend çizimleri zaten liste hâlinde State'te
    tutuyor → toptan GET/PUT en yalın eşleme (çizim-başına CRUD karmaşası yok).
    """

    __tablename__ = "chart_drawings"

    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    symbol = Column(String, nullable=False)  # canonical, UPPER
    payload = Column(JSON, nullable=False)
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )

    __table_args__ = (PrimaryKeyConstraint("user_id", "symbol"),)

    user = relationship("User")
