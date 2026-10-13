"""İzleme listesi (watchlist) kalıcılığı servisi.

Kullanıcının izleme listesini (sıralı sembol listesi) okur/değiştirir. Sembol
başına tek satır + `position` ile sıra korunur. Sembol kanonik (strip + UPPER),
chart_drawing/price_alert servisleriyle tutarlı. Frontend listeyi zaten bütün
hâlde tuttuğu için hem granüler (add/remove) hem toplu (replace=reorder) uçlar
sunulur — bkz. app.api.v1.watchlist.
"""

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.watchlist import WatchlistItem

# Kötüye-kullanım/şişme koruması: makul tavan (UI'da bu kadar sembol zaten taşar).
MAX_SYMBOLS = 200


def _norm(symbol: str) -> str:
    """Sembolü kanonik biçime getir (price_alert/chart_drawing ile aynı)."""
    return (symbol or "").strip().upper()


def get_watchlist(db: Session, user_id: int) -> list[str]:
    """Kullanıcının izleme listesi (position sırasına göre sembol listesi)."""
    rows = (
        db.query(WatchlistItem)
        .filter(WatchlistItem.user_id == user_id)
        .order_by(WatchlistItem.position, WatchlistItem.symbol)
        .all()
    )
    return [r.symbol for r in rows]


def add_symbol(db: Session, user_id: int, symbol: str) -> list[str]:
    """Sembolü listenin SONUNA ekler. Idempotent (zaten varsa dokunmaz);
    tavan dolu ise sessiz no-op. Güncel listeyi döner."""
    sym = _norm(symbol)
    if not sym:
        return get_watchlist(db, user_id)
    exists = (
        db.query(WatchlistItem)
        .filter(WatchlistItem.user_id == user_id, WatchlistItem.symbol == sym)
        .first()
    )
    if exists is None:
        count = (
            db.query(WatchlistItem)
            .filter(WatchlistItem.user_id == user_id)
            .count()
        )
        if count < MAX_SYMBOLS:
            max_pos = (
                db.query(func.max(WatchlistItem.position))
                .filter(WatchlistItem.user_id == user_id)
                .scalar()
            )
            next_pos = (max_pos + 1) if max_pos is not None else 0
            db.add(WatchlistItem(user_id=user_id, symbol=sym, position=next_pos))
            db.commit()
    return get_watchlist(db, user_id)


def remove_symbol(db: Session, user_id: int, symbol: str) -> list[str]:
    """Sembolü listeden çıkarır (yoksa no-op). Güncel listeyi döner."""
    db.query(WatchlistItem).filter(
        WatchlistItem.user_id == user_id,
        WatchlistItem.symbol == _norm(symbol),
    ).delete(synchronize_session=False)
    db.commit()
    return get_watchlist(db, user_id)


def replace_watchlist(db: Session, user_id: int, symbols: list[str]) -> list[str]:
    """İzleme listesini verilen sıralı listeyle TAMAMEN değiştirir (drag-reorder
    + ilk backend taşıması için). Boş/tekrar semboller elenir, sıra korunur,
    MAX_SYMBOLS'a kırpılır. Güncel listeyi döner."""
    seen: set[str] = set()
    clean: list[str] = []
    for s in symbols or []:
        n = _norm(s)
        if n and n not in seen:
            seen.add(n)
            clean.append(n)
        if len(clean) >= MAX_SYMBOLS:
            break
    db.query(WatchlistItem).filter(
        WatchlistItem.user_id == user_id
    ).delete(synchronize_session=False)
    for pos, sym in enumerate(clean):
        db.add(WatchlistItem(user_id=user_id, symbol=sym, position=pos))
    db.commit()
    return get_watchlist(db, user_id)
