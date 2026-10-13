"""`market_state` — her varlık sınıfı için piyasa açık/kapalı.

Neden var: alan YALNIZ ABD hisselerinde doluyordu (pre/post overlay'in yan
ürünüydü) — BIST, kripto ve altın için null geliyor, UI "açık mı kapalı mı"
diyemiyordu. Ayrıca `_us_market_state` ham `hour` okuduğu için saat dilimi
ÇEVRİLMEDEN çağrılırsa TSİ 14:00'te ABD borsasını "REGULAR" sanıyordu.
"""

from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from app.services.market_data_service import market_state_of

TR = ZoneInfo("Europe/Istanbul")


def _tr(day: int, hour: int, minute: int = 0) -> datetime:
    # 2026-09-04 Cuma · 2026-09-05 Cumartesi
    return datetime(2026, 9, day, hour, minute, tzinfo=TR)


@pytest.mark.parametrize("symbol", ["BTC-USD", "ETH-USD"])
def test_crypto_is_always_open(symbol):
    assert market_state_of(symbol, _tr(4, 3)) == "REGULAR"
    assert market_state_of(symbol, _tr(5, 23)) == "REGULAR"   # cumartesi gecesi


def test_bist_follows_istanbul_session():
    assert market_state_of("THYAO.IS", _tr(4, 9, 30)) == "CLOSED"
    assert market_state_of("THYAO.IS", _tr(4, 10)) == "REGULAR"
    assert market_state_of("THYAO.IS", _tr(4, 17, 59)) == "REGULAR"
    assert market_state_of("THYAO.IS", _tr(4, 18)) == "CLOSED"
    assert market_state_of("THYAO.IS", _tr(5, 12)) == "CLOSED"  # cumartesi


def test_us_equity_is_converted_to_new_york_time():
    """TSİ 14:00 = ET 07:00 → pre-market. Çeviri yapılmazsa 'REGULAR' derdi."""
    assert market_state_of("AAPL", _tr(4, 14)) == "PRE"
    assert market_state_of("AAPL", _tr(4, 17)) == "REGULAR"
    assert market_state_of("AAPL", _tr(4, 23, 30)) == "POST"


def test_fx_and_commodity_closed_on_weekend():
    assert market_state_of("USDTRY=X", _tr(4, 22)) == "REGULAR"
    assert market_state_of("GC=F", _tr(5, 12)) == "CLOSED"


def test_fund_has_no_session():
    """TEFAS fonunun seansı yok (günde tek fiyat) → UI gösterge çizmesin."""
    assert market_state_of("AFT.FON", _tr(4, 12)) is None
