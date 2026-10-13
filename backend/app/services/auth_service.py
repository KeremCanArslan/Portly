from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from app.models.user import User
from app.schemas.user_schema import UserCreate
from app.core.database import get_db
from app.core.config import settings
import bcrypt
import pyotp
import qrcode
import base64
import secrets
import hashlib
from io import BytesIO
from loguru import logger
from app.core import cache
from app.models.refresh_token import RefreshToken

ALGORITHM = "HS256"
# Access token kısa, refresh token uzun. Refresh çalınırsa server-side iptal edilebilir.
ACCESS_TOKEN_EXPIRE_MINUTES = 60
REFRESH_TOKEN_EXPIRE_DAYS = 30

security = HTTPBearer()

# ── Oturum durumu PAYLAŞILAN cache'te ──────────────────────────────────
# Logout blacklist'i ve şifre-sıfırlama kodları eskiden süreç belleğindeydi
# (set + dict). İki sorun: (1) süreç her yeniden başladığında — Render'da her
# deploy ve her uyanış — logout edilmiş token'lar yeniden GEÇERLİ oluyor,
# kullanıcının bekleyen sıfırlama kodu kayboluyordu; (2) ileride birden fazla
# worker açılırsa durum worker'lar arasında paylaşılmazdı. Artık app.core.cache
# (REDIS_URL varsa Redis, yoksa süreç-içi sözlük — limiter/cache ile aynı
# graceful-fallback deseni).
_BLACKLIST_PREFIX = "auth:bl:"
_RESET_PREFIX = "auth:reset:"


def _blacklist_key(token: str) -> str:
    # Ham bearer token cache'e YAZILMAZ; sızıntı durumunda kullanılabilir olurdu.
    return _BLACKLIST_PREFIX + hashlib.sha256(token.encode("utf-8")).hexdigest()


def blacklist_token(token: str) -> None:
    # TTL = access token ömrü: token en fazla bu kadar süre daha geçerli
    # olabileceğinden kayıt daha uzun tutulsa boşuna yer kaplar.
    cache.set(_blacklist_key(token), True, ttl=ACCESS_TOKEN_EXPIRE_MINUTES * 60)


def is_token_blacklisted(token: str) -> bool:
    return cache.get(_blacklist_key(token)) is not None


# Şifre sıfırlama kodları. Kayıt: {code, expires, attempts}.
RESET_CODE_TTL_MINUTES = 15
# 6 haneli kod 1.000.000 olasılık; deneme sınırı olmadan uç, hız sınırının
# izin verdiği kadar denenebilirdi. Üç hatadan sonra kod tamamen silinir —
# kullanıcı yeni kod ister.
RESET_CODE_MAX_ATTEMPTS = 3


def _reset_key(email: str) -> str:
    return _RESET_PREFIX + email.lower()


def create_password_reset_code(email: str) -> str:
    code = f"{secrets.randbelow(1_000_000):06d}"
    ttl = RESET_CODE_TTL_MINUTES * 60
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=ttl)
    cache.set(
        _reset_key(email),
        {"code": code, "expires": expires_at.timestamp(), "attempts": 0},
        ttl=ttl,
    )
    return code


def verify_password_reset_code(email: str, code: str) -> bool:
    key = _reset_key(email)
    hit = cache.get(key)
    if hit is None:
        return False
    record = hit[0]
    if not isinstance(record, dict):  # pragma: no cover — eski/bozuk kayıt
        cache.delete(key)
        return False

    if datetime.now(timezone.utc).timestamp() > float(record.get("expires", 0)):
        cache.delete(key)
        return False

    if secrets.compare_digest(str(record.get("code", "")), code):
        return True

    # Hatalı deneme — sayacı artır, sınırı aşınca kodu tamamen düşür.
    attempts = int(record.get("attempts", 0)) + 1
    if attempts >= RESET_CODE_MAX_ATTEMPTS:
        cache.delete(key)
        logger.warning(
            f"Şifre sıfırlama kodu {RESET_CODE_MAX_ATTEMPTS} hatalı denemeden "
            f"sonra iptal edildi (email={email.lower()})"
        )
    else:
        record["attempts"] = attempts
        remaining = max(
            1, int(float(record["expires"]) - datetime.now(timezone.utc).timestamp()))
        cache.set(key, record, ttl=remaining)
    return False


def consume_password_reset_code(email: str) -> None:
    cache.delete(_reset_key(email))


def _hash_refresh_token(raw: str) -> str:
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def create_refresh_token(db: Session, user_id: int) -> str:
    """Yeni refresh token üretir, hash'ini DB'ye kaydeder, ham değeri döndürür."""
    raw = secrets.token_urlsafe(48)
    record = RefreshToken(
        user_id=user_id,
        token_hash=_hash_refresh_token(raw),
        expires_at=datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
    )
    db.add(record)
    db.commit()
    return raw


def verify_and_rotate_refresh_token(db: Session, raw_token: str) -> tuple[User, str] | None:
    """Refresh token'ı doğrular, eskisini iptal eder, yeni access+refresh için kullanıcıyı döner.

    Token rotation: aynı refresh token iki kez kullanılamaz. Aşırı güvenli olmasa da
    çalınan token'ın etkisini sınırlar.
    """
    token_hash = _hash_refresh_token(raw_token)
    record = db.query(RefreshToken).filter(RefreshToken.token_hash == token_hash).first()
    if not record or record.revoked:
        return None
    expires_at = record.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at < datetime.now(timezone.utc):
        return None
    user = db.query(User).filter(User.id == record.user_id).first()
    if not user:
        return None

    # Rotation ATOMİK: iptal, "henüz iptal edilmemiş" koşuluyla doğrudan
    # veritabanında yapılır. Yukarıdaki `record.revoked` okuması ile buradaki
    # yazma arasında rakip bir istek aynı token'ı kullanmış olabilir; koşullu
    # UPDATE'te satırı yalnız BİRİ günceller (rowcount 1), diğeri 0 alır ve
    # reddedilir. Böylece çalınan bir refresh token ikinci kez kullanılamaz.
    rotated = db.query(RefreshToken).filter(
        RefreshToken.id == record.id,
        RefreshToken.revoked == False,  # noqa: E712 — SQLAlchemy karşılaştırma
    ).update({"revoked": True}, synchronize_session=False)
    db.commit()
    if not rotated:
        logger.warning(
            f"Refresh token ikinci kez kullanılmaya çalışıldı (user={user.id})")
        return None

    new_raw = create_refresh_token(db, user.id)
    return user, new_raw


