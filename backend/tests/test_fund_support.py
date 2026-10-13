"""TEFAS yatırım fonu desteği (TLY.FON, LTL.FON …).

Bağlam: Kerem'in portföyündeki `TLY` ve `LTL` TEFAS yatırım fonuydu; ekstre
içe aktarımı kur TRY diye sonlarına ".IS" ekleyip BIST hissesi sanıyor, Yahoo
bunları HİÇ kapsamadığı için pozisyonlar "Fiyat —" görünüyor ve portföy değeri
maliyetle sayılıyordu. Bu testler ağa ÇIKMAZ: HTTP katmanı sahte yanıtla
değiştirilir.
"""

import pytest

from app.core import cache
from app.services import fund_catalog
from app.services import fund_source_service as fss
from app.services import market_data_service as mds


# conftest'teki autouse fixture yedek kaynakları "veri yok"a sabitliyor.
# Bu dosya TAM DA fon kaynağını sınıyor → gerçek fonksiyonları geri koy.
_REAL = {
    "quotes": fss.get_quotes,
    "closes": fss.get_daily_closes,
    "ohlcv": fss.get_daily_ohlcv,
    "rows": fss.get_history_rows,
}


@pytest.fixture(autouse=True)
def _real_fund_source(monkeypatch):
    monkeypatch.setattr(fss, "get_quotes", _REAL["quotes"])
    monkeypatch.setattr(fss, "get_daily_closes", _REAL["closes"])
    monkeypatch.setattr(fss, "get_daily_ohlcv", _REAL["ohlcv"])
    monkeypatch.setattr(fss, "get_history_rows", _REAL["rows"])
    cache._mem.clear()
    fss._blocked_until = 0.0
    yield
    cache._mem.clear()


def _series(days: int = 30, start: float = 100.0, step: float = 1.0):
    """{gün: birim pay değeri} — 2026-01-01'den itibaren artan seri."""
    from datetime import date, timedelta
    base = date(2026, 1, 1)
    return {(base + timedelta(days=i)).isoformat(): start + i * step
            for i in range(days)}


def _use_series(monkeypatch, series, code="TLY"):
    monkeypatch.setattr(fss, "_fetch_series",
                        lambda c, client, _s=series: _s if c == code else None)


# ── Katalog / sembol biçimi ─────────────────────────────────────────────────
def test_katalog_dolu_ve_kodlar_uc_harf():
    assert len(fund_catalog.CATALOG) > 500
    assert all(len(code) == 3 for code in fund_catalog.CATALOG)


def test_sembol_bicimi():
    assert fund_catalog.to_symbol("tly") == "TLY.FON"
    assert fund_catalog.code_of("TLY.FON") == "TLY"
    assert fund_catalog.is_fund_symbol("TLY.FON")
    assert not fund_catalog.is_fund_symbol("THYAO.IS")


def test_arama_kod_ve_unvanla_bulur():
    assert any(r["symbol"] == "TLY.FON" for r in fund_catalog.search("TLY"))
    hits = fund_catalog.search("tera birinci", limit=5)
    assert any(r["symbol"] == "TLY.FON" for r in hits)
    assert all(r["market"] == "TEFAS" for r in hits)


# ── Kaynak sözleşmesi ───────────────────────────────────────────────────────
def test_fiyat_ve_gunluk_degisim(monkeypatch):
    _use_series(monkeypatch, _series(days=5, start=10.0, step=0.5))
    quote = fss.get_quotes(["TLY.FON"])["TLY.FON"]
    assert quote["current_price"] == 12.0            # 10 + 4*0,5
    assert quote["change_percent"] == pytest.approx(4.35, abs=0.02)
    assert "TERA" in quote["company_name"]           # katalogdan resmi unvan


def test_fiyat_alti_basamak_korunur(monkeypatch):
    """Birim pay değeri 1,096196 gibi olabiliyor — 2 basamak binde 3 hata."""
    _use_series(monkeypatch, {"2026-01-01": 1.0, "2026-01-02": 1.096196})
    assert fss.get_quotes(["TLY.FON"])["TLY.FON"]["current_price"] == 1.096196


def test_ohlcv_gun_ici_aralik_uydurmaz(monkeypatch):
    _use_series(monkeypatch, _series(days=10))
    bars = fss.get_daily_ohlcv(["TLY.FON"], days=365)["TLY.FON"]
    assert bars["open"] == bars["high"] == bars["low"] == bars["close"]
    assert set(bars["volume"]) == {0.0}              # uydurma hacim YOK


def test_pencere_takvim_gunune_gore_kesilir(monkeypatch):
    """Fon yalnız iş günü fiyat açıklar → 'son N satır' N takvim günü etmez."""
    _use_series(monkeypatch, _series(days=60))
    bars = fss.get_daily_ohlcv(["TLY.FON"], days=10)["TLY.FON"]
    assert len(bars["date"]) == 11                   # 10 günlük pencere + sınır
    assert bars["date"][-1] == "2026-03-01"   # 1 Oca + 59 gün


