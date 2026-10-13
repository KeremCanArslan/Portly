"""C8 — Hisse bölünmesi mutabakatı (forward-only, idempotent).

reconcile_splits: _SPLIT_EPOCH'tan SONRAki, henüz uygulanmamış bölünmeleri
pozisyona yansıtır — adet ×faktör, ort. maliyet ÷faktör (TOPLAM MALİYET sabit →
bölünme günü yapay %50 düşüş gibi görünmez). 'ADJUST' işleminden idempotent.

_symbol_splits yfinance .splits'e gider → mock'lanır.

Çalıştırma:  cd backend && pytest -q
"""

from datetime import datetime

import pytest

from app.services import order_service
from app.models.portfolio import Portfolio
from app.models.transaction import Transaction


def _patch_splits(monkeypatch, rows):
    """_symbol_splits'i sabit [(datetime, factor)] listesiyle değiştirir."""
    monkeypatch.setattr(
        "app.services.order_service._symbol_splits", lambda sym: list(rows))


def test_split_adjusts_qty_and_cost_keeping_total(db, make_user, monkeypatch):
    """2:1 bölünme → adet ×2, maliyet ÷2; toplam maliyet (adet×maliyet) sabit."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=10, average_cost=200.0))
    db.commit()
    _patch_splits(monkeypatch, [(datetime(2026, 5, 20), 2.0)])  # epoch (5-18) sonrası

    applied = order_service.reconcile_splits(db, user.id)

    assert applied == 1
    pos = db.query(Portfolio).filter_by(user_id=user.id, symbol="AAPL").one()
    assert pos.quantity == pytest.approx(20.0)        # 10×2
    assert pos.average_cost == pytest.approx(100.0)   # 200÷2
    assert pos.quantity * pos.average_cost == pytest.approx(10 * 200.0)  # toplam sabit


def test_split_is_idempotent(db, make_user, monkeypatch):
    """İki kez koşmak çift uygulamaz (ADJUST işleminden dedup)."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=10, average_cost=200.0))
    db.commit()
    _patch_splits(monkeypatch, [(datetime(2026, 5, 20), 2.0)])

    first = order_service.reconcile_splits(db, user.id)
    second = order_service.reconcile_splits(db, user.id)

    assert first == 1
    assert second == 0                                # ikinci tur uygulamaz
    pos = db.query(Portfolio).filter_by(user_id=user.id, symbol="AAPL").one()
    assert pos.quantity == pytest.approx(20.0)        # hâlâ tek kez
    n_adjust = db.query(Transaction).filter_by(
        user_id=user.id, transaction_type="ADJUST").count()
    assert n_adjust == 1


def test_split_before_epoch_ignored(db, make_user, monkeypatch):
    """_SPLIT_EPOCH'tan ÖNCEki bölünme uygulanmaz (forward-only; geçmiş drift'e
    dokunulmaz — kullanıcı tercihi)."""
    user = make_user()
    db.add(Portfolio(user_id=user.id, symbol="AAPL", quantity=10, average_cost=200.0))
    db.commit()
    _patch_splits(monkeypatch, [(datetime(2026, 5, 1), 2.0)])  # epoch (5-18) ÖNCESİ

    applied = order_service.reconcile_splits(db, user.id)

    assert applied == 0
    pos = db.query(Portfolio).filter_by(user_id=user.id, symbol="AAPL").one()
    assert pos.quantity == pytest.approx(10.0)        # değişmedi
    assert pos.average_cost == pytest.approx(200.0)


# ── Batch ısıtma (Yahoo istek sayısı) ─────────────────────────────────────

def test_prewarm_splits_uses_single_batch(monkeypatch):
    """`reconcile_splits` HER portföy okumasında çalışır. Eskiden sembol
    başına ayrı `yf.Ticker().splits` isteği gidiyordu → 40 pozisyonda soğuk
    açılış 40 ek Yahoo isteği, Render IP'si 429. Tek batch olmalı."""
    from app.core import cache as _cache
    from app.services import order_service as os_

    _cache._mem.clear()
    batch_calls = []

    def fake_batch(symbols):
        batch_calls.append(list(symbols))
        return set(symbols)

    def _boom(symbol):
        raise AssertionError(f"tek tek istek atıldı: {symbol}")

    monkeypatch.setattr(os_, "_prewarm_splits_batch", fake_batch)
    monkeypatch.setattr(os_, "_symbol_splits", _boom)

    os_.prewarm_splits(["AAPL", "NVDA", "THYAO.IS"])

    assert len(batch_calls) == 1
    assert sorted(batch_calls[0]) == ["AAPL", "NVDA", "THYAO.IS"]


def test_prewarm_splits_falls_back_for_symbols_batch_missed(monkeypatch):
    """Batch'in kapsamadığı sembol (kapsam dışı/bozuk) tek tek çekilmeli —
    sessizce bölünmesiz sayılmasın."""
    from app.core import cache as _cache
    from app.services import order_service as os_

    _cache._mem.clear()
    singles = []

    monkeypatch.setattr(os_, "_prewarm_splits_batch", lambda syms: {"AAPL"})
    monkeypatch.setattr(os_, "_symbol_splits", lambda s: singles.append(s) or [])

    os_.prewarm_splits(["AAPL", "WEIRD.XX"])
    assert singles == ["WEIRD.XX"]


def test_prewarm_splits_skips_fresh_cache(monkeypatch):
    """Taze cache varken ağa hiç çıkılmamalı."""
    from app.core import cache as _cache
    from app.services import order_service as os_

    _cache._mem.clear()
    _cache.set(os_._SPLITS_KEY + "AAPL", [], os_._SPLITS_TTL_SECONDS)

    def _boom(*a, **k):
        raise AssertionError("taze cache varken ağa çıkıldı")

    monkeypatch.setattr(os_, "_prewarm_splits_batch", _boom)
    monkeypatch.setattr(os_, "_symbol_splits", _boom)
    os_.prewarm_splits(["AAPL"])
