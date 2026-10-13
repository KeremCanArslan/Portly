"""Sektör dağılımı — "Diğer"in kapsamı + dilim içeriği (members).

İki regresyon noktası:
 1. Kripto/emtia/parite/endeks ve ETF'ler "Diğer"e DÜŞMEZ. Eskiden elle
    tutulan 9 sembollük liste dışındaki her enstrüman "Diğer" oluyordu →
    portföyün ~yarısı tek anlamsız dilimde toplanıyordu.
 2. Her sektör, içindeki pozisyonları `members` ile döndürür — UI "Diğer"
    diliminin içinde ne olduğunu gösterebilsin diye.

Ağ yok: Finnhub çağrısı ve fiyat/FX mock'lanır.
"""

import pytest

from app.models.portfolio import Portfolio
from app.services import portfolio_service


@pytest.fixture(autouse=True)
def _no_network(monkeypatch):
    """Finnhub + yfinance .info yollarını kapat, sektör cache'ini temizle."""
    monkeypatch.setattr(
        "app.services.finnhub_service.get_profile", lambda symbol: None)
    portfolio_service._sector_cache.clear()
    yield
    portfolio_service._sector_cache.clear()


# ── Son ek kuralı: elle liste tutmadan varlık sınıfı ──────────────────────

@pytest.mark.parametrize("symbol,expected", [
    ("BTC-USD", "Kripto"),
    ("XRP-USD", "Kripto"),      # _FALLBACK_SECTORS'te YOK — kural yakalamalı
    ("EURTRY=X", "Döviz"),
    ("HG=F", "Emtia"),          # bakır: listede yok
    ("^GSPC", "Endeks"),
    ("GC=F", "Altın"),          # açık haritada → kuralın önünde
])
def test_suffix_rules_keep_assets_out_of_other(symbol, expected):
    assert portfolio_service._resolve_sector(symbol) == expected


@pytest.mark.parametrize("symbol,expected", [
    ("THYAO.IS", "Ulaştırma"),
    ("LOGO.IS", "Teknoloji"),   # haritaya sonradan eklendi
    ("ENJSA.IS", "Enerji"),
    ("TRGYO.IS", "Gayrimenkul"),
])
def test_bist_map_covers_catalog(symbol, expected):
    assert portfolio_service._resolve_sector(symbol) == expected


def test_bist_sector_map_covers_whole_catalog():
    """bist_catalog'daki her hissenin sektörü olmalı — katalogda adı olup
    sektörü olmayan sembol sessizce "Diğer"e düşerdi."""
    from app.services.bist_catalog import CATALOG
    missing = [t for t in CATALOG if t not in portfolio_service._BIST_SECTORS]
    assert missing == [], f"sektörsüz BIST hissesi: {missing}"


def test_known_etf_is_labelled_as_fund_not_other():
    """Finnhub ETF'e sanayi vermez → eskiden "Diğer". Artık dürüst etiket."""
    assert portfolio_service._resolve_sector("SPY") == "Fon/ETF"
    assert portfolio_service._resolve_sector("SMH") == "Fon/ETF"


def test_unknown_symbol_still_falls_back_to_other():
    """Kural uydurmuyoruz: gerçekten tanınmayan sembol "Diğer" kalmalı."""
    assert portfolio_service._resolve_sector("ZZQQXX") == "Diğer"


# ── members: dilimin İÇİNDE ne var ────────────────────────────────────────

def test_breakdown_returns_members_per_sector(db, make_user, market):
    user = make_user()
    market.set_price("THYAO.IS", 300.0)   # Ulaştırma
    market.set_price("PGSUS.IS", 200.0)   # Ulaştırma
    market.set_price("ASELS.IS", 100.0)   # Savunma
    db.add_all([
        Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=10, average_cost=1),
        Portfolio(user_id=user.id, symbol="PGSUS.IS", quantity=5, average_cost=1),
        Portfolio(user_id=user.id, symbol="ASELS.IS", quantity=4, average_cost=1),
    ])
    db.commit()

    out = portfolio_service.get_sector_breakdown(db, user.id)
    by_name = {s["name"]: s for s in out["sectors"]}

    ulastirma = by_name["Ulaştırma"]
    assert ulastirma["value"] == pytest.approx(4000.0)   # 3000 + 1000
    syms = [m["symbol"] for m in ulastirma["members"]]
    assert syms == ["THYAO.IS", "PGSUS.IS"]              # değere göre azalan

    # members yüzdesi SEKTÖR içi paydır (portföy değil): 3000/4000, 1000/4000
    assert ulastirma["members"][0]["percent"] == pytest.approx(75.0)
    assert ulastirma["members"][1]["percent"] == pytest.approx(25.0)

    # Tek pozisyonlu sektör de members döndürür (UI 2'den azını açmaz).
    assert [m["symbol"] for m in by_name["Savunma"]["members"]] == ["ASELS.IS"]


