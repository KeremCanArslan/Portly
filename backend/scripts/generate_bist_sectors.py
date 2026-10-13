# =============================================================================
# BIST sektör haritasını üretir → app/data/bist_sectors.json
#
# Neden: sektör dağılımı elle tutulan ~90 sembollük bir haritaya bağlıydı;
# haritada olmayan HER BIST hissesi "Diğer" dilimine düşüyordu (canlı geri
# bildirim: "BNTAS var mesela bende, ambalaj diye ayırsa mükemmel olurmuş").
# BIST'te ~630 hisse var — elle yazmak hem eksik hem bakımsız kalıyor.
#
# Kaynak: TradingView'in açık ekran (screener) ucu — borsanın TÜM hisselerini
# sektör + sanayi kırılımıyla tek istekte veriyor. Sanayi (industry) alanı
# sektörden daha ayırt edici: "Process Industries" değil "Containers/Packaging"
# → "Ambalaj". Yahoo `.info` bu iş için kullanılamıyor (Render'da bloklu ve
# sembol başına ayrı istek), Finnhub ücretsiz tier BIST'i kapsamıyor.
#
# Çalıştırma (yılda birkaç kez ya da "sektörü Diğer görünüyor" şikâyetinde):
#   cd backend && venv/bin/python -m scripts.generate_bist_sectors
#
# Üretilen dosya TEMELDİR (ağsız açılış). `portfolio_service._BIST_SECTORS`
# elle bakılan haritadır ve bu dosyanın ÜSTÜNDE gelir — kürasyon (FENER→Spor,
# AKCNS→Çimento) otomatik eşlemeyle ezilmesin.
# =============================================================================
import json
from pathlib import Path

import httpx

URL = "https://scanner.tradingview.com/turkey/scan"
OUT = Path(__file__).resolve().parent.parent / "app" / "data" / "bist_sectors.json"

PAYLOAD = {
    "filter": [{"left": "type", "operation": "equal", "right": "stock"}],
    "columns": ["name", "description", "sector", "industry"],
    "range": [0, 2000],
    "sort": {"sortBy": "name", "sortOrder": "asc"},
}

