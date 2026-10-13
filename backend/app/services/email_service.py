import smtplib
from email.message import EmailMessage

import requests
from loguru import logger

from app.core.config import settings

_BREVO_ENDPOINT = "https://api.brevo.com/v3/smtp/email"


def _build_reset_content(code: str, full_name: str | None) -> tuple[str, str, str]:
    """Şifre sıfırlama maili için (subject, text, html) üçlüsünü üretir.
    Hem Brevo hem SMTP yolu aynı içeriği kullanır."""
    subject = "Portly — Şifre Sıfırlama Kodu"
    greeting = f"Merhaba {full_name}," if full_name else "Merhaba,"
    text = (
        f"{greeting}\n\n"
        f"Portly şifre sıfırlama kodunuz: {code}\n\n"
        "Bu kod 15 dakika boyunca geçerlidir. Eğer bu isteği siz yapmadıysanız "
        "bu e-postayı yok sayabilirsiniz.\n\n"
        "Portly Ekibi"
    )
    html = f"""
        <div style="font-family: -apple-system, sans-serif; max-width: 480px; margin: auto; padding: 24px;">
          <h2 style="color: #14b8a6;">Portly Şifre Sıfırlama</h2>
          <p>{greeting}</p>
          <p>Aşağıdaki kodu uygulamaya girerek yeni şifrenizi belirleyebilirsiniz:</p>
          <div style="font-size: 32px; font-weight: 700; letter-spacing: 6px;
                      background: #f1f5f9; padding: 16px; text-align: center;
                      border-radius: 12px; color: #0f172a;">
            {code}
          </div>
          <p style="color: #64748b; font-size: 13px; margin-top: 16px;">
            Kod 15 dakika geçerlidir. Bu isteği siz yapmadıysanız bu maili yok sayabilirsiniz.
          </p>
        </div>
        """
    return subject, text, html


def _send_via_brevo(to_email: str, subject: str, text: str, html: str) -> bool:
    """Brevo transactional API (HTTPS/443) ile gönderir. Render giden SMTP'yi
    blokladığı için cloud'da çalışan tek yol budur."""
    sender_email = settings.BREVO_SENDER_EMAIL or settings.SMTP_USER
    if not sender_email:
        logger.error("Brevo: gönderici adresi yok (BREVO_SENDER_EMAIL/SMTP_USER boş).")
        return False
    try:
        resp = requests.post(
            _BREVO_ENDPOINT,
            headers={
                "api-key": settings.BREVO_API_KEY,
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            json={
                "sender": {"name": settings.SMTP_FROM_NAME, "email": sender_email},
                "to": [{"email": to_email}],
                "subject": subject,
                "textContent": text,
                "htmlContent": html,
            },
            timeout=15,
        )
        if resp.status_code in (200, 201):
            logger.info(f"Brevo: şifre sıfırlama maili gönderildi → {to_email}")
            return True
        # Brevo hata gövdesi sebebi (doğrulanmamış gönderici, geçersiz key vb.) söyler.
        logger.error(f"Brevo gönderim hatası: HTTP {resp.status_code} {resp.text}")
        return False
    except Exception as exc:
        logger.error(f"Brevo istek hatası: {exc}")
        return False


def _send_via_smtp(to_email: str, subject: str, text: str, html: str) -> bool:
    """Gmail SMTP ile gönderir. Lokal geliştirmede çalışır; Render giden SMTP
    portlarını blokladığı için cloud'da çalışmaz (orada Brevo'ya düşülür)."""
    if not settings.SMTP_USER or not settings.SMTP_PASSWORD:
        logger.error("SMTP ayarları eksik — şifre sıfırlama maili gönderilemiyor.")
        return False

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = f"{settings.SMTP_FROM_NAME} <{settings.SMTP_USER}>"
    msg["To"] = to_email
    msg.set_content(text)
    msg.add_alternative(html, subtype="html")

    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as smtp:
            smtp.starttls()
            smtp.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            smtp.send_message(msg)
        logger.info(f"SMTP: şifre sıfırlama maili gönderildi → {to_email}")
        return True
    except Exception as exc:
        logger.error(f"SMTP gönderim hatası: {exc}")
        return False


def send_password_reset_email(to_email: str, code: str, full_name: str | None = None) -> bool:
    """Şifre sıfırlama kodunu e-postayla gönderir.

    BREVO_API_KEY tanımlıysa HTTPS üzerinden Brevo ile gönderir (Render giden
    SMTP'yi bloklar → cloud'da tek çalışan yol). Aksi halde lokal geliştirme
    için Gmail SMTP'ye düşer.
    """
    subject, text, html = _build_reset_content(code, full_name)
    if settings.BREVO_API_KEY:
        return _send_via_brevo(to_email, subject, text, html)
    return _send_via_smtp(to_email, subject, text, html)