def test_members_sum_matches_sector_value(db, make_user, market):
    """members toplamı sektör değerine EŞİT olmalı — donut'un alt görünümü
    üst dilimle aynı ₺ birimini (total_value_try) göstersin."""
    user = make_user()
    market.set_price("THYAO.IS", 300.0)
    market.set_price("BTC-USD", 1000.0)
    market.set_usdtry(40.0)
    db.add_all([
        Portfolio(user_id=user.id, symbol="THYAO.IS", quantity=10, average_cost=1),
        Portfolio(user_id=user.id, symbol="BTC-USD", quantity=2, average_cost=1),
    ])
    db.commit()

    out = portfolio_service.get_sector_breakdown(db, user.id)
    for sector in out["sectors"]:
        total = sum(m["value"] for m in sector["members"])
        assert total == pytest.approx(sector["value"], rel=1e-6)

    # BTC ₺'ye çevrilmeli (2 × $1000 × 40) — ham USD toplanırsa yüzdeler bozulur
    kripto = next(s for s in out["sectors"] if s["name"] == "Kripto")
    assert kripto["value"] == pytest.approx(80_000.0)


def test_breakdown_accepts_prebuilt_portfolio(db, make_user, market):
    """Sağlık skoru pozisyonları zaten yüklüyor; ikinci kez okunmamalı."""
    user = make_user()
    market.set_price("ASELS.IS", 100.0)
    db.add(Portfolio(user_id=user.id, symbol="ASELS.IS", quantity=3,
                     average_cost=1))
    db.commit()

    positions = portfolio_service.get_user_portfolio(db, user.id)

    def _boom(*a, **k):
        raise AssertionError("portföy ikinci kez okundu")

    import app.services.portfolio_service as ps
    original = ps.get_user_portfolio
    ps.get_user_portfolio = _boom
    try:
        out = ps.get_sector_breakdown(db, user.id, portfolio=positions)
    finally:
        ps.get_user_portfolio = original

    assert out["sectors"][0]["name"] == "Savunma"
    assert out["sectors"][0]["value"] == pytest.approx(300.0)


# ── Sektör ısıtması + `.info` devre kesicisi (4 Eyl 2026, 9. tur) ─────────
# Canlı ölçüm: soğuk /portfolio/1/health 7,5 sn, ikinci çağrı 0,28 sn. Sağlık
# skoru sektör dağılımına dayanıyor ve süreç-içi sözlük her uyanışta sıfır →
# çözüm bedeli kullanıcı isteğine biniyordu. Artık arka plan turu ısıtıyor.

def test_prewarm_resolves_only_uncached_symbols(monkeypatch):
    from app.core import cache
    cache.delete_prefix(portfolio_service._SECTOR_KEY)
    resolved = []
    monkeypatch.setattr(portfolio_service, "_resolve_sector",
                        lambda sym: resolved.append(sym) or "Teknoloji")
    portfolio_service._sector_cache["AAPL"] = "Teknoloji"

    warmed = portfolio_service.prewarm_sectors(["AAPL", "MSFT", "ASELS.IS"])

    assert resolved == ["MSFT", "ASELS.IS"], "cache'te olan sembol tekrar çözülmemeli"
    assert warmed == 2


def test_prewarm_respects_round_limit(monkeypatch):
    from app.core import cache
    cache.delete_prefix(portfolio_service._SECTOR_KEY)
    monkeypatch.setattr(portfolio_service, "_resolve_sector", lambda sym: "Diğer")

    warmed = portfolio_service.prewarm_sectors([f"S{i}" for i in range(20)], limit=3)

    assert warmed == 3, "tur başına tavan aşılmamalı (Finnhub ücretsiz tier)"


def test_info_is_skipped_while_breaker_is_open(monkeypatch):
    """Render'da `.info` BLOKLU: kesici kapalıyken sektör yolu denememeli —
    yoksa her sembolde boşuna saniyeler yanıyor (aynı uç, aynı ceza)."""
    from app.services import fundamental_analysis_service as fa
    portfolio_service._sector_cache.clear()
    from app.core import cache
    cache.delete_prefix(portfolio_service._SECTOR_KEY)

    def _boom(*a, **k):
        raise AssertionError("devre kesici kapalıyken .info denendi")

    monkeypatch.setattr(portfolio_service.yf, "Ticker", _boom)
    fa._info_blocked_until = fa.time.time() + 600

    assert portfolio_service._resolve_sector("ZZZZ") == "Diğer"


# ── Üretilmiş tam BIST haritası (app/data/bist_sectors.json) ─────────────
# Canlı geri bildirim: "BNTAS var mesela bende, ambalaj diye ayırsa mükemmel
# olurmuş" — elle haritada olmayan her BIST hissesi "Diğer"e düşüyordu.

@pytest.mark.parametrize("symbol,expected", [
    ("BNTAS.IS", "Ambalaj"),      # elle haritada YOK, üretilmiş haritada var
    ("KLKIM.IS", "Kimya"),
    ("ISDMR.IS", "Metal"),
    ("MPARK.IS", "Sağlık"),
])
def test_generated_map_covers_small_caps(symbol, expected):
    assert portfolio_service._resolve_sector(symbol) == expected


def test_manual_curation_wins_over_generated_map():
    """Elle kürasyon üstte: futbol kulüpleri 'Spor', çimentocular 'Çimento'."""
    assert portfolio_service._resolve_sector("FENER.IS") == "Spor"
    assert portfolio_service._resolve_sector("AKCNS.IS") == "Çimento"


def test_generated_map_is_loaded():
    """Dosya okunamazsa harita sessizce boşalır → kapsam çöker."""
    from app.services import bist_sectors
    assert len(bist_sectors.SECTORS) > 500
