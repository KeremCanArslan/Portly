"""Fiziki altın/gümüş portföy desteği (CEYREK.ALTIN, GRAM.GUMUS …).

Canlı geri bildirim: "ben altınımı somut tutuyorum, portföye onu da
ekleyebilsek efsane olurmuş" / "fiziki altınlarımın değeri kaç şuanda,
hepsini satsam ne kadar gelir".

Riskli noktalar (hepsi burada kilitli):
 1. Para birimi ₺ — USD sayılsaydı çeyrek altın portföyde ~40 katına çıkardı.
 2. Değerleme ALIŞ fiyatıyla — satış fiyatı makas kadar şişirirdi.
 3. Yahoo'ya SORULMAZ — bu semboller orada yok, her istek boşuna 429 riski.
 4. Sinyal/temettü üretilmez — mumu ve bilançosu olmayan varlık.

Ağ yok: fiyat kaynağı mock'lanır.
"""

import pytest
from fastapi.testclient import TestClient

from app.core.database import get_db
from app.core.limiter import limiter
from app.main import app
from app.services import gold_catalog


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    limiter.enabled = False
    try:
        yield TestClient(app)
    finally:
        app.dependency_overrides.clear()
        limiter.enabled = True


@pytest.fixture
def rates(monkeypatch):
    """gold_rates_service'in canlı çıktısının şekli (canlidoviz kesiti)."""
    data = {
        "market_buy": 6858.66,
        "market_sell": 6859.64,
        "reference_change": "%-0,57",
        "extra_products": [
            {"name": "Çeyrek Altın", "buy": 11109.80, "sell": 11285.35,
             "change": "%-0,67", "stale": False},
            {"name": "22 Ayar Bilezik", "buy": 6240.69, "sell": 6448.77,
             "change": "%-0,67", "stale": False},
            {"name": "Gümüş", "buy": 102.93, "sell": 103.03,
             "change": "%-0,10", "stale": False},
        ],
    }
    from app.services import gold_rates_service
    monkeypatch.setattr(gold_rates_service, "get_bank_gold_rates",
                        lambda: data)
    return gold_rates_service


# ── Katalog + arama ──────────────────────────────────────────────────────

def test_only_catalog_symbols_are_gold():
    assert gold_catalog.is_gold_symbol("CEYREK.ALTIN")
    assert not gold_catalog.is_gold_symbol("UYDURMA.ALTIN")
    # Sonek kontrolü uydurmayı da yakalar (Yahoo'ya gitmesin diye)
    assert gold_catalog.is_gold_suffix("UYDURMA.ALTIN")


@pytest.mark.parametrize("query,expected", [
    ("çeyrek", "CEYREK.ALTIN"),
    ("ceyrek", "CEYREK.ALTIN"),      # Türkçe karakter katlanır
    ("bilezik", "BILEZIK22.ALTIN"),
    ("fiziki altin", "GRAM.ALTIN"),  # anahtar kelime
    ("gram gümüş", "GRAM.GUMUS"),
])
def test_search_finds_products(query, expected):
    symbols = [r["symbol"] for r in gold_catalog.search(query)]
    assert expected in symbols


# ── Fiyat ────────────────────────────────────────────────────────────────

def test_quote_uses_buy_price_not_sell(rates):
    """"Hepsini satsam ne kadar gelir" → satarken alınan fiyat ALIŞ'tır."""
    q = rates.get_quotes(["CEYREK.ALTIN"])["CEYREK.ALTIN"]
    assert q["current_price"] == 11109.80
    assert q["ask_price"] == 11285.35        # yeni alacaksa ödeyeceği
    assert q["company_name"] == "Çeyrek Altın"
    assert q["change_percent"] == -0.67


def test_gram_gold_comes_from_reference_fields(rates):
    """"Gram Altın" ürün listesinde YOK — serbest piyasa referansı odur."""
    q = rates.get_quotes(["GRAM.ALTIN"])["GRAM.ALTIN"]
    assert q["current_price"] == 6858.66


def test_unknown_symbols_ignored(rates):
    assert rates.get_quotes(["AAPL", "TLY.FON"]) == {}


# ── Portföy bütünlüğü ────────────────────────────────────────────────────

