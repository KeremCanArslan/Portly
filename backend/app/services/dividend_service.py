"""Temettü takibi.

• Kullanıcının pozisyonları için geçmiş + tahmini yıllık temettü geliri
• Yaklaşan ex-temettü tarihi (mümkünse)
• Sanal temettü tahsilatı: BIST (.IS, TL) hisselerinin satın alımdan sonraki
  ex-temettülerini idempotent biçimde nakde yansıtır (Transaction tipi
  'DIVIDEND'). Yabancı (USD) temettüler kur karmaşası yaratmamak için
  yalnızca bilgi olarak gösterilir, otomatik tahsil edilmez.
"""

import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from loguru import logger
from sqlalchemy.orm import Session
import yfinance as yf

from app.core.database import SessionLocal
from app.models.dividend_cache import DividendCache
from app.models.portfolio import Portfolio
from app.models.transaction import Transaction
from app.models.user import User
from app.services import fx_service
from app.services.symbol_alias import canonical


def _is_try(symbol: str) -> bool:
    s = symbol.upper()
    return s.endswith((".IS", ".TR", ".FON", ".ALTIN", ".GUMUS"))


# ── Paylaşılan temettü cache'i (bellek + KALICI DB) ──────────────────────
# `yf.Ticker().dividends` + `.calendar` bu serviste en yavaş çağrılar
# (sembol başına ~1-3s ağ). Temettü verisi nadiren değişir, o yüzden
# sembol başına uzun TTL ile cache'lenir. ÖNEMLİ: overview + preview/collect
# bu tek kaynağı paylaşır → eskiden iki ucu da yfinance'i bağımsız çekip
# soğuk açılışta toplamı 30s client timeout'unu aşıyor, fetch sessizce boş
# dönüp ekranı "boş portföy" sanıyordu (market_data_service._name_cache ile
# aynı sınıf düzeltme).
#
# Bellek cache süreç ömürlüydü → Render free instance uyuyup uyandığında /
# her deploy'da sıfırlanıp ekran HER oturumda soğuk açılıyordu. Artık seri
# `dividend_cache` tablosuna da yazılır: süreç yeniden başlasa bile ilk
# çekimden sonra anında açılır (bkz. models/dividend_cache.py).
_DIV_TTL_SEC = 6 * 3600
_div_cache: dict[str, tuple[float, object, object]] = {}  # sym → (ts, divs, cal)
_div_locks: dict[str, threading.Lock] = {}
_div_locks_guard = threading.Lock()


def _lock_for(key: str) -> threading.Lock:
    with _div_locks_guard:
        lk = _div_locks.get(key)
        if lk is None:
            lk = threading.Lock()
            _div_locks[key] = lk
        return lk


def _serialize(divs, cal) -> dict:
    """(divs_serisi, cal) → JSON-uyumlu payload. Tz-bilgili ISO tarih +
    tutar çiftleri; cal'dan yalnız ham Ex-Dividend Date saklanır (downstream
    onu bugüne göre yeniden doğrular)."""
    rows = []
    if divs is not None:
        for ts, v in divs.items():
            try:
                rows.append([ts.isoformat(), float(v)])
            except Exception:
                continue
    cal_ex = None
    try:
        if isinstance(cal, dict):
            ed = cal.get("Ex-Dividend Date")
            if ed:
                cal_ex = str(ed[0] if isinstance(ed, list) else ed)[:10]
    except Exception:
        cal_ex = None
    return {"divs": rows, "cal_ex": cal_ex}


def _deserialize(payload: dict):
    """payload → (divs_serisi, cal|None). Tz-bilgili DatetimeIndex yeniden
    kurulur (sabit offset olur ama tüm downstream tarih işlemleri doğru
    çalışır — round-trip doğrulandı)."""
    import pandas as pd

    rows = (payload or {}).get("divs") or []
    if rows:
        idx = pd.DatetimeIndex([pd.Timestamp(r[0]) for r in rows])
        divs = pd.Series([float(r[1]) for r in rows], index=idx)
    else:
        divs = pd.Series([], dtype="float64")
    cal_ex = (payload or {}).get("cal_ex")
    cal = {"Ex-Dividend Date": cal_ex} if cal_ex else None
    return divs, cal


