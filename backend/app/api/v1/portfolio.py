from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from typing import List
from app.core.database import get_db
from app.core.limiter import limiter
from app.services import (
    portfolio_service,
    portfolio_performance_service,
    auth_service,
    benchmark_service,
    portfolio_health_service,
    dividend_service,
)
from app.models.user import User
from app.schemas.portfolio_schema import PortfolioItemResponse
from app.schemas.benchmark_schema import BenchmarkResponse
from app.schemas.dividend_schema import (
    DividendOverviewResponse,
    DividendCollectResponse,
)

router = APIRouter()


def _ensure_self(user_id: int, current_user: User):
    if current_user.id != user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcının verisine erişim yetkiniz yok",
        )


@router.get("/{user_id}", response_model=List[PortfolioItemResponse])
def get_portfolio(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    _ensure_self(user_id, current_user)
    return portfolio_service.get_user_portfolio(db=db, user_id=user_id)


@router.get("/{user_id}/sectors")
def get_portfolio_sectors(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    _ensure_self(user_id, current_user)
    return portfolio_service.get_sector_breakdown(db=db, user_id=user_id)


@router.get("/{user_id}/performance")
def get_performance(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Ana ekran için dönem getirisi (hafta/ay). Kapanış serisi zaten
    cache'te → ek piyasa isteği YOK, bu yüzden benchmark gibi rate-limit
    gerektirmez."""
    _ensure_self(user_id, current_user)
    return portfolio_performance_service.compute_performance(
        db=db, user_id=user_id)


@router.get("/{user_id}/benchmark", response_model=BenchmarkResponse)
@limiter.limit("20/minute")
def get_benchmark(
    request: Request,
    user_id: int,
    period: str = "3m",
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Portföy getirisini BIST 100 / S&P 500 / Nasdaq / Altın ile karşılaştırır.

    C4: pahalı uç (10+ sembol + Sharpe, 5-10sn). IP başına 20/dk —
    bot/spam tek kullanıcıyı veya yfinance kotasını yakmasın.
    """
    _ensure_self(user_id, current_user)
    return benchmark_service.compute_benchmark(db=db, user_id=user_id, period=period)


@router.get("/{user_id}/health")
def get_portfolio_health(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Portföy Sağlık Skoru — çeşitlendirme/konsantrasyon/sektör/döviz/nakit."""
    _ensure_self(user_id, current_user)
    return portfolio_health_service.compute_health(db=db, user_id=user_id)


@router.get("/{user_id}/dividends", response_model=DividendOverviewResponse)
def get_dividends(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Pozisyonların geçmiş + tahmini yıllık temettü geliri."""
    _ensure_self(user_id, current_user)
    return dividend_service.get_dividend_overview(db=db, user_id=user_id)


@router.post("/{user_id}/dividends/collect",
             response_model=DividendCollectResponse)
def collect_dividends(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """BIST (TL) temettülerini gelir kaydı olarak işle (idempotent; bakiye yok)."""
    _ensure_self(user_id, current_user)
    return dividend_service.collect_virtual_dividends(db=db, user_id=user_id)


@router.get("/{user_id}/dividends/preview",
            response_model=DividendCollectResponse)
@limiter.limit("20/minute")
def preview_dividends(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Kuru çalıştırma (dry-run): collect'i ÇALIŞTIRMADAN şu an tahsil
    edilebilir KESİN tutarı/olayları döndürür — bakiye/işlem mutasyonu
    YOK. collect ile birebir aynı hesap; UI'da sahte rakam yerine gerçek
    'Tahsil et: ₺X' göstermek için.

    C4: yfinance pozisyon başına çağrı (collect kadar pahalı) → IP
    başına 20/dk.
    """
    _ensure_self(user_id, current_user)
    return dividend_service.collect_virtual_dividends(
        db=db, user_id=user_id, dry_run=True)


@router.delete("/{user_id}/positions/{symbol}")
@limiter.limit("20/minute")
def delete_position(
    request: Request,
    user_id: int,
    symbol: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Pozisyonu portföyden tamamen kaldırır (yanlış giriş düzeltme).

    Satış akışı DEĞİL: satış için `/trading/order` (SELL) kullanılır, orada
    işlem kaydı geçmişte kalır. Burada sembolün işlem kayıtları da silinir.
    """
    _ensure_self(user_id, current_user)
    return portfolio_service.delete_position(
        db=db, user_id=user_id, symbol=symbol)
