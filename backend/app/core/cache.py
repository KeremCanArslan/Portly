"""Paylaşılan uygulama cache'i — Redis (varsa) + in-process fallback.

limiter.py ile aynı graceful-fallback deseni: REDIS_URL set ve erişilebilirse
Redis (restart'a dayanır + worker'lar paylaşır), aksi halde süreç-içi dict.
Değerler JSON olarak saklanır → yalnız JSON-serileştirilebilir veri geçirin
(datetime gibi tipleri çağıran taraf iso string'e çevirmeli).

Kullanım:
    from app.core import cache
    cache.set("mkt:q:AAPL", {...}, ttl=600)
    hit = cache.get("mkt:q:AAPL")   # -> (data, ts_epoch) | None
"""
import json
import time

from loguru import logger

from app.core.config import settings


def _build_redis():
    if not settings.REDIS_URL:
        logger.info("Cache: REDIS_URL yok → in-process cache kullanılıyor.")
        return None
    try:
        import redis as _redis
        client = _redis.from_url(
            settings.REDIS_URL, socket_connect_timeout=2, decode_responses=True
        )
        client.ping()
        logger.info(f"Cache: Redis backend {settings.REDIS_URL}")
        return client
    except Exception as exc:
        logger.warning(f"Cache Redis'e bağlanamadı ({exc}) → in-process'e düşülüyor.")
        return None


_redis_client = _build_redis()

# Redis yoksa / düşerse kullanılan fallback. full_key -> (data, ts_epoch).
_mem: dict[str, tuple[object, float]] = {}


def is_redis() -> bool:
    return _redis_client is not None


def get(key: str) -> tuple[object, float] | None:
    """(data, ts_epoch) döner ya da None. Redis hatası → cache miss gibi davranır."""
    if _redis_client is not None:
        try:
            raw = _redis_client.get(key)
            if raw is None:
                return None
            obj = json.loads(raw)
            return obj["data"], obj["ts"]
        except Exception as exc:
            logger.debug(f"Cache get hata ({key}): {exc}")
            return None
    return _mem.get(key)


def delete(key: str) -> None:
    """Anahtarı siler. Redis hatası sessizce yutulur (cache zaten en iyi çaba)."""
    if _redis_client is not None:
        try:
            _redis_client.delete(key)
            return
        except Exception as exc:
            logger.debug(f"Cache delete hata ({key}): {exc}")
    _mem.pop(key, None)


def delete_prefix(prefix: str) -> None:
    """Önekle başlayan TÜM anahtarları siler (test izolasyonu / toplu temizlik).

    Redis'te `scan_iter` ile gezilir — `KEYS` üretimde bloklar, kullanılmaz.
    """
    if _redis_client is not None:
        try:
            for key in _redis_client.scan_iter(match=f"{prefix}*", count=500):
                _redis_client.delete(key)
            return
        except Exception as exc:
            logger.debug(f"Cache delete_prefix hata ({prefix}): {exc}")
    for key in [k for k in _mem if k.startswith(prefix)]:
        _mem.pop(key, None)


def set(key: str, data: object, ttl: int) -> None:
    """Değeri ts damgasıyla saklar; Redis'te ttl sn sonra düşer. Redis düşerse
    bu çağrı için in-process'e yazar (graceful)."""
    ts = time.time()
    if _redis_client is not None:
        try:
            _redis_client.set(key, json.dumps({"data": data, "ts": ts}), ex=ttl)
            return
        except Exception as exc:
            logger.debug(f"Cache set hata ({key}): {exc}")
    _mem[key] = (data, ts)
