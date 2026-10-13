"""Fiyat alarmı servisi.

Worker periyodik olarak aktif alarmları kontrol eder.
Koşul sağlandığında:
  1. Alarmı `triggered_at` ile işaretle ve deaktif et
  2. notify_email=True ise SMTP'den mail gönder
"""

from datetime import datetime, timezone
from sqlalchemy.orm import Session
from fastapi import HTTPException
from loguru import logger

from app.core.database import SessionLocal
from app.models.price_alert import PriceAlert
from app.models.user import User
from app.services.market_data_service import get_stock_data
from app.services.email_service import send_password_reset_email  # SMTP altyapısı

# E-posta alarmı için ayrı template yazıyoruz
import smtplib
from email.message import EmailMessage
from app.core.config import settings


def _send_alert_email(to_email: str, full_name: str | None, symbol: str,
                     direction: str, threshold: float, current: float,
                     note: str | None) -> bool:
    if not settings.SMTP_USER or not settings.SMTP_PASSWORD:
        logger.error("SMTP ayarları eksik — alarm maili gönderilemiyor.")
        return False
    msg = EmailMessage()
    arrow = "↑" if direction == "ABOVE" else "↓"
    msg["Subject"] = f"Portly Alarm: {symbol} {arrow} {threshold}"
    msg["From"] = f"{settings.SMTP_FROM_NAME} <{settings.SMTP_USER}>"
    msg["To"] = to_email

    greeting = f"Merhaba {full_name}," if full_name else "Merhaba,"
    body_text = (
        f"{greeting}\n\n"
        f"{symbol} fiyat alarmın tetiklendi.\n"
        f"  Yön: {direction}\n"
        f"  Eşik: {threshold}\n"
        f"  Cari: {current}\n"
    )
    if note:
        body_text += f"  Not: {note}\n"
    body_text += "\nPortly"
    msg.set_content(body_text)
    msg.add_alternative(f"""
        <div style="font-family: -apple-system, sans-serif; max-width: 480px; margin: auto; padding: 24px;">
          <h2 style="color: #14b8a6;">🔔 Portly Alarm</h2>
          <p>{greeting}</p>
          <p><strong>{symbol}</strong> için kurduğun fiyat alarmı tetiklendi:</p>
          <div style="background: #f1f5f9; padding: 14px; border-radius: 8px; margin: 12px 0;">
            <div style="font-size: 22px; font-weight: 700; color: #0f172a;">
              {symbol} {arrow} {threshold}
            </div>
            <div style="color: #64748b; margin-top: 6px; font-size: 13px;">
              Cari fiyat: <strong>{current}</strong>
            </div>
          </div>
          {f'<p style="color:#475569;font-size:13px;">Not: {note}</p>' if note else ''}
          <p style="color:#94a3b8;font-size:12px;margin-top:18px;">Portly · Portföy Takibi ve Yatırım Sinyalleri</p>
        </div>
    """, subtype="html")
    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as smtp:
            smtp.starttls()
            smtp.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            smtp.send_message(msg)
        logger.info(f"Alarm maili gönderildi → {to_email} ({symbol})")
        return True
    except Exception as exc:
        logger.error(f"Alarm mail hata: {exc}")
        return False


def create_alert(
    db: Session, user_id: int, symbol: str,
    threshold_price: float, direction: str,
    notify_email: bool = True, note: str | None = None,
) -> PriceAlert:
    if threshold_price <= 0:
        raise HTTPException(status_code=400, detail="Eşik fiyatı pozitif olmalı")
    if direction not in ("ABOVE", "BELOW"):
        raise HTTPException(status_code=400, detail="Yön ABOVE veya BELOW olmalı")
    alert = PriceAlert(
        user_id=user_id,
        symbol=symbol.upper(),
        threshold_price=threshold_price,
        direction=direction,
        notify_email=notify_email,
        active=True,
        note=note,
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)
    return alert


def list_user_alerts(db: Session, user_id: int) -> list[PriceAlert]:
    return (
        db.query(PriceAlert)
        .filter(PriceAlert.user_id == user_id)
        .order_by(PriceAlert.active.desc(), PriceAlert.created_at.desc())
        .all()
    )


