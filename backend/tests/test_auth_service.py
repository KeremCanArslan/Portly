"""auth_service birim testleri — kimlik doğrulama güvenlik çekirdeği (para-yolu DIŞI).

Kapsam: bcrypt şifre hash + doğrulama (salt'lı), create_user (hash + ₺100k
başlangıç bakiyesi), authenticate_user, JWT access token üret/çöz + süre dolması,
refresh token ROTATION (tek kullanım + toplu iptal), şifre sıfırlama kodu (TTL +
consume), token blacklist (logout yolu). Ağ/Postgres yok — conftest'in bellek-içi
SQLite oturumu; bcrypt/jose gerçekten koşar (hızlı).

Çalıştırma:  cd backend && pytest -q
"""

from datetime import timedelta

import pytest
from jose import JWTError, jwt

from app.core.config import settings
from app.schemas.user_schema import UserCreate
from app.services import auth_service
from app.services.auth_service import ALGORITHM


# ── Şifre hash ───────────────────────────────────────────────────────────

def test_password_hash_roundtrip():
    """Hash düz şifreden farklı; doğru şifre doğrulanır, yanlış reddedilir."""
    h = auth_service.get_password_hash("secret123")
    assert h != "secret123"
    assert auth_service.verify_password("secret123", h) is True
    assert auth_service.verify_password("wrong", h) is False


def test_password_hash_is_salted():
    """Aynı şifre iki kez hash'lenince farklı çıktı (rastgele salt), ikisi de doğrular."""
    a = auth_service.get_password_hash("samepass")
    b = auth_service.get_password_hash("samepass")
    assert a != b
    assert auth_service.verify_password("samepass", a)
    assert auth_service.verify_password("samepass", b)


# ── create_user ──────────────────────────────────────────────────────────

def test_create_user_hashes_password(db):
    """create_user şifreyi DÜZ saklamaz; bcrypt hash + doğrulanabilir."""
    u = auth_service.create_user(
        db, UserCreate(email="a@mail.com", password="hunter2x"))
    assert u.hashed_password != "hunter2x"
    assert auth_service.verify_password("hunter2x", u.hashed_password)


def test_create_user_has_no_virtual_balance(db):
    """Pivot: sanal bakiye kalktı — User modelinde balance alanı yok."""
    u = auth_service.create_user(
        db, UserCreate(email="b@mail.com", password="abc12345"))
    assert not hasattr(u, "balance")


# ── authenticate_user ────────────────────────────────────────────────────

def test_authenticate_correct_credentials(db):
    """Doğru e-posta + şifre → kullanıcı döner."""
    auth_service.create_user(
        db, UserCreate(email="c@mail.com", password="rightpass"))
    user = auth_service.authenticate_user(db, "c@mail.com", "rightpass")
    assert user is not None and user.email == "c@mail.com"


def test_authenticate_wrong_password(db):
    """Yanlış şifre → None (sızıntı yok)."""
    auth_service.create_user(
        db, UserCreate(email="d@mail.com", password="rightpass"))
    assert auth_service.authenticate_user(db, "d@mail.com", "wrongpass") is None


def test_authenticate_unknown_email(db):
    """Kayıtlı olmayan e-posta → None."""
    assert auth_service.authenticate_user(db, "nobody@mail.com", "x") is None


# ── JWT access token ─────────────────────────────────────────────────────

def test_access_token_roundtrip():
    """Token çözülünce sub korunur, exp claim'i eklenir."""
    token = auth_service.create_access_token({"sub": "42"})
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])
    assert payload["sub"] == "42"
    assert "exp" in payload


def test_access_token_expired_rejected():
    """Süresi geçmiş token decode'da JWTError (ExpiredSignature) fırlatır."""
    token = auth_service.create_access_token(
        {"sub": "1"}, expires_delta=timedelta(minutes=-5))
    with pytest.raises(JWTError):
        jwt.decode(token, settings.SECRET_KEY, algorithms=[ALGORITHM])


# ── Refresh token rotation ───────────────────────────────────────────────

def test_refresh_token_create_and_rotate(db, make_user):
    """Geçerli refresh token kullanıcıyı + YENİ token döner (eskisinden farklı)."""
    user = make_user()
    raw = auth_service.create_refresh_token(db, user.id)
    result = auth_service.verify_and_rotate_refresh_token(db, raw)
    assert result is not None
    rotated_user, new_raw = result
    assert rotated_user.id == user.id
    assert new_raw != raw


def test_refresh_token_single_use(db, make_user):
    """Rotation: aynı refresh token İKİNCİ kez kullanılamaz (çalıntı koruması)."""
    user = make_user()
    raw = auth_service.create_refresh_token(db, user.id)
    auth_service.verify_and_rotate_refresh_token(db, raw)            # 1. kullanım
    assert auth_service.verify_and_rotate_refresh_token(db, raw) is None  # 2.


