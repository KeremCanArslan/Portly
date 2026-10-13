"""C4 — Temettü tahsilatı (gelir kaydı) regresyon testleri.

collect_virtual_dividends finansal açıdan hassas: DIVIDEND gelir kaydı düşer
(pivot: sanal nakit yok → bakiye mutasyonu YOK), idempotent olmalı (çift
tahsil = sahte gelir), USD temettüyü kurla çevirmeli ama _collected_summary
kuru YENİDEN uygulamamalı (DIVIDEND.price zaten ₺/adet kilitli). Bu testler
o davranışların nöbetçisi.

`_dividends_raw` yfinance'e gider → mock'lanır (tz-bilgili pandas Series).
FX rate fx_service üzerinden okunur → `market` fixture'ı sağlar (ağ yok).

Çalıştırma:  cd backend && pytest -q
"""

from datetime import datetime, timedelta, timezone

import pandas as pd
import pytest

from app.services import dividend_service
from app.models.portfolio import Portfolio
from app.models.transaction import Transaction


def _div_series(rows):
    """rows = [(tz-bilgili datetime, hisse_başı_tutar), ...] → pandas Series
    (yfinance .dividends ile aynı şekil: tz-bilgili DatetimeIndex)."""
    idx = pd.DatetimeIndex([pd.Timestamp(d) for d, _ in rows])
    return pd.Series([float(a) for _, a in rows], index=idx)


def _patch_divs(monkeypatch, series_by_symbol):
    """dividend_service._dividends_raw'ı sembol→(Series, cal) sözlüğüyle
    değiştirir; bilinmeyen sembol (None, None) (yfinance boş gibi)."""
    def fake(symbol):
        s = series_by_symbol.get((symbol or "").upper())
        return (s, None) if s is not None else (None, None)
    monkeypatch.setattr(
        "app.services.dividend_service._dividends_raw", fake)


def _give_holding(db, user, symbol, qty, avg_cost, buy_date):
    """Portföye pozisyon + onu doğuran BUY işlemi (edinim tarihiyle) ekler —
    temettü cutoff'u ilk alımı baz alır."""
    db.add(Portfolio(user_id=user.id, symbol=symbol,
                     quantity=qty, average_cost=avg_cost))
    db.add(Transaction(user_id=user.id, symbol=symbol, transaction_type="BUY",
                       quantity=qty, price=avg_cost, timestamp=buy_date))
    db.commit()


def _div_count(db, user):
    return db.query(Transaction).filter_by(
        user_id=user.id, transaction_type="DIVIDEND").count()


# ── BIST (₺ doğrudan) ─────────────────────────────────────────────────────

def test_bist_dividend_credited_in_try(db, market, make_user, monkeypatch):
    """BIST temettüsü ₺ gelir olarak kaydedilir; DIVIDEND.price = ₺/adet."""
    now = datetime.now(timezone.utc)
    user = make_user(balance=100000.0)
    _give_holding(db, user, "THYAO.IS", 100, 50.0,
                  (now - timedelta(days=180)).replace(tzinfo=None))
    _patch_divs(monkeypatch, {"THYAO.IS": _div_series(
        [(now - timedelta(days=90), 2.0)])})

    res = dividend_service.collect_virtual_dividends(db, user.id)

    assert res["credited"] == pytest.approx(200.0)        # 2.0 × 100
    tx = db.query(Transaction).filter_by(
        user_id=user.id, transaction_type="DIVIDEND").one()
    assert tx.price == pytest.approx(2.0)                  # ₺/adet kilitli
    assert tx.quantity == pytest.approx(100.0)


# ── USD (kur çevrimi + çift-çevrim koruması) ──────────────────────────────

def test_usd_dividend_converted_at_fx(db, market, make_user, monkeypatch):
    """USD temettü güncel kurla ₺'ye çevrilir; DIVIDEND.price = ₺/adet (kilitli)."""
    market.set_usdtry(40.0)
    now = datetime.now(timezone.utc)
    user = make_user(balance=100000.0)
    _give_holding(db, user, "AAPL", 10, 150.0,
                  (now - timedelta(days=180)).replace(tzinfo=None))
    _patch_divs(monkeypatch, {"AAPL": _div_series(
        [(now - timedelta(days=90), 0.5)])})

    res = dividend_service.collect_virtual_dividends(db, user.id)

    assert res["credited"] == pytest.approx(0.5 * 10 * 40)   # ₺200
    tx = db.query(Transaction).filter_by(
        user_id=user.id, transaction_type="DIVIDEND").one()
    assert tx.price == pytest.approx(0.5 * 40)               # ₺/adet = 20


