from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.services import behavioral_finance_service, auth_service
from app.models.user import User

router = APIRouter()


@router.get("/profile/{user_id}")
def get_behavior_profile(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """
    Kullanıcının davranışsal finans profilini döner.
    Üç önyargı ölçer: Disposition Effect, Overconfidence, Loss Aversion.
    """
    if user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcının profiline erişemezsiniz",
        )
    return behavioral_finance_service.analyze_user_behavior(db=db, user_id=user_id)