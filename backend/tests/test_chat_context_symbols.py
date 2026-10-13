"""AI Koç bağlamında sembol gösterimi (4 Eylül 2026, 6. tur).

Kerem sohbette şu cevabı aldı: "özellikle TLY.FON ve GC=F gibi büyük ağırlıklı
varlıkların getirileri..." ve "bu GC=F her yerde karşıma çıkıyor, bu altın
demek, lütfen hiçbir yerde karşıma çıkmasın" dedi. Arayüzdeki `SymbolDisplay`
bunu düzeltemez — LLM çıktısı serbest metindir. Tek güvenilir yol: modele HAM
sembolü hiç vermemek (+ prompt kuralı).

Kayıt/sorgu/filtre HAM sembolde kalır; değişen yalnız modele giden metin.
"""

import pytest

from app.models.portfolio import Portfolio
from app.models.transaction import Transaction
from app.models.user import User
from app.services import chat_service


@pytest.fixture
def _user(db):
    u = User(email="sembol@test.com", full_name="Umut", hashed_password="x")
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


@pytest.fixture
def _fiyat(monkeypatch):
    monkeypatch.setattr(
        chat_service.market_data_service, "get_stock_data",
        lambda symbol, *a, **k: {"current_price": 100.0,
                                 "change_percent": 1.0,
                                 "change_available": True})


def test_baglamda_ham_yahoo_sembolu_gecmez(db, _user, _fiyat):
    for sym in ("GC=F", "TLY.FON", "KARCL.IS", "USDTRY=X"):
        db.add(Portfolio(user_id=_user.id, symbol=sym, quantity=5.0,
                         average_cost=50.0))
    db.commit()

    ctx = chat_service.build_user_context(db, _user.id)

    for ham in ("GC=F", "TLY.FON", "KARCL.IS", "USDTRY=X"):
        assert ham not in ctx, f"bağlamda ham sembol duruyor: {ham}"
    # Yerine okunabilir adlar geçmeli.
    assert "Altın" in ctx
    assert "USD/TRY" in ctx
    assert "TLY" in ctx and "KARCL" in ctx


def test_islem_gecmisi_satirinda_da_ham_sembol_yok(db, _user, _fiyat):
    db.add(Portfolio(user_id=_user.id, symbol="GC=F", quantity=5.0,
                     average_cost=50.0))
    db.add(Transaction(user_id=_user.id, symbol="GC=F", quantity=5.0,
                       price=50.0, transaction_type="BUY"))
    db.commit()

    ctx = chat_service.build_user_context(db, _user.id)

    assert "GC=F" not in ctx
    assert "ALIŞ Altın" in ctx


def test_sistem_prompt_sembol_kuralini_soyluyor():
    prompt = chat_service.get_system_prompt("(bağlam)")
    assert "SEMBOL YAZIM KURALI" in prompt
    assert "GC=F" in prompt  # neyin yazılmayacağı örnekle anlatılıyor
