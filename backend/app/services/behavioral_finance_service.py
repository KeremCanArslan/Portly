# =============================================================================
# Behavioral Finance Analysis Service
#
# Bu modül, kullanıcının alım-satım işlemlerini üç temel akademik bilişsel
# önyargı modeli çerçevesinde analiz etmektedir. Hesaplanan skorlar, AI
# koçunun kişiselleştirilmiş geri bildirim üretmesinde bağlam verisi olarak
# kullanılmaktadır.
#
# Akademik Referanslar:
#   [1] Shefrin, H. & Statman, M. (1985). The Disposition to Sell Winners
#       Too Early and Ride Losers Too Long: Theory and Evidence.
#       Journal of Finance, 40(3), 777–790.
#   [2] Barber, B.M. & Odean, T. (2001). Trading Is Hazardous to Your Wealth:
#       The Common Stock Investment Performance of Individual Investors.
#       Journal of Finance, 55(2), 773–806.
#   [3] Kahneman, D. & Tversky, A. (1979). Prospect Theory: An Analysis of
#       Decision under Risk. Econometrica, 47(2), 263–291.
# =============================================================================
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from collections import defaultdict
from app.models.transaction import Transaction
from app.services import market_data_service


def _calculate_disposition_effect(transactions: list) -> dict:
    """
    Disposition Effect: Kazançları erken satma, kayıpları tutma eğilimi.
    PGR (Proportion of Gains Realized) - PLR (Proportion of Losses Realized)
    Pozitif değer = bu önyargı var.
    Shefrin & Statman (1985) metodolojisi.
    """
    # Lot takibi: her sembol için ağırlıklı ortalama maliyet (WAC) tutulur.
    # FIFO yerine WAC tercih edilmiştir; BIST'teki çoklu lot alımlarını
    # daha gerçekçi biçimde modellemektedir.
    holdings = defaultdict(lambda: {"qty": 0.0, "total_cost": 0.0})
    realized_gains = 0    # Kârda kapatılan pozisyon sayısı
    realized_losses = 0   # Zararda kapatılan pozisyon sayısı
    paper_gains = 0       # Açık konumda ve kârda olan pozisyon sayısı
    paper_losses = 0      # Açık konumda ve zararda olan pozisyon sayısı

    for tx in transactions:
        sym = tx.symbol
        if tx.transaction_type == "BUY":
            holdings[sym]["qty"] += tx.quantity
            holdings[sym]["total_cost"] += tx.quantity * tx.price
        elif tx.transaction_type == "SELL" and holdings[sym]["qty"] > 0:
            avg_cost = holdings[sym]["total_cost"] / holdings[sym]["qty"]
            if tx.price > avg_cost:
                realized_gains += 1
            elif tx.price < avg_cost:
                realized_losses += 1
            holdings[sym]["qty"] -= tx.quantity
            holdings[sym]["total_cost"] -= tx.quantity * avg_cost
            # Kayan nokta birikimli hatasından korunmak için epsilon eşiği uygulanır
            if holdings[sym]["qty"] < 0.0001:
                holdings[sym]["qty"] = 0.0
                holdings[sym]["total_cost"] = 0.0

    open_positions = [(sym, h) for sym, h in holdings.items() if h["qty"] > 0]

    if open_positions:
        from concurrent.futures import ThreadPoolExecutor

        # Açık pozisyonların güncel piyasa fiyatlarını eş zamanlı olarak çekmek için
        # ThreadPoolExecutor kullanılmaktadır. Her pozisyon ayrı bir yfinance HTTP
        # isteği gerektirdiğinden, bu I/O-bound işlemler thread havuzuyla
        # paralel yürütülür (Python GIL bu durumda performans engeli değildir).
        def _fetch_price(item):
            sym, h = item
            try:
                avg_cost = h["total_cost"] / h["qty"]
                current = market_data_service.get_stock_data(sym)["current_price"]
                return (current, avg_cost)
            except Exception:
                return None

        with ThreadPoolExecutor(max_workers=8) as ex:
            results = list(ex.map(_fetch_price, open_positions))

        for r in results:
            if r is None:
                continue
            current, avg_cost = r
            if current > avg_cost:
                paper_gains += 1
            elif current < avg_cost:
                paper_losses += 1

    # PGR = realized_gains / (realized_gains + paper_gains)
    # PLR = realized_losses / (realized_losses + paper_losses)
    # DE Skoru = PGR - PLR; pozitif değer Disposition Effect varlığını gösterir.
    # Teorik aralık: [-1, +1]; sıfıra yakın değerler rasyonel davranışı işaret eder.
    pgr = realized_gains / (realized_gains + paper_gains) if (realized_gains + paper_gains) > 0 else 0
    plr = realized_losses / (realized_losses + paper_losses) if (realized_losses + paper_losses) > 0 else 0
    de_score = pgr - plr  # -1 ile +1 arasında

    return {
        "score": round(de_score, 3),
        "pgr": round(pgr, 3),
        "plr": round(plr, 3),
        "realized_gains": realized_gains,
        "realized_losses": realized_losses,
        "paper_gains": paper_gains,
        "paper_losses": paper_losses,
    }


