"""Grafik çizim kalıcılığı servisi.

Kullanıcı+sembol başına çizim setini (tek JSON blob) okur/yazar/siler.
payload frontend'in sahibi olduğu serbest-biçim sözlük (timestamp-bazlı, 'v'
sürüm alanlı) — bkz. app.models.chart_drawing.ChartDrawing.
"""

from datetime import datetime, timezone
from sqlalchemy.orm import Session

from app.models.chart_drawing import ChartDrawing


def _norm(symbol: str) -> str:
    """Sembolü kanonik biçime getir (price_alert ile tutarlı: strip + UPPER)."""
    return (symbol or "").strip().upper()


def get_drawings(db: Session, user_id: int, symbol: str) -> dict | None:
    """Kullanıcının sembol için kaydettiği çizim payload'u (yoksa None)."""
    row = (
        db.query(ChartDrawing)
        .filter(
            ChartDrawing.user_id == user_id,
            ChartDrawing.symbol == _norm(symbol),
        )
        .first()
    )
    return row.payload if row else None


def save_drawings(db: Session, user_id: int, symbol: str, payload: dict) -> ChartDrawing:
    """Çizim setini upsert eder (sembol başına tek satır)."""
    sym = _norm(symbol)
    row = (
        db.query(ChartDrawing)
        .filter(ChartDrawing.user_id == user_id, ChartDrawing.symbol == sym)
        .first()
    )
    if row:
        row.payload = payload
        row.updated_at = datetime.now(timezone.utc)
    else:
        row = ChartDrawing(user_id=user_id, symbol=sym, payload=payload)
        db.add(row)
    db.commit()
    db.refresh(row)
    return row


def delete_drawings(db: Session, user_id: int, symbol: str) -> bool:
    """Sembolün çizimlerini siler. Silinen satır olduysa True döner."""
    deleted = (
        db.query(ChartDrawing)
        .filter(
            ChartDrawing.user_id == user_id,
            ChartDrawing.symbol == _norm(symbol),
        )
        .delete(synchronize_session=False)
    )
    db.commit()
    return deleted > 0