# TradingView sanayi adı → Portly'nin Türkçe sektör etiketi.
# Etiketler kasten AZ tutuldu (~25): donut'ta 100 dilim okunmaz. Eşlenmemiş
# bir sanayi çıkarsa script uyarır ve o sembol dosyaya YAZILMAZ (sessizce
# yanlış etiket vermektense "Diğer"e düşsün).
INDUSTRY_TR = {
    # Ulaştırma
    "Airlines": "Ulaştırma", "Air Freight/Couriers": "Ulaştırma",
    "Marine Shipping": "Ulaştırma", "Trucking": "Ulaştırma",
    "Railroads": "Ulaştırma", "Other Transportation": "Ulaştırma",
    # Finans
    "Major Banks": "Bankacılık", "Regional Banks": "Bankacılık",
    "Investment Banks/Brokers": "Finans", "Investment Managers": "Finans",
    "Finance/Rental/Leasing": "Finans",
    "Investment Trusts/Mutual Funds": "Finans",
    "Multi-Line Insurance": "Sigorta", "Life/Health Insurance": "Sigorta",
    "Property/Casualty Insurance": "Sigorta",
    "Financial Conglomerates": "Holding",
    "Industrial Conglomerates": "Holding",
    # Gayrimenkul / inşaat
    "Real Estate Investment Trusts": "Gayrimenkul",
    "Real Estate Development": "Gayrimenkul",
    "Homebuilding": "Gayrimenkul",
    "Engineering & Construction": "İnşaat",
    "Construction Materials": "Yapı Malzemesi",
    "Building Products": "Yapı Malzemesi",
    # Enerji
    "Electric Utilities": "Enerji", "Alternative Power Generation": "Enerji",
    "Gas Distributors": "Enerji", "Oil Refining/Marketing": "Enerji",
    "Integrated Oil": "Enerji", "Oil & Gas Production": "Enerji",
    # Sanayi / metal
    "Steel": "Metal", "Metal Fabrication": "Metal", "Aluminum": "Metal",
    "Precious Metals": "Madencilik", "Other Metals/Minerals": "Madencilik",
    "Industrial Machinery": "Sanayi", "Electrical Products": "Sanayi",
    "Industrial Specialties": "Sanayi",
    "Miscellaneous Manufacturing": "Sanayi",
    "Trucks/Construction/Farm Machinery": "Sanayi",
    "Office Equipment/Supplies": "Sanayi",
    "Electronic Production Equipment": "Sanayi",
    "Containers/Packaging": "Ambalaj",
    "Pulp & Paper": "Kâğıt/Orman", "Forest Products": "Kâğıt/Orman",
    # Kimya
    "Chemicals: Specialty": "Kimya", "Chemicals: Major Diversified": "Kimya",
    "Chemicals: Agricultural": "Kimya",
    # Otomotiv
    "Motor Vehicles": "Otomotiv", "Auto Parts: OEM": "Otomotiv",
    "Automotive Aftermarket": "Otomotiv",
    # Savunma / teknoloji / iletişim
    "Aerospace & Defense": "Savunma",
    "Packaged Software": "Teknoloji",
    "Information Technology Services": "Teknoloji",
    "Data Processing Services": "Teknoloji",
    "Computer Processing Hardware": "Teknoloji",
    "Computer Communications": "Teknoloji",
    "Semiconductors": "Teknoloji",
    "Electronic Equipment/Instruments": "Teknoloji",
    "Telecommunications Equipment": "Teknoloji",
    "Major Telecommunications": "İletişim",
    "Wireless Telecommunications": "İletişim",
    # Gıda / tüketim / perakende
    "Food: Specialty/Candy": "Gıda", "Food: Major Diversified": "Gıda",
    "Food: Meat/Fish/Dairy": "Gıda", "Food Distributors": "Gıda",
    "Agricultural Commodities/Milling": "Gıda", "Restaurants": "Gıda",
    "Beverages: Non-Alcoholic": "Gıda", "Beverages: Alcoholic": "Gıda",
    "Food Retail": "Perakende", "Specialty Stores": "Perakende",
    "Department Stores": "Perakende", "Internet Retail": "Perakende",
    "Apparel/Footwear Retail": "Perakende",
    "Electronics/Appliance Stores": "Perakende",
    "Wholesale Distributors": "Ticaret",
    "Electronics Distributors": "Ticaret",
    "Textiles": "Tekstil", "Apparel/Footwear": "Tekstil",
    "Home Furnishings": "Tüketim", "Electronics/Appliances": "Tüketim",
    "Household/Personal Care": "Tüketim", "Consumer Sundries": "Tüketim",
    "Other Consumer Specialties": "Tüketim",
    "Recreational Products": "Tüketim",
    # Sağlık
    "Pharmaceuticals: Major": "Sağlık", "Pharmaceuticals: Other": "Sağlık",
    "Pharmaceuticals: Generic": "Sağlık", "Biotechnology": "Sağlık",
    "Medical Specialties": "Sağlık", "Medical Distributors": "Sağlık",
    "Hospital/Nursing Management": "Sağlık",
    "Medical/Nursing Services": "Sağlık",
    # Hizmet / medya / turizm
    "Hotels/Resorts/Cruise lines": "Turizm",
    "Movies/Entertainment": "Medya", "Media Conglomerates": "Medya",
    "Publishing: Newspapers": "Medya",
    "Publishing: Books/Magazines": "Medya",
    "Advertising/Marketing Services": "Medya",
    "Commercial Printing/Forms": "Medya",
    "Miscellaneous Commercial Services": "Hizmet",
    "Other Consumer Services": "Hizmet",
}


def fetch() -> list[dict]:
    r = httpx.post(URL, json=PAYLOAD, timeout=45,
                   headers={"User-Agent": "Mozilla/5.0"})
    r.raise_for_status()
    return r.json().get("data", [])


def main() -> None:
    rows = fetch()
    out: dict[str, str] = {}
    unmapped: dict[str, list[str]] = {}

    for row in rows:
        code, _name, _sector, industry = (row.get("d") or [None] * 4)[:4]
        if not code:
            continue
        tr = INDUSTRY_TR.get(industry or "")
        if not tr:
            unmapped.setdefault(industry or "(boş)", []).append(code)
            continue
        out[code.upper()] = tr

    OUT.write_text(
        json.dumps(dict(sorted(out.items())), ensure_ascii=False, indent=0),
        encoding="utf-8")
    print(f"{len(out)} sembol yazıldı → {OUT}")
    if unmapped:
        print("\nEşlenmemiş sanayi (bu semboller 'Diğer'e düşecek):")
        for ind, codes in sorted(unmapped.items(), key=lambda kv: -len(kv[1])):
            print(f"  {len(codes):3d}  {ind}  ({', '.join(codes[:6])})")


if __name__ == "__main__":
    main()
