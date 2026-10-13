from typing import List
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict, Field
from typing import Literal

from app.core.database import get_db
from app.services import price_alert_service, auth_service
from app.models.user import User

router = APIRouter()


class CreateAlertRequest(BaseModel):
    symbol: str = Field(..., min_length=1, max_length=20)
    threshold_price: float = Field(..., gt=0)
    direction: Literal["ABOVE", "BELOW"]
    notify_email: bool = True
    note: str | None = Field(default=None, max_length=200)


class AlertResponse(BaseModel):
    id: int
    symbol: str
    threshold_price: float
    direction: str
    notify_email: bool
    active: bool
    triggered_at: datetime | None = None
    triggered_price: float | None = None
    note: str | None = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


@router.post("", response_model=AlertResponse)
def create_alert(
    payload: CreateAlertRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    return price_alert_service.create_alert(
        db=db,
        user_id=current_user.id,
        symbol=payload.symbol,
        threshold_price=payload.threshold_price,
        direction=payload.direction,
        notify_email=payload.notify_email,
        note=payload.note,
    )


@router.get("", response_model=List[AlertResponse])
def list_alerts(
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    return price_alert_service.list_user_alerts(db=db, user_id=current_user.id)


@router.get("/unseen-count")
def unseen_count(
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Tetiklenmiş ama uygulama içinde henüz görülmemiş alarm sayısı (rozet)."""
    return {"count": price_alert_service.count_unseen_triggered(db, current_user.id)}


@router.post("/mark-seen")
def mark_seen(
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Tetiklenmiş alarmları 'görüldü' işaretle (alarm ekranı açılınca çağrılır)."""
    return {"marked": price_alert_service.mark_alerts_seen(db, current_user.id)}


@router.delete("/{alert_id}")
def delete_alert(
    alert_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    price_alert_service.delete_alert(db=db, alert_id=alert_id, user_id=current_user.id)
    return {"deleted": True, "id": alert_id}
