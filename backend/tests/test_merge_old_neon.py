"""Eski Neon projesinden veri birleştirme (scripts/merge_old_neon.py).

Bu script CANLI VERİYE yazıyor: eski Neon projesi kota resetiyle uyanınca
Umut'un pozisyon/işlem/izleme satırları yeni DB'ye taşınacak. En kritik
sözleşme "üstüne YAZMA": Kerem taşınmadan bu yana pozisyon ekledi.
"""

import importlib.util
from pathlib import Path

import pytest
import sqlalchemy as sa


@pytest.fixture
def merge_mod():
    path = (Path(__file__).resolve().parent.parent / "scripts"
            / "merge_old_neon.py")
    spec = importlib.util.spec_from_file_location("merge_old_neon", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_SCHEMA = [
    "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT)",
    "CREATE TABLE portfolios (id INTEGER PRIMARY KEY, user_id INTEGER, "
    "symbol TEXT, quantity REAL, average_cost REAL)",
    "CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id INTEGER, "
    "symbol TEXT, transaction_type TEXT, quantity REAL, price REAL, "
    "timestamp TEXT)",
    "CREATE TABLE watchlist_items (user_id INTEGER, symbol TEXT, "
    "position INTEGER, created_at TEXT, PRIMARY KEY (user_id, symbol))",
]


def _db(tmp_path, name: str) -> str:
    url = f"sqlite:///{tmp_path / name}"
    with sa.create_engine(url).begin() as conn:
        for ddl in _SCHEMA:
            conn.execute(sa.text(ddl))
    return url


def _exec(url: str, sql: str) -> None:
    with sa.create_engine(url).begin() as conn:
        conn.execute(sa.text(sql))


def _symbols(url: str, table: str = "portfolios") -> list[str]:
    with sa.create_engine(url).connect() as conn:
        return sorted(r[0] for r in
                      conn.execute(sa.text(f"SELECT symbol FROM {table}")))


def test_eposta_ile_eslesir_ve_ustune_yazmaz(tmp_path, merge_mod):
    old = _db(tmp_path, "old.db")
    new = _db(tmp_path, "new.db")

    # Eski DB: user_id 1; yeni DB'de AYNI kullanıcı id 7 → e-posta eşlemesi şart.
    _exec(old, "INSERT INTO users VALUES (1, 'umut@mail.com')")
    _exec(old, "INSERT INTO portfolios VALUES (1, 1, 'AAPL', 10, 100)")
    _exec(old, "INSERT INTO portfolios VALUES (2, 1, 'THYAO.IS', 5, 200)")
    _exec(new, "INSERT INTO users VALUES (7, 'umut@mail.com')")
    # Kerem taşınmadan SONRA aynı sembolü farklı adetle eklemiş.
    _exec(new, "INSERT INTO portfolios VALUES (1, 7, 'AAPL', 99, 999)")

    merge_mod.merge(old, new, apply=True)

    with sa.create_engine(new).connect() as conn:
        rows = {r[0]: (r[1], r[2], r[3]) for r in conn.execute(sa.text(
            "SELECT symbol, user_id, quantity, average_cost FROM portfolios"))}
    assert rows["AAPL"] == (7, 99, 999)      # DOKUNULMADI
    assert rows["THYAO.IS"] == (7, 5, 200)   # yeni satır, user_id remap edildi


def test_kuru_calisma_yazmaz(tmp_path, merge_mod):
    old = _db(tmp_path, "old.db")
    new = _db(tmp_path, "new.db")
    _exec(old, "INSERT INTO users VALUES (1, 'umut@mail.com')")
    _exec(old, "INSERT INTO portfolios VALUES (1, 1, 'AAPL', 10, 100)")
    _exec(new, "INSERT INTO users VALUES (1, 'umut@mail.com')")

    merge_mod.merge(old, new, apply=False)
    assert _symbols(new) == []


def test_eski_fon_sembolu_kanoniklestirilir(tmp_path, merge_mod):
    """Eski satırlarda fon kodları TLY.IS diye duruyor (.FON göçünden önce)."""
    old = _db(tmp_path, "old.db")
    new = _db(tmp_path, "new.db")
    _exec(old, "INSERT INTO users VALUES (1, 'umut@mail.com')")
    _exec(old, "INSERT INTO portfolios VALUES (1, 1, 'TLY.IS', 98, 6318.98)")
    _exec(new, "INSERT INTO users VALUES (1, 'umut@mail.com')")

    merge_mod.merge(old, new, apply=True)
    assert _symbols(new) == ["TLY.FON"]


def test_eslesmeyen_kullanici_atlanir(tmp_path, merge_mod):
    old = _db(tmp_path, "old.db")
    new = _db(tmp_path, "new.db")
    _exec(old, "INSERT INTO users VALUES (1, 'baskasi@mail.com')")
    _exec(old, "INSERT INTO portfolios VALUES (1, 1, 'AAPL', 10, 100)")
    _exec(new, "INSERT INTO users VALUES (1, 'umut@mail.com')")

    merge_mod.merge(old, new, apply=True)
    assert _symbols(new) == []


def test_islem_ve_izleme_satirlari_da_tasinir(tmp_path, merge_mod):
    old = _db(tmp_path, "old.db")
    new = _db(tmp_path, "new.db")
    _exec(old, "INSERT INTO users VALUES (1, 'umut@mail.com')")
    _exec(old, "INSERT INTO transactions VALUES "
               "(1, 1, 'AAPL', 'BUY', 10, 100, '2026-01-01')")
    _exec(old, "INSERT INTO watchlist_items VALUES (1, 'NVDA', 0, '2026-01-01')")
    _exec(new, "INSERT INTO users VALUES (1, 'umut@mail.com')")

    merge_mod.merge(old, new, apply=True)
    assert _symbols(new, "transactions") == ["AAPL"]
    assert _symbols(new, "watchlist_items") == ["NVDA"]

    merge_mod.merge(old, new, apply=True)          # iki kez çalıştır → çift yok
    assert _symbols(new, "transactions") == ["AAPL"]
