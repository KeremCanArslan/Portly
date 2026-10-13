# =============================================================================
# BIST sektör haritası (üretilmiş, ağsız)
#
# `app/data/bist_sectors.json` = çıplak BIST kodu → Türkçe sektör etiketi;
# üretici: `scripts/generate_bist_sectors.py` (kaynak: TradingView ekran ucu,
# BIST'in TÜM hisseleri sanayi kırılımıyla).
#
# Neden dosya: elle tutulan ~90 sembollük harita dışındaki her BIST hissesi
# sektör dağılımında "Diğer"e düşüyordu. Sektör çözümü sırası
# (`portfolio_service._resolve_sector`): elle kürasyon → BU DOSYA → ağ.
# Elle harita üstte kalır ki kürasyon (FENER→Spor, AKCNS→Çimento) ezilmesin.
# =============================================================================
import json
from pathlib import Path

from loguru import logger

_DATA = Path(__file__).resolve().parent.parent / "data" / "bist_sectors.json"


def _load() -> dict[str, str]:
    try:
        raw = json.loads(_DATA.read_text(encoding="utf-8"))
    except Exception as exc:  # dosya yoksa uygulama ÇALIŞMAYA DEVAM ETMELİ
        logger.warning(f"BIST sektör haritası okunamadı ({_DATA}): {exc}")
        return {}
    return {str(k).upper(): str(v) for k, v in raw.items() if k and v}


SECTORS: dict[str, str] = _load()


def sector_of(symbol: str) -> str | None:
    """'BNTAS' ya da 'BNTAS.IS' → 'Ambalaj'. Bilinmiyorsa None."""
    if not symbol:
        return None
    code = symbol.upper()
    if code.endswith(".IS"):
        code = code[:-3]
    return SECTORS.get(code)
