"""Yatırımcı günlüğü (not alma) API'si — kullanıcıya özel notlar.

GET    /api/v1/notes?symbol=...   → notlar (symbol verilirse o hisse, yoksa hepsi), en yeni önce.
POST   /api/v1/notes              → not oluştur (content + opsiyonel symbol).
PUT    /api/v1/notes/{note_id}    → not içeriğini güncelle.
DELETE /api/v1/notes/{note_id}    → notu sil.

Not bir hisseye bağlı (symbol) ya da serbest (symbol yok → genel günlük) olabilir;
hisse detay + yatırımcı günlüğü ekranları aynı uçları kullanır. watchlist/chart
ile aynı auth deseni; sahiplik tüm sorgularda `user_id` filtresiyle sağlanır →
başka kullanıcının notu bu kullanıcı için 'yok' (404), varlığı sızdırılmaz.

İçerik doğrulaması iki katman: boş `""`/tavan aşımı → Pydantic 422; yalnız-boşluk
`"   "` → servis 400 (chat ile aynı desen).
"""

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field, ConfigDict

from app.core.database import get_db
from app.services import note_service, auth_service
from app.models.user import User

router = APIRouter()


class NoteCreateRequest(BaseModel):
    content: str = Field(min_length=1, max_length=note_service.MAX_CONTENT_LEN)
    symbol: Optional[str] = None


class NoteUpdateRequest(BaseModel):
    content: str = Field(min_length=1, max_length=note_service.MAX_CONTENT_LEN)


class NoteResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    symbol: Optional[str]
    content: str
    created_at: Optional[datetime]
    updated_at: Optional[datetime]


@router.get("", response_model=list[NoteResponse])
def list_notes(
    symbol: Optional[str] = Query(default=None),
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    return note_service.list_notes(db, current_user.id, symbol)


@router.post("", response_model=NoteResponse)
def create_note(
    body: NoteCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    try:
        return note_service.create_note(
            db, current_user.id, body.content, body.symbol
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.put("/{note_id}", response_model=NoteResponse)
def update_note(
    note_id: int,
    body: NoteUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    try:
        note = note_service.update_note(db, current_user.id, note_id, body.content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    if note is None:
        raise HTTPException(status_code=404, detail="Not bulunamadı")
    return note


@router.delete("/{note_id}")
def delete_note(
    note_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    if not note_service.delete_note(db, current_user.id, note_id):
        raise HTTPException(status_code=404, detail="Not bulunamadı")
    return {"deleted": True}