def _db_load(key: str):
    """DB kalıcı cache'ten oku → (divs, cal, fetched_at_epoch) ya da
    (None, None, 0.0). Kendi kısa-ömürlü session'ını açar (thread-güvenli;
    overview ThreadPoolExecutor'ından çağrılabilir)."""
    db = SessionLocal()
    try:
        row = db.query(DividendCache).filter(
            DividendCache.symbol == key).first()
        if not row:
            return None, None, 0.0
        divs, cal = _deserialize(row.payload)
        ts = row.fetched_at.timestamp() if row.fetched_at else 0.0
        return divs, cal, ts
    except Exception as exc:
        logger.debug(f"dividend db-load {key}: {exc}")
        return None, None, 0.0
    finally:
        db.close()


def _db_save(key: str, divs, cal) -> None:
    """DB kalıcı cache'e yaz (upsert). Hata sessizce yutulur — kalıcı cache
    bir optimizasyon, başarısızlığı isteği bozmamalı."""
    db = SessionLocal()
    try:
        payload = _serialize(divs, cal)
        row = db.query(DividendCache).filter(
            DividendCache.symbol == key).first()
        now = datetime.now(timezone.utc)
        if row:
            row.payload = payload
            row.fetched_at = now
        else:
            db.add(DividendCache(symbol=key, fetched_at=now, payload=payload))
        db.commit()
    except Exception as exc:
        logger.debug(f"dividend db-save {key}: {exc}")
        db.rollback()
    finally:
        db.close()


def _dividends_raw(symbol: str):
    """Bir sembol için (divs_serisi, calendar|None) — bellek + DB cache'li.

    Sıra: bellek → DB (kalıcı) → yfinance. Eşzamanlı aynı-sembol istekleri
    per-symbol lock ile BİRLEŞTİRİLİR: overview'ın ThreadPoolExecutor'ı ve
    onunla paralel gelen preview isteği aynı sembolü yalnızca BİR KEZ
    yfinance'ten çeker; diğerleri cache'i okur. yfinance başarısız olursa
    (Render'da Yahoo zaman zaman boş döner) bayat DB verisine geri düşülür —
    bayat veri 'boş portföy' yanılgısından iyidir. Tam başarısızlık
    cache'lenmez (sonraki çağrı yeniden dener)."""
    key = symbol.upper()
    now = time.time()
    hit = _div_cache.get(key)  # hızlı yol (GIL altında okuma güvenli)
    if hit and now - hit[0] < _DIV_TTL_SEC:
        return hit[1], hit[2]
    with _lock_for(key):
        hit = _div_cache.get(key)  # kilit içinde çift kontrol
        if hit and time.time() - hit[0] < _DIV_TTL_SEC:
            return hit[1], hit[2]
        # Kalıcı DB cache — restart/sleep sonrası soğuk yfinance'i atlar.
        db_divs, db_cal, db_ts = _db_load(key)
        if db_divs is not None and time.time() - db_ts < _DIV_TTL_SEC:
            _div_cache[key] = (db_ts, db_divs, db_cal)
            return db_divs, db_cal
        # Soğuk → yfinance'ten çek.
        try:
            t = yf.Ticker(symbol)
            divs = t.dividends
            try:
                cal = t.calendar
            except Exception:
                cal = None
        except Exception as exc:
            logger.debug(f"dividend fetch {symbol}: {exc}")
            # yfinance düştü ama bayat DB verisi varsa onu kullan.
            if db_divs is not None:
                _div_cache[key] = (db_ts, db_divs, db_cal)
                return db_divs, db_cal
            return None, None
        _div_cache[key] = (time.time(), divs, cal)
        _db_save(key, divs, cal)
        return divs, cal


def prewarm_dividends(symbols) -> None:
    """Verilen sembollerin temettü serisini paralel ısıt (bellek + DB cache).

    Startup'ta tutulan pozisyonlar için çağrılır (bkz. main.lifespan) →
    temettü ekranının ilk-ever açılışı (DB cache henüz boşken, ör. taze
    deploy) bile soğuk yfinance beklemesin. DB cache zaten varsa bu çağrı
    hızlıdır (yfinance'e gitmez)."""
    seen: set[str] = set()
    syms = []
    for s in symbols:
        k = (s or "").upper()
        if k and k not in seen:
            seen.add(k)
            syms.append(s)
    if not syms:
        return
    with ThreadPoolExecutor(max_workers=8) as ex:
        list(ex.map(_dividends_raw, syms))


