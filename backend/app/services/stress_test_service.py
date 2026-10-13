# =============================================================================
# Stres Testi Servisi — Hisse-bazlı Tarihsel Senaryo Şoku + Monte Carlo Bandı
#
# YAKLAŞIM (neden bu modeli seçtik):
#   Klasik "tek varlık GBM" modeli portföyü tek bir blok gibi simüle eder ve
#   "kriz herkesi aynı oranda vurur" varsayar. Gerçekte oynak bir hisse
#   (örn. yüksek-beta teknoloji) krizde, savunmacı bir hisseden çok daha
#   sert düşer. Bu yüzden:
#
#   1) Her hissenin son 1 yıl GERÇEK fiyat geçmişinden yıllık oynaklığı
#      ölçülür. Oynaklık / piyasa referansı = "krize duyarlılık" (β proxy).
#   2) Her senaryonun tarihsel ~30 günlük piyasa şoku (market_shock),
#      hisseye duyarlılığıyla ölçeklenerek uygulanır:
#         yeni_değer_i = değer_i × (1 + market_shock × duyarlılık_i)
#      → Merkezi (en olası) tahmin buradan gelir; doğal olarak asimetriktir.
#   3) Belirsizlik bandı (kötü/iyi %5) için, merkezi tahmin etrafında
#      portföyün ölçülen oynaklığı kriz rejimiyle büyütülerek 10.000 yollu
#      Monte Carlo (GBM) çalıştırılır.
#
#   Çıktı ayrıca hisse-bazlı kırılımı verir → kullanıcı hangi pozisyonun
#   riski sürüklediğini somut görür.
#
# Referanslar:
#   - Markowitz, H. (1952). Portfolio Selection. Journal of Finance.
#   - Black, F. & Scholes, M. (1973). Option Pricing. J. Political Economy.
#   - Sharpe, W. (1964). Capital Asset Prices (β / piyasa duyarlılığı).
#   - Taleb, N.N. (2007). The Black Swan.
#   - Reinhart, C.M. & Rogoff, K.S. (2009). This Time Is Different.
# =============================================================================
import math
import random
import statistics
import yfinance as yf
from sqlalchemy.orm import Session
from app.services import market_data_service, portfolio_service, fx_service

# Geniş piyasa referans yıllık oynaklığı (~%20). Bir hissenin oynaklığı
# bunun kaç katıysa krize o oranda duyarlı kabul edilir.
_MARKET_REF_ANNUAL_VOL = 0.20
# Duyarlılık (β proxy) makul banda kıstırılır: en savunmacı 0.55×,
# en agresif 2.2×. Aşırı uçlar tek bir hissenin simülasyonu patlatmasın.
_SENS_MIN, _SENS_MAX = 0.55, 2.2

# Geçmiş veri hiç yoksa kullanılan makul hisse tabanı.
_FALLBACK_DAILY_VOL = 0.015
_FALLBACK_ANNUAL_VOL = _FALLBACK_DAILY_VOL * math.sqrt(252)

