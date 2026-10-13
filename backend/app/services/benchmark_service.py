"""Portföy benchmark servisi.

Kullanıcının portföy getirisini BIST 100 / S&P 500 ile karşılaştırır.
Basit yaklaşım: son N gün boyunca her sembolün ağırlıklı getirisi.
"""

from datetime import datetime, timedelta
from sqlalchemy.orm import Session
import math
import pandas as pd

from app.models.portfolio import Portfolio
from app.services import market_data_service


# Period → gün sayısı
_PERIOD_DAYS = {
    "1m": 30,
    "3m": 90,
    "6m": 180,
    "1y": 365,
}

_BENCHMARK_SYMBOLS = {
    "BIST100": "XU100.IS",
    "SP500": "^GSPC",
    "USDTRY": "USDTRY=X",
}

# "Paranı bankada/altında tutsaydın" kıyas hurdle'ları.
# Mevduat ve TÜFE için ücretsiz canlı API olmadığından yaklaşık yıllık
# oranlar kullanılır (dönem uzunluğuna bileşik orantılanır). UI 'yaklaşık'
# etiketi gösterir. Güncel: Haziran 2026 (TÜİK Nis 2026 TÜFE %32.4 yıllık;
# TCMB 3-ay TL mevduat ağırlıklı ort. ~%49). Makro değiştikçe elle güncelle.
_ANNUAL_DEPOSIT_PCT = 49.0   # TL vadeli mevduat ağ. ort., yaklaşık yıllık (Haz 2026)
_ANNUAL_CPI_PCT = 32.5       # TÜFE enflasyon, yaklaşık yıllık (Haz 2026)


def _synthetic_return(annual_pct: float, days: int) -> float:
    """Yıllık oranı dönem gün sayısına bileşik orantıla."""
    return ((1 + annual_pct / 100) ** (days / 365) - 1) * 100


def _series_from_closes(raw: dict[str, float]) -> dict | None:
    """{iso_gün: kapanış} → {start, end, pct, sharpe, _series}.

    Ağa ÇIKMAZ; seriyi market_data_service.get_daily_closes tek batch'te
    çekiyor. (Eski kod sembol başına ayrı `yf.Ticker().history()` yapıyordu:
    40 pozisyonluk portföyde 44 Yahoo isteği → Render IP'si 429 yiyor,
    tüm getiriler "+0,00%" çıkıyordu.)"""
    if not raw or len(raw) < 2:
        return None
    # NaN/inf kapanışları AT (BIST kapalıyken yfinance SON barı NaN
    # döndürebiliyor → end=NaN → getiri NaN → "hesaplanamadı").
    items = sorted((d, float(c)) for d, c in raw.items()
                   if c is not None and not (math.isnan(float(c))
                                             or math.isinf(float(c))))
    if len(items) < 2:
        return None
    closes = [c for _, c in items]
    start, end = closes[0], closes[-1]
    # Tek bir yeni/bozuk sembol (geçersiz başlangıç fiyatı) tüm benchmark'ı
    # bozMASIN: None dön → çağıran o sembolü atlar ve dışlananlarda raporlar.
    if start <= 0:
        return None
    pct = (end - start) / start * 100
    sharpe = None
    if len(closes) >= 10:
        rets = [(closes[k] - closes[k - 1]) / closes[k - 1]
                for k in range(1, len(closes)) if closes[k - 1]]
        if rets:
            mean = sum(rets) / len(rets)
            var = sum((r - mean) ** 2 for r in rets) / len(rets)
            std = var ** 0.5
            if std:
                sharpe = round(mean / std * (252 ** 0.5), 2)
    # _series: takvim-günü endeksli kapanış serisi (portföy Sharpe'ı bundan).
    # Gün bazlı index → BIST/NYSE tz farkı hizalamayı bozmaz.
    ser = pd.Series([c for _, c in items],
                    index=pd.DatetimeIndex([d for d, _ in items]))
    return {"start": start, "end": end, "pct": pct, "sharpe": sharpe,
            "_series": ser}


def _is_try_symbol(symbol: str) -> bool:
    su = symbol.upper()
    return (su.endswith((".IS", ".TR", ".FON", ".ALTIN", ".GUMUS"))
            or "TRY=X" in su)


