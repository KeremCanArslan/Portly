# =============================================================================
# AI Sohbet Servisi — RAG (Retrieval-Augmented Generation) Pipeline
#
# Bu modül, LLM (Large Language Model) çağrılarını kullanıcının gerçek zamanlı
# finansal verisiyle zenginleştirir. Temel akış şu şekildedir:
#
#   1. Kullanıcı mesajı veritabanına kaydedilir (kalıcılık ve geçmiş için)
#   2. Kullanıcıya ait bağlam verisi toplanır:
#      - Portföy pozisyonları (güncel piyasa fiyatlarıyla)
#      - Son 5 işlem
#      - Davranışsal finans profili (Disposition Effect, Overconfidence, Loss Aversion)
#      - Güncel piyasa haberleri (VADER sentiment etiketi ile)
#   3. Sistem prompt'u = rolü tanımlayan talimatlar + kullanıcı bağlamı
#   4. llm_service üzerinden streaming çağrı (Gemini 2.5 Flash birincil +
#      Google Search grounding ile gerçek zamanlı; hata/limitte Groq yedeği)
#   5. Token'lar alındıkça generator aracılığıyla client'a iletilir
#   6. Tamamlanan yanıt veritabanına kaydedilir
#
# Model: Gemini 2.5 Flash (grounding) → Groq Llama 3.3 70B yedek
# Sohbet geçmişi: Son 10 mesaj (token maliyetini kontrol altında tutar)
# =============================================================================
from sqlalchemy.orm import Session
from datetime import datetime
from app.models.user import User
from app.models.portfolio import Portfolio
from app.models.transaction import Transaction
from app.models.chat import ChatMessage
from app.utils.symbol_display import compact as _display_symbol
from app.services import (
    market_data_service,
    behavioral_finance_service,
    nlp_sentiment_service,
    fx_service,
    llm_service,
)

# Modelin kapasitesi: Llama 3.3 70B - 128K token. Biz kullanıcı başına son 10 mesajı tutacağız.
MAX_HISTORY_MESSAGES = 10


