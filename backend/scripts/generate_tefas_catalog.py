# =============================================================================
# TEFAS fon kataloğunu üretir → app/data/tefas_funds.json
#
# Neden statik katalog: fon kodu (TLY, LTL) ile BIST kodu ya da ABD tickerı
# ayırt edilemiyor (örn. "URA" HEM bir TEFAS fonu HEM Global X Uranium ETF'i).
# Kod → fon adı eşlemesi ağ İSTEĞİ ATMADAN bilinmeli ki:
#   1) ekstre içe aktarımı fon kodunu yanlışlıkla ".IS" (BIST) yapmasın,
#   2) Alembic veri göçü ağa çıkmadan eski satırları düzeltebilsin,
#   3) arama/ad çözümü soğuk açılışta TEFAS'a bağımlı olmasın.
#
# Çalıştırma (yılda birkaç kez ya da "fonu bulamıyor" şikâyetinde):
#   cd backend && venv/bin/python -m scripts.generate_tefas_catalog
#
# Kaynak: TEFAS'ın kendi web arayüzünün kullandığı açık uç (2026-04'te
# yenilenen /api/funds/* mimarisi). Eski /api/DB/BindHistoryInfo KAPALI.
# =============================================================================
import json
from pathlib import Path

import httpx

URL = "https://www.tefas.gov.tr/api/funds/fonGetiriBazliBilgiGetir"
OUT = Path(__file__).resolve().parent.parent / "app" / "data" / "tefas_funds.json"

# Uç, dönem getirisi bayrakları eksikse "Sistem Hatası!!" döndürüyor.
PAYLOAD = {
    "fonTipi": "YAT",          # YAT = yatırım fonu (EMK = emeklilik, kapsam dışı)
    "dil": "TR",
    "calismaTipi": 2,
    "donemGetiri1a": "1", "donemGetiri3a": "1", "donemGetiri6a": "1",
    "donemGetiriyb": "1", "donemGetiri1y": "1", "donemGetiri3y": "1",
    "donemGetiri5y": "1",
}
HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
}


def main() -> None:
    with httpx.Client(timeout=60.0, headers=HEADERS) as client:
        data = client.post(URL, json=PAYLOAD).raise_for_status().json()

    if data.get("errorMessage"):
        raise SystemExit(f"TEFAS hatası: {data['errorMessage']}")

    rows = data.get("resultList") or []
    catalog: dict[str, list[str]] = {}
    for row in rows:
        code = (row.get("fonKodu") or "").strip().upper()
        name = (row.get("fonUnvan") or "").strip()
        kind = (row.get("fonTurAciklama") or "").strip()
        if code and name:
            catalog[code] = [name, kind]

    if len(catalog) < 500:
        raise SystemExit(f"Beklenenden az fon geldi ({len(catalog)}) — "
                         f"uç değişmiş olabilir, katalog YAZILMADI.")

    OUT.write_text(
        json.dumps(dict(sorted(catalog.items())), ensure_ascii=False, indent=0),
        encoding="utf-8")
    print(f"{len(catalog)} fon → {OUT}")


if __name__ == "__main__":
    main()