def _symbol_dividends(symbol: str) -> dict | None:
    """Bir sembol için temettü özeti (paylaşılan cache üzerinden)."""
    # Fiziki altın/gümüş temettü ÖDEMEZ ve Yahoo'da karşılığı yok — sormak
    # her portföy açılışında boşuna 429 riski demek.
    if symbol.upper().endswith((".ALTIN", ".GUMUS")):
        return {"symbol": symbol, "has_dividend": False}
    try:
        divs, cal = _dividends_raw(symbol)
        if divs is None or len(divs) == 0:
            return {"symbol": symbol, "has_dividend": False}
        import pandas as pd

        idx = divs.index
        last_amt = float(divs.iloc[-1])
        last_date = idx[-1].strftime("%Y-%m-%d")
        now_ts = pd.Timestamp.now(tz=idx.tz)
        cutoff = now_ts - pd.Timedelta(days=365)
        ttm = float(divs[idx >= cutoff].sum())

        # Ödeme periyodunu geçmişten çıkar (çeyreklik/yarı/yıllık).
        interval_days = 365
        if len(idx) >= 3:
            med = float(pd.Series((idx[1:] - idx[:-1]).days).median())
            for cand, lo, hi in (
                (30, 18, 45), (91, 60, 135),
                (182, 135, 250), (365, 250, 460),
            ):
                if lo <= med <= hi:
                    interval_days = cand
                    break
            else:
                interval_days = max(int(med), 1)
        elif len(idx) == 2:
            interval_days = max((idx[-1] - idx[-2]).days, 1)

        # Son ex + periyot → bugünden sonraki ilk tarihe ilerlet.
        proj = idx[-1]
        while proj <= now_ts:
            proj = proj + pd.Timedelta(days=interval_days)
        projected = proj.strftime("%Y-%m-%d")

        # yfinance takvimi GERÇEKTEN gelecekteyse onu tercih et.
        cal_future = None
        try:
            if isinstance(cal, dict):
                ed = cal.get("Ex-Dividend Date")
                if ed:
                    raw = str(ed[0] if isinstance(ed, list) else ed)[:10]
                    if pd.Timestamp(raw, tz=idx.tz) >= now_ts.normalize():
                        cal_future = raw
        except Exception:
            pass

        return {
            "symbol": symbol,
            "has_dividend": True,
            "last_amount": round(last_amt, 4),
            "last_date": last_date,
            "ttm_per_share": round(ttm, 4),
            "next_ex_date": cal_future or projected,
            "next_ex_estimated": cal_future is None,
        }
    except Exception as exc:
        logger.debug(f"dividend fetch {symbol}: {exc}")
        return None


def _collected_summary(db: Session, user_id: int) -> dict:
    """Şimdiye dek sanal tahsil edilmiş temettüler (DIVIDEND işlemleri).

    DIVIDEND işlemlerinde `price` artık TAHSİL ANINDAKİ ₺/adet değeri
    (USD hisseler o günkü kurla kilitlenmiş) → `price × adet` = bakiyeye
    eklenen gerçek ₺. Burada yeniden kur uygulanMAZ; aksi halde ekrandaki
    "şimdiye kadar aldığın" rakamı gerçekte eklenen nakitle tutmuyordu."""
    txns = (
        db.query(Transaction)
        .filter(
            Transaction.user_id == user_id,
            Transaction.transaction_type == "DIVIDEND",
        )
        .order_by(Transaction.timestamp.desc())
        .all()
    )
    by_symbol: dict[str, float] = {}
    recent = []
    total = 0.0
    count = 0
    for t in txns:
        csym = canonical(t.symbol)
        amt_try = float(t.price) * float(t.quantity)  # zaten ₺ (kilitli)
        if amt_try <= 0:
            continue
        count += 1
        total += amt_try
        by_symbol[csym] = by_symbol.get(csym, 0.0) + amt_try
        if len(recent) < 8:
            recent.append({
                "symbol": csym,
                "date": t.timestamp.strftime("%Y-%m-%d") if t.timestamp else "",
                "amount_try": round(amt_try, 2),
            })
    return {
        "total_try": round(total, 2),
        "count": count,
        "by_symbol": {k: round(v, 2) for k, v in by_symbol.items()},
        "recent": recent,
    }


