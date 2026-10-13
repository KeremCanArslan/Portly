# =============================================================================
# Eski Neon projesinden (askıya alınan "portly" DB) veri BİRLEŞTİRME
#
# Bağlam: eski Neon projesi ücretsiz katman compute kotasını doldurup askıya
# alındı; canlı DB yeni projeye (`portly-2`) taşındı. Eski projenin verisi
# silinmedi — kota resetlenince erişilebilir. Bu script Umut'un eski
# satırlarını yeni DB'ye TAŞIR, üstüne YAZMAZ.
#
# Kurallar:
#   - Kullanıcı eşleşmesi E-POSTA ile (id'ler iki DB'de farklı olabilir).
#   - Yeni DB'de olmayan satır eklenir; VAR OLAN SATIRA DOKUNULMAZ
#     (Kerem taşınmadan sonra pozisyon ekledi — üstüne yazmak veri kaybı olur).
#   - Semboller kanonikleştirilir (eski satırlarda TLY.IS gibi fon kodları
#     olabilir → TLY.FON; bkz. symbol_alias.canonical).
#   - VARSAYILAN KURU ÇALIŞMA: ne yapacağını yazar, yazmaz. Gerçekten
#     yazmak için `--apply`.
#
# Kullanım:
#   cd backend
#   venv/bin/python -m scripts.merge_old_neon --old "postgresql://...eski..."
#   venv/bin/python -m scripts.merge_old_neon --old "..." --apply
#
# Hedef DB varsayılan olarak ortamdaki DATABASE_URL'dir (`--new` ile değişir).
# =============================================================================
import argparse
import sys

import sqlalchemy as sa

from app.core.config import settings
from app.services.symbol_alias import canonical

# (tablo, birleştirme anahtarı, taşınacak sütunlar)
_TABLES = [
    ("portfolios", ("user_id", "symbol"),
     ("user_id", "symbol", "quantity", "average_cost")),
    ("transactions", ("user_id", "symbol", "transaction_type", "quantity",
                      "price", "timestamp"),
     ("user_id", "symbol", "transaction_type", "quantity", "price",
      "timestamp")),
    ("watchlist_items", ("user_id", "symbol"),
     ("user_id", "symbol", "position", "created_at")),
]


def _user_map(old_conn, new_conn) -> dict[int, int]:
    """Eski user_id → yeni user_id (e-posta eşleyerek)."""
    new_by_mail = {
        (m or "").lower(): i for i, m in
        new_conn.execute(sa.text("SELECT id, email FROM users"))
    }
    mapping: dict[int, int] = {}
    for old_id, mail in old_conn.execute(sa.text("SELECT id, email FROM users")):
        new_id = new_by_mail.get((mail or "").lower())
        if new_id is None:
            print(f"  ! eski kullanıcı yeni DB'de yok, atlanıyor: {mail}")
            continue
        mapping[old_id] = new_id
    return mapping


def _rows(conn, table: str, cols: tuple[str, ...]) -> list[dict]:
    sel = ", ".join(cols)
    return [dict(r._mapping) for r in
            conn.execute(sa.text(f"SELECT {sel} FROM {table}"))]


def merge(old_url: str, new_url: str, apply: bool) -> int:
    old_eng = sa.create_engine(old_url)
    new_eng = sa.create_engine(new_url)
    added_total = 0

    with old_eng.connect() as old_conn, new_eng.begin() as new_conn:
        users = _user_map(old_conn, new_conn)
        print(f"Eşleşen kullanıcı: {len(users)}")
        if not users:
            print("Eşleşen kullanıcı yok — birleştirilecek bir şey de yok.")
            return 0

        for table, key_cols, cols in _TABLES:
            old_rows = _rows(old_conn, table, cols)
            new_rows = _rows(new_conn, table, cols)
            existing = {tuple(str(r[k]) for k in key_cols) for r in new_rows}

            added = skipped = 0
            for row in old_rows:
                new_uid = users.get(row["user_id"])
                if new_uid is None:
                    continue
                row = {**row, "user_id": new_uid,
                       "symbol": canonical(str(row["symbol"]))}
                if tuple(str(row[k]) for k in key_cols) in existing:
                    skipped += 1
                    continue
                added += 1
                if apply:
                    placeholders = ", ".join(f":{c}" for c in cols)
                    new_conn.execute(
                        sa.text(f"INSERT INTO {table} "
                                f"({', '.join(cols)}) VALUES ({placeholders})"),
                        row)
            added_total += added
            print(f"{table}: eski {len(old_rows)} satır → "
                  f"{'EKLENDİ' if apply else 'eklenecek'} {added} · "
                  f"zaten var {skipped}")

        if not apply:
            print("\nKURU ÇALIŞMA — hiçbir şey yazılmadı. Yazmak için: --apply")
    return added_total


def main() -> None:
    ap = argparse.ArgumentParser(description="Eski Neon verisini birleştir")
    ap.add_argument("--old", required=True, help="ESKİ Neon bağlantı dizesi")
    ap.add_argument("--new", default=settings.DATABASE_URL,
                    help="Hedef DB (varsayılan: DATABASE_URL)")
    ap.add_argument("--apply", action="store_true",
                    help="Gerçekten yaz (varsayılan kuru çalışma)")
    args = ap.parse_args()
    if not args.new:
        sys.exit("Hedef DB yok: DATABASE_URL tanımlı değil, --new ver.")
    merge(args.old, args.new, args.apply)


if __name__ == "__main__":
    main()
