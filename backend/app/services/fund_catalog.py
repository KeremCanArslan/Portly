# =============================================================================
# TEFAS Yatırım Fonu Kataloğu (yerel, ağsız)
#
# Sorun: TEFAS fon kodları 3 harflidir ve hiçbir sonek taşımaz — "TLY", "LTL".
# Koda bakarak fonu BIST hissesinden ya da ABD tickerından ayırmak MÜMKÜN
# DEĞİL: "URA" hem bir TEFAS fonu hem Global X Uranium ETF'i. Bu yüzden kod
# tek başına asla "bu bir fondur" demez; karar için ya kur bilgisi (TRY) ya
# da kullanıcının açık seçimi gerekir.
#
# Portly'de fon sembolü ".FON" soneğiyle saklanır (TLY → TLY.FON):
#   - ".IS" (BIST) ile karışmaz, Yahoo'ya boşuna sorulmaz (Yahoo TEFAS
#     fonlarını HİÇ kapsamıyor — sorun erişim değil, kapsam),
#   - mevcut sonek kuralları ("-USD"→kripto, "=F"→emtia) ile aynı desen,
#   - URL'de güvenli ("TEFAS:TLY" gibi bir biçim uç yollarını bozardı).
#
# Katalog `app/data/tefas_funds.json`'dan okunur; üretici:
# `scripts/generate_tefas_catalog.py`. Dosya TEMELDİR (ağsız açılış, göç,
# ekstre içe aktarımı ona bakar); arka plan işçisi günde bir TEFAS'tan
# gelen yeni fonları üstüne EKLER (`refresh_if_due`) — böylece dün kurulan
# bir fon için deploy beklemek gerekmez. Dosya hiç değişmez, silme yok.
# =============================================================================
import json
import threading
import time
from pathlib import Path

from loguru import logger

SUFFIX = ".FON"

_DATA = Path(__file__).resolve().parent.parent / "data" / "tefas_funds.json"


def _load() -> dict[str, tuple[str, str]]:
    try:
        raw = json.loads(_DATA.read_text(encoding="utf-8"))
    except Exception as exc:  # dosya yoksa uygulama ÇALIŞMAYA DEVAM ETMELİ
        logger.warning(f"TEFAS fon kataloğu okunamadı ({_DATA}): {exc}")
        return {}
    out: dict[str, tuple[str, str]] = {}
    for code, val in raw.items():
        if isinstance(val, list) and val:
            out[code.upper()] = (val[0], val[1] if len(val) > 1 else "")
    return out


CATALOG: dict[str, tuple[str, str]] = _load()

# Canlı tazeleme (yalnız EKLER; dosyadaki kayıtları ne siler ne değiştirir).
_REFRESH_INTERVAL = 24 * 3600
_last_refresh: float = 0.0
_refresh_lock = threading.Lock()


def merge(entries: dict[str, tuple[str, str]]) -> int:
    """Katalogda OLMAYAN kodları ekler; eklenen sayısını döndürür.

    Var olan kayda dokunmaz: dosya elle üretilip gözden geçiriliyor, canlı
    uç ise bir gün yarım/bozuk liste dönebilir — yeni fonu kazanmak isteriz,
    doğrulanmış adı kaybetmeyi değil.
    """
    added = 0
    for code, val in (entries or {}).items():
        code = (code or "").strip().upper()
        if not code or code in CATALOG:
            continue
        name = (val[0] or "").strip() if val else ""
        if not name:
            continue
        CATALOG[code] = (name, val[1] if len(val) > 1 else "")
        added += 1
    return added


def refresh_if_due(force: bool = False) -> int:
    """Günde bir TEFAS'tan katalogu tazeler (arka plan işçisi çağırır).

    Ağ yoksa/uç bozuksa SESSİZCE 0 döner — katalog dosyadaki hâliyle çalışır.
    """
    global _last_refresh
    now = time.time()
    with _refresh_lock:
        if not force and now - _last_refresh < _REFRESH_INTERVAL:
            return 0
        _last_refresh = now  # başarısız denemede de bekle (uç düşükse dövmeyelim)

    try:
        from app.services import fund_source_service
        added = merge(fund_source_service.fetch_catalog())
    except Exception as exc:
        logger.debug(f"Fon kataloğu tazelenemedi: {exc}")
        return 0
    if added:
        logger.info(f"Fon kataloğuna {added} yeni fon eklendi "
                    f"(toplam {len(CATALOG)})")
    return added


def is_fund_symbol(symbol: str) -> bool:
    """Sembol Portly'nin fon biçiminde mi (TLY.FON)?"""
    return bool(symbol) and symbol.upper().endswith(SUFFIX)


def code_of(symbol: str) -> str:
    """'TLY.FON' → 'TLY'. Sonek yoksa sembolün kendisi."""
    s = (symbol or "").upper()
    return s[: -len(SUFFIX)] if s.endswith(SUFFIX) else s


def to_symbol(code: str) -> str:
    """'tly' → 'TLY.FON'."""
    c = (code or "").strip().upper()
    return c if c.endswith(SUFFIX) else f"{c}{SUFFIX}"


def is_known_code(code: str) -> bool:
    """Çıplak kod katalogda kayıtlı bir TEFAS fonu mu? (Sonek EKLEMEZ —
    "bu koda fon muamelesi yapılsın mı" kararı çağırana aittir.)"""
    return (code or "").strip().upper() in CATALOG


def name_of(symbol: str) -> str | None:
    """Fon sembolünün (ya da çıplak kodun) resmi TEFAS unvanı."""
    entry = CATALOG.get(code_of(symbol))
    return entry[0] if entry else None


def kind_of(symbol: str) -> str | None:
    """Şemsiye fon türü ('Hisse Senedi Şemsiye Fonu' gibi)."""
    entry = CATALOG.get(code_of(symbol))
    return entry[1] if entry and entry[1] else None


def _fold(s: str) -> str:
    """Türkçe diakritikleri katlayarak arama karşılaştırması yapar."""
    from app.services.bist_catalog import tr_fold
    return tr_fold(s)


def search(query: str, limit: int = 10) -> list[dict]:
    """Kod ya da unvana göre fon arar → sembol arama sonucu sözlükleri.

    Çok kelimeli sorgu ("tera birinci") unvanda ARDIŞIK geçmek zorunda değil:
    her kelime ayrı ayrı aranır — fon unvanları uzun ve kalıplı olduğu için
    ("... PORTFÖY BİRİNCİ SERBEST FON") tam ifade eşleşmesi işe yaramıyor.
    Sıra: kod tam eşleşmesi → kod öneki → unvan. Sonuçlar
    market_data_service.search_symbols sözleşmesine uyar."""
    q = _fold((query or "").strip())
    if len(q) < 2:
        return []
    words = [w for w in q.split() if w]

    def _hit(code_f: str, name_f: str) -> int | None:
        """Küçük sayı = daha iyi eşleşme; None = eşleşme yok."""
        if code_f == q:
            return 0
        if code_f.startswith(q):
            return 1
        if all(w in name_f or w in code_f for w in words):
            return 2
        return None

    scored: list[tuple[int, str, dict]] = []
    for code, (name, kind) in CATALOG.items():
        rank = _hit(_fold(code), _fold(name))
        if rank is None:
            continue
        scored.append((rank, name, {
            "symbol": to_symbol(code),
            "name": name,
            "market": "TEFAS",
            "type": kind or "Yatırım Fonu",
        }))

    scored.sort(key=lambda x: (x[0], x[1]))
    return [item for _rank, _name, item in scored[:limit]]
