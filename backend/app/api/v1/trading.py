from typing import List
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from loguru import logger
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.schemas.trade_schema import (
    TradeRequest,
    TradeResponse,
    ManualPositionRequest,
    StatementCommitRequest,
)
from app.services import (
    order_service,
    auth_service,
    screenshot_import_service,
    statement_import_service,
)
from app.models.user import User

# Portföy screenshot'ı için kabul edilen görsel tipleri + boyut sınırı (8 MB).
_ALLOWED_IMAGE_MIME = {"image/png", "image/jpeg", "image/jpg", "image/webp"}
_MAX_IMAGE_BYTES = 8 * 1024 * 1024

router = APIRouter()


# alış/satış KAYDI — sanal emir motoru değil, kayıt defteri: kullanıcının
# gerçekte yaptığı işlemi deftere işler (pozisyon + Transaction güncellenir)
@router.post("/order", response_model=TradeResponse)
def place_order(
    trade_req: TradeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    # başka birinin hesabıyla işlem yapmaya çalışıyor mu?
    # token'daki user ile request'teki user_id eşleşmeli
    if trade_req.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcı adına işlem açamazsınız",
        )
    return order_service.execute_trade(db=db, trade_req=trade_req)


# manuel pozisyon içe aktarma — kullanıcının zaten sahip olduğu pozisyonu
# maliyet + lot ile tanımlar
@router.post("/manual-position", response_model=TradeResponse)
def add_manual_position(
    payload: ManualPositionRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    if payload.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcı adına pozisyon ekleyemezsiniz",
        )
    return order_service.import_manual_position(db=db, req=payload)


# portföy ekran görüntüsünü AI ile okuyup pozisyon adaylarına çevirir.
# Hiçbir şey kaydetmez — sadece parse eder; kullanıcı toplu editörde onaylar.
@router.post("/parse-screenshot")
async def parse_portfolio_screenshot(
    file: UploadFile = File(...),
    current_user: User = Depends(auth_service.get_current_user),
):
    # content_type ucuz bir ön-filtre (sahtelenebilir → güvenlik kararı DEĞİL).
    if file.content_type and file.content_type not in _ALLOWED_IMAGE_MIME:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Yalnızca PNG/JPEG/WebP görseli yükleyebilirsin",
        )
    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="Boş dosya")
    if len(image_bytes) > _MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Görsel 8 MB'tan büyük",
        )
    # Asıl gate: baytları gerçekten decode ederek görsel olduğunu doğrula
    # (sahte content_type'lı/bozuk/zararlı yük AI vision'a ULAŞMADAN reddedilir).
    try:
        screenshot_import_service.verify_image(image_bytes)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=str(exc),
        )
    return screenshot_import_service.parse_screenshot(image_bytes, file.content_type)


# Aracı kurum ekstresi (Midas PDF) → işlem satırları. İKİ ADIM:
# 1) /import-statement       → yalnız ayrıştırır, HİÇBİR ŞEY KAYDETMEZ
# 2) /import-statement/commit → kullanıcının onayladığı satırları işler
# Onay adımı zorunlu: kaynak PDF formatı değişince sessizce yanlış veri
# girmesinin tek güvencesi bu.
_MAX_STATEMENT_FILES = 36  # 3 yıllık aylık ekstre


