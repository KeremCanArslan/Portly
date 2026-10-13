"""Yahoo Finance için tarayıcı-fingerprint'li paylaşılan oturum.

Render gibi cloud sunucularda ham `requests`/yfinance default oturumu Yahoo'nun
quoteSummary endpoint'ine (`ticker.info`, `ticker.income_stmt`) boş yanıt
döndürüyor — Yahoo bot fingerprint'i tespit edip crumb cookie servis etmiyor.
`curl_cffi` gerçek Chrome TLS handshake'ini taklit eder → Yahoo bunu normal
tarayıcı sanır, veri akar.

Kullanım:
    from app.core.yf_session import get_session
    ticker = yf.Ticker(symbol, session=get_session())

curl_cffi yüklü değilse `None` döner; yfinance kendi default'una düşer
(local geliştirmede sorun değil — sorun yalnız Render IP'lerinde).
"""
from loguru import logger

_session = None
_inited = False


def get_session():
    global _session, _inited
    if _inited:
        return _session
    _inited = True
    try:
        from curl_cffi import requests as curl_requests
        _session = curl_requests.Session(impersonate="chrome")
        logger.info("yf_session: curl_cffi Chrome impersonation aktif")
    except ImportError:
        logger.warning("yf_session: curl_cffi yüklü değil, yfinance default oturumu kullanılıyor")
        _session = None
    except Exception as exc:
        logger.warning(f"yf_session: curl_cffi başlatılamadı: {exc}")
        _session = None
    return _session
