"""Yatırımcı günlüğü (not alma) servisi.

Kullanıcının notlarını okur/yazar/günceller/siler. Not bir hisseye bağlı
(`symbol`) ya da serbest (`symbol=None` → genel günlük) olabilir. Sembol kanonik
(strip + UPPER, boş → None), diğer servislerle tutarlı. Bir hisseye birden çok
not yazılabilir → liste en yeni önce (created_at DESC, id ile tie-break) döner.

İçerik doğrulaması iki katman: boş-DEĞİL/uzunluk üst sınırı API'de Pydantic
(`Field`) ile (422); yalnız-boşluk ("   ") ve tavanlar burada `_norm_content` ile
(ValueError → API 400). Bu, chat servisinin iki-katman doğrulama deseniyle aynı.
"""

from sqlalchemy.orm import Session

from app.models.note import Note

MAX_CONTENT_LEN = 5000   # tek not içerik tavanı (abuse/şişme koruması)
MAX_NOTES = 1000         # kullanıcı başına makul tavan


def _norm_symbol(symbol: str | None) -> str | None:
    """Sembolü kanonik biçime getir (watchlist/chart_drawing ile aynı); boş → None."""
    s = (symbol or "").strip().upper()
    return s or None


def _norm_content(content: str) -> str:
    """İçeriği strip eder; boş ya da tavanı aşan içerik → ValueError (API 400)."""
    c = (content or "").strip()
    if not c:
        raise ValueError("Not içeriği boş olamaz")
    if len(c) > MAX_CONTENT_LEN:
        raise ValueError("Not çok uzun")
    return c


def list_notes(db: Session, user_id: int, symbol: str | None = None) -> list[Note]:
    """Kullanıcının notları, en yeni önce. `symbol` verilirse o hisseye filtrele;
    verilmezse (None) tüm notlar (hisseye bağlı + genel) gelir."""
    q = db.query(Note).filter(Note.user_id == user_id)
    sym = _norm_symbol(symbol)
    if sym is not None:
        q = q.filter(Note.symbol == sym)
    return q.order_by(Note.created_at.desc(), Note.id.desc()).all()


def create_note(
    db: Session, user_id: int, content: str, symbol: str | None = None
) -> Note:
    """Yeni not oluşturur. İçerik boşsa/çok uzunsa ya da tavan dolduysa ValueError."""
    if db.query(Note).filter(Note.user_id == user_id).count() >= MAX_NOTES:
        raise ValueError("Not sınırına ulaşıldı")
    note = Note(
        user_id=user_id,
        symbol=_norm_symbol(symbol),
        content=_norm_content(content),
    )
    db.add(note)
    db.commit()
    db.refresh(note)
    return note


def update_note(
    db: Session, user_id: int, note_id: int, content: str
) -> Note | None:
    """Notun içeriğini günceller. Sahiplik: yalnız kullanıcının kendi notu (aksi
    halde None → API 404). İçerik geçersizse ValueError (API 400)."""
    note = (
        db.query(Note)
        .filter(Note.id == note_id, Note.user_id == user_id)
        .first()
    )
    if note is None:
        return None
    note.content = _norm_content(content)
    db.commit()
    db.refresh(note)
    return note


def delete_note(db: Session, user_id: int, note_id: int) -> bool:
    """Notu siler (yalnız sahibinin). Silindiyse True, yoksa/başkasınınsa False.

    Bulk `.delete()` yerine fetch + `db.delete()`: bu, silinen satırı session'ın
    identity map'inden de düşürür → aynı session aynı not nesnesini elinde tutsa
    bile (örn. servis testi) sonraki sorguda stale-refresh (ObjectDeletedError)
    olmaz. (HTTP'de her istek taze session aldığı için ikisi de çalışır.)
    """
    note = (
        db.query(Note)
        .filter(Note.id == note_id, Note.user_id == user_id)
        .first()
    )
    if note is None:
        return False
    db.delete(note)
    db.commit()
    return True
