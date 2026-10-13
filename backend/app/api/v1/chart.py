"""Grafik çizim kalıcılığı API'si (kullanıcıya özel, sembol başına çizim seti).

GET    /api/v1/chart/drawings/{symbol}  → kayıtlı çizim payload'u (yoksa boş {}).
PUT    /api/v1/chart/drawings/{symbol}  → çizim setini upsert et.
DELETE /api/v1/chart/drawings/{symbol}  → çizimleri sil (hepsini temizle).

payload frontend'in sahibi olduğu serbest-biçim JSON nesnesi ('v' sürüm alanlı,
timestamp-bazlı). Backend tek istemciye (Flutter) hizmet ettiği için şemayı tip
tip doğrulamak yerine OPAK dict tutarız → yeni bir çizim tipi eklenince backend
churn olmaz. Yalnız makul bir boyut sınırı (kötüye-kullanım/şişme koruması)
uygulanır.
"""

import json
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from app.core.database import get_db
from app.services import chart_drawing_service, auth_service
from app.models.user import User

router = APIRouter()

# Çizimler küçüktür (birkaç düzine nokta); 256 KB fazlasıyla yeterli + şişme/abuse engeli.
_MAX_PAYLOAD_BYTES = 256 * 1024


class SaveDrawingsRequest(BaseModel):
    payload: dict = Field(default_factory=dict)


class DrawingsResponse(BaseModel):
    symbol: str
    payload: dict


@router.get("/drawings/{symbol}", response_model=DrawingsResponse)
def get_drawings(
    symbol: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    payload = chart_drawing_service.get_drawings(db, current_user.id, symbol)
    return DrawingsResponse(symbol=symbol.strip().upper(), payload=payload or {})


@router.put("/drawings/{symbol}", response_model=DrawingsResponse)
def put_drawings(
    symbol: str,
    body: SaveDrawingsRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    if len(json.dumps(body.payload)) > _MAX_PAYLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Çizim verisi çok büyük")
    row = chart_drawing_service.save_drawings(
        db, current_user.id, symbol, body.payload
    )
    return DrawingsResponse(symbol=row.symbol, payload=row.payload)


@router.delete("/drawings/{symbol}")
def delete_drawings(
    symbol: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    deleted = chart_drawing_service.delete_drawings(db, current_user.id, symbol)
    return {"deleted": deleted, "symbol": symbol.strip().upper()}
