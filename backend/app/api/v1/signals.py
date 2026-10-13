"""Alım-satım sinyalleri API'si.

GET /api/v1/signals            → kullanıcının portföy + izleme sembollerinin
                                 kural tabanlı AL/TUT/SAT taraması.
GET /api/v1/signals/{symbol}   → tek sembol sinyali (hisse detay ekranı).

Sinyaller signal_service'te kural tabanlı üretilir (LLM yok, 15 dk cache);
`?force=true` cache'i atlar. Yanıtlar yatırım tavsiyesi değildir — disclaimer
yanıt gövdesinde taşınır, frontend gösterir.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.services import signal_service, auth_service
from app.models.user import User

router = APIRouter()


@router.get("")
def get_my_signals(
    force: bool = False,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    return signal_service.get_signals_for_user(
        db, current_user.id, force_refresh=force
    )


@router.get("/{symbol}")
def get_symbol_signal(
    symbol: str,
    force: bool = False,
    current_user: User = Depends(auth_service.get_current_user),
):
    try:
        return signal_service.get_signal(symbol, force_refresh=force)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Sinyal üretilemedi: {exc}")