# Senaryolar.
#   market_shock      : geniş piyasanın ~30 günlük kümülatif getirisi
#                       (kriz dönemlerinin gerçek ~1 aylık dilimlerinden).
#   vol_multiplier    : oynaklığın kriz rejiminde kaç katına çıktığı.
#   vol_floor         : sakin portföyde bile kriz bandı tabanı (günlük σ).
SCENARIOS = {
    "normal": {
        "name": "Sakin Piyasa (referans)",
        "description": "Kriz yok — olağan dönem. Diğer senaryoların ne kadar "
                       "kötü olduğunu görmek için karşılaştırma tabanı; "
                       "portföyünün son 1 yıldaki oynaklığı kullanılır.",
        "market_shock": None,   # ölçülen drift'ten türetilir
        "vol_multiplier": 1.0,
        "vol_floor": 0.006,
        "duration_days": 30,
        "academic": "Markowitz (1952) — Modern Portföy Teorisi",
    },
    "subprime_2008": {
        "name": "2008 Subprime Krizi",
        "description": "Lehman Brothers iflası. Portföyündeki hisselerin Eylül–"
                       "Kasım 2008'deki yüzde hareketi pozisyonlarına uygulanır.",
        "crisis_window": ("2008-09-02", "2008-11-21", "Eylül–Kasım 2008"),
        "market_shock": -0.28,   # tarihsel veri yoksa kullanılan piyasa tahmini
        "vol_multiplier": 3.5,
        "vol_floor": 0.030,
        "duration_days": 30,
        "academic": "Reinhart & Rogoff (2009) — This Time Is Different",
    },
    "covid_2020": {
        "name": "2020 COVID Çöküşü",
        "description": "Pandemi paniği. Portföyündeki hisselerin 19 Şubat–23 "
                       "Mart 2020'deki yüzde hareketi pozisyonlarına uygulanır.",
        "crisis_window": ("2020-02-19", "2020-03-23", "Şubat–Mart 2020"),
        "market_shock": -0.34,
        "vol_multiplier": 4.0,
        "vol_floor": 0.040,
        "duration_days": 30,
        "academic": "Baker et al. (2020) — COVID-Induced Uncertainty",
    },
    "bist_2018": {
        "name": "2018 BIST/TL Krizi",
        "description": "Kur krizi. Portföyündeki hisselerin Ağustos–Eylül "
                       "2018'deki yüzde hareketi pozisyonlarına uygulanır.",
        "crisis_window": ("2018-08-01", "2018-09-10", "Ağustos 2018"),
        "market_shock": -0.20,
        "vol_multiplier": 3.0,
        "vol_floor": 0.028,
        "duration_days": 30,
        "academic": "Akıncı & Olmstead-Rumsey (2018) — EM Capital Flows",
    },
    "savas_2022": {
        "name": "2022 Rusya-Ukrayna Savaşı",
        "description": "Rusya'nın Ukrayna'yı işgali. Portföyündeki varlıkların "
                       "24 Şubat–8 Mart 2022'deki yüzde hareketi pozisyonlarına "
                       "uygulanır (riskli varlıklar satılır, enerji/emtia sıçrar).",
        "crisis_window": ("2022-02-21", "2022-03-08", "Şubat–Mart 2022"),
        "market_shock": -0.12,
        "vol_multiplier": 2.8,
        "vol_floor": 0.022,
        "duration_days": 30,
        "academic": "Caldara & Iacoviello (2022) — Geopolitical Risk Index",
    },
    "iran_2024": {
        "name": "2024 İran-Ortadoğu Gerilimi",
        "description": "İran-İsrail doğrudan çatışma korkusunun tetiklediği "
                       "risk-off dönemi. Portföyündeki varlıkların 11–22 Nisan "
                       "2024'teki yüzde hareketi pozisyonlarına uygulanır "
                       "(teknoloji/yüksek-beta hisseler en sert düşer).",
        "crisis_window": ("2024-04-11", "2024-04-22", "Nisan 2024"),
        "market_shock": -0.06,
        "vol_multiplier": 2.2,
        "vol_floor": 0.018,
        "duration_days": 30,
        "academic": "Caldara & Iacoviello (2022) — Geopolitical Risk Index",
    },
    "black_swan": {
        "name": "Ekstrem Şok (hipotetik)",
        "description": "Tarihte görülmemiş, öngörülemeyen aşırı çöküş — en kötü "
                       "durum testi. Gerçek bir dönem yok; her hisse kendi "
                       "oynaklığına göre en sert biçimde vurulur.",
        "crisis_window": None,   # hipotetik — gerçek tarihsel dönem yok
        "market_shock": -0.45,
        "vol_multiplier": 5.0,
        "vol_floor": 0.055,
        "duration_days": 30,
        "academic": "Taleb (2007) — The Black Swan",
    },
}

# Kriz pencereleri sabit tarihlerde → süreç ömrü boyunca cache'lenebilir.
_window_cache: dict[tuple, tuple] = {}


def _window_performance(symbol: str, start: str, end: str) -> tuple | None:
    """Hissenin belirli kriz tarih aralığındaki GERÇEK performansı.

    Döndürür: (kümülatif_getiri, gerçekleşen_günlük_oynaklık) veya
    hisse o dönemde işlem görmüyorsa / veri yoksa None.
    """
    key = (symbol.upper(), start, end)
    if key in _window_cache:
        return _window_cache[key]
    result = None
    try:
        raw = yf.Ticker(symbol).history(start=start, end=end, interval="1d")
        closes = [float(x) for x in raw["Close"].tolist() if x and x > 0]
        if len(closes) >= 5:
            cum = closes[-1] / closes[0] - 1.0
            rets = [
                (closes[i] - closes[i - 1]) / closes[i - 1]
                for i in range(1, len(closes))
            ]
            rvol = statistics.pstdev(rets) if len(rets) >= 2 else 0.0
            result = (cum, rvol)
    except Exception:
        result = None
    _window_cache[key] = result
    return result


def _symbol_currency(symbol: str) -> str:
    """Sembol → para birimi (BIST/.IS, TEFAS fonu/.FON ve TRY paritesi ₺,
    gerisi $)."""
    s = symbol.upper()
    if s.endswith((".IS", ".TR", ".FON", ".ALTIN", ".GUMUS")) \
            or "TRY=X" in s:
        return "TRY"
    return "USD"