def count_unseen_triggered(db: Session, user_id: int) -> int:
    """Tetiklenmiş ama kullanıcının henüz uygulama içinde görmediği alarm sayısı.

    Uygulama-içi rozet bunu kullanır → e-posta (SMTP) çıkmasa bile tetik görünür.
    """
    return (
        db.query(PriceAlert)
        .filter(
            PriceAlert.user_id == user_id,
            PriceAlert.active == False,          # noqa: E712 — tetiklenince pasif olur
            PriceAlert.triggered_at.isnot(None),
            PriceAlert.acknowledged == False,    # noqa: E712
        )
        .count()
    )


def mark_alerts_seen(db: Session, user_id: int) -> int:
    """Kullanıcının tetiklenmiş tüm alarmlarını 'görüldü' işaretler. Sayı döner."""
    marked = (
        db.query(PriceAlert)
        .filter(
            PriceAlert.user_id == user_id,
            PriceAlert.triggered_at.isnot(None),
            PriceAlert.acknowledged == False,    # noqa: E712
        )
        .update({PriceAlert.acknowledged: True}, synchronize_session=False)
    )
    db.commit()
    return marked


def delete_alert(db: Session, alert_id: int, user_id: int) -> None:
    alert = db.query(PriceAlert).filter(PriceAlert.id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail="Alarm bulunamadı")
    if alert.user_id != user_id:
        raise HTTPException(status_code=403, detail="Bu alarm size ait değil")
    db.delete(alert)
    db.commit()


def check_and_fire_alerts() -> int:
    """Worker tarafından çağrılır. Tetiklenen alarm sayısını döner.

    E-posta gönderimi veritabanı oturumu KAPANDIKTAN sonra yapılır. Aksi halde
    tetiklenen her alarm için SMTP/Brevo yanıtı, açık bir Neon bağlantısı ve
    açık bir transaction beklerken alınırdı: yavaş bir posta sunucusu tetiklerin
    veritabanına yazılmasını da geciktirir, uzun süre açık kalan transaction
    Postgres tarafında gereksiz kilit ve bağlantı tüketimi demektir. Ayrıca
    postanın gitmemesi artık alarmın "tetiklendi" olarak KAYDEDİLMESİNİ
    engellemez — uygulama içi rozet (`count_unseen_triggered`) yine çalışır.
    """
    db: Session = SessionLocal()
    fired = 0
    pending_mail: list[dict] = []
    try:
        active = (
            db.query(PriceAlert)
            .filter(PriceAlert.active == True)  # noqa: E712
            .all()
        )
        if not active:
            return 0

        price_cache: dict[str, float] = {}
        for alert in active:
            try:
                if alert.symbol not in price_cache:
                    data = get_stock_data(alert.symbol)
                    price_cache[alert.symbol] = float(data["current_price"])
                current = price_cache[alert.symbol]

                triggered = False
                if alert.direction == "ABOVE" and current >= alert.threshold_price:
                    triggered = True
                elif alert.direction == "BELOW" and current <= alert.threshold_price:
                    triggered = True

                if not triggered:
                    continue

                alert.active = False
                alert.triggered_at = datetime.now(timezone.utc)
                alert.triggered_price = current

                if alert.notify_email:
                    user = db.query(User).filter(User.id == alert.user_id).first()
                    if user:
                        pending_mail.append({
                            "to_email": user.email,
                            "full_name": user.full_name,
                            "symbol": alert.symbol,
                            "direction": alert.direction,
                            "threshold": alert.threshold_price,
                            "current": current,
                            "note": alert.note,
                        })
                fired += 1
                logger.info(f"Alarm tetiklendi: #{alert.id} {alert.symbol} {alert.direction} @ {current}")
            except Exception as exc:
                logger.warning(f"Alarm #{alert.id} hata: {exc}")
                continue
        db.commit()
    finally:
        db.close()

    # Oturum kapandı — posta ağı artık veritabanı bağlantısı tutmuyor.
    for mail in pending_mail:
        try:
            _send_alert_email(**mail)
        except Exception as exc:
            logger.warning(f"Alarm e-postası gönderilemedi ({mail['symbol']}): {exc}")
    return fired
