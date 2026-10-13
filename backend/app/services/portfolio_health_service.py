"""Portföy Sağlık Skoru.

Tek bir 0-100 skor + 4 alt boyut + somut öneriler üretir:
  • Çeşitlendirme   — etkin pozisyon sayısı (1/HHI)
  • Konsantrasyon    — en büyük pozisyonun ağırlığı
  • Sektör dağılımı  — sektör yoğunlaşması (1/sektör HHI)
  • Döviz dengesi    — TL / yabancı para karışımı (kur riski hedge'i)

Veri kaynağı: portfolio_service (canlı fiyat + sektör + para birimi).
(Sanal nakit bakiye pivotla kaldırıldı → "Nakit oranı" boyutu yok;
uygulama kullanıcının nakdini bilmez, yalnız pozisyonlarını izler.)
"""

from sqlalchemy.orm import Session

from app.services import portfolio_service


def _clamp(v: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, v))


def compute_health(db: Session, user_id: int) -> dict:
    positions = portfolio_service.get_user_portfolio(db, user_id)

    # ⚠️ Doğruluk: USD pozisyonları ₺'ye çevrilmiş olmalı (yoksa $1266 ≈
    # ₺1266 sayılır, ağırlık/konsantrasyon/sektör tamamen yanlış olurdu).
    # portfolio_service total_value_try'ı fx_service ile hesaplar — tek
    # doğruluk kaynağı (eskiden buradaki yerel fetch 1.0 fallback'le
    # başarısızsa aynı bug'ı sessizce geri getiriyordu).
    for p in positions:
        p["_try_value"] = p.get("total_value_try", p["total_value"])

    holdings_value = sum(p["_try_value"] for p in positions)
    total = holdings_value

    if total <= 0 or not positions:
        return {
            "has_data": False,
            "score": 0,
            "grade": "—",
            "dimensions": [],
            "recommendations": [
                "Sağlık skoru için portföyüne en az birkaç pozisyon ekle."
            ],
        }

    n = len(positions)
    weights = [p["_try_value"] / holdings_value for p in positions
               if holdings_value > 0]
    hhi = sum(w * w for w in weights) if weights else 1.0
    eff_n = 1 / hhi if hhi > 0 else 1
    top_w = max(weights) if weights else 1.0

    # Sektör yoğunlaşması (Nakit hariç)
    sb = portfolio_service.get_sector_breakdown(db, user_id, portfolio=positions)
    sec_vals = [s["value"] for s in sb["sectors"] if s["name"] != "Nakit"]
    sec_tot = sum(sec_vals)
    if sec_tot > 0:
        sec_hhi = sum((v / sec_tot) ** 2 for v in sec_vals)
        eff_sec = 1 / sec_hhi if sec_hhi > 0 else 1
    else:
        eff_sec = 1

    # Döviz kırılımı (payda: pozisyonların ₺ toplam değeri).
    foreign_val = sum(p["_try_value"] for p in positions
                      if p.get("currency") != "TRY")
    foreign_share = foreign_val / total if total > 0 else 0

    # --- Alt skorlar (0-100) ---
    s_div = _clamp(eff_n / 8 * 100)
    # ≤%20 → 100, ≥%60 → 0
    s_conc = _clamp((1 - (top_w - 0.20) / 0.40) * 100)
    s_sector = _clamp(eff_sec / 4 * 100)
    # Yabancı para payı ~%35'te zirve (kur hedge'i), 0 veya %100 düşük
    s_fx = _clamp((1 - abs(foreign_share - 0.35) / 0.65) * 100)

    overall = round(
        s_div * 0.30 + s_conc * 0.30 + s_sector * 0.22 + s_fx * 0.18
    )

    grade = (
        "Mükemmel" if overall >= 85 else
        "İyi" if overall >= 70 else
        "Orta" if overall >= 50 else
        "Zayıf" if overall >= 30 else
        "Riskli"
    )

    # Her metrik 4 alana bölünür (frontend dokunulabilir sheet'te yapısal
    # gösterir): what=ne ölçer (genel), reading=senin durumun (bu portföy),
    # action=yapılması gereken (skora göre somut), ideal=hedef bant.
    fp = foreign_share * 100
    dims = [
        {"key": "Çeşitlendirme", "score": round(s_div),
         "detail": f"{n} pozisyon, etkin {eff_n:.1f}",
         "ideal": "Hedef: etkin 8+",
         "what": (
             "Riskini kaç farklı varlığa yaydığını ölçer. 'Etkin pozisyon', "
             "ağırlıkların ne kadar dengeli olduğunu tek bir sayıya indirir: "
             "tüm pozisyonların eşit ağırlıkta olması durumunda kaç tanesine "
             "denk geldiğini gösterir. Paran birkaç pozisyonda toplanmışsa bu "
             "sayı, gerçek pozisyon adedinden küçük çıkar (ör. 12 pozisyon ama "
             "etkin 3.3). Yükseldikçe tek bir varlığın kötü günü portföyü daha "
             "az sarsar."),
         "reading": (
             f"{n} pozisyonun var ama ağırlıklar eşit olmadığı için portföy "
             f"aslında ~{eff_n:.1f} eşit pozisyon gibi davranıyor."),
         "action": (
             "Büyük ağırlıkları kademeli kısıp pozisyonları daha dengeli "
             "dağıt; etkin sayıyı 8'e yaklaştırmayı hedefle."
             if s_div < 60 else
             "İyi durumda — yeni alımları benzer büyüklükte tutarak bu "
             "dengeyi koru.")},
        {"key": "Konsantrasyon", "score": round(s_conc),
         "detail": f"En büyük pozisyon %{top_w * 100:.0f}",
         "ideal": "Hedef: %20 altı",
         "what": (
             "En büyük tek pozisyonun portföydeki ağırlığı. Yüksekse "
             "kaderini büyük ölçüde tek bir varlığa bağlamış olursun; o "
             "varlık çakılırsa hasar büyük olur."),
         "reading": (
             f"En büyük tek pozisyon, hisse varlığının %{top_w * 100:.0f}'ini "
             "oluşturuyor."),
         "action": (
             f"Bu pozisyonu kademeli azaltıp gelirini başka varlıklara "
             "aktar; ağırlığını %20'nin altına indirmeyi hedefle."
             if s_conc < 60 else
             "Sağlıklı — tek bir varlık portföye baskın değil, böyle koru.")},
        {"key": "Sektör dağılımı", "score": round(s_sector),
         "detail": f"Etkin {eff_sec:.1f} sektör",
         "ideal": "Hedef: 4+ sektör",
         "what": (
             "Yatırımının kaç farklı sektöre yayıldığı. Tek sektöre yığılmak, "
             "o sektörü vuran bir gelişmede tüm portföyü birlikte düşürür."),
         "reading": (
             f"Portföyün sektör bazında ~{eff_sec:.1f} eşit sektöre yayılmış."),
         "action": (
             "Farklı sektörlerden (ör. teknoloji, sanayi, enerji, finans, "
             "sağlık) ekleyerek yayılımı artır."
             if s_sector < 60 else
             "İyi yayılmış — sektör dengesini bozmadan koru.")},
        {"key": "Döviz dengesi", "score": round(s_fx),
         "detail": f"Yabancı para %{fp:.0f}",
         "ideal": "Hedef: ~%35 döviz",
         "what": (
             "Portföyünün ne kadarının yabancı para (USD vb.) cinsinden "
             "olduğu. Bir miktar döviz TL'nin değer kaybına karşı korur; ama "
             "tamamı döviz olursa kur düştüğünde topyekûn zarar edersin."),
         "reading": (
             f"Portföyünün %{fp:.0f}'i yabancı para, "
             f"%{100 - fp:.0f}'i TL cinsinden."),
         "action": (
             f"Döviz ağırlığı yüksek; bir kısmını TL varlığa "
             "kaydırarak ~%35'e yaklaştır."
             if foreign_share > 0.55 else
             "Neredeyse hiç dövizin yok; az miktar döviz kur riskine karşı "
             "denge sağlar."
             if foreign_share < 0.15 else
             "Denge iyi — TL ile döviz arasındaki bu dağılımı koru.")},
    ]

    recs = []
    if s_conc < 60:
        recs.append(
            f"En büyük pozisyonun toplam hisselerin %{top_w * 100:.0f}'i — "
            "tek hisse riskini azaltmak için ağırlığı düşürmeyi düşün.")
    if s_div < 60:
        recs.append(
            f"Yalnızca {n} pozisyon var; farklı varlıklara yayılmak "
            "dalgalanmayı azaltır.")
    if s_sector < 60:
        recs.append(
            "Portföy birkaç sektöre yoğunlaşmış; sektör çeşitliliği "
            "sistematik olmayan riski düşürür.")
    if s_fx < 50:
        if foreign_share < 0.1:
            recs.append(
                "Neredeyse tamamı TL varlık; bir miktar döviz/yabancı "
                "hisse kur riskine karşı denge sağlayabilir.")
        elif foreign_share > 0.8:
            recs.append(
                "Neredeyse tamamı yabancı para; TL varlık dengesi "
                "kur oynaklığını azaltır.")
    if not recs:
        recs.append("Portföy dengeli görünüyor — düzenli gözden geçir.")

    return {
        "has_data": True,
        "score": overall,
        "grade": grade,
        "dimensions": dims,
        "recommendations": recs,
    }
