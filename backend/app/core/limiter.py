from slowapi import Limiter
from slowapi.util import get_remote_address
from loguru import logger
from starlette.requests import Request
from app.core.config import settings


def client_key(request: Request) -> str:
    """Hız sınırının saydığı istemci kimliği.

    Uygulama Render'ın yük dengeleyicisinin ARKASINDA çalışıyor: TCP eşi her
    zaman vekil olduğu için `request.client.host` TÜM kullanıcılar için AYNI
    adresi verirdi → tek kullanıcının aşırı isteği herkesi banlar (uygulama
    genelinde çöküş). Gerçek istemci `X-Forwarded-For` başlığında.

    EN SAĞDAKİ girdi okunur, ilk değil: her vekil listeye kendi gördüğü adresi
    EKLER, yani son girdiyi bize en yakın (güvendiğimiz) vekil yazmıştır.
    İstemci kendi sahte `X-Forwarded-For`'unu yollarsa o sahte değer başa
    düşer, sonda yine gerçek adres olur → sınır sahtelenerek aşılamaz. Vekil
    başlığı üzerine yazıyorsa liste tek elemanlıdır, sonuç yine doğrudur.

    Başlık yoksa (lokal geliştirme, test) doğrudan TCP adresine düşülür.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        hops = [h.strip() for h in forwarded.split(",") if h.strip()]
        if hops:
            return hops[-1]
    return get_remote_address(request)


def _build_limiter() -> Limiter:
    """REDIS_URL set ve erişilebilirse Redis backend; aksi halde in-memory fallback."""
    if not settings.REDIS_URL:
        logger.warning(
            "REDIS_URL ayarlanmamış — rate limiter in-memory modda çalışacak "
            "(birden fazla worker'da limitler workerlar arasında paylaşılmaz)."
        )
        return Limiter(key_func=client_key)

    try:
        import redis as _redis
        client = _redis.from_url(settings.REDIS_URL, socket_connect_timeout=2)
        client.ping()
        logger.info(f"Rate limiter Redis backend: {settings.REDIS_URL}")
        return Limiter(key_func=client_key, storage_uri=settings.REDIS_URL)
    except Exception as exc:
        logger.warning(
            f"Redis bağlantısı başarısız ({exc}) — in-memory rate limiter'a düşülüyor."
        )
        return Limiter(key_func=client_key)


# Tek bir Limiter örneği — main.py ve route dosyaları paylaşır.
limiter = _build_limiter()