def test_usd_dividend_not_double_converted_in_summary(db, market, make_user, monkeypatch):
    """_collected_summary FX'i YENİDEN uygulamamalı: tahsil edilen ₺ neyse
    'şimdiye dek alınan' o (200), 200×40 değil."""
    market.set_usdtry(40.0)
    now = datetime.now(timezone.utc)
    user = make_user(balance=100000.0)
    _give_holding(db, user, "AAPL", 10, 150.0,
                  (now - timedelta(days=180)).replace(tzinfo=None))
    _patch_divs(monkeypatch, {"AAPL": _div_series(
        [(now - timedelta(days=90), 0.5)])})

    dividend_service.collect_virtual_dividends(db, user.id)
    summary = dividend_service._collected_summary(db, user.id)

    assert summary["total_try"] == pytest.approx(200.0)


# ── İdempotency (çift tahsil = sahte nakit) ───────────────────────────────

def test_collect_is_idempotent(db, market, make_user, monkeypatch):
    """Aynı temettü iki kez tahsil edilmez (ikinci çağrı 0 kredi, tek kayıt)."""
    now = datetime.now(timezone.utc)
    user = make_user(balance=100000.0)
    _give_holding(db, user, "THYAO.IS", 100, 50.0,
                  (now - timedelta(days=180)).replace(tzinfo=None))
    _patch_divs(monkeypatch, {"THYAO.IS": _div_series(
        [(now - timedelta(days=90), 2.0)])})

    first = dividend_service.collect_virtual_dividends(db, user.id)
    second = dividend_service.collect_virtual_dividends(db, user.id)

    assert first["credited"] == pytest.approx(200.0)
    assert second["credited"] == pytest.approx(0.0)        # zaten tahsil edildi
    assert _div_count(db, user) == 1                       # tek kayıt


# ── dry_run (önizleme) yan etkisiz ────────────────────────────────────────

def test_dry_run_has_no_side_effects(db, market, make_user, monkeypatch):
    """dry_run: credited hesaplanır ama DIVIDEND kaydı yazılmaz."""
    now = datetime.now(timezone.utc)
    user = make_user(balance=100000.0)
    _give_holding(db, user, "THYAO.IS", 100, 50.0,
                  (now - timedelta(days=180)).replace(tzinfo=None))
    _patch_divs(monkeypatch, {"THYAO.IS": _div_series(
        [(now - timedelta(days=90), 2.0)])})

    res = dividend_service.collect_virtual_dividends(db, user.id, dry_run=True)

    assert res["credited"] == pytest.approx(200.0)
    assert _div_count(db, user) == 0                       # yan etki yok


# ── Tarih kapıları ────────────────────────────────────────────────────────

def test_dividend_before_purchase_skipped(db, market, make_user, monkeypatch):
    """Alımdan ÖNCEki ex-temettü tahsil edilmez (sahibi değildin)."""
    now = datetime.now(timezone.utc)
    user = make_user(balance=100000.0)
    _give_holding(db, user, "THYAO.IS", 100, 50.0,
                  (now - timedelta(days=90)).replace(tzinfo=None))   # alım 90g önce
    _patch_divs(monkeypatch, {"THYAO.IS": _div_series(
        [(now - timedelta(days=100), 2.0)])})                        # div 100g önce

    res = dividend_service.collect_virtual_dividends(db, user.id)

    assert res["credited"] == pytest.approx(0.0)
    assert _div_count(db, user) == 0


def test_dividend_older_than_one_year_skipped(db, market, make_user, monkeypatch):
    """365 günden eski ex-temettü cutoff'la elenir."""
    now = datetime.now(timezone.utc)
    user = make_user(balance=100000.0)
    _give_holding(db, user, "THYAO.IS", 100, 50.0,
                  (now - timedelta(days=800)).replace(tzinfo=None))
    _patch_divs(monkeypatch, {"THYAO.IS": _div_series(
        [(now - timedelta(days=400), 2.0)])})                        # 400g önce

    res = dividend_service.collect_virtual_dividends(db, user.id)

    assert res["credited"] == pytest.approx(0.0)