def _usdtry_rate() -> float:
    """1 USD kaç ₺. Ortak fx_service (tek doğruluk kaynağı) — eskiden
    buradaki yerel kopya 3 servisten biriydi, kur tutarsızlığı riskliydi."""
    return fx_service.usdtry_rate()


# UI'da gizli senaryolar: "normal" iç volatilite referansı (SCENARIOS'ta KALMALI —
# default/hesap kullanır), "black_swan" aşırı-jargon → kullanıcı listesinden çıkarıldı.
_HIDDEN_SCENARIOS = {"normal", "black_swan"}


def list_scenarios() -> list:
    """Senaryo listesi (UI seçici için). Gizli senaryolar (referans/jargon) hariç."""
    return [
        {"id": sid, "name": s["name"], "description": s["description"]}
        for sid, s in SCENARIOS.items()
        if sid not in _HIDDEN_SCENARIOS
    ]


def _holding_stats(db: Session, user_id: int) -> tuple[float, list, float]:
    """Her pozisyon için değer, ağırlık ve 1 yıllık oynaklık.

    Para birimi karışık olabilir (BIST ₺, ABD $). Toplam/ağırlık/band ortak
    para birimi ₺ üzerinden hesaplanır; kırılım gösterimi için pozisyonun
    kendi para birimindeki (native) değeri ayrıca saklanır.

    Döndürür: (toplam_değer_try, [ {...} ], usdtry_kuru)
    """
    holdings = portfolio_service.get_user_portfolio(db, user_id)
    if not holdings:
        return 0.0, [], _usdtry_rate()

    rate = _usdtry_rate()

    def _to_try(v: float, cur: str) -> float:
        return v * rate if cur == "USD" else v

    total = sum(
        _to_try(h["total_value"], _symbol_currency(h["symbol"])) for h in holdings
    )
    stats = []
    for h in holdings:
        sym = h["symbol"]
        currency = _symbol_currency(sym)
        value_native = h["total_value"]                 # pozisyonun kendi parası
        value = _to_try(value_native, currency)         # ortak para (₺)
        daily_vol = _FALLBACK_DAILY_VOL
        daily_drift = 0.0003
        has_history = False
        try:
            hist = market_data_service.get_stock_history(
                sym, period="1y", interval="1d"
            )
            closes = [p["close"] for p in hist.get("data", []) if p["close"] > 0]
            if len(closes) >= 30:
                rets = [
                    (closes[i] - closes[i - 1]) / closes[i - 1]
                    for i in range(1, len(closes))
                ]
                daily_vol = statistics.pstdev(rets)
                daily_drift = statistics.mean(rets)
                has_history = True
        except Exception:
            pass

        # Aşırı uçları makul banda çek (tek hisse simülasyonu patlatmasın)
        daily_vol = min(max(daily_vol, 0.004), 0.090)
        daily_drift = min(max(daily_drift, -0.004), 0.004)
        stats.append({
            "symbol": sym,
            "currency": currency,
            "quantity": float(h.get("quantity", 0) or 0),
            "price_native": float(h.get("current_price", 0) or 0),  # birim fiyat
            "value": round(value, 2),                    # ₺ (ortak)
            "value_native": round(value_native, 2),      # $ veya ₺ (kendi)
            "weight": round(value / total, 4) if total > 0 else 0.0,
            "daily_vol": daily_vol,
            "annual_vol": daily_vol * math.sqrt(252),
            "daily_drift": daily_drift,
            "has_history": has_history,
        })
    return total, stats, rate


def _portfolio_sigma(stats: list) -> tuple[float, float, float, str]:
    """Pozisyon oynaklıklarını ağırlıklı birleştir.

    Korelasyonu açıkça modellemek yerine ağırlıklı σ kullanılır (hafif
    tutucu üst sınır — gerçek çeşitlendirme bunu biraz daha düşürür).
    Döndürür: (daily_vol_p, daily_drift_p, annual_vol_pct, source)
    """
    if not stats:
        return _FALLBACK_DAILY_VOL, 0.0003, round(_FALLBACK_ANNUAL_VOL * 100, 1), "fallback"
    dv = sum(s["weight"] * s["daily_vol"] for s in stats)
    dd = sum(s["weight"] * s["daily_drift"] for s in stats)
    covered = sum(s["weight"] for s in stats if s["has_history"])
    if covered >= 0.999:
        source = "measured"
    elif covered > 0.01:
        source = "partial"
    else:
        source = "fallback"
    dv = min(max(dv, 0.004), 0.090)
    return round(dv, 5), round(dd, 5), round(dv * math.sqrt(252) * 100, 1), source


