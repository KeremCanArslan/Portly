import time
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from fastapi import HTTPException
from loguru import logger
import yfinance as yf
import pandas as pd
from app.models.user import User
from app.models.portfolio import Portfolio
from app.models.transaction import Transaction
from app.schemas.trade_schema import TradeRequest
from app.services.market_data_service import get_stock_data
from app.services import fx_service
from app.services.symbol_alias import canonical
from app.core import cache
from datetime import datetime, timezone, timedelta

# kayan nokta hatası için epsilon - 0.000001'den az kalan miktar sıfır kabul edilir
_QTY_EPSILON = 1e-6


# ── Pozisyon satırına eşzamanlı erişim ─────────────────────────────────
# Lot ve ortalama maliyet OKU-DEĞİŞTİR-YAZ döngüsüyle güncellenir. Kilitsiz
# yapılırsa aynı anda gelen iki istek birbirinin yazdığını ezer ("lost
# update"): kullanıcı yavaş bağlantıda "Pozisyonu Ekle"ye iki kez basarsa
# ikinci istek birincinin eklediği lotu GÖRMEDEN yazar → bir lot kaybolur.
# İki katmanlı koruma: (1) mevcut satır FOR UPDATE ile kilitlenir,
# (2) satır henüz yokken iki INSERT yarışırsa (user_id, symbol) benzersiz
# kısıtı ikincisini reddeder ve birleştirmeye düşülür.
def _locked_position(db: Session, user_id: int, symbol: str) -> Portfolio | None:
    """Pozisyon satırını satır kilidiyle okur (Postgres `FOR UPDATE`).

    SQLite'ta (test + lokal geliştirme) SQLAlchemy bu ifadeyi sessizce
    düşürür — tek yazarlı olduğu için davranış değişmez.
    """
    return (
        db.query(Portfolio)
        .filter(Portfolio.user_id == user_id, Portfolio.symbol == symbol)
        .with_for_update()
        .first()
    )


def _insert_position(db: Session, user_id: int, symbol: str,
                     quantity: float, average_cost: float,
                     fx_rate_at_cost: float | None = None) -> Portfolio | None:
    """Yeni pozisyon satırı ekler; benzersiz kısıt çakışırsa None döner.

    Satır YOKKEN kilitlenecek bir şey de yoktur → iki istek aynı anda INSERT
    edebilir. SAVEPOINT içinde denenir ki çakışma çağıranın transaction'ının
    tamamını düşürmesin; çağıran satırı kilitle yeniden okuyup birleştirir.
    """
    savepoint = db.begin_nested()
    try:
        item = Portfolio(user_id=user_id, symbol=symbol,
                         quantity=quantity, average_cost=average_cost,
                         fx_rate_at_cost=fx_rate_at_cost)
        db.add(item)
        db.flush()
        savepoint.commit()
        return item
    except IntegrityError:
        savepoint.rollback()
        return None


def _merge_buy_lot(db: Session, user_id: int, symbol: str,
                   quantity: float, unit_cost: float,
                   acquired_at=None) -> Portfolio:
    """Alış lotunu pozisyona ekler (ağırlıklı ortalama maliyet + alış kuru).

    Standart aracı kurum davranışı: mevcut lot ile yeni lot birleşir. Satır
    varsa kilitli okunur, yoksa eklenir; ekleme yarışı kaybedilirse satır
    kilitle okunup birleştirilir.

    `acquired_at` verilirse (manuel içe aktarma / ekstre satırı) lotun ₺
    maliyeti O GÜNÜN kuruyla işaretlenir; verilmezse bugünkü kur. Pozisyonun
    kuru, lotların NATIVE maliyetiyle ağırlıklandırılır — böylece
    `native_maliyet × kur` her zaman gerçek ₺ maliyeti verir.
    """
    # Para birimi KANONİK sembolden karar verilir: kayıt "THYAO" olarak
    # gelebilir, portfolio_service ise okurken canonical("THYAO")="THYAO.IS"
    # üzerinden ₺ der. İki taraf aynı sembolü görmezse ₺ varlığa boşuna kur
    # damgalanır.
    currency = fx_service.currency_of(canonical(symbol))
    lot_fx = fx_service.rate_at_cost(currency, acquired_at)

    item = _locked_position(db, user_id, symbol)
    if item is None:
        item = _insert_position(db, user_id, symbol, quantity, unit_cost,
                                fx_rate_at_cost=lot_fx)
        if item is not None:
            return item
        # Yarışı kaybettik — satırı rakip yazdı; kilitleyip birleştir.
        item = _locked_position(db, user_id, symbol)
        if item is None:  # pragma: no cover — kısıt varsa buraya düşülmez
            raise HTTPException(status_code=409,
                                detail="Pozisyon güncellenemedi, tekrar dene")

    old_native = item.quantity * item.average_cost
    new_native = quantity * unit_cost
    total_value = old_native + new_native
    item.quantity += quantity
    item.average_cost = total_value / item.quantity

    if lot_fx is not None and total_value > 0:
        # Mevcut satırın kuru bilinmiyorsa (kolon eklenmeden önce yazılmış
        # kayıt) o kısım BUGÜNKÜ kurla değerleniyordu — birleştirmede aynı
        # varsayım sabitlenir, yoksa yeni lotun kuru tüm pozisyona yayılırdı.
        old_fx = item.fx_rate_at_cost or fx_service.usdtry_rate()
        item.fx_rate_at_cost = (
            (old_native * old_fx) + (new_native * lot_fx)) / total_value
    return item