def test_refresh_token_revoke_all(db, make_user):
    """revoke_user_refresh_tokens sonrası mevcut token geçersiz (logout-all)."""
    user = make_user()
    raw = auth_service.create_refresh_token(db, user.id)
    auth_service.revoke_user_refresh_tokens(db, user.id)
    assert auth_service.verify_and_rotate_refresh_token(db, raw) is None


def test_refresh_token_unknown_returns_none(db):
    """Tanınmayan ham token → None (DB'de hash yok)."""
    assert auth_service.verify_and_rotate_refresh_token(
        db, "gecersiz-rastgele-token") is None


# ── Şifre sıfırlama kodu ─────────────────────────────────────────────────

def test_reset_code_verify_and_consume():
    """6 haneli kod: doğru kod doğrular, yanlış reddedilir, consume sonrası geçersiz."""
    email = "reset@mail.com"
    code = auth_service.create_password_reset_code(email)
    assert len(code) == 6 and code.isdigit()
    wrong = "111111" if code != "111111" else "222222"
    assert auth_service.verify_password_reset_code(email, wrong) is False
    assert auth_service.verify_password_reset_code(email, code) is True
    auth_service.consume_password_reset_code(email)
    assert auth_service.verify_password_reset_code(email, code) is False


# ── Token blacklist ──────────────────────────────────────────────────────

def test_token_blacklist():
    """blacklist_token sonrası is_token_blacklisted True (logout yolu)."""
    token = "dummy.jwt.token.unique"
    assert auth_service.is_token_blacklisted(token) is False
    auth_service.blacklist_token(token)
    assert auth_service.is_token_blacklisted(token) is True


def test_reset_code_locks_out_after_three_wrong_attempts():
    """3 hatalı denemeden sonra kod düşer — DOĞRU kod bile artık kabul edilmez.

    6 haneli kod 1.000.000 olasılık; deneme sınırı yokken uç, hız sınırının
    izin verdiği kadar denenebilirdi (kaba kuvvet).
    """
    email = "brute@mail.com"
    code = auth_service.create_password_reset_code(email)
    wrong = "111111" if code != "111111" else "222222"

    for _ in range(auth_service.RESET_CODE_MAX_ATTEMPTS):
        assert auth_service.verify_password_reset_code(email, wrong) is False

    assert auth_service.verify_password_reset_code(email, code) is False


def test_reset_code_attempt_counter_resets_with_new_code():
    """Yeni kod istemek sayacı sıfırlar (kullanıcı kilitli kalmaz)."""
    email = "retry@mail.com"
    first = auth_service.create_password_reset_code(email)
    wrong = "111111" if first != "111111" else "222222"
    for _ in range(auth_service.RESET_CODE_MAX_ATTEMPTS):
        auth_service.verify_password_reset_code(email, wrong)

    second = auth_service.create_password_reset_code(email)
    assert auth_service.verify_password_reset_code(email, second) is True


def test_reset_code_wrong_attempts_below_limit_keep_code_alive():
    """Sınırın altındaki hatalar kodu düşürmez (parmak hatası affedilir)."""
    email = "typo@mail.com"
    code = auth_service.create_password_reset_code(email)
    wrong = "111111" if code != "111111" else "222222"
    for _ in range(auth_service.RESET_CODE_MAX_ATTEMPTS - 1):
        assert auth_service.verify_password_reset_code(email, wrong) is False
    assert auth_service.verify_password_reset_code(email, code) is True


def test_refresh_token_rotation_is_atomic(db, make_user):
    """İptal koşullu UPDATE ile yapılır: satır zaten iptalliyse rotasyon reddedilir.

    Gerçek yarışta iki istek aynı token'la aynı anda gelir; koşullu UPDATE
    yalnız birinde satır günceller. Burada rakibin kazandığı an, kaydı doğrudan
    iptal ederek taklit edilir — kilitsiz kodda `record.revoked` okuması bayat
    kalıp ikinci isteğe de yeni token verilirdi.
    """
    from app.models.refresh_token import RefreshToken

    user = make_user()
    raw = auth_service.create_refresh_token(db, user.id)
    token_hash = auth_service._hash_refresh_token(raw)

    original = db.query(RefreshToken).filter(
        RefreshToken.token_hash == token_hash).first()
    real_query = db.query

    def _revoke_between_read_and_write(*args, **kwargs):
        # İlk RefreshToken okumasından SONRA rakip isteğin iptali devreye girer.
        q = real_query(*args, **kwargs)
        if args and args[0] is RefreshToken and not original.revoked:
            db.query = real_query          # tek seferlik
            original.revoked = True
            db.flush()
        return q

    db.query = _revoke_between_read_and_write
    try:
        assert auth_service.verify_and_rotate_refresh_token(db, raw) is None
    finally:
        db.query = real_query
