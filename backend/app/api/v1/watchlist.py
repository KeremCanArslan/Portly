"""İzleme listesi (watchlist) API'si — kullanıcıya özel, sıralı sembol listesi.

GET    /api/v1/watchlist            → sıralı sembol listesi (["AAPL","THYAO",...]).
PUT    /api/v1/watchlist            → listeyi tümüyle değiştir (reorder + toplu taşıma).
POST   /api/v1/watchlist/{symbol}   → sembolü sona ekle (idempotent).
DELETE /api/v1/watchlist/{symbol}   → sembolü çıkar.

İzleme listesi önceden yalnız cihazdaki SharedPreferences'taydı; bu uçlar onu
hesaba bağlar (cihazlar arası senkron). chart_drawings ile aynı auth + sembol
normalizasyonu deseni. Liste küçük (semboller) → sembol-bazlı doğrulama yerine
tavan (MAX_SYMBOLS) ile şişme/abuse engellenir.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from app.core.database import get_db
from app.services import watchlist_service, auth_service
from app.models.user import User

router = APIRouter()


class WatchlistResponse(BaseModel):
    symbols: list[str]


class ReplaceWatchlistRequest(BaseModel):
    symbols: list[str] = Field(default_factory=list)


@router.get("", response_model=WatchlistResponse)
def get_watchlist(
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    return WatchlistResponse(
        symbols=watchlist_service.get_watchlist(db, current_user.id)
    )


@router.put("", response_model=WatchlistResponse)
def replace_watchlist(
    body: ReplaceWatchlistRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    if len(body.symbols) > watchlist_service.MAX_SYMBOLS:
        raise HTTPException(status_code=413, detail="İzleme listesi çok uzun")
    return WatchlistResponse(
        symbols=watchlist_service.replace_watchlist(
            db, current_user.id, body.symbols
        )
    )


@router.post("/{symbol}", response_model=WatchlistResponse)
def add_symbol(
    symbol: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    return WatchlistResponse(
        symbols=watchlist_service.add_symbol(db, current_user.id, symbol)
    )


@router.delete("/{symbol}", response_model=WatchlistResponse)
def remove_symbol(
    symbol: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    return WatchlistResponse(
        symbols=watchlist_service.remove_symbol(db, current_user.id, symbol)
    )
