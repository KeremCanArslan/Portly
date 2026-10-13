from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserBase(BaseModel):
    email: EmailStr


class UserCreate(UserBase):
    # Gerçek politika auth_service.validate_new_password'da (yaygın şifre,
    # e-posta ile aynılık, tek karakter tekrarı). Buradaki alt sınır onunla aynı.
    password: str = Field(..., min_length=8, max_length=128)
    full_name: str | None = Field(default=None, max_length=120)


class UserResponse(UserBase):
    id: int
    full_name: str | None = None
    risk_profile: str | None = None

    model_config = ConfigDict(from_attributes=True)


class UpdateRiskProfileRequest(BaseModel):
    risk_profile: str = Field(..., min_length=3, max_length=30)


class UserLogin(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=1, max_length=128)


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str
    user: UserResponse


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(..., min_length=10)


class AccessTokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str = Field(..., min_length=6, max_length=6)
    new_password: str = Field(..., min_length=8, max_length=128)


class ChangePasswordRequest(BaseModel):
    """Oturum açıkken şifre değiştirme. Mevcut şifre ŞART: token çalınmış
    olsaydı saldırgan şifreyi değiştirip hesabı ele geçirebilirdi."""
    current_password: str = Field(..., min_length=1, max_length=128)
    new_password: str = Field(..., min_length=8, max_length=128)


class DeleteAccountRequest(BaseModel):
    """Hesap silme. Şifre ŞART: geri dönüşü olmayan bir işlem, token yetmez."""
    password: str = Field(..., min_length=1, max_length=128)