@pytest.mark.parametrize("symbol", ["CEYREK.ALTIN", "GRAM.GUMUS"])
def test_currency_is_try(symbol):
    """En pahalı hata: fiziki altını USD sayıp kurla çarpmak."""
    from app.services import fx_service, stress_test_service
    assert fx_service.currency_of(symbol) == "TRY"
    assert stress_test_service._symbol_currency(symbol) == "TRY"


def test_sector_labels():
    from app.services import portfolio_service
    assert portfolio_service._resolve_sector("CEYREK.ALTIN") == "Altın"
    assert portfolio_service._resolve_sector("GRAM.GUMUS") == "Gümüş"


def test_not_sent_to_yahoo_batch(monkeypatch):
    from app.services import market_data_service as m
    seen: list[list[str]] = []
    monkeypatch.setattr(m, "_fetch_quotes_batch",
                        lambda syms: seen.append(syms) or {})
    monkeypatch.setattr(m, "_fetch_many_via_download", lambda syms: {})
    m._fetch_many(["AAPL", "CEYREK.ALTIN"])
    assert seen == [["AAPL"]]


def test_history_is_empty_with_reason():
    """Grafik uydurulmaz: seri yok, gerekçe var."""
    from app.services import market_data_service as m
    out = m.get_stock_history("CEYREK.ALTIN", "1mo")
    assert out["data"] == []
    assert "geçmiş fiyat serisi yok" in out["unavailable_reason"]


def test_no_market_state_dot():
    """Kuyumcunun borsa seansı yok → açık/kapalı noktası çizilmez."""
    from app.services import market_data_service as m
    assert m.market_state_of("CEYREK.ALTIN") is None


def test_no_dividend_lookup():
    from app.services import dividend_service
    assert dividend_service._symbol_dividends("CEYREK.ALTIN") == {
        "symbol": "CEYREK.ALTIN", "has_dividend": False}


def test_classified_as_physical():
    """Sinyal taraması bu sınıfı atlar (mum/oran yok)."""
    from app.services.fundamental_analysis_service import _classify
    assert _classify("CEYREK.ALTIN") == "physical"
    assert _classify("GRAM.GUMUS") == "physical"
    assert _classify("THYAO.IS") == "stock"


# ── Uçtan uca: portföye ekleme ve ₺ değerleme ────────────────────────────

def test_gold_position_end_to_end(client, db, market):
    """5 çeyrek altın ekle → portföyde ₺ değeriyle görünsün.

    En pahalı hata burada yakalanır: fiziki altın USD sayılsaydı 5 × 11.110 ₺
    değil 5 × 11.110 × 40 ₺ görünürdü."""
    from app.models.user import User

    r = client.post("/api/v1/auth/register",
                    json={"email": "altin@mail.com", "password": "testpass1"})
    hdr = {"Authorization": f"Bearer {r.json()['access_token']}"}
    uid = db.query(User).filter_by(email="altin@mail.com").one().id

    market.set_price("CEYREK.ALTIN", 11109.80)
    add = client.post("/api/v1/trading/manual-position", headers=hdr, json={
        "user_id": uid, "symbol": "CEYREK.ALTIN",
        "quantity": 5, "avg_cost": 9000.0})
    assert add.status_code == 200, add.text

    rows = client.get(f"/api/v1/portfolio/{uid}", headers=hdr).json()
    gold = next(x for x in rows if x["symbol"] == "CEYREK.ALTIN")
    assert gold["current_price"] == pytest.approx(11109.80)
    # Kur 40 iken USD sansaydı bu 2.221.960 ₺ olurdu
    assert gold["total_value"] == pytest.approx(55549.0)


def test_gold_lands_in_gold_sector(client, db, market):
    from app.models.user import User

    r = client.post("/api/v1/auth/register",
                    json={"email": "altin2@mail.com", "password": "testpass1"})
    hdr = {"Authorization": f"Bearer {r.json()['access_token']}"}
    uid = db.query(User).filter_by(email="altin2@mail.com").one().id

    market.set_price("TAM.ALTIN", 44302.03)
    client.post("/api/v1/trading/manual-position", headers=hdr, json={
        "user_id": uid, "symbol": "TAM.ALTIN",
        "quantity": 2, "avg_cost": 40000.0})

    body = client.get(f"/api/v1/portfolio/{uid}/sectors", headers=hdr).json()
    gold = next(s for s in body["sectors"] if s["name"] == "Altın")
    assert gold["percent"] == pytest.approx(100.0)
    assert [m["symbol"] for m in gold["members"]] == ["TAM.ALTIN"]
