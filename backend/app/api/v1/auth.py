from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.limiter import limiter
from app.schemas.user_schema import (
    UserCreate,
    UserResponse,
    UserLogin,
    Token,
    RefreshTokenRequest,
    AccessTokenResponse,
    ForgotPasswordRequest,
    ResetPasswordRequest,
    ChangePasswordRequest,
    DeleteAccountRequest,
    UpdateRiskProfileRequest,
)
from app.services import account_service, auth_service, email_service
from app.models.user import User

router = APIRouter()


# kullanıcı kaydı - dakikada 5 denemeden fazlasına izin verme
# yoksa bot ile spam açılıyor
@router.post("/register", response_model=Token)
@limiter.limit("5/minute")
def register_user(request: Request, user: UserCreate, db: Session = Depends(get_db)):
    """Yeni kullanıcı oluşturur, access + refresh token döner."""
    auth_service.validate_new_password(user.password, user.email)
    db_user = db.query(User).filter(User.email == user.email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Bu e-posta zaten kayıtlı")

    new_user = auth_service.create_user(db=db, user=user)
    access_token = auth_service.create_access_token(data={"sub": str(new_user.id)})
    refresh_token = auth_service.create_refresh_token(db, new_user.id)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": new_user,
    }


@router.post("/login", response_model=Token)
# Kaba kuvvete karşı: dakikada 5 deneme (yanlış yazan gerçek kullanıcıya yeter,
# sözlük saldırısını pahalı yapar).
@limiter.limit("5/minute")
def login(request: Request, credentials: UserLogin, db: Session = Depends(get_db)):
    """E-posta ve şifre ile giriş yapar, access + refresh token döner."""
    user = auth_service.authenticate_user(db, credentials.email, credentials.password)
    if not user:
        # yanlış şifre veya yanlış mail - ikisini ayırt etmiyoruz, güvenlik gereği
        raise HTTPException(status_code=401, detail="E-posta veya şifre hatalı")

    access_token = auth_service.create_access_token(data={"sub": str(user.id)})
    refresh_token = auth_service.create_refresh_token(db, user.id)
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": user,
    }


@router.post("/refresh", response_model=AccessTokenResponse)
@limiter.limit("30/minute")
def refresh_access_token(
    request: Request,
    payload: RefreshTokenRequest,
    db: Session = Depends(get_db),
):
    """Refresh token'ı doğrular, yeni access + refresh (rotated) döner."""
    result = auth_service.verify_and_rotate_refresh_token(db, payload.refresh_token)
    if not result:
        raise HTTPException(status_code=401, detail="Refresh token geçersiz veya süresi dolmuş")
    user, new_refresh = result
    new_access = auth_service.create_access_token(data={"sub": str(user.id)})
    return {
        "access_token": new_access,
        "refresh_token": new_refresh,
        "token_type": "bearer",
    }


@router.get("/me", response_model=UserResponse)
def get_current_user_info(
    current_user: User = Depends(auth_service.get_current_user),
):
    """JWT token'dan mevcut kullanıcının bilgilerini döner."""
    return current_user