def _calculate_overconfidence(transactions: list) -> dict:
    """
    Overconfidence: Yüksek işlem sıklığı.
    Barber & Odean (2001) - "Trading is Hazardous to Your Wealth".
    Aktif gün başına işlem oranı ile ölçülür.
    """
    if not transactions:
        return {"score": 0.0, "trades_per_day": 0.0, "total_trades": 0, "active_days": 0}

    # İşlem tarihlerinden benzersiz günler çıkarılır; aktif işlem periyodu hesaplanır.
    # Barber & Odean (2001) metodolojisine paralel biçimde "active_days", ilk ve son
    # işlem tarihleri arasındaki toplam takvim günü olarak tanımlanmıştır.
    dates = sorted({tx.timestamp.date() for tx in transactions})
    if len(dates) < 2:
        active_days = 1
    else:
        active_days = (dates[-1] - dates[0]).days + 1

    total_trades = len(transactions)
    trades_per_day = total_trades / active_days

    # 0-1 arasına normalize et: 0.5 işlem/gün = 0.5 skor (üzeri yüksek)
    # Eşik değer, bireysel yatırımcı çalışmalarındaki medyan değer temel alınarak seçilmiştir.
    score = min(trades_per_day / 1.0, 1.0)

    return {
        "score": round(score, 3),
        "trades_per_day": round(trades_per_day, 3),
        "total_trades": total_trades,
        "active_days": active_days,
    }


def _calculate_loss_aversion(transactions: list) -> dict:
    """
    Loss Aversion: Zarardaki pozisyonu satmama, kazançtakini hızla satma.
    Tutuş süresi farkı ile ölçülür (Kahneman & Tversky, 1979).
    """
    # FIFO (First-In, First-Out) mantığıyla lot eşleştirmesi yapılır:
    # Her alış, kronolojik olarak en eski lota atanır ve satış bununla eşleştirilir.
    # Bu yöntem, bireysel lot bazında gerçek tutuş süresini hesaplamak için gereklidir.
    holdings = defaultdict(list)  # sym -> [(qty, cost, buy_date)]
    gain_holding_days = []   # Kârla kapatılan pozisyonların tutuş süreleri (gün)
    loss_holding_days = []   # Zararla kapatılan pozisyonların tutuş süreleri (gün)

    for tx in transactions:
        sym = tx.symbol
        if tx.transaction_type == "BUY":
            holdings[sym].append({
                "qty": tx.quantity,
                "cost": tx.price,
                "buy_date": tx.timestamp,
            })
        elif tx.transaction_type == "SELL" and holdings[sym]:
            qty_to_sell = tx.quantity
            while qty_to_sell > 0 and holdings[sym]:
                lot = holdings[sym][0]
                used = min(lot["qty"], qty_to_sell)
                hold_days = (tx.timestamp - lot["buy_date"]).days
                if tx.price > lot["cost"]:
                    gain_holding_days.append(hold_days)
                elif tx.price < lot["cost"]:
                    loss_holding_days.append(hold_days)
                lot["qty"] -= used
                qty_to_sell -= used
                if lot["qty"] <= 0:
                    holdings[sym].pop(0)

    avg_gain_hold = sum(gain_holding_days) / len(gain_holding_days) if gain_holding_days else 0
    avg_loss_hold = sum(loss_holding_days) / len(loss_holding_days) if loss_holding_days else 0

    # Score: zarardaki pozisyonu kazançtakine göre ne kadar uzun tutuyor?
    # Oran > 1 ise Loss Aversion önyargısı mevcut demektir.
    # Kahneman & Tversky (1979) Prospect Theory'sine göre kayıplar kazançlardan
    # yaklaşık 2 kat daha güçlü hissedilir; bu asimetri tutma süresine yansır.
    # (ratio - 1) / 2 dönüşümüyle [0, 1] aralığına normalize edilmektedir.
    if avg_gain_hold > 0:
        ratio = avg_loss_hold / avg_gain_hold
        score = min((ratio - 1) / 2, 1.0) if ratio > 1 else 0.0
    else:
        score = 0.0

    return {
        "score": round(max(score, 0), 3),
        "avg_gain_holding_days": round(avg_gain_hold, 1),
        "avg_loss_holding_days": round(avg_loss_hold, 1),
        "gains_count": len(gain_holding_days),
        "losses_count": len(loss_holding_days),
    }