def revoke_user_refresh_tokens(db: Session, user_id: int) -> None:
    db.query(RefreshToken).filter(
        RefreshToken.user_id == user_id,
        RefreshToken.revoked == False,  # noqa: E712 — SQLAlchemy karşılaştırma
    ).update({"revoked": True})
    db.commit()


# düz şifreyi kaydetmiyoruz, bcrypt ile hashliyoruz
# bcrypt otomatik salt ekliyor, ayrıca salt tutmak gerekmez
def get_password_hash(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


# login sırasında şifre kontrolü buradan yapılıyor
def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))


# yeni kullanıcı oluştur
def create_user(db: Session, user: UserCreate):
    hashed_password = get_password_hash(user.password)
    db_user = User(
        email=user.email,
        hashed_password=hashed_password,
        full_name=user.full_name,
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user


# mail ve şifre doğru mu diye kontrol et, ikisi de tutmalı
def authenticate_user(db: Session, email: str, password: str):
    user = db.query(User).filter(User.email == email).first()
    if not user or not verify_password(password, user.hashed_password):
        return None
    return user


# JWT token üret, içine user_id koy
def create_access_token(data: dict, expires_delta: timedelta | None = None):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=ALGORITHM)


# 2FA - henüz aktif değil, ileride login flow'a eklenecek
# QR kodu base64 olarak frontend'e gönderiyoruz
# TODO: login endpoint'ine 2FA doğrulama adımı ekle
def generate_2fa_secret(user_email: str) -> dict:
    secret = pyotp.random_base32()
    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=user_email, issuer_name="Portly")

    # QR code oluştur (base64 olarak frontend'e gönder)
    qr = qrcode.make(uri)
    buf = BytesIO()
    qr.save(buf, format='PNG')
    qr_b64 = base64.b64encode(buf.getvalue()).decode()

    return {
        "secret": secret,
        "qr_code": f"data:image/png;base64,{qr_b64}",
        "uri": uri,
    }


# 2FA kodu geçerli mi? valid_window=1 yani 30 saniyelik tolerans var
def verify_2fa(secret: str, code: str) -> bool:
    totp = pyotp.TOTP(secret)
    return totp.verify(code, valid_window=1)


# her korumalı endpoint'te çağrılıyor - token'dan user_id çıkar, DB'den kullanıcıyı getir
def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Geçersiz veya süresi dolmuş token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    token = credentials.credentials
    if is_token_blacklisted(token):
        raise credentials_exception
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise credentials_exception
        user_id_int = int(user_id)
    except (JWTError, ValueError, TypeError):
        raise credentials_exception

    # token geçerli ama kullanıcı silinmiş olabilir
    user = db.query(User).filter(User.id == user_id_int).first()
    if user is None:
        raise credentials_exception
    return user


# ── Yeni şifre politikası ────────────────────────────────────────────────
# Uygulamayı artık dışarıdan gerçek kullanıcılar kullanıyor. Tek koruma
# uzunluk olsaydı "123456" kabul edilirdi ve giriş ucundaki dakikada 5 deneme
# limiti böyle bir şifreyi uzun vadede korumaz. Kural YALNIZ yeni/değiştirilen
# şifrelere uygulanır — mevcut kullanıcılar girişte kilitlenmez.
MIN_PASSWORD_LENGTH = 8

# Türkiye'de ve genelde en çok denenen şifreler (sızıntı listelerinin tepesi).
# Uzun bir sözlük tutmanın anlamı yok: saldırgan sıralı denemede bunlarla
# başlar, geri kalanı zaten uzunluk + oran sınırı ile pahalı hale gelir.
_COMMON_PASSWORDS = {
    "12345678", "123456789", "1234567890", "password", "password1",
    "qwerty123", "qwertyui", "11111111", "00000000", "abcd1234",
    "iloveyou", "sifre123", "parola123", "deneme123", "portly123",
    "admin123", "asdasdasd", "123456123", "112233445", "qazwsxedc",
}


def validate_new_password(password: str, email: str | None = None) -> None:
    """Yeni şifreyi politikaya göre denetler; uymuyorsa 400 fırlatır."""
    from fastapi import HTTPException

    pwd = (password or "").strip()
    if len(pwd) < MIN_PASSWORD_LENGTH:
        raise HTTPException(
            status_code=400,
            detail=f"Şifre en az {MIN_PASSWORD_LENGTH} karakter olmalı")
    if pwd.lower() in _COMMON_PASSWORDS:
        raise HTTPException(
            status_code=400,
            detail="Bu şifre çok yaygın kullanılıyor, başka bir şey seç")
    if len(set(pwd)) == 1:
        raise HTTPException(
            status_code=400, detail="Şifre tek bir karakterin tekrarı olamaz")
    if email:
        local = email.split("@")[0].lower()
        if local and pwd.lower() in (email.lower(), local):
            raise HTTPException(
                status_code=400,
                detail="Şifre e-posta adresinle aynı olamaz")