def _sensitivity(annual_vol: float) -> float:
    """Hissenin krize duyarlılığı (β proxy): oynaklık / piyasa referansı."""
    return min(max(annual_vol / _MARKET_REF_ANNUAL_VOL, _SENS_MIN), _SENS_MAX)


def _monte_carlo_band(
    initial: float, target_value: float, daily_vol: float, days: int
) -> dict:
    """Merkezi tahmin (target_value) etrafında belirsizlik bandı.

    GBM, 30 günde beklenen değeri target_value'ya getirecek drift ile
    çalıştırılır; oynaklık kriz rejimini yansıtır. 10.000 yol — sabit
    tutulur: daha fazla yol = daha az örnekleme varyansı; kararlılık
    ve matematiksel doğruluk hızdan önceliklidir (kullanıcı kararı).
    """
    n = 10000
    # E[S_T] = S_0 · e^{μ·T}  →  μ = ln(target/initial) / T
    ratio = max(target_value / initial, 0.02)
    mu = math.log(ratio) / days
    finals = []
    for _ in range(n):
        v = initial
        for _ in range(days):
            z = random.gauss(0, 1)
            v *= math.exp((mu - 0.5 * daily_vol ** 2) + daily_vol * z)
        finals.append(v)
    finals.sort()
    p5 = finals[int(n * 0.05)]
    p50 = finals[int(n * 0.50)]
    p95 = finals[int(n * 0.95)]
    mean = statistics.mean(finals)
    cvar = statistics.mean(finals[: int(n * 0.05)])
    return {
        "p5_worst_case": round(p5, 2),
        "p50_median": round(p50, 2),
        "p95_best_case": round(p95, 2),
        "mean": round(mean, 2),
        "var_95": round(initial - p5, 2),
        "cvar_95": round(initial - cvar, 2),
    }


