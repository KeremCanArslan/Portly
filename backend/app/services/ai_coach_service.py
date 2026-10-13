from sqlalchemy.orm import Session
from app.models.user import User
from app.models.portfolio import Portfolio
from app.services import (
    market_data_service,
    nlp_sentiment_service,
    fx_service,
    llm_service,
)


def generate_portfolio_advice(db: Session, user_id: int) -> dict:
    """Kullanıcının portföyünü, PnL'ini ve güncel haber sentiment'ını analiz edip
    Türkçe kişisel yorum üretir. Llama 3.3 70B kullanır."""
    # davranışsal profili de prompt'a ekle ki tavsiye kişiselleşsin
    from app.services import behavioral_finance_service
    behavior = behavioral_finance_service.analyze_user_behavior(db, user_id)

    if behavior.get("has_enough_data"):
        persona = behavior["persona"]
        behavior_text = (
            f"\n\nDAVRANIŞSAL FİNANS PROFİLİ:\n"
            f"Karakter: {persona['title']}\n"
            f"Açıklama: {persona['description']}\n"
            f"Disposition Effect Skoru: {behavior['disposition_effect']['score']} (kazancı erken satma, kaybı tutma)\n"
            f"Overconfidence Skoru: {behavior['overconfidence']['score']} (aşırı işlem)\n"
            f"Loss Aversion Skoru: {behavior['loss_aversion']['score']} (zararı kabul etmeme)"
        )
    else:
        # yeterli işlem yoksa davranışsal analiz eklenmez
        behavior_text = ""

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        return {"error": "Kullanıcı bulunamadı"}

    holdings = db.query(Portfolio).filter(Portfolio.user_id == user_id).all()

    # Portföy bilgilerini güncel fiyatlarla zenginleştir.
    # Her hisse için yfinance API çağrısı yapılır; hata alan hisseler atlanır.
    # Gelecekte ThreadPoolExecutor ile paralel çekilebilir (chat servisi bunu yapıyor).
    portfolio_summary = []
    total_cost = 0.0
    total_value = 0.0
    for h in holdings:
        try:
            market = market_data_service.get_stock_data(h.symbol)
            cp = market["current_price"]
            # USD pozisyonlar ₺'ye çevrilir — toplam/PnL ortak ₺ olmalı
            # (AAPL $200'ü ₺200 saymak koça yanlış tablo veriyordu).
            cur = fx_service.currency_of(h.symbol)
            sym_c = "$" if cur == "USD" else "₺"
            cost_try = fx_service.to_try(h.average_cost * h.quantity, cur)
            val_try = fx_service.to_try(cp * h.quantity, cur)
            total_cost += cost_try
            total_value += val_try
            portfolio_summary.append({
                "symbol": h.symbol,
                "quantity": h.quantity,
                "cur": sym_c,
                "avg_cost": round(h.average_cost, 2),
                "current_price": round(cp, 2),
                "pnl": round(val_try - cost_try, 2),
                "pnl_percent": round(((val_try - cost_try) / cost_try * 100) if cost_try > 0 else 0, 2),
            })
        except Exception:
            continue

    total_pnl = total_value - total_cost

    # Son haberleri sentiment'la birlikte al
    try:
        news = nlp_sentiment_service.get_financial_news("stocks market")[:5]
    except Exception:
        news = []

    portfolio_text = "\n".join([
        f"- {p['symbol']}: {p['quantity']:.4g} lot, maliyet {p['cur']}{p['avg_cost']}, "
        f"güncel {p['cur']}{p['current_price']}, PnL: {p['pnl']:+} TL ({p['pnl_percent']:+}%)"
        for p in portfolio_summary
    ]) if portfolio_summary else "Hiç hisse yok, tüm varlık nakit."

    news_text = "\n".join([
        f"- [{n['sentiment_label']}] {n['title']}"
        for n in news
    ]) if news else "Haber verisi yok."

    # Prompt mühendisliği: dil kısıtlamaları çok önemli.
    # Modelin İngilizce kelime sızdırmaması için açık talimatlar verildi.
    # temperature=0.3 → daha tutarlı ve az değişken yanıtlar
    # max_tokens=600 → 120-180 kelime hedefi için yeterli
    prompt = f"""Sen Portly adlı portföy takip ve analiz uygulamasının Türk AI finansal koçusun.

KESIN DİL KURALI: Cevabının %100'ü Türkçe olacak. İngilizce tek bir kelime bile KULLANMA.
- "especially" → "özellikle"
- "stocks" → "hisseler"
- "portfolio" → "portföy"
- Şirket isimleri aynen kalır (Apple, Tesla, Türk Hava Yolları)
- Sembol isimleri aynen kalır (THYAO.IS, AAPL)
- Başka TÜM kelimeler Türkçe olmalı

Yatırım tavsiyesi VERME, sadece eğitici gözlemler yap.

KULLANICININ PORTFÖYÜ:
Toplam Portföy Değeri: ₺{total_value:.2f}
Toplam Kâr/Zarar: {total_pnl:+.2f} TL

Hisseler:
{portfolio_text}

GÜNCEL PİYASA HABERLERİ (VADER sentiment analizi ile):
{news_text}
{behavior_text}

GÖREVİN (hepsi Türkçe, akıcı dille):
1. Portföy yapısını yorumla (çeşitlendirme, konsantrasyon, sektör riski)
2. Haberlerdeki genel duygu durumunu kullanıcının pozisyonlarıyla ilişkilendir
3. Eğitici bir kavram veya soruyla bitir
4. Davranışsal profilini gözlemleyerek (varsa) yatırımcı kişiliğine uygun eğitici öneride bulun

Format: 3-4 kısa paragraf, markdown yok, emoji yok, 120-180 kelime arası, TAMAMI TÜRKÇE."""
    try:
        advice = llm_service.complete(
            [{"role": "user", "content": prompt}],
            max_tokens=600,
            temperature=0.3,
        )
        return {
            "advice": advice,
            "portfolio_size": len(portfolio_summary),
            "total_pnl": round(total_pnl, 2),
            "total_value": round(total_value, 2),
            "news_analyzed": len(news),
        }
    except Exception as e:
        return {"error": f"AI yanıt vermedi: {str(e)}"}