def _portfolio_sharpe(holdings, series: dict,
                      weights: dict[str, float]) -> float | None:
    """Portföyün günlük ₺ getiri serisinden yıllık Sharpe.

    Yöntem: r_portföy,t = Σ(wᵢ · rᵢ,t) — dönem-başı ağırlıklarla (gösterilen
    getiriyle tutarlı). Ağırlıklı-ortalama Sharpe'tan farkı: getiri serisinin
    oynaklığı varlıklar arası korelasyonu (kovaryansı) içerir → çeşitlendirme
    faydası doğru yansır. Risksiz faiz olarak TL mevduat oranı çıkarılır.

    Seviye (V_t) yerine GETİRİ ağırlıklama: farklı piyasa takvimleri
    (kripto hafta sonu, farklı başlangıç tarihi) seviye toplamında sahte
    sıçrama yaratırdı; getiri tarih-kesişiminde (dropna) bu sorun olmaz.
    """
    fx = series.get("USDTRY=X")
    fx_ser = fx.get("_series") if fx else None

    cols: dict[str, pd.Series] = {}
    for h in holdings:
        w = weights.get(h.symbol, 0.0)
        if w <= 0:
            continue
        s = series.get(h.symbol)
        if not s or s.get("_series") is None:
            continue
        close = s["_series"].astype(float)
        if close.empty:
            continue
        if not _is_try_symbol(h.symbol) and fx_ser is not None:
            # USD kapanışı, o tarihteki USDTRY ile ₺'ye → ₺ getirisi kur
            # hareketini de içerir (ileri-doldur: FX tatili)
            close = close * fx_ser.reindex(close.index, method="ffill")
        cols[h.symbol] = close.pct_change() * w

    if not cols:
        return None
    # dropna → yalnız TÜM pozisyonların getirisi olan günler (tarih kesişimi);
    # hafta sonu/uyuşmayan tatil günleri elenir, sahte getiri oluşmaz.
    rdf = pd.DataFrame(cols).dropna()
    if len(rdf) < 10:
        return None
    port_ret = rdf.sum(axis=1)  # Σ(wᵢ·rᵢ) — kovaryans dahil
    sd = port_ret.std()
    if sd == 0 or pd.isna(sd):
        return None
    rf_daily = (1 + _ANNUAL_DEPOSIT_PCT / 100) ** (1 / 252) - 1
    sharpe = (port_ret.mean() - rf_daily) / sd * (252 ** 0.5)
    if pd.isna(sharpe) or math.isinf(sharpe):
        return None
    return round(float(sharpe), 2)


_bench_cache: dict[tuple[int, str], tuple[dict, datetime]] = {}
_BENCH_TTL = timedelta(minutes=5)


