from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.core.config import settings

# Neon (serverless Postgres) boşta kalınca compute'u askıya alır ve idle bağlantıları
# kapatır. pre_ping her checkout'ta bağlantıyı doğrular (ölüyse atıp yenisini açar) →
# Neon uyanır, sorgu 500 yerine sorunsuz devam eder. Bu olmadan havuzdaki çürük
# bağlantı tekrar tekrar kullanılıp tüm DB uçlarını 500'letiyordu.
_engine_kwargs = {"pool_pre_ping": True}
# SQLite'a özgü connect_args sadece sqlite:// URL'de gerekli; PostgreSQL'de yanlış parametre hatası verir.
if settings.DATABASE_URL.startswith("sqlite"):
    _engine_kwargs["connect_args"] = {"check_same_thread": False}
else:
    # 5 dk'dan eski bağlantıyı proaktif tazele (Neon idle-suspend eşiğiyle uyumlu).
    _engine_kwargs["pool_recycle"] = 300

engine = create_engine(settings.DATABASE_URL, **_engine_kwargs)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()