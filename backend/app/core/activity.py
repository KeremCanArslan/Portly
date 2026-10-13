"""Uygulamanın son 'gerçek kullanım' anını bellekte tutar (DB'ye DOKUNMAZ).

Arka plan worker'ı (fiyat alarmı) bunu okur; kimse uygulamayı kullanmıyorken
DB'yi yoklamayı bırakır. Böylece Neon (serverless Postgres) compute'u boşta
uyuyabilir ve free-tier aylık compute kotası 7/24 yoklama ile yanmaz (bir kez
yandı → tüm DB uçları 500 oldu).

UptimeRobot'un /health ping'i AKTİVİTE SAYILMAZ — yalnız /api/ istekleri işaretler.
Yoksa uygulama hiç kullanılmasa bile /health ping'i worker'ı sürekli çalıştırırdı.
"""
import time

# 0.0 => açılışta 'boşta' kabul edilir; ilk gerçek /api isteğiyle güncellenir.
_last_activity_monotonic: float = 0.0


def mark_activity() -> None:
    """Gerçek bir API isteği geldi — worker bir süre aktif poll yapsın."""
    global _last_activity_monotonic
    _last_activity_monotonic = time.monotonic()


def seconds_since_activity() -> float:
    return time.monotonic() - _last_activity_monotonic
