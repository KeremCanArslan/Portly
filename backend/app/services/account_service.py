# =============================================================================
# Hesap silme (KVKK / GDPR "unutulma hakkı")
#
# Uygulamada hesabı kapatmanın hiçbir yolu yoktu; dışarıdan gerçek kullanıcılar
# gelince bu bir eksiklik değil, yükümlülük oldu. Silme GERÇEK silmedir:
# "pasife çekme" değil, satırların kendisi gider.
#
# Alt satırlar AÇIKÇA siliniyor. Göç (b8d4f6c2a713) yabancı anahtarlara
# ON DELETE CASCADE koydu ama tek dayanak o olmasın: veritabanı bir gün başka
# bir ortamda (SQLite testi, yeni kurulum) cascade'siz açılırsa kullanıcı
# silinir ama portföyü yetim kalırdı — sessiz veri sızıntısı.
# =============================================================================
from fastapi import HTTPException
from loguru import logger
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.models.user import User
from app.services import auth_service

# Silme sırası: önce kullanıcıya bağlı her şey, en son kullanıcı.
_CHILD_TABLES = (
    "chart_drawings",
    "chat_messages",
    "notes",
    "price_alerts",
    "portfolios",
    "refresh_tokens",
    "transactions",
    "watchlist_items",
)


def delete_account(db: Session, user: User, password: str) -> dict:
    """Kullanıcıyı ve ona ait TÜM kayıtları siler.

    Şifre doğrulaması ŞART: erişim token'ı ele geçiren biri hesabı
    silememeli (geri dönüşü yok).
    """
    if not auth_service.verify_password(password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Şifre yanlış")

    user_id = user.id
    email = user.email
    silinen: dict[str, int] = {}

    try:
        for table in _CHILD_TABLES:
            result = db.execute(
                text(f"DELETE FROM {table} WHERE user_id = :uid"),  # noqa: S608
                {"uid": user_id},
            )
            if result.rowcount:
                silinen[table] = result.rowcount
        db.execute(text("DELETE FROM users WHERE id = :uid"), {"uid": user_id})
        db.commit()
    except Exception as exc:
        db.rollback()
        logger.error(f"Hesap silinemedi (user_id={user_id}): {exc}")
        raise HTTPException(
            status_code=500,
            detail="Hesap silinemedi. Bir şey ters gitti, tekrar dene.")

    # E-posta loglanmaz (silinen kişinin verisi logda yaşamasın); yalnız id.
    logger.info(f"Hesap silindi (user_id={user_id}, kayıt={silinen})")
    del email
    return {"detail": "Hesabın ve tüm verilerin silindi", "deleted": silinen}
