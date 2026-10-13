import json
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from sse_starlette.sse import EventSourceResponse
from starlette.concurrency import iterate_in_threadpool
from app.core.database import get_db
from app.core.limiter import limiter
from app.schemas.chat_schema import ChatMessageCreate
from app.services import chat_service, auth_service
from app.models.user import User

router = APIRouter()

MAX_MESSAGE_LENGTH = 2000


def _validate_message(message: str) -> str:
    msg = message.strip()
    if not msg:
        raise HTTPException(status_code=400, detail="Boş mesaj gönderilemez")
    if len(msg) > MAX_MESSAGE_LENGTH:
        raise HTTPException(
            status_code=400,
            detail=f"Mesaj çok uzun (max {MAX_MESSAGE_LENGTH} karakter)",
        )
    return msg


def _stream_response(db: Session, user_id: int, message: str) -> EventSourceResponse:
    async def event_generator():
        # `stream_chat_response` BAŞTAN SONA senkron: DB yazar, RAG bağlamını
        # kurar, LLM akışını bloklayarak okur. `async def` içinde düz `for` ile
        # dönmek onu OLAY DÖNGÜSÜNDE çalıştırır → sohbet sürerken tek uvicorn
        # işçisindeki DİĞER TÜM istekler (portföy, fiyat, sinyal) sıraya girer;
        # sse_starlette'in ping'i ve kopma dinleyicisi de bu sırada duraksar.
        # `iterate_in_threadpool` her `next()` çağrısını iş parçacığına atar,
        # token'lar arasında döngü nefes alır.
        stream = chat_service.stream_chat_response(
            db=db, user_id=user_id, user_message=message
        )
        try:
            yield {"event": "thinking", "data": "{}"}
            async for token in iterate_in_threadpool(stream):
                # JSON encode — SSE protokolü "data: " sonrası ilk boşluğu trimliyor,
                # Groq token'ları sıkça leading space içerdiğinden bu kayba yol açıyordu.
                yield {"event": "token", "data": json.dumps({"t": token})}
            yield {"event": "done", "data": "{}"}
        except Exception as e:
            yield {"event": "error", "data": json.dumps({"msg": str(e)})}
        finally:
            # İstemci sekmeyi kapatınca sse_starlette görev grubunu iptal eder;
            # iptal buraya CancelledError olarak düşer. Senkron üreteci AÇIKÇA
            # kapat ki LLM akışı (ve kotası) arkada tükenmeye devam etmesin.
            stream.close()

    return EventSourceResponse(
        event_generator(),
        media_type="text/event-stream",
        ping=20,
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


@router.post("/send")
@limiter.limit("20/minute")
async def send_message(
    request: Request,
    payload: ChatMessageCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    if payload.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcı adına mesaj gönderemezsiniz",
        )
    msg = _validate_message(payload.message)
    return _stream_response(db, current_user.id, msg)


@router.get("/send")
@limiter.limit("20/minute")
async def send_message_get(
    request: Request,
    user_id: int,
    message: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    if user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcı adına mesaj gönderemezsiniz",
        )
    msg = _validate_message(message)
    return _stream_response(db, current_user.id, msg)


@router.get("/history/{user_id}")
def get_history(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Kullanıcının sohbet geçmişini döndürür."""
    if user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcının geçmişine erişemezsiniz",
        )
    return chat_service.get_chat_history(db=db, user_id=user_id)


@router.delete("/history/{user_id}")
def clear_history(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Kullanıcının tüm sohbet geçmişini siler."""
    if user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcının geçmişini silemezsiniz",
        )
    count = chat_service.clear_chat_history(db=db, user_id=user_id)
    return {"success": True, "deleted_count": count}