@router.patch("/risk-profile", response_model=UserResponse)
def update_risk_profile(
    payload: UpdateRiskProfileRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Risk profili testi sonucunu kaydeder."""
    current_user.risk_profile = payload.risk_profile
    db.commit()
    db.refresh(current_user)
    return current_user


@router.post("/logout")
def logout(
    credentials: HTTPAuthorizationCredentials = Depends(auth_service.security),
    current_user: User = Depends(auth_service.get_current_user),
    db: Session = Depends(get_db),
):
    """Access token'ı blacklist'e ekler ve kullanıcının tüm refresh token'larını iptal eder."""
    auth_service.blacklist_token(credentials.credentials)
    auth_service.revoke_user_refresh_tokens(db, current_user.id)
    return {"detail": "Çıkış yapıldı"}


@router.post("/forgot-password")
@limiter.limit("3/minute")
def forgot_password(
    request: Request,
    payload: ForgotPasswordRequest,
    db: Session = Depends(get_db),
):
    """E-posta adresine 6 haneli sıfırlama kodu gönderir.

    Güvenlik: Kullanıcı kayıtlı olmasa bile aynı yanıtı döneriz, böylece
    saldırgan hangi e-postaların kayıtlı olduğunu öğrenemez (user enumeration).
    """
    user = db.query(User).filter(User.email == payload.email).first()
    if user:
        code = auth_service.create_password_reset_code(payload.email)
        sent = email_service.send_password_reset_email(payload.email, code, user.full_name)
        # SMTP fail olsa bile generic mesajı koru — 500 vermek user enumeration'a
        # yol açıyor (saldırgan 500'den e-postanın kayıtlı olduğunu çıkarır).
        # Hata sadece sunucu logunda kalsın; kullanıcıya hep aynı yanıt.
        if not sent:
            from loguru import logger
            logger.error(f"forgot-password: SMTP gönderim başarısız (email={payload.email})")
    return {"detail": "Eğer bu e-posta kayıtlıysa, sıfırlama kodu gönderildi."}


@router.post("/reset-password")
@limiter.limit("5/minute")
def reset_password(
    request: Request,
    payload: ResetPasswordRequest,
    db: Session = Depends(get_db),
):
    """6 haneli kodu doğrular ve yeni şifreyi kaydeder."""
    if not auth_service.verify_password_reset_code(payload.email, payload.code):
        raise HTTPException(status_code=400, detail="Kod hatalı veya süresi dolmuş")

    user = db.query(User).filter(User.email == payload.email).first()
    if not user:
        raise HTTPException(status_code=400, detail="Kod hatalı veya süresi dolmuş")

    auth_service.validate_new_password(payload.new_password, payload.email)
    user.hashed_password = auth_service.get_password_hash(payload.new_password)
    db.commit()
    auth_service.consume_password_reset_code(payload.email)
    return {"detail": "Şifre başarıyla güncellendi"}


@router.post("/change-password")
@limiter.limit("5/minute")
def change_password(
    request: Request,
    payload: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Oturum açıkken şifre değiştirir (e-posta kodu gerektirmez).

    Mevcut şifre ŞART: erişim token'ı ele geçiren biri şifreyi değiştirip
    hesabı tamamen kilitleyebilirdi.

    Değişiklikten sonra TÜM refresh token'lar iptal edilir — şifre
    değiştirmenin asıl amacı "başka cihazdaki oturumu düşürmek"tir; eski
    token yaşarsa amaç boşa çıkar. Ama o zaman BU cihaz da 60 dk sonra
    dışarı düşerdi, o yüzden çağırana YENİ bir refresh token dönülür ve
    istemci onu saklar (login/refresh ile aynı sözleşme).
    """
    if not auth_service.verify_password(
            payload.current_password, current_user.hashed_password):
        raise HTTPException(status_code=400, detail="Mevcut şifre yanlış")

    if payload.new_password == payload.current_password:
        raise HTTPException(
            status_code=400, detail="Yeni şifre eskisiyle aynı olamaz")

    auth_service.validate_new_password(payload.new_password, current_user.email)

    current_user.hashed_password = auth_service.get_password_hash(
        payload.new_password)
    db.commit()
    auth_service.revoke_user_refresh_tokens(db, current_user.id)
    return {
        "detail": "Şifre güncellendi",
        "refresh_token": auth_service.create_refresh_token(db, current_user.id),
    }


@router.post("/delete-account")
@limiter.limit("3/minute")
def delete_account(
    request: Request,
    payload: DeleteAccountRequest,
    credentials: HTTPAuthorizationCredentials = Depends(auth_service.security),
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Hesabı ve ona ait TÜM verileri kalıcı olarak siler (KVKK silme hakkı).

    Şifre doğrulaması şart. Silme sonrası elde kalan access token'ın hiçbir
    kullanıcıya karşılığı kalmaz ama yine de kara listeye alınır: token
    süresi dolana kadar (60 dk) ortada geçerli imzalı bir anahtar kalmasın.
    """
    result = account_service.delete_account(
        db=db, user=current_user, password=payload.password)
    auth_service.blacklist_token(credentials.credentials)
    return result
