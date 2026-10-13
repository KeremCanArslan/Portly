from sqlalchemy import Column, String, DateTime, JSON
from app.core.database import Base


class DividendCache(Base):
    """Sembol başına temettü serisi — KALICI cache (DB).

    `dividend_service._div_cache` yalnız süreç-bellekteydi; Render free
    instance uyuyup uyandığında veya her deploy/restart'ta sıfırlanıyordu →
    temettü ekranı HER oturumda soğuk açılıp sembol başına ~1-3s yfinance
    çekiyordu. Bu tablo seriyi DB'ye kalıcı yazar: süreç yeniden başlasa bile
    ilk çekimden sonra ekran anında açılır. Ayrıca yfinance anlık başarısız
    olursa (Render'da Yahoo zaman zaman boş döner — bkz. yf_session.py)
    bayat veri "boş portföy"den iyidir, geri düşülür.

    payload: {"divs": [[iso_tarih, tutar], ...], "cal_ex": "YYYY-MM-DD"|null}
    """

    __tablename__ = "dividend_cache"

    symbol = Column(String, primary_key=True)  # canonical, UPPER
    fetched_at = Column(DateTime(timezone=True), nullable=False)
    payload = Column(JSON, nullable=False)
