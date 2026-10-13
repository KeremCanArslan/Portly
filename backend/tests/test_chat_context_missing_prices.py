"""AI Koç bağlamı: fiyatı alınamayan pozisyonlar.

Bağlam (canlıda görüldü, 3 Eyl): Yahoo kısıtlıyken portföyün çoğu pozisyonun
fiyatı gelmedi; ağırlıklar yalnız fiyatı BİLİNEN 5 pozisyon üzerinden
hesaplandığı için model "portföyünde beş farklı varlık bulunuyor" dedi —
oysa kullanıcının 38 pozisyonu vardı. Model, eksik veriyi bilmediği için
kullanıcının portföyü hakkında YANLIŞ kesin hüküm kurdu.

Kural: bağlam eksikliği AÇIKÇA söylemeli (arayüzdeki "N pozisyonun fiyatı
alınamadı" notunun karşılığı) ve sistem prompt'u modele bunu nasıl
anlatacağını söylemeli.
"""

import pytest

from app.models.portfolio import Portfolio
from app.models.user import User
from app.services import chat_service


@pytest.fixture
def _user(db):
    u = User(email="koc@test.com", full_name="Umut", hashed_password="x")
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def _add(db, uid, symbol, qty=10.0, cost=100.0):
    db.add(Portfolio(user_id=uid, symbol=symbol, quantity=qty,
                     average_cost=cost))
    db.commit()


def test_fiyati_alinamayan_pozisyonlar_baglamda_uyarilir(
        db, _user, monkeypatch):
    for sym in ("AAPL", "THYAO.IS", "ASELS.IS", "TUPRS.IS"):
        _add(db, _user.id, sym)

    # Yalnız AAPL'ın fiyatı geliyor (Yahoo kısıtlı senaryosu).
    def _fake(symbol, *a, **k):
        if symbol == "AAPL":
            return {"current_price": 200.0, "change_percent": 1.0,
                    "change_available": True}
        raise RuntimeError("kaynak erişilemez")

    monkeypatch.setattr(chat_service.market_data_service, "get_stock_data",
                        _fake)

    ctx = chat_service.build_user_context(db, _user.id)
    assert "UYARI: 3 pozisyonun güncel fiyatı ALINAMADI" in ctx
    assert "yalnızca fiyatı bilinen 1 pozisyondan" in ctx.lower() \
        or "YALNIZCA fiyatı bilinen 1 pozisyondan" in ctx
    assert "toplam 4 pozisyondur" in ctx


def test_hepsi_geliyorsa_uyari_yok(db, _user, monkeypatch):
    _add(db, _user.id, "AAPL")
    monkeypatch.setattr(
        chat_service.market_data_service, "get_stock_data",
        lambda symbol, *a, **k: {"current_price": 200.0,
                                 "change_percent": 1.0,
                                 "change_available": True})
    ctx = chat_service.build_user_context(db, _user.id)
    assert "ALINAMADI" not in ctx


def test_sistem_prompt_eksik_veriyi_anlatmayi_soyluyor():
    prompt = chat_service.get_system_prompt("(bağlam)")
    assert "güncel fiyat alınamadı" in prompt
    assert "N varlıktan oluşuyor" in prompt