def test_kaynak_cevap_vermezse_bos_doner(monkeypatch):
    monkeypatch.setattr(fss, "_fetch_series", lambda code, client: None)
    assert fss.get_quotes(["TLY.FON"]) == {}


def test_429_devre_kesici(monkeypatch):
    """TEFAS 429 verince modül susar — ceza uzatılmasın."""
    calls = []

    class _R:
        status_code = 429

        def json(self):
            return {}

    class _C:
        def post(self, *a, **k):
            calls.append(1)
            return _R()

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    monkeypatch.setattr(fss.httpx, "Client", lambda *a, **k: _C())
    assert fss.get_quotes(["TLY.FON", "LTL.FON"]) == {}
    assert len(calls) == 1                # ilk 429'dan sonra ikinciyi denemez
    assert not fss.available()


def test_bayat_seri_kaynak_dusunce_servis_edilir(monkeypatch):
    """Kaynak düştüğünde "veri yok" demektense son bilinen fiyatı ver."""
    _use_series(monkeypatch, _series(days=5))
    assert fss.get_quotes(["TLY.FON"])                       # cache dolsun
    monkeypatch.setattr(fss, "_fetch_series", lambda code, client: None)
    monkeypatch.setattr(fss, "_FRESH_SECONDS", -1)           # her şey bayat
    assert "TLY.FON" in fss.get_quotes(["TLY.FON"])


# ── market_data_service yönlendirmesi ───────────────────────────────────────
def test_fon_yahoo_batchine_girmez(monkeypatch):
    """Yahoo TEFAS fonlarını kapsamıyor → batch'i kirletmesin."""
    seen = {}

    def _fake_download(symbols, **kwargs):
        seen["symbols"] = symbols
        raise RuntimeError("çağrılmamalıydı" if not symbols else "boş")

    monkeypatch.setattr(mds.yf, "download", _fake_download)
    assert mds._fetch_many(["TLY.FON"]) == {}
    assert "symbols" not in seen                     # hiç indirmeye gitmedi


def test_batch_fiyat_fonu_tefas_kaynagindan_alir(monkeypatch):
    _use_series(monkeypatch, _series(days=5, start=20.0))
    monkeypatch.setattr(mds, "_fetch_many", lambda symbols: {})
    out = mds.get_stock_prices(["TLY.FON"])
    assert out["TLY.FON"]["current_price"] == 24.0


def test_grafik_fonda_gunluk_dondurur(monkeypatch):
    _use_series(monkeypatch, _series(days=40))
    hist = mds.get_stock_history("TLY.FON", period="1mo")
    assert hist["interval"] == "1d"                  # istenen 1h olsa bile
    assert hist["data_points"] > 0
    assert hist["data"][-1]["volume"] == 0


def test_bilinmeyen_fon_kodu_404(monkeypatch):
    from fastapi import HTTPException
    monkeypatch.setattr(fss, "_fetch_series", lambda code, client: None)
    with pytest.raises(HTTPException) as exc:
        mds.get_stock_data("ZZZ.FON")
    assert exc.value.status_code == 404               # katalogda yok
    with pytest.raises(HTTPException) as exc:
        mds.get_stock_data("TLY.FON")
    assert exc.value.status_code == 503               # var ama kaynak sessiz


def test_aramada_fon_yahoo_dusse_bile_gelir(monkeypatch):
    def _boom(*a, **k):
        raise RuntimeError("Yahoo 429")
    monkeypatch.setattr(mds.yf, "Search", _boom)
    mds._search_cache.clear()
    results = mds.search_symbols("TLY", limit=5)
    assert any(r["symbol"] == "TLY.FON" for r in results)


# ── Sembol çözümü: fon mu hisse mi? ─────────────────────────────────────────
def test_ekstre_ice_aktarimi_fona_is_eklemez():
    from app.services.statement_import_service import resolve_symbol
    assert resolve_symbol("TLY", "TRY") == "TLY.FON"
    assert resolve_symbol("THYAO", "TRY") == "THYAO.IS"
    assert resolve_symbol("AKBNK", "TRY") == "AKBNK.IS"


def test_ayni_kod_usd_hesabinda_fon_sayilmaz():
    """'URA' HEM bir TEFAS fonu HEM Global X Uranium ETF'i — kur belirler."""
    from app.services.statement_import_service import resolve_symbol
    from app.services.symbol_alias import canonical
    assert fund_catalog.is_known_code("URA")
    assert resolve_symbol("URA", "USD") == "URA"
    assert canonical("URA") == "URA"          # çıplak koda ASLA dokunma


def test_eski_is_bicimi_calisma_aninda_fona_donusur():
    from app.services.symbol_alias import canonical
    assert canonical("TLY.IS") == "TLY.FON"
    assert canonical("THYAO.IS") == "THYAO.IS"    # 5 harfli BIST kodu korunur