def _generate_persona(de: float, oc: float, la: float) -> dict:
    """3 skordan kullanıcı kişiliği üret."""
    # Kişilik sınıflandırması hiyerarşik önceliklere göre yapılmaktadır:
    # Önce "ideal" yatırımcı profili kontrol edilir (tüm önyargılar düşük),
    # ardından her önyargının baskınlığına göre etiketleme yapılır.
    if de < 0.1 and oc < 0.3 and la < 0.3:
        return {
            "title": "Disiplinli Yatırımcı",
            "description": "İşlemlerin tutarlı, duygu kontrolü güçlü. Akademik literatürde 'rasyonel ajan' profiline yakınsın.",
            "color": "#26C281",
        }
    if de > 0.3:
        return {
            "title": "Erken Satıcı",
            "description": "Kazançları erken realize edip kayıpları sürüklüyorsun. Klasik Disposition Effect (Shefrin & Statman, 1985).",
            "color": "#F5A623",
        }
    if la > 0.4:
        return {
            "title": "Kayıp Reddedici",
            "description": "Zarardaki pozisyonları çok uzun süre tutuyorsun. Loss Aversion (Kahneman & Tversky, 1979).",
            "color": "#E74C3C",
        }
    if oc > 0.5:
        return {
            "title": "Aşırı Güvenli",
            "description": "Yüksek işlem sıklığı uzun vadede getiriyi azaltır. Overconfidence Bias (Barber & Odean, 2001).",
            "color": "#9B59B6",
        }
    return {
        "title": "Gelişen Yatırımcı",
        "description": "Profilin henüz şekilleniyor. Daha fazla işlem yaptıkça davranışsal kalıpların belirginleşecek.",
        "color": "#3498DB",
    }


def analyze_user_behavior(db: Session, user_id: int) -> dict:
    """Ana fonksiyon: kullanıcının davranışsal profilini hesaplar."""
    # İşlemler kronolojik sıraya göre çekilir; FIFO lot eşleştirme ve
    # overconfidence hesaplama bu sıralamaya bağımlıdır.
    transactions = (
        db.query(Transaction)
        .filter(Transaction.user_id == user_id)
        .order_by(Transaction.timestamp.asc())
        .all()
    )

    # İstatistiksel güvenilirlik eşiği: minimum 3 işlem.
    # Daha az veriyle hesaplanan önyargı skorları istatistiksel olarak anlamlı değildir;
    # kullanıcıya bu durum açıkça bildirilmektedir.
    if len(transactions) < 3:
        return {
            "has_enough_data": False,
            "message": "Davranışsal profil için en az 3 işlem gerekli. Şu an: " + str(len(transactions)),
            "transaction_count": len(transactions),
        }

    de = _calculate_disposition_effect(transactions)
    oc = _calculate_overconfidence(transactions)
    la = _calculate_loss_aversion(transactions)
    persona = _generate_persona(de["score"], oc["score"], la["score"])

    return {
        "has_enough_data": True,
        "transaction_count": len(transactions),
        "persona": persona,
        "disposition_effect": de,
        "overconfidence": oc,
        "loss_aversion": la,
    }