# İşlem KAYDI — sanal emir motoru değil, kayıt defteri: kullanıcının gerçekte
# yaptığı alış/satışı deftere işler. Pozisyon güncellenir, Transaction düşülür;
# sanal nakit YOK (pivot: uygulama gerçek portföyü izler, alım-satım simüle etmez).
def execute_trade(db: Session, trade_req: TradeRequest):
    if trade_req.quantity <= 0:
        raise HTTPException(status_code=400, detail="Miktar pozitif olmalı")

    user = db.query(User).filter(User.id == trade_req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    # güncel fiyatı yfinance'tan çek, cache varsa oradan gelir. Kayıt fiyatı
    # NATIVE kalır (USD hissede USD); gösterim/temettü fx_service ile çevirir.
    market_data = get_stock_data(trade_req.symbol)
    current_price = market_data["current_price"]

    if trade_req.transaction_type == "BUY":
        # Lot birleştirme + ağırlıklı ortalama maliyet, satır kilidi altında
        # (NATIVE maliyet — gösterimde ₺'ye çevrilir).
        portfolio_item = _merge_buy_lot(
            db, user.id, trade_req.symbol.upper(),
            trade_req.quantity, current_price,
        )

    elif trade_req.transaction_type == "SELL":
        portfolio_item = _locked_position(
            db, user.id, trade_req.symbol.upper())

        # elinde olmayan hisseyi satmaya çalışıyor
        if not portfolio_item or portfolio_item.quantity < trade_req.quantity:
            raise HTTPException(status_code=400, detail="Yetersiz hisse senedi miktarı")

        portfolio_item.quantity -= trade_req.quantity

        # çok az kaldıysa (float hata payı) kaydı tamamen sil
        if portfolio_item.quantity < _QTY_EPSILON:
            db.delete(portfolio_item)
    else:
        raise HTTPException(status_code=400, detail="Geçersiz işlem tipi")

    # her işlemi transaction tablosuna kaydet, davranışsal analiz bunu kullanıyor
    transaction = Transaction(
        user_id=user.id,
        symbol=trade_req.symbol.upper(),
        transaction_type=trade_req.transaction_type,
        quantity=trade_req.quantity,
        price=current_price
    )
    db.add(transaction)
    db.commit()
    db.refresh(transaction)

    return transaction


def import_manual_position(db: Session, req):
    """Manuel pozisyon içe aktarma — kullanıcının GERÇEKTE sahip olduğu bir
    pozisyonu (maliyet + lot) portföye tanımlar (Midas screenshot→import
    dahil). Auditlenebilir olması + temettü mutabakatının ilk-alım tarihini
    cutoff alması + davranış servisinin maliyet-baz lotu kurabilmesi için
    bir BUY işlemi kaydeder (girilen birim maliyet + edinim tarihi)."""
    if req.quantity <= 0:
        raise HTTPException(status_code=400, detail="Lot pozitif olmalı")
    if req.avg_cost <= 0:
        raise HTTPException(status_code=400, detail="Maliyet pozitif olmalı")

    user = db.query(User).filter(User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    symbol = req.symbol.upper()

    # Edinim tarihi: verilmezse şimdi. Gelecek tarih şimdiye sıkıştırılır
    # (temettü cutoff'u tutarsız olmasın). Naive UTC olarak normalize edilir
    # (diğer işlemler de naive utcnow kaydediyor).
    now = datetime.utcnow()
    acquired = req.acquired_at or now
    if acquired.tzinfo is not None:
        acquired = acquired.astimezone(timezone.utc).replace(tzinfo=None)
    if acquired > now:
        acquired = now

    # execute_trade BUY ile birebir aynı kalıp (mevcut + yeni lot birleşir),
    # aynı satır kilidi + benzersiz-kısıt koruması altında.
    _merge_buy_lot(db, user.id, symbol, req.quantity, req.avg_cost,
                   acquired_at=acquired)

    transaction = Transaction(
        user_id=user.id,
        symbol=symbol,
        transaction_type="BUY",
        quantity=req.quantity,
        price=req.avg_cost,
        timestamp=acquired,
    )
    db.add(transaction)
    db.commit()
    db.refresh(transaction)
    return transaction


# ── Kurumsal işlem mutabakatı: hisse bölünmesi (forward-only) ───────────
# Kullanıcı tercihi: GERİYE dönük düzeltme YOK. Yalnız bu tarihten İTİBAREN
# gerçekleşen bölünmeler uygulanır; bundan önceki geçmiş drift'e dokunulmaz.
_SPLIT_EPOCH = datetime(2026, 5, 18)
# Bölünme serisi paylaşılan cache'te (Redis varsa restart'a dayanır + worker'lar
# paylaşır; yoksa in-process). Bölünme nadir → 24s TTL. Değer JSON olduğundan
# datetime'ı iso string olarak saklarız.
_SPLITS_TTL_SECONDS = 24 * 3600
_SPLITS_KEY = "splits:"


def _symbol_splits(symbol: str) -> list:
    """yfinance bölünme serisi, 24s paylaşılan cache. [(naive_utc_datetime, factor)]."""
    key = _SPLITS_KEY + symbol
    hit = cache.get(key)
    if hit is not None and (time.time() - hit[1]) < _SPLITS_TTL_SECONDS:
        return [(datetime.fromisoformat(iso), f) for iso, f in hit[0]]

    out = []  # [(datetime, factor)]
    try:
        s = yf.Ticker(symbol).splits
        if s is not None and len(s) > 0:
            for ts, factor in s.items():
                d = ts.to_pydatetime()
                if d.tzinfo is not None:
                    d = d.astimezone(timezone.utc).replace(tzinfo=None)
                f = float(factor)
                if f > 0:
                    out.append((d, f))
    except Exception as exc:
        logger.debug(f"splits fetch {symbol}: {exc}")
    # Boş sonuç da cache'lenir (negatif cache). iso + factor olarak sakla.
    cache.set(key, [(d.isoformat(), f) for d, f in out], _SPLITS_TTL_SECONDS)
    return out


# Forward-only mutabakat yalnız _SPLIT_EPOCH SONRASINI uygular → batch'te tüm
# geçmişi çekmeye gerek yok. Epoch'u rahat kapsayan pencere yeter.
_SPLITS_BATCH_PERIOD = "2y"


def _prewarm_splits_batch(symbols: list[str]) -> set[str]:
    """Bölünme serilerini TEK `yf.download(actions=True)` ile çekip cache'e
    yazar; ısıtılan sembolleri döner. Boş küme = indirme başarısız.

    Neden: `reconcile_splits` HER portföy okumasında çalışıyor ve eskiden
    sembol başına ayrı `yf.Ticker().splits` isteği atıyordu. 40 pozisyonlu
    portföyde soğuk açılış = 40 ek Yahoo isteği → Render IP'si 429 yiyordu."""
    if not symbols:
        return set()
    try:
        df = yf.download(
            symbols, period=_SPLITS_BATCH_PERIOD, interval="1d",
            group_by="ticker", threads=True, progress=False,
            auto_adjust=False, actions=True,
        )
    except Exception as exc:
        logger.warning(f"Bölünme batch hatası ({len(symbols)} sembol): {exc}")
        return set()
    if df is None or df.empty:
        return set()

    warmed: set[str] = set()
    multi = isinstance(df.columns, pd.MultiIndex)
    level0 = set(df.columns.get_level_values(0)) if multi else set()
    for sym in symbols:
        try:
            if multi:
                if sym not in level0:
                    continue
                sub = df[sym]
            else:
                sub = df
            if "Stock Splits" not in sub.columns:
                continue
            col = sub["Stock Splits"].dropna()
            out = []
            for ts, factor in col[col > 0].items():
                d = ts.to_pydatetime()
                if d.tzinfo is not None:
                    d = d.astimezone(timezone.utc).replace(tzinfo=None)
                f = float(factor)
                if f > 0:
                    out.append((d, f))
            # Boş sonuç da yazılır (negatif cache) — bölünmesi olmayan sembol
            # her okumada yeniden sorgulanmasın.
            cache.set(_SPLITS_KEY + sym,
                      [(d.isoformat(), f) for d, f in out],
                      _SPLITS_TTL_SECONDS)
            warmed.add(sym)
        except Exception as exc:
            logger.debug(f"Bölünme parse atlandı ({sym}): {exc}")
    return warmed


def prewarm_splits(symbols: list[str]) -> None:
    """Bölünme serilerini ısıtır: önce TEK batch, batch'in kaçırdıkları için
    (kapsam dışı sembol) tek tek fallback. Zaten taze cache'te olanlara
    dokunulmaz."""
    syms = {canonical(s) for s in symbols}
    if not syms:
        return

    now = time.time()
    todo = []
    for sym in syms:
        hit = cache.get(_SPLITS_KEY + sym)
        if hit is not None and (now - hit[1]) < _SPLITS_TTL_SECONDS:
            continue
        todo.append(sym)
    if not todo:
        return

    warmed = _prewarm_splits_batch(sorted(todo))
    rest = [s for s in todo if s not in warmed]
    if not rest:
        return
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=8) as ex:
        list(ex.map(_symbol_splits, rest))


def reconcile_splits(db: Session, user_id: int) -> int:
    """Forward-only hisse bölünmesi mutabakatı.

    _SPLIT_EPOCH'tan SONRA gerçekleşen, henüz uygulanmamış bölünmeleri
    pozisyona yansıtır: adet ×faktör, ortalama maliyet ÷faktör (toplam
    maliyet sabit, P&L bozulmaz; bölünme günü -%50 'çakılma' gibi
    görünmez). Her (sembol, gün) için bir 'ADJUST' işlemi kaydı →
    idempotent (iki kez çalışsa da çift uygulamaz). Geçmiş drift'e
    DOKUNMAZ — kullanıcı 'forward-only' seçti."""
    holdings = db.query(Portfolio).filter(
        Portfolio.user_id == user_id).all()
    if not holdings:
        return 0
    # Tüm sembollerin bölünme serisini PARALEL ısıt → aşağıdaki döngü sıcak
    # cache'ten okur (soğukta N×~1s sıralı ağ isteği yerine ~1s tek dalga).
    prewarm_splits([h.symbol for h in holdings])
    seen = {
        (t.symbol, t.timestamp.strftime("%Y-%m-%d"))
        for t in db.query(Transaction).filter(
            Transaction.user_id == user_id,
            Transaction.transaction_type == "ADJUST",
        ).all() if t.timestamp
    }
    applied = 0
    for h in holdings:
        csym = canonical(h.symbol)
        for d, factor in _symbol_splits(csym):
            if d < _SPLIT_EPOCH:
                continue  # forward-only: geçmiş bölünme geriye uygulanmaz
            day = d.strftime("%Y-%m-%d")
            if (h.symbol, day) in seen:
                continue
            old_qty = float(h.quantity)
            if old_qty <= _QTY_EPSILON or factor <= 0:
                continue
            new_qty = old_qty * factor
            h.quantity = new_qty
            h.average_cost = float(h.average_cost) / factor
            db.add(Transaction(
                user_id=user_id,
                symbol=h.symbol,
                transaction_type="ADJUST",
                quantity=round(new_qty - old_qty, 6),  # +/- eklenen adet
                price=0.0,  # nakit etkisi yok (yalnız bölünme)
                timestamp=d,
            ))
            seen.add((h.symbol, day))
            applied += 1
    if applied:
        db.commit()
    return applied


def apply_statement_rows(db: Session, user_id: int, rows: list[dict]) -> dict:
    """Onaylanmış ekstre satırlarını portföye işler (statement import 2. adım).

    `statement_import_service` yalnız ayrıştırır; kaydı burası yapar. Satırlar
    KRONOLOJİK sırayla oynatılır — ortalama maliyet ancak alış/satışlar gerçek
    sırasıyla uygulanırsa doğru çıkar.

    Aynı ekstre iki kez yüklenirse işlemler ÇİFTLENMEZ: (sembol, tip, adet,
    fiyat, gün) dörtlüsü zaten kayıtlıysa satır atlanır.

    Elde olmayan lotun satışı hata değildir (kullanıcı ekstrenin yalnız son
    dönemini yüklemiş olabilir) — satır `skipped`'a yazılır, kalanlar işlenir.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    ordered = sorted(rows, key=lambda r: str(r.get("date") or ""))
    now = datetime.utcnow()
    imported, duplicates = 0, 0
    skipped: list[str] = []
    # Oturum autoflush=False (core/database.py) → döngü içinde db.add() ile
    # eklenen yeni pozisyon sonraki query'de GÖRÜNMEZ; aynı sembolden ikinci
    # bir alış ikinci bir Portfolio satırı yaratırdı. Sembol→pozisyon eşlemesi
    # döngü boyunca burada tutulur.
    positions: dict[str, Portfolio] = {}

    for row in ordered:
        try:
            symbol = canonical(str(row["symbol"]).strip().upper())
            side = str(row["side"]).upper()
            quantity = float(row["quantity"])
            price = float(row["price"])
        except (KeyError, TypeError, ValueError):
            skipped.append(f"{row!r}: alanlar okunamadı")
            continue

        if side not in ("BUY", "SELL") or quantity <= 0 or price <= 0:
            skipped.append(f"{symbol}: geçersiz satır (tip/adet/fiyat)")
            continue

        raw_date = row.get("date")
        ts = now
        if raw_date:
            try:
                ts = datetime.fromisoformat(str(raw_date))
                if ts.tzinfo is not None:
                    ts = ts.astimezone(timezone.utc).replace(tzinfo=None)
            except ValueError:
                pass
        if ts > now:
            ts = now

        # Çift yükleme koruması: aynı gün + aynı işlem zaten varsa atla.
        day_start = ts.replace(hour=0, minute=0, second=0, microsecond=0)
        day_end = day_start + timedelta(days=1)
        exists = db.query(Transaction).filter(
            Transaction.user_id == user_id,
            Transaction.symbol == symbol,
            Transaction.transaction_type == side,
            Transaction.timestamp >= day_start,
            Transaction.timestamp < day_end,
        ).all()
        if any(abs(float(t.quantity) - quantity) < _QTY_EPSILON
               and abs(float(t.price) - price) < 0.005 for t in exists):
            duplicates += 1
            continue

        item = positions.get(symbol)
        if item is None:
            item = _locked_position(db, user_id, symbol)
            if item is not None:
                positions[symbol] = item

        if side == "BUY":
            item = _merge_buy_lot(db, user_id, symbol, quantity, price,
                                  acquired_at=ts)
            positions[symbol] = item
        else:
            if not item or item.quantity + _QTY_EPSILON < quantity:
                held = item.quantity if item else 0
                skipped.append(
                    f"{symbol}: {quantity:g} lot satışı elde {held:g} lot varken "
                    "uygulanamadı (ekstrenin önceki dönemi eksik olabilir)"
                )
                continue
            # Satış ortalama maliyeti değiştirmez (standart aracı kurum davranışı)
            item.quantity -= quantity
            if item.quantity <= _QTY_EPSILON:
                item.quantity = 0.0

        db.add(Transaction(
            user_id=user_id,
            symbol=symbol,
            transaction_type=side,
            quantity=quantity,
            price=price,
            timestamp=ts,
        ))
        imported += 1

    db.commit()
    logger.info(
        f"Ekstre içe aktarma: user={user_id} işlenen={imported} "
        f"çift={duplicates} atlanan={len(skipped)}"
    )
    return {
        "imported": imported,
        "duplicates": duplicates,
        "skipped": skipped,
        "message": (
            f"{imported} işlem kaydedildi"
            + (f", {duplicates} tekrar atlandı" if duplicates else "")
            + (f", {len(skipped)} satır uygulanamadı" if skipped else "")
        ),
    }


def apply_statement_positions(db: Session, user_id: int,
                              positions: list[dict],
                              as_of: datetime | None = None) -> dict:
    """Ekstrenin PORTFÖY ÖZETİ'ni portföye yazar (statement import, snapshot modu).

    `apply_statement_rows`tan farkı: bu bir ANLIK GÖRÜNTÜ, hareket değil.
    Ekstredeki adet ve hisse başı ortalama maliyet aracı kurumun kendi
    kaydıdır → mevcut pozisyonun üstüne EKLENMEZ, onunla DEĞİŞTİRİLİR.

    Neden gerekli: kullanıcının hesabı yıllar önce açılmış olabilir; yalnız
    son birkaç ayın ekstresi varsa işlemleri oynatmak portföyü kuramaz
    (`apply_statement_rows` o zaman eksik kalır). Portföy özeti ise tek
    dosyada doğru adet + maliyeti verir.

    Denetlenebilirlik için pozisyon başına bir BUY işlemi kaydedilir
    (`import_manual_position` ile aynı sözleşme: temettü mutabakatı ve
    davranış servisi maliyet-baz lotu bu kayıttan kurar).
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Kullanıcı bulunamadı")

    now = datetime.utcnow()
    ts = as_of or now
    if ts.tzinfo is not None:
        ts = ts.astimezone(timezone.utc).replace(tzinfo=None)
    if ts > now:
        ts = now

    applied, unchanged = 0, 0
    skipped: list[str] = []

    for pos in positions:
        try:
            symbol = canonical(str(pos["symbol"]).strip().upper())
            quantity = float(pos["quantity"])
            avg_cost = float(pos.get("avg_cost") or 0)
        except (KeyError, TypeError, ValueError):
            skipped.append(f"{pos!r}: alanlar okunamadı")
            continue

        if quantity <= 0:
            skipped.append(f"{symbol}: adet sıfır/negatif")
            continue
        if avg_cost <= 0:
            # Bedelsiz/rüçhan kaydı (ekstrede maliyet 0,00 gelir) — maliyeti
            # olmayan satır portföy değerini bozar, atla.
            skipped.append(f"{symbol}: maliyet yok (bedelsiz kayıt)")
            continue

        item = _locked_position(db, user_id, symbol)

        if item and abs(float(item.quantity) - quantity) < _QTY_EPSILON \
                and abs(float(item.average_cost) - avg_cost) < 0.005:
            unchanged += 1
            continue

        # Ekstre özeti mutlak durumu yazdığı için ₺ maliyet de ekstrenin
        # tarihindeki kurla işaretlenir (birleştirme yok).
        pos_fx = fx_service.rate_at_cost(
            fx_service.currency_of(canonical(symbol)), ts)

        if item is None:
            # Ekstre ÖZETİ mutlak durumu yazar (birleştirmez) — ekleme yarışı
            # kaybedilirse satır kilitle okunup üzerine yazılır.
            item = _insert_position(db, user_id, symbol, quantity, avg_cost,
                                    fx_rate_at_cost=pos_fx)
            if item is None:
                item = _locked_position(db, user_id, symbol)
        if item is not None:
            item.quantity = quantity
            item.average_cost = avg_cost
            item.fx_rate_at_cost = pos_fx

        db.add(Transaction(
            user_id=user_id,
            symbol=symbol,
            transaction_type="BUY",
            quantity=quantity,
            price=avg_cost,
            timestamp=ts,
        ))
        applied += 1

    db.commit()
    logger.info(
        f"Ekstre portföy özeti: user={user_id} yazılan={applied} "
        f"değişmeyen={unchanged} atlanan={len(skipped)}"
    )
    return {
        "imported": applied,
        "unchanged": unchanged,
        "skipped": skipped,
        "message": (
            f"{applied} pozisyon güncellendi"
            + (f", {unchanged} pozisyon zaten güncel" if unchanged else "")
            + (f", {len(skipped)} satır atlandı" if skipped else "")
        ),
    }
