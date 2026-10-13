"""Pozisyon satırına eşzamanlı yazma koruması.

Lot + ortalama maliyet OKU-DEĞİŞTİR-YAZ ile güncelleniyor. İki koruma var:
  1. mevcut satır `FOR UPDATE` ile kilitli okunur (Postgres; SQLite'ta ifade
     sessizce düşer — bu yüzden burada kilidin KENDİSİ değil, kilidin
     kaybedildiği durumda devreye giren 2. katman sınanır),
  2. satır henüz yokken iki INSERT yarışırsa (user_id, symbol) benzersiz
     kısıtı ikincisini reddeder → SAVEPOINT geri alınır, satır okunup
     BİRLEŞTİRİLİR (lot kaybolmaz).

Yarış, `_locked_position`'ı bir kez "satır yok" dedirterek taklit edilir:
gerçek hayatta rakip istek satırı tam bu iki adım arasında yazar.
"""
import pytest
from sqlalchemy.exc import IntegrityError

from app.models.portfolio import Portfolio
from app.services import order_service


def test_unique_constraint_blocks_second_row(db, make_user):
    """Aynı (user_id, symbol) ikinci satırı veritabanı reddeder."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="AAPL",
                     quantity=10, average_cost=100))
    db.commit()
    db.add(Portfolio(user_id=user.id, symbol="AAPL",
                     quantity=5, average_cost=200))
    with pytest.raises(IntegrityError):
        db.commit()
    db.rollback()


def test_lost_insert_race_merges_instead_of_failing(db, make_user, monkeypatch):
    """Ekleme yarışı kaybedilirse lot KAYBOLMAZ, mevcut satıra birleşir."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="AAPL",
                     quantity=10, average_cost=100))
    db.commit()

    real = order_service._locked_position
    calls = {"n": 0}

    def _blind_once(session, user_id, symbol):
        # İlk okuma satırı GÖRMEZ (rakip istek tam bu anda yazmış gibi).
        calls["n"] += 1
        return None if calls["n"] == 1 else real(session, user_id, symbol)

    monkeypatch.setattr(order_service, "_locked_position", _blind_once)

    item = order_service._merge_buy_lot(db, user.id, "AAPL", 10, 200)
    db.commit()

    rows = db.query(Portfolio).filter(Portfolio.user_id == user.id).all()
    assert len(rows) == 1                    # ikinci satır oluşmadı
    assert item.quantity == pytest.approx(20)
    assert item.average_cost == pytest.approx(150)  # (10*100 + 10*200)/20


def test_merge_buy_lot_creates_row_when_absent(db, make_user):
    """Satır yoksa normal yol: tek INSERT, birleştirme yok."""
    user = make_user()
    item = order_service._merge_buy_lot(db, user.id, "MSFT", 4, 50)
    db.commit()
    assert item.quantity == pytest.approx(4)
    assert item.average_cost == pytest.approx(50)
    assert db.query(Portfolio).filter(Portfolio.user_id == user.id).count() == 1
