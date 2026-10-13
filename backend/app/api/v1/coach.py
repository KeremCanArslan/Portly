from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.services import (
    ai_coach_service,
    auth_service,
    technical_analysis_service,
    ai_portfolio_service,
    fundamental_analysis_service,
)
from app.models.user import User
from pydantic import BaseModel, Field

router = APIRouter()


@router.get("/advice/{user_id}")
def get_portfolio_advice(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Kullanıcının portföyüne özel AI koçluk tavsiyesi üretir."""
    if user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcı için tavsiye alamazsınız",
        )
    return ai_coach_service.generate_portfolio_advice(db=db, user_id=user_id)


@router.get("/fundamental/{symbol}")
def fundamental_analysis(
    symbol: str,
    force: bool = False,
    current_user: User = Depends(auth_service.get_current_user),
):
    """LLM tabanlı temel analiz — P/E, ROE, büyüme, kâr marjı, borç vb."""
    try:
        return fundamental_analysis_service.analyze(symbol, force_refresh=force)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Temel analiz üretilemedi: {e}")


@router.get("/financials/{symbol}")
def financials(
    symbol: str,
    current_user: User = Depends(auth_service.get_current_user),
):
    """Geçmiş gelir tablosu + trend tabanlı ileri tahmin (bilanço takibi)."""
    try:
        return fundamental_analysis_service.get_financials(symbol)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Bilanço alınamadı: {e}")


@router.get("/predict/{symbol}")
def predict_stock(
    symbol: str,
    force: bool = False,
    current_user: User = Depends(auth_service.get_current_user),
):
    """LLM tabanlı teknik analiz tahmini — yön, hedef, stop-loss önerisi."""
    try:
        return technical_analysis_service.predict(symbol, force_refresh=force)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Tahmin üretilemedi: {e}")


class PortfolioBuilderRequest(BaseModel):
    risk_profile: str = Field(..., min_length=3, max_length=30)
    horizon: str = Field(..., min_length=3, max_length=20)  # short / medium / long
    amount: float = Field(..., gt=0)


@router.post("/build-portfolio")
def build_portfolio(
    payload: PortfolioBuilderRequest,
    current_user: User = Depends(auth_service.get_current_user),
):
    """Risk profili + vade + tutara göre AI portföy önerir ve backtest yapar."""
    try:
        return ai_portfolio_service.build_portfolio(
            risk_profile=payload.risk_profile,
            horizon=payload.horizon,
            amount=payload.amount,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Portföy üretilemedi: {e}")