def test_genel_ekstrede_uc_harfli_kod_fon_adayi():
    from app.services.statement_generic import _detect_symbol
    assert _detect_symbol("01/06/26 TLY ALIS 98 6318,98") == "TLY.FON"


# ── Para birimi / sektör / varlık sınıfı ────────────────────────────────────
def test_fon_para_birimi_try():
    from app.services import fx_service
    from app.services.benchmark_service import _is_try_symbol
    from app.services.dividend_service import _is_try
    from app.services.stress_test_service import _symbol_currency
    assert fx_service.currency_of("TLY.FON") == "TRY"
    assert _symbol_currency("TLY.FON") == "TRY"
    assert _is_try("TLY.FON") and _is_try_symbol("TLY.FON")


def test_fon_sektoru_fon_etf():
    from app.services.portfolio_service import _sector_from_suffix
    assert _sector_from_suffix("TLY.FON") == "Fon/ETF"


def test_varlik_sinifi_fon():
    from app.services.fundamental_analysis_service import _classify
    assert _classify("TLY.FON") == "fund"
    assert _classify("AAPL") == "stock"


# ── Sinyal: uydurma teknik sinyal üretme ────────────────────────────────────
def _indicator_stub(monkeypatch, closes):
    from app.services import signal_service as ss
    from app.services import technical_analysis_service as tas
    monkeypatch.setattr(
        mds, "get_daily_ohlcv",
        lambda symbols, period="6mo": {
            s.upper(): {"date": [], "open": closes, "high": closes,
                        "low": closes, "close": closes,
                        "volume": [0.0] * len(closes)}
            for s in symbols})
    ss._signal_cache.clear()
    return ss, tas


def test_birikimli_fonda_asiri_alim_sinyali_uretilmez(monkeypatch):
    """Para piyasası fonu hiç düşmez → RSI daima 100. Motor bunu 'aşırı alım,
    geri çekilme riski' diye okuyordu; fonun düşmemesi ürünün doğası."""
    ss, _ = _indicator_stub(monkeypatch, [100.0 + i for i in range(200)])
    sig = ss.get_signal("TLY.FON")
    assert sig["asset_class"] == "fund"
    assert sig["signal"] == "TUT"
    assert not any("geri çekilme riski" in r for r in sig["reasons"])
    assert any("birikimli" in r for r in sig["reasons"])


def test_dalgalanan_fonda_teknik_kurallar_isler(monkeypatch):
    """Hisse senedi fonu piyasayı takip eder → teknik kurallar anlamlı."""
    closes = [100.0 + (5 if i % 2 else -4) * (i / 40) for i in range(200)]
    ss, _ = _indicator_stub(monkeypatch, closes)
    sig = ss.get_signal("LTL.FON")
    assert sig["fundamental_available"] is False     # F/K-ROE uygulanmaz
    assert any("F/K" in r for r in sig["reasons"])


# ── Veri göçü: eski TLY.IS satırları ────────────────────────────────────────
def test_gocu_yalnizca_fon_kodlarini_tasir(monkeypatch):
    """Alembic göçü ağa çıkmadan, YALNIZ 3 harfli fon kodlarına dokunmalı.
    BIST kodları (5 harf) ve çıplak ABD tickerları olduğu gibi kalmalı."""
    import importlib.util
    from pathlib import Path

    import sqlalchemy as sa
    from alembic import op

    path = (Path(__file__).resolve().parent.parent / "alembic" / "versions"
            / "b7d1f4c2e8a9_fund_symbols_to_fon.py")
    spec = importlib.util.spec_from_file_location("mig_fund", path)
    mig = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mig)

    engine = sa.create_engine("sqlite://")
    with engine.begin() as conn:
        conn.execute(sa.text("CREATE TABLE portfolios (id INTEGER, symbol TEXT)"))
        conn.execute(sa.text("CREATE TABLE watchlist_items (id INTEGER, symbol TEXT)"))
        for sym in ("TLY.IS", "LTL.IS", "THYAO.IS", "URA", "AAPL"):
            conn.execute(sa.text("INSERT INTO portfolios VALUES (1, :s)"),
                         {"s": sym})
        conn.execute(sa.text("INSERT INTO watchlist_items VALUES (1, 'TLY.IS')"))

        monkeypatch.setattr(op, "get_bind", lambda: conn)
        mig.upgrade()
        got = sorted(r[0] for r in
                     conn.execute(sa.text("SELECT symbol FROM portfolios")))
        assert got == ["AAPL", "LTL.FON", "THYAO.IS", "TLY.FON", "URA"]
        assert conn.execute(
            sa.text("SELECT symbol FROM watchlist_items")).scalar() == "TLY.FON"

        mig.downgrade()                      # geri alınabilir olmalı
        assert sorted(r[0] for r in
                      conn.execute(sa.text("SELECT symbol FROM portfolios"))) == [
            "AAPL", "LTL.IS", "THYAO.IS", "TLY.IS", "URA"]