def compute_benchmark(db: Session, user_id: int, period: str = "3m") -> dict:
    days = _PERIOD_DAYS.get(period, 90)
    ck = (user_id, period)
    if ck in _bench_cache:
        data, ts = _bench_cache[ck]
        if datetime.now() - ts < _BENCH_TTL:
            return data

    holdings = db.query(Portfolio).filter(
        Portfolio.user_id == user_id).all()

    # Tüm benzersiz sembolleri TEK SEFERDE, PARALEL çek
    bench_syms = dict(_BENCHMARK_SYMBOLS)            # ad -> sembol
    need = set(bench_syms.values()) | {"GC=F", "USDTRY=X"}
    for h in holdings:
        need.add(h.symbol)

    # TEK batch (yf.download) — sembol başına ayrı istek yerine. Yahoo 429
    # verirse get_daily_closes son bilinen seriyi döndürür (boş değil).
    closes = market_data_service.get_daily_closes(sorted(need), days)
    series: dict[str, dict | None] = {
        sym: _series_from_closes(closes.get(sym) or {}) for sym in need
    }

    usdtry = series.get("USDTRY=X")
    fx_start = usdtry["start"] if usdtry else None
    fx_end = usdtry["end"] if usdtry else None

    # Portföy getirisi — DOĞRU yöntem: her pozisyon DÖNEM BAŞI ₺ değerine
    # göre ağırlıklandırılır (eskiden dönem SONU değeriyle ağırlıklanıyordu
    # → kazananlar fazla ağırlık alıp portföy getirisi sistematik olarak
    # yukarı sapıyordu). USD pozisyonlar başta start-kuru, sonda end-kuru
    # ile ₺'ye çevrilir → getiri kur etkisini de içerir (₺ yatırımcısının
    # gerçek getirisi) ve başlık = Σ(ağırlık·getiri) birebir tutar.
    per_symbol = []
    valued = []  # (symbol, start_try, end_try, sharpe)
    excluded: list[str] = []  # dönem verisi olmayan pozisyonlar (A4 dürüst rapor)
    for h in holdings:
        s = series.get(h.symbol)
        if not s or s["start"] <= 0:
            excluded.append(h.symbol)
            continue
        is_try = _is_try_symbol(h.symbol)
        start_try = h.quantity * s["start"]
        end_try = h.quantity * s["end"]
        if not is_try:
            if fx_start and fx_end:
                start_try *= fx_start
                end_try *= fx_end
            elif fx_end:  # start kuru yoksa en azından tek kurla tutarlı kal
                start_try *= fx_end
                end_try *= fx_end
        valued.append((h.symbol, start_try, end_try, s["sharpe"]))

    total_start = sum(st for _, st, _, _ in valued)
    weighted = 0.0
    for sym, st, en, _sh in valued:
        w = st / total_start if total_start > 0 else 0.0
        ret = (en / st - 1) * 100 if st > 0 else 0.0
        weighted += w * ret
        per_symbol.append({
            "symbol": sym, "weight": round(w, 4),
            "return_pct": round(ret, 2),
        })
    # Σ(ağırlık·getiri) ≡ (Σ son − Σ baş) / Σ baş — başlık per_symbol ile tutar
    portfolio_return = weighted

    # Portföy Sharpe — GERÇEK portföy Sharpe'ı: tek tek varlık Sharpe'larının
    # ağırlıklı ortalaması DEĞİL (o, varlıklar arası korelasyonu yok sayıp
    # çeşitlendirme faydasını kaçırırdı). Bunun yerine portföyün BİRLEŞİK
    # günlük ₺ değer serisini kurup onun getirilerinden hesaplanır:
    #   • USD pozisyonlar günlük USDTRY ile ₺'ye çevrilir (tarih hizalı, ffill)
    #   • V_t = Σ(adet · ₺kapanış)   → günlük getiri = V_t / V_{t-1} − 1
    #   • Sharpe = (ort.getiri − risksiz faiz) / oynaklık · √252  (yıllık)
    # Risksiz faiz: TL mevduat (_ANNUAL_DEPOSIT_PCT) — uygulamanın Akademi
    # dersindeki "(Getiri − Risksiz Faiz)/Std" tanımıyla artık tutarlı.
    weights = {sym: (st / total_start if total_start > 0 else 0.0)
               for sym, st, _en, _sh in valued}
    portfolio_sharpe = _portfolio_sharpe(holdings, series, weights)

    benchmarks = {}
    for name, sym in bench_syms.items():
        s = series.get(sym)
        benchmarks[name] = {
            "return_pct": round(s["pct"], 2) if s else None,
            "symbol": sym,
            "sharpe": s["sharpe"] if s else None,
        }

    # Gram altın ₺ = ons USD × USDTRY / 31.1035
    g = series.get("GC=F")
    gram = None
    if g and usdtry:
        gs = g["start"] * usdtry["start"] / 31.1035
        ge = g["end"] * usdtry["end"] / 31.1035
        if gs > 0:
            gram = (ge - gs) / gs * 100
    benchmarks["GRAM_ALTIN"] = {
        "return_pct": round(gram, 2) if gram is not None else None,
        "symbol": "gram-altın ₺", "sharpe": None,
    }
    benchmarks["MEVDUAT"] = {
        "return_pct": round(_synthetic_return(_ANNUAL_DEPOSIT_PCT, days), 2),
        "symbol": f"~%{_ANNUAL_DEPOSIT_PCT:.0f}/yıl TL mevduat",
        "sharpe": None, "approx": True,
    }
    benchmarks["ENFLASYON"] = {
        "return_pct": round(_synthetic_return(_ANNUAL_CPI_PCT, days), 2),
        "symbol": f"~%{_ANNUAL_CPI_PCT:.0f}/yıl TÜFE",
        "sharpe": None, "approx": True,
    }

    result = {
        "period": period,
        "days": days,
        "portfolio": {
            "return_pct": round(portfolio_return, 2),
            "has_holdings": len(holdings) > 0,
            "sharpe": portfolio_sharpe,
            "components": per_symbol,
            # Dürüstlük: getiri yalnız dönem verisi OLAN pozisyonlardan
            # hesaplanır. Dışlananları say & listele ki "portföy getirisi"
            # aslında alt kümeyi temsil ettiğinde kullanıcı görsün.
            "symbols_included": len(valued),
            "symbols_excluded": excluded,
        },
        "benchmarks": benchmarks,
        "generated_at": datetime.now().isoformat(),
    }
    _bench_cache[ck] = (result, datetime.now())
    return result
