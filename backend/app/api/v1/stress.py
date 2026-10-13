from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.limiter import limiter
from app.services import stress_test_service, auth_service
from app.models.user import User

router = APIRouter()


@router.get("/scenarios")
def get_scenarios():
    """Mevcut stres testi senaryolarının listesi."""
    return stress_test_service.list_scenarios()


@router.get("/run/{user_id}")
@limiter.limit("10/minute")
def run_stress_test(
    request: Request,
    user_id: int,
    scenario: str = "normal",
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """
    Belirtilen kullanıcı portföyü için Monte Carlo stres testi çalıştırır.
    scenario: normal, subprime_2008, covid_2020, bist_2018, black_swan

    C4: 10k Monte Carlo yolu (1-3sn). IP başına 10/dk — DoS koruması.
    """
    if user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcı için stres testi çalıştıramazsınız",
        )
    return stress_test_service.run_monte_carlo(
        db=db, user_id=user_id, scenario=scenario
    )