def build_user_context(db: Session, user_id: int) -> str:
    """
    RAG (Retrieval-Augmented Generation) — kullanıcının kişisel verisini
    sistem prompt'una dahil etmek için bağlam oluşturur.

    Şunları çeker:
    1. Kullanıcı bilgileri (isim, bakiye)
    2. Portföy pozisyonları (güncel fiyat ve PnL ile)
    3. Son 5 işlem
    4. Davranışsal finans profili (varsa)
    5. Son haberler (sentiment ile)
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        return "Kullanıcı bulunamadı."

    # 1. Portföy — paralel fiyat çekme
    # Her pozisyon için ayrı bir yfinance HTTP isteği gerektiğinden
    # ThreadPoolExecutor ile eş zamanlı çekilmektedir (sıralı 6 istek ~10 sn sürerdi).
    holdings = db.query(Portfolio).filter(Portfolio.user_id == user_id).all()
    portfolio_lines = []
    total_value = 0.0
    total_cost = 0.0

    if holdings:
        from concurrent.futures import ThreadPoolExecutor

        def _fetch_one(h):
            try:
                md = market_data_service.get_stock_data(h.symbol)
                # Günlük değişim bilinmiyorsa (altın/gümüş spot kaynağı)
                # None taşınır — 0.0 vermek modele "bugün hiç oynamadı"
                # dedirtiyordu.
                day = (md.get("change_percent", 0.0)
                       if md.get("change_available", True) else None)
                return (h, md.get("current_price"), day, None)
            except Exception as e:
                return (h, None, 0.0, str(e))

        # Tüm hisseleri PARALEL çek - 6 hisse 1-2 sn'de biter, sıralı 10+ sn'di
        with ThreadPoolExecutor(max_workers=8) as ex:
            results = list(ex.map(_fetch_one, holdings))

        # Bugünkü (günlük) hareket — "bugün neden düştüm?" sorusu için kritik
        today_delta_total = 0.0
        rows = []  # (symbol, val, pnl, pnl_pct, day_pct, day_delta)
        for h, cp, day_pct, err in results:
            if err is None and cp is not None:
                # USD pozisyonlar ₺'ye çevrilir; toplam/ağırlık/günlük TL
                # ortak ₺ üzerinden olmalı (AAPL $200'ü ₺200 saymak LLM'e
                # yanlış ağırlık/PnL veriyordu). Satırda native fiyat + para
                # simgesi gösterilir ki model "AAPL ₺200" sanmasın.
                cur = fx_service.currency_of(h.symbol)
                sym_c = "$" if cur == "USD" else "₺"
                cost_try = fx_service.to_try(h.average_cost * h.quantity, cur)
                val_try = fx_service.to_try(cp * h.quantity, cur)
                total_cost += cost_try
                total_value += val_try
                pnl = val_try - cost_try
                pnl_pct = (pnl / cost_try * 100) if cost_try > 0 else 0
                # Bugünün ₺ katkısı: prev_close = cp / (1 + day_pct/100)
                # (değişim bilinmiyorsa günlük katkı YOK — uydurma sıfır değil,
                # hesabın dışında)
                prev_val = val_try if day_pct in (None, -100) \
                    else val_try / (1 + day_pct / 100)
                day_delta = val_try - prev_val
                today_delta_total += day_delta
                # Modele HAM sembol verilmez: "GC=F" gibi Yahoo kodlarını
                # cevabında birebir tekrarlıyordu (kullanıcı "bu altın demek,
                # hiçbir yerde çıkmasın" dedi). Kayıt/sorgu ham sembolde kalır.
                rows.append((_display_symbol(h.symbol), h.quantity,
                             h.average_cost, cp,
                             sym_c, val_try, pnl, pnl_pct, day_pct, day_delta))
            else:
                rows.append((_display_symbol(h.symbol), h.quantity,
                             h.average_cost, None, "₺", 0, 0, 0, 0, 0))

        for (sym, qty, avg, cp, sym_c, val, pnl, pnl_pct,
             day_pct, day_delta) in rows:
            if cp is None:
                portfolio_lines.append(
                    f"- {sym}: {qty:.4g} lot, maliyet {sym_c}{avg:.2f} "
                    f"(güncel fiyat alınamadı)")
                continue
            weight = (val / total_value * 100) if total_value > 0 else 0
            day_txt = ("bugünkü değişim bilinmiyor" if day_pct is None
                       else f"bugün {day_pct:+.2f}% ({day_delta:+,.0f} TL)")
            portfolio_lines.append(
                f"- {sym}: {qty:.4g} lot, maliyet {sym_c}{avg:.2f}, "
                f"güncel {sym_c}{cp:.2f}, ağırlık %{weight:.1f}, "
                f"{day_txt}, "
                f"toplam PnL {pnl:+,.0f} TL ({pnl_pct:+.2f}%)"
            )

    # Fiyatı alınamayan pozisyonlar ağırlık/toplam hesabının DIŞINDA kalıyor.
    # Bu bilgi modele söylenmezse model kalan birkaç satırı portföyün TAMAMI
    # sanıyor ("portföyünde beş farklı varlık bulunuyor" — canlıda görüldü,
    # oysa 38 pozisyon vardı). Arayüzdeki "N pozisyonun fiyatı alınamadı"
    # notunun bağlam karşılığı.
    priced = sum(1 for r in rows if r[3] is not None) if holdings else 0
    missing = (len(rows) - priced) if holdings else 0
    if missing:
        portfolio_lines.append(
            f"UYARI: {missing} pozisyonun güncel fiyatı ALINAMADI (veri kaynağı "
            f"geçici olarak erişilemez). Yukarıdaki toplam değer, ağırlıklar ve "
            f"bugünkü hareket YALNIZCA fiyatı bilinen {priced} pozisyondan "
            f"hesaplandı. Kullanıcının portföyü toplam {len(rows)} pozisyondur."
        )

    portfolio_text = "\n".join(portfolio_lines) if portfolio_lines else "Henüz hisse pozisyonu yok, tüm varlık nakit."
    total_pnl = total_value - total_cost
    today_total = today_delta_total if holdings else 0.0
    today_pct = (today_total / (total_value - today_total) * 100
                 if (total_value - today_total) > 0 else 0.0)

    # 2. Son 5 işlem — LLM'e "kullanıcı son ne zaman, ne aldı/sattı" bilgisi verilir
    recent_txs = (
        db.query(Transaction)
        .filter(Transaction.user_id == user_id)
        .order_by(Transaction.timestamp.desc())
        .limit(5)
        .all()
    )
    tx_lines = []
    for tx in recent_txs:
        # Python'ın strftime'ı İngilizce ay adı üretiyor; LLM'e Türkçe veriyoruz
        date_str = tx.timestamp.strftime("%d %B").replace(
            "January", "Ocak").replace("February", "Şubat").replace("March", "Mart") \
            .replace("April", "Nisan").replace("May", "Mayıs").replace("June", "Haziran") \
            .replace("July", "Temmuz").replace("August", "Ağustos").replace("September", "Eylül") \
            .replace("October", "Ekim").replace("November", "Kasım").replace("December", "Aralık")
        action = "ALIŞ" if tx.transaction_type == "BUY" else "SATIŞ"
        tx_lines.append(f"- {date_str}: {action} {_display_symbol(tx.symbol)} {tx.quantity:.0f} lot @ ₺{tx.price:.2f}")
    tx_text = "\n".join(tx_lines) if tx_lines else "Henüz işlem yok."

    # 3. Davranışsal profil — LLM bunu kullanarak kişiselleştirilmiş geri bildirim üretir
    behavior = behavioral_finance_service.analyze_user_behavior(db, user_id)
    if behavior.get("has_enough_data"):
        persona = behavior["persona"]
        de = behavior["disposition_effect"]["score"]
        oc = behavior["overconfidence"]["score"]
        la = behavior["loss_aversion"]["score"]
        behavior_text = (
            f"Yatırımcı tipi: {persona['title']} - {persona['description']}\n"
            f"Disposition Effect (kazancı erken satma): {de} / 1.00\n"
            f"Overconfidence (aşırı işlem): {oc} / 1.00\n"
            f"Loss Aversion (zarardan kaçınma): {la} / 1.00"
        )
    else:
        behavior_text = "Davranışsal profil için yeterli veri yok (en az 3 işlem gerekli)."

    # 4. Son haberler — VADER sentiment etiketi ile birlikte LLM'e iletilir
    # Cache'den alındığı için ek gecikme yaratmaz
    try:
        news = nlp_sentiment_service.get_financial_news("stocks market")[:3]
        news_text = "\n".join([
            f"- [{n['sentiment_label']}] {n['title'][:120]}"
            for n in news
        ])
    except Exception:
        news_text = "Haber verisi alınamadı."

    # Tüm bağlamı birleştir — bu metin sistem prompt'unun içine yerleştirilir
    context = f"""KULLANICI BİLGİLERİ:
İsim: {user.full_name or 'Kullanıcı'}
Toplam Portföy Değeri: ₺{total_value:,.2f}
Toplam PnL: {total_pnl:+,.2f} TL
BUGÜNKÜ HİSSE HAREKETİ: {today_total:+,.2f} TL ({today_pct:+.2f}%)

PORTFÖY (ağırlık + bugünkü hareket + toplam PnL):
{portfolio_text}

SON İŞLEMLER:
{tx_text}

DAVRANIŞSAL FİNANS PROFİLİ:
{behavior_text}

GÜNCEL PİYASA HABERLERİ:
{news_text}"""

    return context


def get_system_prompt(user_context: str) -> str:
    """
    Sistem prompt'u — AI'ın nasıl davranacağını ve hangi kısıtlamalar
    altında yanıt vereceğini belirler (guardrail'ler burada tanımlanır).
    """
    return f"""Sen Portly adlı portföy takip ve analiz uygulamasının Türk AI finansal koçusun.
Kullanıcı GERÇEK portföyünü uygulamaya ekler; sen haber, analiz ve eğitimle yol gösterirsin.

KESİN DİL KURALI: Cevabının %100'ü Türkçe olacak. İngilizce tek bir kelime bile kullanma.
Şirket isimleri (Apple, Tesla) ve hisse kodları (THYAO, AAPL) aynen kalır.

SEMBOL YAZIM KURALI: Varlıkları SANA VERİLEN adlarıyla an. Teknik borsa kodu
YAZMA: "GC=F" değil Altın, "SI=F" değil Gümüş, "USDTRY=X" değil USD/TRY,
"THYAO.IS" değil THYAO, "TLY.FON" değil TLY. Bu kodlar kullanıcıya anlamsız.

ÖNEMLİ KURALLAR:
1. Kullanıcı öneri isterse somut hisse, sektör veya ETF örnekleri VEREBİLİRSİN —
   ama mutlaka GEREKÇESİYLE açıkla (neden uygun olabilir, hangi riskleri taşır),
   2-3 alternatif sun ve kullanıcının risk profili/portföyüyle ilişkilendir.
   Yanıtının sonuna kısa bir uyarı ekle: "Bu eğitim amaçlı bir fikirdir, kesin
   yatırım tavsiyesi değildir; kendi araştırmanı yap." Tek bir hisseye
   "hemen al/sat" baskısı yapma.
2. Eğitici ol — kavramları açıkla, akademik referans ver (Kahneman, Markowitz, Shefrin gibi).
3. Kullanıcının verisine dayalı kişisel cevap ver. Generic cevap verme.
4. Cevaplar KISA olsun: en fazla 3 kısa paragraf. Uzun madde listeleri, başlıklar,
   numaralı bölümler ve markdown (** , #, - gibi) KULLANMA — düz, akıcı cümlelerle yaz.
   Cevabını verilen alana SIĞDIR ve mutlaka tamamla; cümleyi yarıda kesme.
5. Emoji kullanma, gereksiz süslemelerden kaçın.
6. Davranışsal önyargıları (Disposition Effect, Loss Aversion, Overconfidence) gördüğünde nazikçe işaret et.
7. Eğer kullanıcı bilmediğin bir şey sorarsa "bu konuda kesin bilgim yok" de, uydurma.
8. "Bugün neden düştüm/kazandım?" gibi sorularda BUGÜNKÜ HİSSE HAREKETİ ve her
   pozisyonun bugünkü %/TL katkısına bak; portföye en çok etki eden 1-2
   pozisyonu ağırlığıyla birlikte somut sayılarla açıkla (toplam PnL ile karıştırma —
   o maliyete göre kümülatif, bugünkü hareket ayrıdır).
9. Portföy listesinde "güncel fiyat alınamadı" satırları ya da "UYARI: ... fiyatı
   ALINAMADI" notu varsa: portföyü "N varlıktan oluşuyor" diye ANLATMA ve o
   ağırlıkları portföyün tamamı gibi sunma. Önce eksik veriyi bir cümleyle
   söyle ("şu an X pozisyonun fiyatı alınamıyor, aşağıdaki ağırlıklar yalnız
   fiyatı bilinen kısmı yansıtıyor"), sonra yorumla. Eksik pozisyonları yok
   sayıp portföy hakkında kesin hüküm verme.

KULLANICININ MEVCUT DURUMU:
{user_context}

Yukarıdaki verilere dayanarak kullanıcının sorularını yanıtla. Kullanıcıyı tanıyorsun gibi, kişisel ve sıcak bir tonla yaz."""


def save_message(db: Session, user_id: int, role: str, content: str) -> ChatMessage:
    """Mesajı DB'ye kaydet."""
    msg = ChatMessage(user_id=user_id, role=role, content=content)
    db.add(msg)
    db.commit()
    db.refresh(msg)
    return msg


def get_chat_history(db: Session, user_id: int, limit: int = 50) -> list:
    """Kullanıcının SON `limit` mesajını kronolojik sırayla döndürür."""
    recent = (
        db.query(ChatMessage)
        .filter(ChatMessage.user_id == user_id)
        .order_by(ChatMessage.timestamp.desc())
        .limit(limit)
        .all()
    )
    recent.reverse()  # eskiden yeniye sırala
    return [
        {
            "id": m.id,
            "role": m.role,
            "content": m.content,
            "timestamp": m.timestamp.isoformat() if m.timestamp else None,
        }
        for m in recent
    ]


def clear_chat_history(db: Session, user_id: int) -> int:
    """Kullanıcının tüm sohbet geçmişini sil. Silinen mesaj sayısını döndürür."""
    count = db.query(ChatMessage).filter(ChatMessage.user_id == user_id).delete()
    db.commit()
    return count


def get_recent_messages_for_context(db: Session, user_id: int, limit: int = MAX_HISTORY_MESSAGES) -> list:
    """
    Son N mesajı LLM'e bağlam olarak göndermek için al.
    Llama'nın beklediği {role, content} formatında döndürür.
    """
    messages = (
        db.query(ChatMessage)
        .filter(ChatMessage.user_id == user_id)
        .order_by(ChatMessage.timestamp.desc())
        .limit(limit)
        .all()
    )
    # Tersine çevir (chronological)
    messages.reverse()
    return [{"role": m.role, "content": m.content} for m in messages]


def stream_chat_response(db: Session, user_id: int, user_message: str):
    """
    Streaming generator — Llama'dan token-by-token cevap alıp yield eder.
    Aynı zamanda kullanıcı mesajını ve tam cevabı DB'ye kaydeder.

    Yield edilen formatın kendisi: SSE event verisi.
    """
    # 1. Kullanıcı mesajını DB'ye kaydet
    save_message(db, user_id, "user", user_message)

    # 2. RAG: kullanıcının güncel verilerini topla (portföy, işlemler, davranış, haberler)
    user_context = build_user_context(db, user_id)
    system_prompt = get_system_prompt(user_context)

    # 3. Sohbet geçmişini al (yeni eklediğimiz user message'ı dahil)
    history = get_recent_messages_for_context(db, user_id, MAX_HISTORY_MESSAGES)

    # 4. LLM'e gönderilecek mesaj dizisini oluştur:
    #    [system_prompt] + [son N mesaj geçmişi]
    #    Sistem prompt'u her çağrıda en güncel kullanıcı verisini içermektedir.
    messages = [{"role": "system", "content": system_prompt}]
    messages.extend(history)

    # 5. Streaming çağrı — her token geldikçe generator üzerinden client'a iletilir
    full_response = ""
    try:
        # grounding=True → Gemini, güncel haber/piyasa için Google Search'e bağlanır
        # (Groq yedeğinde grounding yok ama yine de yanıt verir).
        for token in llm_service.stream(
            messages,
            max_tokens=1200,
            temperature=0.4,  # Düşük temperature → daha tutarlı ve az "yaratıcı" yanıtlar
            grounding=True,
        ):
            full_response += token
            yield token

    except Exception as e:
        error_msg = f"\n\n[Hata: AI yanıt veremedi - {str(e)}]"
        full_response += error_msg
        yield error_msg

    # 6. Streaming tamamlandıktan sonra tam yanıtı DB'ye kaydet
    if full_response.strip():
        save_message(db, user_id, "assistant", full_response.strip())