def get_dividend_overview(db: Session, user_id: int) -> dict:
    holdings = db.query(Portfolio).filter(
        Portfolio.user_id == user_id).all()
    if not holdings:
        return {"has_data": False, "items": [], "est_annual_try": 0.0,
                "est_annual_usd": 0.0, "collected_total_try": 0.0,
                "collected_count": 0, "collected_recent": []}

    collected = _collected_summary(db, user_id)

    syms = [canonical(h.symbol) for h in holdings]
    with ThreadPoolExecutor(max_workers=8) as ex:
        infos = list(ex.map(_symbol_dividends, syms))

    items = []
    est_try = 0.0
    est_usd = 0.0
    for h, csym, info in zip(holdings, syms, infos):
        if not info or not info.get("has_dividend"):
            continue
        qty = float(h.quantity)
        ttm = info["ttm_per_share"]
        annual = ttm * qty
        is_try = _is_try(csym)
        if is_try:
            est_try += annual
        else:
            est_usd += annual
        last_amt = info["last_amount"]
        items.append({
            "symbol": csym,
            "name": csym,
            "currency": "₺" if is_try else "$",
            "quantity": round(qty, 2),
            "last_amount": last_amt,
            "last_date": info["last_date"],
            "ttm_per_share": ttm,
            "est_annual_income": round(annual, 2),
            # Bu pozisyondan beklenen sonraki ödeme (hisse başı son × adet)
            "next_payout": round(last_amt * qty, 2),
            "next_ex_date": info.get("next_ex_date"),
            "next_ex_estimated": info.get("next_ex_estimated", True),
            # Bu sembolden bugüne dek tahsil edilen (₺, USD ≈ güncel kur)
            "collected_try": collected["by_symbol"].get(csym, 0.0),
            "auto_collect": True,  # ₺ doğrudan, USD kurla çevrilip eklenir
        })

    items.sort(key=lambda x: x["est_annual_income"], reverse=True)
    # Birleşik ₺ yıllık gelir = TL + (USD × güncel kur). Tahsilat USD
    # temettüleri zaten kurla ₺'ye çevirip bakiyeye ekliyor → başlık da
    # ₺-karşılığını içermeli. Eskiden hero yalnız est_try'yi gösteriyordu;
    # USD-ağırlıklı portföyde gelir ciddi düşük görünüyordu (fx_service tek
    # kaynak; asla 0/NaN dönmez ama yine de korumalı topla).
    fx = fx_service.usdtry_rate()
    est_total_try = est_try + (est_usd * fx if fx > 0 else 0.0)

    # Şu an tahsil edilebilir KESİN tutar/olaylar — eskiden ayrı bir
    # `/dividends/preview` round-trip'iydi; ekran iki isteği `Future.wait`
    # ile bekliyordu. Burada gömülü: dry-run hesap collect ile BİREBİR aynı
    # tek kaynaktan gelir (kopya matematik yok) ve yukarıdaki çekimle ısınan
    # paylaşılan cache'i okur (ek yfinance yok) → tek istekte hazır.
    try:
        preview = collect_virtual_dividends(db, user_id, dry_run=True)
        claimable = preview.get("credited", 0.0)
        claim_events = preview.get("events", [])
    except Exception as exc:
        logger.debug(f"dividend preview embed {user_id}: {exc}")
        claimable, claim_events = 0.0, []

    return {
        "has_data": len(items) > 0,
        "items": items,
        "est_annual_try": round(est_try, 2),
        "est_annual_usd": round(est_usd, 2),
        # Hero/aylık ortalama bunu kullanır (TL + USD₺-karşılığı).
        "est_annual_total_try": round(est_total_try, 2),
        "collected_total_try": collected["total_try"],
        "collected_count": collected["count"],
        "collected_recent": collected["recent"],
        # Tahsil edilebilir (gömülü dry-run) — frontend ayrı istek atmaz.
        "claimable": claimable,
        "claim_events": claim_events,
    }