@router.post("/import-statement")
async def parse_broker_statement(
    files: List[UploadFile] = File(...),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Bir veya daha çok ekstre PDF'i → işlem satırları (KAYDETMEZ).

    Çoklu dosya kabul edilir: Midas ekstreyi yalnız aylık verdiği için bir
    yıllık geçmiş 12 dosya demek. Hepsi bir kerede yüklenir, birleştirilir,
    ay sınırında tekrar eden satırlar bir kez sayılır.
    """
    if not files:
        raise HTTPException(status_code=400, detail="Dosya yüklenmedi")
    if len(files) > _MAX_STATEMENT_FILES:
        raise HTTPException(
            status_code=400,
            detail=f"En fazla {_MAX_STATEMENT_FILES} ekstre yükleyebilirsin",
        )

    payload: list[tuple[str, bytes]] = []
    for f in files:
        if f.content_type and f.content_type != "application/pdf":
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail=f"{f.filename}: yalnızca PDF ekstre yükleyebilirsin",
            )
        data = await f.read()
        if len(data) > statement_import_service.MAX_PDF_BYTES:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"{f.filename}: ekstre 10 MB'tan büyük",
            )
        payload.append((f.filename or "ekstre.pdf", data))

    try:
        result = statement_import_service.parse_statements(payload)
    except Exception as exc:
        logger.error(f"Ekstre parse hatası: {exc}")
        raise HTTPException(
            status_code=500, detail="Ekstre okunamadı, dosyaları kontrol et"
        )

    # Hiçbir dosyadan işlem VE pozisyon çıkmadıysa bunu başarı gibi döndürme:
    # kullanıcı boş bir önizleme ekranında kalıp nedenini anlayamaz. Servis
    # zaten "tanınmayan kurum / boş dönem / ekstre değil" ayrımını yapıp
    # anlamlı bir mesaj üretiyor — ilkini yüzeye çıkar.
    if not result["rows"] and not result["positions"]:
        detail = (
            result["failed_files"][0]["error"]
            if result["failed_files"]
            else "Ekstrede işlem veya pozisyon bulunamadı"
        )
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=detail
        )
    return result


@router.post("/import-statement/commit")
def commit_broker_statement(
    payload: StatementCommitRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    if payload.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Başka kullanıcı adına işlem aktaramazsınız",
        )

    if payload.mode == "positions":
        if not payload.positions:
            raise HTTPException(
                status_code=400, detail="Aktarılacak pozisyon yok"
            )
        return order_service.apply_statement_positions(
            db=db,
            user_id=current_user.id,
            positions=[p.model_dump() for p in payload.positions],
            as_of=payload.positions_as_of,
        )

    if not payload.rows:
        raise HTTPException(status_code=400, detail="Aktarılacak işlem yok")
    return order_service.apply_statement_rows(
        db=db,
        user_id=current_user.id,
        rows=[r.model_dump() | {"date": r.date.isoformat()} for r in payload.rows],
    )


@router.get("/transactions/{user_id}", response_model=List[TradeResponse])
def get_transactions(
    user_id: int,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """Kullanıcının işlem geçmişini en yeniden eskiye doğru döndürür.

    C3: offset tabanlı sayfalama. Eskiden yalnız limit vardı (sabit
    50-200) → eski işlemlere erişim yoktu. offset geriye uyumlu
    (varsayılan 0); limit/offset güvenli aralığa sıkıştırılır.
    """
    if user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Başka kullanıcının işlemlerini göremezsiniz")
    limit = max(1, min(limit, 200))
    offset = max(0, offset)
    from app.models.transaction import Transaction
    return (
        db.query(Transaction)
        .filter(Transaction.user_id == user_id)
        .order_by(Transaction.timestamp.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )


# CSV'de ham Yahoo sembolü (GC=F/=X/-USD) yerine kullanıcı-dostu ad göster
# (frontend SymbolDisplay.compact ile aynı; Kerem "=F/=X görmek istemiyorum").
_CSV_SYMBOL_LABELS = {
    "GC=F": "Altın", "SI=F": "Gümüş", "CL=F": "Ham Petrol",
    "USDTRY=X": "USD/TRY", "EURTRY=X": "EUR/TRY", "GBPTRY=X": "GBP/TRY",
    "BTC-USD": "Bitcoin", "ETH-USD": "Ethereum", "SOL-USD": "Solana",
    "BNB-USD": "BNB", "DOGE-USD": "Dogecoin", "XRP-USD": "XRP",
}


def _csv_display_symbol(symbol: str) -> str:
    import re
    s = (symbol or "").upper()
    if s in _CSV_SYMBOL_LABELS:
        return _CSV_SYMBOL_LABELS[s]
    if s.endswith("-USD"):                       # kripto: ETH-USD → ETH
        base = re.sub(r"\d+$", "", s[:-4])       # Yahoo CMC id'si (HYPE32196) at
        return base or s
    if s.endswith("=X") or s.endswith("=F"):     # döviz/emtia: suffix at
        return s[:-2]
    if s.endswith(".IS") or s.endswith(".TR"):   # BIST: ASELS.IS → ASELS
        return s[:-3]
    if s.endswith(".FON"):                       # TEFAS fonu: TLY.FON → TLY
        return s[:-4]
    return symbol


@router.get("/transactions/{user_id}/csv")
def export_transactions_csv(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(auth_service.get_current_user),
):
    """İşlem geçmişini CSV olarak indirir."""
    if user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Başka kullanıcının işlemlerini göremezsiniz")
    from app.models.transaction import Transaction
    from app.services import fx_service
    from fastapi.responses import Response
    import csv
    from io import StringIO

    txs = (
        db.query(Transaction)
        .filter(Transaction.user_id == user_id)
        .order_by(Transaction.timestamp.desc())
        .all()
    )

    # İşlem tipi Türkçe + para birimi netliği (kullanıcı "dolar mı TL mi
    # belli değil" dedi). Temettü, tahsil anında ₺/adet KİLİTLİ kaydedilir
    # (dividend_service) → sembol USD olsa da satır ₺ cinsidir.
    type_tr = {
        "BUY": "Alış", "SELL": "Satış",
        "DIVIDEND": "Temettü", "ADJUST": "Düzeltme",
    }
    fx = fx_service.usdtry_rate()  # USD satırların ₺ karşılığı için

    def _sym(c: str) -> str:
        return "₺" if c == "TRY" else "$"

    buf = StringIO()
    writer = csv.writer(buf)
    writer.writerow([
        "Tarih", "Sembol", "İşlem", "Adet",
        "Birim Fiyat", "Para Birimi", "Toplam", "Toplam (₺)",
    ])
    for tx in txs:
        cur = "TRY" if tx.transaction_type == "DIVIDEND" \
            else fx_service.currency_of(tx.symbol)
        total = round(float(tx.quantity) * float(tx.price), 2)
        total_try = total if cur == "TRY" else round(total * fx, 2)
        writer.writerow([
            tx.timestamp.strftime("%d.%m.%Y %H:%M") if tx.timestamp else "",
            _csv_display_symbol(tx.symbol),
            type_tr.get(tx.transaction_type, tx.transaction_type),
            round(float(tx.quantity), 6),
            round(float(tx.price), 4),
            _sym(cur),
            total,
            total_try,
        ])
    csv_bytes = buf.getvalue().encode("utf-8-sig")  # BOM Excel uyumluluğu için
    return Response(
        content=csv_bytes,
        media_type="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename=portly_islemler_{user_id}.csv",
        },
    )