def run_stress_test(db: Session, user_id: int, scenario: str = "normal") -> dict:
    """Ana fonksiyon."""
    if scenario not in SCENARIOS:
        scenario = "normal"
    sc = SCENARIOS[scenario]
    days = sc["duration_days"]

    total, stats, usdtry = _holding_stats(db, user_id)
    if total <= 0 or not stats:
        return {
            "has_portfolio": False,
            "message": "Stres testi için en az bir hisse pozisyonu gerekli.",
        }

    dv_p, dd_p, annual_vol_pct, source = _portfolio_sigma(stats)

    # Senaryonun piyasa şoku (normal'de ölçülen drift'ten, damped).
    if sc["market_shock"] is None:
        market_shock = max(min(dd_p * days * 0.5, 0.05), -0.05)
    else:
        market_shock = sc["market_shock"]

    window = sc.get("crisis_window")
    crisis_period = window[2] if window else None

    # Hisse-bazlı şok (değişim bir yüzdedir → para biriminden bağımsız;
    # aynı oran hem ₺ hem native değere uygulanır):
    #   1) Senaryonun kriz penceresi varsa → hissenin o dönemdeki yüzde
    #      hareketini kullan.
    #   2) Hisse o dönemde işlem görmüyorsa ya da senaryo hipotetikse →
    #      oynaklık-tabanlı tahmine düş.
    breakdown = []
    stressed_total = 0.0
    band_vol_acc = 0.0          # ağırlıklı günlük oynaklık (band için)
    historical_count = 0
    for s in stats:
        sens = _sensitivity(s["annual_vol"])
        basis = "estimated"
        realized_dvol = s["daily_vol"] * sc["vol_multiplier"]

        if window:
            perf = _window_performance(s["symbol"], window[0], window[1])
            if perf is not None:
                change, rvol = perf
                basis = "historical"
                historical_count += 1
                if rvol > 0:
                    realized_dvol = rvol
            else:
                change = market_shock * sens
        elif sc["market_shock"] is None:
            # Normal piyasa: ölçülen drift'i ufka taşı (hafif sönümlü).
            change = market_shock * sens
            basis = "normal"
        else:
            # Hipotetik (Siyah Kuğu): oynaklığa göre tahmin.
            change = market_shock * sens

        # Bir hisse bu pencerelerde gerçekçi olarak %92'den fazla kaybetmez.
        keep = max(1 + change, 0.08)
        new_value = s["value"] * keep                   # ₺ (toplam için)
        new_value_native = s["value_native"] * keep     # kendi para birimi
        price_b = s["price_native"]                     # birim fiyat (kendi)
        price_a = price_b * keep
        rate_i = (s["value"] / s["value_native"]) if s["value_native"] else 1.0
        stressed_total += new_value
        band_vol_acc += s["weight"] * realized_dvol
        breakdown.append({
            "symbol": s["symbol"],
            "currency": s["currency"],
            "quantity": s["quantity"],
            "price_before": round(price_b, 2),             # birim fiyat (kendi)
            "price_after": round(price_a, 2),
            "price_before_try": round(price_b * rate_i, 2),
            "price_after_try": round(price_a * rate_i, 2),
            "value_before": round(s["value_native"], 2),   # bakiye (kendi)
            "value_after": round(new_value_native, 2),
            "value_before_try": round(s["value"], 2),
            "value_after_try": round(new_value, 2),
            "change_pct": round((keep - 1) * 100, 1),
            "weight": s["weight"],
            "annual_vol_pct": round(s["annual_vol"] * 100, 1),
            "sensitivity": round(sens, 2),
            "basis": basis,
        })

    breakdown.sort(key=lambda b: b["change_pct"])

    # Band oynaklığı: gerçek kriz penceresinin gerçekleşen oynaklığından
    # (mümkünse), değilse ölçülen σ × kriz çarpanından; tabanın altına inme.
    sim_daily_vol = max(band_vol_acc, sc["vol_floor"])
    sim_daily_vol = min(sim_daily_vol, 0.12)
    band = _monte_carlo_band(total, stressed_total, sim_daily_vol, days)

    central_pct = round((stressed_total / total - 1) * 100, 1)

    # Toparlanma süresi (eğitsel tahmin): krizden sonra eski tepeye (initial)
    # dönmek için portföyün normal büyümesiyle kaç ay gerekir. Drift çok
    # düşük/negatifse makul taban (~%0.5/ay ≈ %6/yıl) ile sonlu tutulur; üst 120 ay.
    if stressed_total >= total:
        recovery_months = 0
    else:
        monthly_growth = max(dd_p * 21, 0.005)
        recovery_months = int(min(
            math.ceil(math.log(total / stressed_total) / math.log(1 + monthly_growth)),
            120,
        ))

    # Zayıf halka: bu senaryoda EN SERT % düşen 1-2 pozisyon (en kırılgan varlık).
    # ₺ kaybı değil yüzde düşüş baz alınır → senaryoya göre değişir ve breakdown'daki
    # "En çok zarar gören" (%) rozetiyle tutarlı. (₺ kaybı pozisyon büyüklüğüne baskın
    # olduğundan senaryodan bağımsız hep en büyük pozisyonu — NVDA/MSFT — gösterirdi.)
    losers = sorted(
        (b for b in breakdown if b["change_pct"] < 0),
        key=lambda b: b["change_pct"],
    )
    weak_links = [
        {
            "symbol": b["symbol"],
            "change_pct": b["change_pct"],
            "loss_try": round(b["value_before_try"] - b["value_after_try"], 2),
            "weight": b["weight"],
        }
        for b in losers[:2]
    ]

    # Sade dayanıklılık etiketi (en olası kayba göre).
    if central_pct >= -3:
        resilience = "DAYANIKLI"
    elif central_pct >= -15:
        resilience = "ORTA"
    elif central_pct >= -30:
        resilience = "KIRILGAN"
    else:
        resilience = "ÇOK KIRILGAN"

    return {
        "has_portfolio": True,
        "scenario_id": scenario,
        "scenario_name": sc["name"],
        "scenario_description": sc["description"],
        "academic_reference": sc["academic"],
        "duration_days": days,
        "initial_value": round(total, 2),
        "expected_value": round(stressed_total, 2),
        "expected_change_pct": central_pct,
        "recovery_months": recovery_months,
        "weak_links": weak_links,
        "resilience": resilience,
        "market_shock_pct": round(market_shock * 100, 1),
        "crisis_period": crisis_period,
        "historical_count": historical_count,
        "total_holdings": len(stats),
        "usdtry_rate": round(usdtry, 2),
        "usd_holdings_count": sum(1 for s in stats if s["currency"] == "USD"),
        "portfolio": {
            "annual_vol_pct": annual_vol_pct,
            "applied_annual_vol_pct": round(sim_daily_vol * math.sqrt(252) * 100, 1),
            "data_source": source,
        },
        "band": band,
        "breakdown": breakdown,
    }


# Geriye dönük uyumluluk (eski import adı).
def run_monte_carlo(db: Session, user_id: int, scenario: str = "normal") -> dict:
    return run_stress_test(db, user_id, scenario)