def collect_virtual_dividends(db: Session, user_id: int,
                              dry_run: bool = False) -> dict:
    """Pozisyonların satın alımdan sonraki ex-temettülerini idempotent
    biçimde GELİR KAYDI olarak işler (işlem geçmişine DIVIDEND satırı).
    BIST (₺) doğrudan; yabancı (USD) hisseler güncel USDTRY kuruyla ₺'ye
    çevrilir. Daha önce 'DIVIDEND' işlemi kaydedilmiş (sembol, gün) çifti
    atlanır. (Sanal nakit pivotla kalktı → bakiyeye ekleme YOK; kayıt
    defteri semantiği.)

    dry_run=True (önizleme): hesap BİREBİR aynı yürür ama HİÇBİR yan etki
    yapılmaz — Transaction eklenmez, commit edilmez. 'credited' = şu an
    tahsil edilebilir kesin tutar."""
    user = db.query(User).filter(User.id == user_id).first()
    holdings = db.query(Portfolio).filter(
        Portfolio.user_id == user_id).all()
    if not user or not holdings:
        return {"credited": 0.0, "events": []}

    # USD→₺: tek doğruluk kaynağı (fx_service). Eskiden buradaki yerel
    # _usdtry_rate() çekim hatasında 0.0 dönüp USD temettüleri SESSİZCE
    # atlıyordu; fx_service asla 0/NaN dönmez (başarısızsa makul fallback)
    # → USD temettüler artık tutarlı kurla tahsil edilir, yutulmaz.
    fx = fx_service.usdtry_rate()

    existing = db.query(Transaction).filter(
        Transaction.user_id == user_id,
        Transaction.transaction_type == "DIVIDEND",
    ).all()
    seen = {(t.symbol, t.timestamp.strftime("%Y-%m-%d"))
            for t in existing if t.timestamp}

    total = 0.0
    events = []
    for h in holdings:
        csym = canonical(h.symbol)
        is_try = _is_try(csym)
        if not is_try and fx <= 0:
            continue  # kur yoksa USD temettüyü güvenli şekilde atla
        rate = 1.0 if is_try else fx
        # Bu sembolün ilk alımı (ex-tarih bundan sonra olmalı)
        first_buy = (
            db.query(Transaction)
            .filter(
                Transaction.user_id == user_id,
                Transaction.symbol == h.symbol,
                Transaction.transaction_type == "BUY",
            )
            .order_by(Transaction.timestamp.asc())
            .first()
        )
        divs, _ = _dividends_raw(csym)  # overview ile paylaşılan cache
        if divs is None or len(divs) == 0:
            continue
        buy_ts = first_buy.timestamp if first_buy else None
        cutoff = datetime.now(divs.index.tz) - timedelta(days=365)
        for ts, amt in divs.items():
            d = ts.to_pydatetime()
            if d < cutoff:
                continue
            if buy_ts is not None:
                # Saat dilimini DÖNÜŞTÜR, sadece etiketleme. Eski kod naive
                # buy_ts'e d'nin tz'ini replace() ediyordu → aynı an farklı
                # tz etiketiyle damgalanıp meşru temettüler "alımdan önce"
                # sanılıp düşüyordu. Naive buy_ts'i UTC kabul edip d'nin
                # tz'ine çevir (ya da tersi).
                bt = buy_ts
                if d.tzinfo is not None:
                    if bt.tzinfo is None:
                        bt = bt.replace(tzinfo=timezone.utc)
                    bt = bt.astimezone(d.tzinfo)
                elif bt.tzinfo is not None:
                    bt = bt.astimezone(timezone.utc).replace(tzinfo=None)
                if d < bt:
                    continue
            day = d.strftime("%Y-%m-%d")
            if (h.symbol, day) in seen:
                continue
            qty = float(h.quantity)
            payout = float(amt) * qty * rate  # ₺ cinsi (USD ise kur uygulandı)
            if payout <= 0:
                continue
            if not dry_run:
                db.add(Transaction(
                    user_id=user_id,
                    symbol=h.symbol,
                    transaction_type="DIVIDEND",
                    quantity=qty,
                    # Tahsil anındaki ₺/adet (USD ise o günkü kurla KİLİTLİ)
                    # → price × adet = kaydedilen gerçek ₺ gelir.
                    # _collected_summary bunu kuru yeniden uygulamadan okur.
                    price=payout / qty if qty else 0.0,
                    timestamp=d,
                ))
            # seen/total/events HER ZAMAN işlenir → dry_run hesabı collect
            # ile birebir aynı (idempotent dedup dahil).
            seen.add((h.symbol, day))
            total += payout
            events.append({
                "symbol": csym,
                "date": day,
                "per_share": round(float(amt), 4),
                "amount": round(payout, 2),
            })

    if total > 0 and not dry_run:
        db.commit()
    events.sort(key=lambda e: e["date"], reverse=True)
    return {"credited": round(total, 2), "events": events}
