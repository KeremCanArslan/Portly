import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

enum _Level { basic, mid, adv }

extension _LevelLabel on _Level {
  String get label => switch (this) {
        _Level.basic => 'Başlangıç',
        _Level.mid => 'Orta',
        _Level.adv => 'İleri',
      };
}

/// Tek bir mini-test sorusu. [correct] = [options] içindeki doğru indeks.
class _QuizQ {
  final String q;
  final List<String> options;
  final int correct;
  final String explain;
  const _QuizQ(this.q, this.options, this.correct, this.explain);
}

class _Lesson {
  final String id;
  final String title;
  final String summary;
  final String body;
  final IconData icon;
  final _Level level;
  final List<_QuizQ> quiz;
  const _Lesson({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.icon,
    this.level = _Level.basic,
    this.quiz = const [],
  });
}

class _Category {
  final String name;
  final IconData icon;
  final List<_Lesson> lessons;
  const _Category(
      {required this.name, required this.icon, required this.lessons});
}

const _categories = <_Category>[
  _Category(
    name: 'Temel Kavramlar',
    icon: Icons.school,
    lessons: [
      _Lesson(
        id: 'hisse_nedir',
        title: 'Hisse Senedi Nedir?',
        summary: 'Bir şirketin küçük bir parçasına sahip olmak.',
        icon: Icons.business,
        level: _Level.basic,
        body:
            '''Hisse senedi, bir şirketin sermayesinin küçük bir parçasını temsil eder. Hisse alarak şirketin ortaklarından biri olursun.

**Nasıl para kazanırsın?**
1. Fiyat artışı (sermaye kazancı): Hisseyi düşük fiyattan alıp yüksek fiyattan satarsın.
2. Temettü (dividend): Şirket kâr ettiğinde ortaklarına dağıtır.

**Risk:** Şirket batarsa veya kötü yönetilirse yatırımın eriyebilir. Bu yüzden çeşitlendirme (farklı şirketlere yatırım) önemlidir.''',
        quiz: [
          _QuizQ(
            'Hisse alarak bir şirkette ne elde edersin?',
            [
              'Şirkete borç verirsin',
              'Şirketin bir parçasına ortak olursun',
              'Garantili faiz',
              'Şirketi yönetme hakkı'
            ],
            1,
            'Hisse = şirketin sermayesinin küçük bir parçası; ortağı '
                'olursun, borç vermezsin.',
          ),
          _QuizQ(
            'Hisseden para kazanmanın iki yolu nedir?',
            [
              'Faiz ve kira',
              'Temettü ve fiyat artışı',
              'Sadece temettü',
              'Komisyon iadesi'
            ],
            1,
            'Sermaye kazancı (fiyat artışı) + temettü (kâr payı) iki '
                'ana kazanç kaynağıdır.',
          ),
          _QuizQ(
            'Tek bir şirkete tüm parayı yatırmak neden risklidir?',
            [
              'Komisyon yüksektir',
              'O şirket batarsa büyük kayıp olur',
              'Temettü alınamaz',
              'Vergi artar'
            ],
            1,
            'Çeşitlendirme tam da bu tekil şirket riskini dağıtmak '
                'içindir.',
          ),
        ],
      ),
      _Lesson(
        id: 'endeks_nedir',
        title: 'Endeks Nedir?',
        summary: 'BIST 100, S&P 500, Nasdaq gibi piyasa göstergeleri.',
        icon: Icons.show_chart,
        level: _Level.basic,
        body:
            '''Endeks, belirli bir grup hissenin ortalama performansını ölçer. Piyasanın nabzını tutmak için kullanılır.

**Önemli endeksler:**
- **BIST 100:** Borsa İstanbul'un en büyük 100 şirketi.
- **S&P 500:** ABD'nin en büyük 500 şirketi.
- **Nasdaq:** ABD teknoloji ağırlıklı endeks.

**Neden önemli?** Portföyünü endeksle kıyaslayarak iyi mi yoksa kötü mü performans gösterdiğini ölçebilirsin.''',
      ),
      _Lesson(
        id: 'volatilite',
        title: 'Volatilite (Oynaklık)',
        summary: 'Fiyatın ne kadar dalgalandığının ölçüsü.',
        icon: Icons.waves,
        level: _Level.mid,
        body:
            '''Volatilite, fiyatın belirli bir sürede ne kadar oynadığını gösterir.

**Yüksek volatilite:** Fiyatlar sert hareket eder. Yüksek getiri ihtimali ama yüksek kayıp riski.

**Düşük volatilite:** Fiyatlar sakin. Daha öngörülebilir ama getiri de sınırlı.

**Örnek:** Bitcoin (yüksek volatilite) vs altın (düşük-orta volatilite). Volatilite ölçen popüler gösterge: VIX endeksi.''',
      ),
    ],
  ),
  _Category(
    name: 'Teknik Analiz',
    icon: Icons.candlestick_chart,
    lessons: [
      _Lesson(
        id: 'mum_grafigi',
        title: 'Mum Grafiği',
        summary: 'OHLC: Açılış, Yüksek, Düşük, Kapanış.',
        icon: Icons.candlestick_chart,
        level: _Level.basic,
        body: '''Her mum bir dönem için 4 fiyatı gösterir:

- **Açılış (Open):** Dönemin başındaki fiyat
- **Yüksek (High):** Dönemde görülen en yüksek
- **Düşük (Low):** Dönemde görülen en düşük
- **Kapanış (Close):** Dönemin sonundaki fiyat

**Renkler:**
- **Yeşil mum:** Kapanış > açılış (alıcı baskın)
- **Kırmızı mum:** Kapanış < açılış (satıcı baskın)

**Fitil (gölge):** Mum gövdesinin üstündeki/altındaki çizgi. Yüksek/düşük noktalarını gösterir.''',
      ),
      _Lesson(
        id: 'hareketli_ortalama',
        title: 'Hareketli Ortalama (MA)',
        summary: 'Fiyat trendini yumuşatan klasik gösterge.',
        icon: Icons.timeline,
        level: _Level.mid,
        body:
            '''Hareketli ortalama (Moving Average), son N günün ortalama kapanış fiyatıdır.

**MA20 (kısa vade):** Son 20 günün ortalaması. Hızlı tepki verir.
**MA50 (orta vade):** Trend belirleyici olarak yaygın.
**MA200 (uzun vade):** Birinci derece destek/direnç. Üstündeysek genel trend yukarı sayılır.

**Sinyal:** Kısa vade MA, uzun vade MA'yı yukarı keserse "Golden Cross" (alış sinyali). Tersi "Death Cross".''',
      ),
      _Lesson(
        id: 'rsi',
        title: 'RSI (Relative Strength Index)',
        summary: 'Aşırı alım / aşırı satım göstergesi.',
        icon: Icons.speed,
        level: _Level.mid,
        body:
            '''RSI, 0-100 arasında değer alır. Fiyatın "aşırı alınmış" veya "aşırı satılmış" olduğunu gösterir.

- **RSI > 70:** Aşırı alım — düzeltme gelebilir
- **RSI < 30:** Aşırı satım — toparlanma gelebilir
- **50 civarı:** Nötr

**Önemli not:** RSI tek başına alım/satım sinyali değildir. Trend devam ederken RSI uzun süre aşırı bölgede kalabilir.''',
        quiz: [
          _QuizQ(
            'RSI 75 ise klasik yorum nedir?',
            [
              'Aşırı satım — al',
              'Aşırı alım — düzeltme gelebilir',
              'Nötr',
              'Trend bitti, kesin sat'
            ],
            1,
            'RSI > 70 aşırı alım bölgesidir; düzeltme ihtimaline işaret '
                'eder ama tek başına satış emri değildir.',
          ),
          _QuizQ(
            'RSI hakkında doğru olan hangisi?',
            [
              'Tek başına kesin sinyaldir',
              'Güçlü trendde uzun süre aşırı bölgede kalabilir',
              '100 üstüne çıkabilir',
              'Sadece kriptoda çalışır'
            ],
            1,
            'Güçlü trendde RSI uzun süre 70 üstünde / 30 altında '
                'kalabilir; teyit için başka araç gerekir.',
          ),
        ],
      ),
      _Lesson(
        id: 'heikin_ashi',
        title: 'Heikin Ashi Mum',
        summary: 'Klasik mumun "yumuşatılmış" hali — trendi daha net gösterir.',
        icon: Icons.bar_chart,
        level: _Level.adv,
        body:
            '''Heikin Ashi ("ortalama bar"), Japonca bir teknik. Klasik OHLC'den hesaplanır:

- HA_Close = (O+H+L+C) / 4
- HA_Open = (önceki HA_Open + önceki HA_Close) / 2
- HA_High, HA_Low: max/min

**Sonuç:** Gürültü azalır, trendler daha belirgin görünür. Üst üste aynı renkte mumlar = güçlü trend.

**Dezavantaj:** Gerçek açılış/kapanışı göstermez. Giriş-çıkış noktaları için klasik mumdan bakman gerekir.''',
      ),
    ],
  ),
  _Category(
    name: 'Temel Analiz',
    icon: Icons.assessment,
    lessons: [
      _Lesson(
        id: 'fk_orani',
        title: 'F/K Oranı (Fiyat / Kazanç)',
        summary: 'Hisse pahalı mı ucuz mu? En çok bakılan oran.',
        icon: Icons.price_change,
        level: _Level.basic,
        body:
            '''**F/K = Hisse Fiyatı / Hisse Başı Kâr.** Şirketin yıllık kârının kaç katına alındığını gösterir.

**Örnek:** Hisse 100 TL, hisse başı kâr 10 TL → F/K = 10. "Bu şirketin 1 yıllık kârını 10 yılda geri alırım" gibi düşün.

**Yorum:**
- **Düşük F/K:** Ucuz olabilir — ya da şirket sorunlu (değer tuzağı).
- **Yüksek F/K:** Pahalı — ya da yüksek büyüme bekleniyor (Tesla, teknoloji).

**Kritik kural:** F/K'yı SADECE aynı sektördeki şirketlerle kıyasla. Bankanın F/K'sı ile teknoloji şirketininki kıyaslanmaz. Uygulamadaki "Temel Analiz" sekmesinde her hissenin F/K'sını görebilirsin.''',
        quiz: [
          _QuizQ(
            'Hisse 200 TL, hisse başı kâr 20 TL. F/K kaçtır?',
            ['2', '10', '20', '40'],
            1,
            'F/K = Fiyat / Hisse Başı Kâr = 200 / 20 = 10.',
          ),
          _QuizQ(
            'Çok düşük F/K her zaman "ucuz fırsat" mıdır?',
            [
              'Evet, daima al',
              'Hayır, sorunlu şirket de olabilir (değer tuzağı)',
              'Sadece bankada',
              'F/K önemsizdir'
            ],
            1,
            'Düşük F/K bazen piyasanın şirkete güvenmediğini gösterir — '
                '"değer tuzağı" olabilir.',
          ),
          _QuizQ(
            'F/K kıyaslaması nasıl yapılmalı?',
            [
              'Tüm borsa geneliyle',
              'Aynı sektördeki şirketlerle',
              'Geçen yılın faiziyle',
              'Döviz kuruyla'
            ],
            1,
            'F/K sektörler arası çok değişir; anlamlı kıyas ancak aynı '
                'sektörde olur.',
          ),
        ],
      ),
      _Lesson(
        id: 'pd_dd',
        title: 'PD/DD ve Özsermaye',
        summary: 'Şirketin defter değerine göre fiyatı.',
        icon: Icons.account_balance_wallet,
        level: _Level.mid,
        body:
            '''**PD/DD = Piyasa Değeri / Defter Değeri.** Şirketin muhasebe değerinin kaç katına işlem gördüğü.

- **PD/DD < 1:** Şirket, kâğıt üzerindeki net varlığından ucuza satılıyor. Bankalar/holdingler için yaygın.
- **PD/DD yüksek:** Marka, patent, büyüme gibi "görünmeyen" değer fiyatlanıyor.

**Defter değeri (özsermaye):** Toplam varlık − toplam borç. Şirket bugün kapansa ortaklara teorik olarak kalan tutar.

**Pratik:** PD/DD'yi F/K ile birlikte oku. Düşük F/K + düşük PD/DD + sağlam kâr = klasik "değer yatırımı" sinyali (Graham/Buffett ekolü).''',
      ),
      _Lesson(
        id: 'roe_marj',
        title: 'Kâr Marjı, ROE ve Büyüme',
        summary: 'Şirket ne kadar verimli para kazanıyor?',
        icon: Icons.trending_up,
        level: _Level.mid,
        body: '''Kalite göstergeleri — ucuzluk değil, "iyi şirket mi?":

**Net kâr marjı:** Net Kâr / Ciro. 100 TL satıştan kaç TL kâr kalıyor. Yüksek marj = fiyatlama gücü.

**ROE (Özsermaye Kârlılığı):** Net Kâr / Özsermaye. Ortakların parasını ne verimle çeviriyor. **%15+ sürdürülebilir ROE güçlü kabul edilir.**

**Büyüme:** Ciro ve net kârın yıllık artışı (CAGR). Uygulamadaki "Bilanço & İleri Tahmin" bu CAGR'a dayanır.

**Sentez:** Yüksek ROE + büyüyen kâr + makul F/K = "kaliteyi uygun fiyata almak". Buffett'in aradığı şey budur.''',
      ),
      _Lesson(
        id: 'bilanco_101',
        title: 'Bilanço Okuma 101',
        summary: 'Gelir tablosu, bilanço, nakit akışı.',
        icon: Icons.description,
        level: _Level.adv,
        body: '''Bir şirketin 3 temel finansal tablosu:

**1. Gelir Tablosu:** Ciro → maliyetler → faaliyet kârı → net kâr. "Şirket para kazanıyor mu?"

**2. Bilanço:** Varlıklar = Borçlar + Özsermaye. "Şirket ne kadar borçlu, ne kadar sağlam?" Yüksek borç + düşen kâr tehlikelidir.

**3. Nakit Akışı:** Kâr "muhasebe", nakit "gerçek". Kârlı görünüp nakit yakan şirketler vardır. Faaliyet nakit akışının pozitif ve büyüyen olması istenir.

**Hızlı sağlık testi:** Kâr büyüyor mu? Borç/özsermaye makul mü? Faaliyet nakdi kârı destekliyor mu? Üçü de "evet" ise temel sağlam.''',
      ),
    ],
  ),
  _Category(
    name: 'Risk Yönetimi',
    icon: Icons.shield,
    lessons: [
      _Lesson(
        id: 'stop_tp',
        title: 'Stop-Loss & Take-Profit',
        summary: 'Zararı kes, kârı al — disiplinli yatırım.',
        icon: Icons.shield_outlined,
        level: _Level.basic,
        body:
            '''**Stop-Loss:** Fiyat belirli bir seviyeye DÜŞERSE otomatik SAT. Zararı sınırlar.

**Take-Profit:** Fiyat belirli bir seviyeye ÇIKARSA otomatik SAT. Kârı garantiler.

**Örnek:** AAPL'yi 200\$'dan aldın.
- Stop-Loss: 190\$ (max %5 zarar göze al)
- Take-Profit: 230\$ (%15 kâr al, fırsat olursa)

**Neden önemli?** Duygusal karar vermeyi engeller. "Daha düşecek mi?" stresi yerine plan uygulanır.''',
      ),
      _Lesson(
        id: 'cesitlendirme',
        title: 'Çeşitlendirme',
        summary: 'Tüm yumurtaları aynı sepete koyma.',
        icon: Icons.donut_large,
        level: _Level.basic,
        body:
            '''Tek bir varlığa yatırım yapmak çok risklidir. Çeşitlendirme, riskleri farklı varlıklara yayar.

**Strateji türleri:**
- **Sektör:** Teknoloji + sağlık + enerji
- **Coğrafya:** ABD + Türkiye + Avrupa
- **Varlık sınıfı:** Hisse + tahvil + altın + kripto
- **Şirket büyüklüğü:** Mega-cap + orta + küçük

**Modern teori:** ~%70 hisse / %20 tahvil / %10 alternatif (altın, kripto) genç yatırımcı için yaygın bir öneri.''',
        quiz: [
          _QuizQ(
            'Çeşitlendirmenin temel amacı nedir?',
            [
              'Getiriyi garantilemek',
              'Riski farklı varlıklara yaymak',
              'Komisyonu sıfırlamak',
              'Vergi kaçırmak'
            ],
            1,
            'Çeşitlendirme getiriyi garantilemez; tekil varlık riskini '
                'azaltır.',
          ),
          _QuizQ(
            'Hangisi gerçek bir çeşitlendirme değildir?',
            [
              'Farklı sektörler',
              'Farklı ülkeler',
              'Aynı sektörden 10 banka hissesi',
              'Hisse + tahvil + altın'
            ],
            2,
            'Hepsi aynı sektördeyse ortak şoka birlikte maruz kalır — '
                'gerçek dağıtım sağlamaz.',
          ),
        ],
      ),
      _Lesson(
        id: 'davranissal_onyargi',
        title: 'Davranışsal Önyargılar',
        summary: 'Disposition Effect, Overconfidence, Loss Aversion.',
        icon: Icons.psychology,
        level: _Level.mid,
        body: '''Yatırımcı duygusal kararlar verir. Bilinen 3 önemli önyargı:

**1. Disposition Effect (Shefrin & Statman, 1985):**
Kazançlı hisseyi erken satıp zararlı hisseyi tutma eğilimi. Mantıksız ama yaygındır.

**2. Overconfidence (Barber & Odean, 2001):**
Yatırımcılar bilgilerini abartırlar. Aşırı işlem yaparlar (komisyon yer), genelde kaybederler.

**3. Loss Aversion (Kahneman & Tversky, 1979):**
Kaybın acısı, eş değer kazancın sevinçten 2x güçlüdür. Bu yüzden insanlar gereksiz risk alır veya almaz.''',
      ),
      _Lesson(
        id: 'sharpe',
        title: 'Sharpe Oranı',
        summary: 'Risk-ağırlıklı getiriyi ölçen klasik metrik.',
        icon: Icons.equalizer,
        level: _Level.adv,
        body:
            '''Sharpe Oranı = (Portföy Getirisi − Risksiz Faiz) / Standart Sapma

**Yorum:**
- **> 1.0:** İyi — riski karşılayan getiri
- **0 – 1:** Pozitif ama yetersiz
- **< 0:** Risksiz faizden bile kötü

**Örnek:** %20 yıllık getiri kazanan iki portföy:
- A: çok dalgalı → Sharpe 0.4
- B: istikrarlı → Sharpe 1.6

Aynı getiri, ama B çok daha "iyi" bir yatırım. Çünkü daha az stresle aynı sonucu alıyorsun.

**Pratik kullanım:** Portföyünü endeksle veya farklı stratejilerle karşılaştır. Yüksek Sharpe daima tercih sebebidir.''',
      ),
      _Lesson(
        id: 'var',
        title: 'VaR — Value at Risk',
        summary: '%95 ihtimalle, max ne kadar kaybedersin?',
        icon: Icons.warning_amber,
        level: _Level.adv,
        body:
            '''VaR (Riske Maruz Değer), belirli bir güven aralığında maksimum potansiyel kaybı ölçer.

**Örnek (1 günlük, %95 VaR):** 100.000 TL portföyün için VaR = 5.000 TL ise:
"100 günden 95'inde 5.000 TL'den fazla kaybetmem."

**Sınırlamaları:**
- Geçmiş veriye dayalı, gelecek garantisi yok
- "Kara kuğu" olaylarını yakalamaz (2008, COVID)
- %5 olası kuyruk kayıpları çok daha büyük olabilir

**Tamamlayıcı:** CVaR (Conditional VaR) — kuyrukta gerçek beklenen kayıp.''',
      ),
      _Lesson(
        id: 'pozisyon_boyut',
        title: 'Pozisyon Boyutlandırma',
        summary: 'Her işlemde portföyün ne kadarını riske atmalı?',
        icon: Icons.scale,
        level: _Level.adv,
        body:
            '''**Klasik kural: 2% rule** — Tek bir işlemde portföyünün max %2'sini riske at.

**Örnek:** 100.000 TL portföy. AAPL almak istiyorsun:
- Stop-loss: %5 aşağıda
- Max risk: 100.000 × %2 = 2.000 TL
- Pozisyon: 2.000 / %5 = **40.000 TL**

Stop-loss tetiklenirse 2.000 TL kaybedersin — portföyün %2'si.

**Neden önemli?** 50 art arda yanlış işlemde bile portföyün ~%63'ü kalır. Disiplinli pozisyon boyutu uzun ömür sağlar.''',
      ),
    ],
  ),
  _Category(
    name: 'Makro & Türkiye',
    icon: Icons.account_balance,
    lessons: [
      _Lesson(
        id: 'enflasyon_reel',
        title: 'Enflasyon ve Reel Getiri',
        summary: 'Kazandığın para gerçekten kazanç mı?',
        icon: Icons.local_fire_department,
        level: _Level.basic,
        body:
            '''**Reel getiri = Nominal getiri − Enflasyon.** Asıl önemli olan budur.

**Örnek:** Yıllık %40 getiri elde ettin. Enflasyon %45 ise:
- Cebindeki para arttı (nominal +%40)
- Ama alım gücün **azaldı** (reel ≈ −%5)

Türkiye gibi yüksek enflasyon ortamında "kazandım" yanılgısı çok yaygındır. Mevduat faizi çoğu zaman enflasyonun altında kalır — reel olarak kaybettirir.

**Pratik:** Uygulamadaki "Kıyasla" ekranında getirini **enflasyon ve mevduatla** yan yana gör. Hisse/altın/dövizin uzun vadede enflasyonu yenme potansiyeli, mevduata göre temel avantajıdır.''',
        quiz: [
          _QuizQ(
            'Nominal getirin %40, enflasyon %50. Reel getirin?',
            [
              '+%40 (kazandın)',
              'Yaklaşık −%10 (alım gücün azaldı)',
              '%0',
              '+%90'
            ],
            1,
            'Reel ≈ nominal − enflasyon = %40 − %50 ≈ −%10. Para arttı '
                'ama alım gücü düştü.',
          ),
          _QuizQ(
            'Yüksek enflasyonda asıl bakman gereken nedir?',
            [
              'Nominal getiri',
              'Reel (enflasyondan arındırılmış) getiri',
              'Hisse sayısı',
              'Komisyon'
            ],
            1,
            'Cebindeki rakam değil, alım gücün önemli — yani reel getiri.',
          ),
        ],
      ),
      _Lesson(
        id: 'faiz_borsa',
        title: 'Faiz ve Borsa İlişkisi',
        summary: 'Merkez bankası faizi neden hisseleri etkiler?',
        icon: Icons.percent,
        level: _Level.mid,
        body: '''Faiz, tüm varlıkların fiyatını belirleyen "yerçekimi" gibidir.

**Faiz YÜKSELİRSE:**
- Mevduat/tahvil cazipleşir → para borsadan çıkar
- Şirketlerin borç maliyeti artar → kâr baskılanır
- Genelde hisseler (özellikle büyüme/teknoloji) baskı görür

**Faiz DÜŞERSE:** Tersi — borsaya para akar, hisseler değerlenir.

**Türkiye özelinde:** TCMB faiz kararları + TL'nin değeri + enflasyon iç içedir. Yüksek faiz dönemlerinde "mevduatta dur" baskısı artar; ama enflasyon faizden yüksekse mevduat da reel kaybettirebilir. Tek değişkene değil, bütüne bak.''',
      ),
      _Lesson(
        id: 'usdtry_yabanci',
        title: 'USD/TRY ve Yabancı Hisse',
        summary: 'Dolar bazlı düşünmek neden önemli?',
        icon: Icons.currency_exchange,
        level: _Level.basic,
        body: '''Yabancı (ABD) hisse aldığında iki şeye birden yatırım yaparsın:
1. Şirketin performansı (USD bazında)
2. **USD/TRY kuru**

**Örnek:** AAPL %0 değişti ama dolar TL karşısında %20 yükseldi → TL bazında pozisyonun +%20.

Bu yüzden uygulamada **₺ / \$ görüntüleme modu** var: portföyünü dolar bazında görünce şirketin "gerçek" performansını, TL bazında görünce cebindeki alım gücünü ölçersin.

**Risk:** Kur her iki yöne de hareket eder. Yabancı hisse, döviz çeşitlendirmesi sağlar ama kur riski de taşır. İkisini ayırarak düşün.''',
      ),
      _Lesson(
        id: 'ekonomik_dongu',
        title: 'Resesyon & Ekonomik Döngüler',
        summary: 'Genişleme, zirve, daralma, dip — ve sektör rotasyonu.',
        icon: Icons.cyclone,
        level: _Level.adv,
        body:
            '''Ekonomi 4 fazlı döngülerde hareket eder: **genişleme → zirve → daralma (resesyon) → dip → toparlanma.**

**Sektör rotasyonu:** Her fazda farklı sektörler öne çıkar:
- Erken toparlanma: bankacılık, sanayi, teknoloji
- Geç döngü/zirve: enerji, emtia
- Resesyon: savunmacı — gıda, sağlık, kamu hizmetleri (insanlar bunlardan kısmaz)

**Önemli:** Borsa ekonomiden ~6 ay ÖNCE hareket eder. Haberler en kötüyken dip yapmış olabilir.

**Pratik ders:** Döngüyü zamanlamak çok zordur. Çoğu yatırımcı için doğru cevap, çeşitlendirilmiş portföyü döngü boyunca tutmaktır — çıkıp girmeye çalışmak değil.''',
      ),
    ],
  ),
  _Category(
    name: 'Temettü Yatırımı',
    icon: Icons.payments,
    lessons: [
      _Lesson(
        id: 'temettu_nedir',
        title: 'Temettü Nedir, Nasıl İşler?',
        summary: 'Şirketin kârından sana düşen pay.',
        icon: Icons.payments_outlined,
        level: _Level.basic,
        body:
            '''**Temettü:** Şirketin elde ettiği kârın bir kısmını ortaklarına nakit olarak dağıtması.

**Önemli tarihler:**
- **Ex-tarih (temettü kesinti tarihi):** Bu tarihten ÖNCE hisseye sahip olman gerekir. Sonra alırsan o dönem temettüyü alamazsın.
- Ex-tarihte hisse fiyatı yaklaşık temettü kadar düşer (bedava para değil, değer transferi).

**Uygulamada:** Portföyündeki BIST hisselerinin alımından sonraki ex-temettüleri **otomatik nakde** geçer (USD hisseler için kurla TL'ye). "Temettü" ekranından yıllık tahmini geliri ve yaklaşan ödemeleri görebilirsin.''',
        quiz: [
          _QuizQ(
            'Bir hissenin temettüsünü almak için ne gerekir?',
            [
              'Ex-tarihten sonra almak',
              'Ex-tarihten önce/o gün hisseye sahip olmak',
              'Hisseyi hemen satmak',
              'Sadece kayıt olmak'
            ],
            1,
            'Hak (ex) tarihinde portföyünde olması gerekir; sonra alırsan '
                'o dönem temettüye giremezsin.',
          ),
          _QuizQ(
            'Ex-tarihte hisse fiyatına ne olur?',
            [
              'Değişmez',
              'Yaklaşık temettü kadar düşer',
              'İki katına çıkar',
              'Sıfırlanır'
            ],
            1,
            'Temettü bedava para değil, değer transferidir; fiyat '
                'yaklaşık o kadar düşer.',
          ),
        ],
      ),
      _Lesson(
        id: 'temettu_verimi',
        title: 'Temettü Verimi & Dağıtım Oranı',
        summary: 'Yüksek verim her zaman iyi mi?',
        icon: Icons.water_drop,
        level: _Level.mid,
        body:
            '''**Temettü Verimi = Yıllık Temettü / Hisse Fiyatı.** Örn. 100 TL hisse, 6 TL temettü → %6 verim.

**Dağıtım Oranı (Payout) = Temettü / Net Kâr.** Şirket kârının ne kadarını dağıtıyor.

**Tuzak:** Çok yüksek verim cazip görünür ama:
- Fiyat çöktüğü için verim "şişmiş" olabilir (şirket sorunlu).
- Payout %100'ü aşıyorsa temettü sürdürülemez — kesilebilir.

**Sağlıklı profil:** Makul verim (%3–6) + payout %70 altı + büyüyen kâr. "Temettüyü ödeyebilecek ve artırabilecek" şirket, en yüksek veren şirketten iyidir.''',
      ),
      _Lesson(
        id: 'temettu_bilesik',
        title: 'Temettü Aristokratları & Bileşik Büyüme',
        summary: 'Temettünün yeniden yatırımı = kartopu etkisi.',
        icon: Icons.snowing,
        level: _Level.adv,
        body:
            '''**Temettü Aristokratı:** 25+ yıl üst üste temettüsünü ARTIRMIŞ şirket (Coca-Cola, J&J gibi). İstikrar ve disiplin işaretidir.

**Bileşik etki (DRIP):** Aldığın temettüyle tekrar hisse alırsan, sonraki dönem daha fazla hisseden temettü alırsın → kartopu.

**Örnek:** %4 verimli, temettüsünü yıllık %7 artıran bir hisse. Temettüyü hep tekrar yatırırsan ~20 yılda yatırılan maliyetine göre efektif verimin çok katlanır ("yield on cost").

**Ders:** Uzun vadeli temettü yatırımında asıl güç fiyat dalgasında değil, **kesintisiz artan temettünün yeniden yatırımında** saklıdır. Sabır gerektirir.''',
      ),
    ],
  ),
  _Category(
    name: 'Kripto Temelleri',
    icon: Icons.currency_bitcoin,
    lessons: [
      _Lesson(
        id: 'blokzincir',
        title: 'Blok Zinciri & Kripto Nedir?',
        summary: 'Merkezi olmayan, dağıtık defter mantığı.',
        icon: Icons.link,
        level: _Level.basic,
        body:
            '''**Blok zinciri:** Herkesin kopyasını tuttuğu, geriye dönük değiştirilemeyen bir kayıt defteri. Banka gibi merkezi bir otorite yerine ağ doğrular.

**Kripto para:** Bu ağ üzerinde değer taşıyan birim (Bitcoin, Ethereum...).

**Hisseden farkı:**
- Arkasında şirket, kâr, temettü, bilanço **yok**.
- Değeri tamamen arz/talep ve "ağın benimsenmesi" beklentisiyle oluşur.
- 7/24 işlem görür, devre kesici yoktur.

**Sonuç:** Klasik temel analiz (F/K, kâr) kriptoda çalışmaz. Bu farklı bir varlık sınıfıdır — ona göre değerlendir.''',
        quiz: [
          _QuizQ(
            'Kripto paranın hisseden temel farkı nedir?',
            [
              'Arkasında şirket/kâr/temettü yoktur',
              'Daha düşük risklidir',
              'Devlet garantilidir',
              'F/K oranı vardır'
            ],
            0,
            'Kriptonun arkasında bilanço/kâr yoktur; değeri arz-talep ve '
                'benimsenme beklentisiyle oluşur.',
          ),
          _QuizQ(
            'Blok zinciri en iyi nasıl tanımlanır?',
            [
              'Bir banka sunucusu',
              'Herkesin kopyasını tuttuğu, değiştirilemeyen kayıt defteri',
              'Bir şirket hissesi',
              'Devlet tahvili'
            ],
            1,
            'Merkezi otorite yerine ağın doğruladığı, geriye dönük '
                'değiştirilemeyen dağıtık defterdir.',
          ),
        ],
      ),
      _Lesson(
        id: 'btc_eth_alt',
        title: 'BTC vs ETH vs Altcoin',
        summary: 'Hepsi "kripto" ama çok farklılar.',
        icon: Icons.account_tree,
        level: _Level.mid,
        body:
            '''**Bitcoin (BTC):** Arzı sınırlı (21 milyon). "Dijital altın" — değer saklama anlatısı. Kriptoda en az riskli kabul edilir (göreceli).

**Ethereum (ETH):** Üzerinde uygulama/sözleşme çalışan platform. "Dijital petrol" — kullanım odaklı.

**Altcoin'ler:** BTC/ETH dışındaki binlerce coin. Çoğu yüksek riskli, bir kısmı tamamen değersizleşir. Yüksek getiri vaadi = yüksek toplam kayıp riski.

**Pratik:** Risk merdiveni genelde BTC < ETH < büyük altcoin < küçük altcoin şeklindedir. "Bedava token", "garanti %X" söylemlerinden uzak dur — kriptoda dolandırıcılık yoğundur.''',
      ),
      _Lesson(
        id: 'kripto_portfoy',
        title: 'Kriptonun Portföydeki Yeri & Riskleri',
        summary: 'Ne kadar, neden, hangi riskle?',
        icon: Icons.pie_chart,
        level: _Level.adv,
        body:
            '''Kripto yüksek getiri **ve** yüksek kayıp potansiyeli taşır. %70-80 düşüşler tarihte birden çok kez yaşandı.

**Yaygın yaklaşım:** Toplam portföyün küçük bir dilimi (örn. %1–10), "tamamını kaybetsem hayatım değişmez" diyebileceğin kadar.

**Riskler:**
- **Volatilite:** Bir günde %20 oynayabilir.
- **Anlatı riski:** Değer beklentiye dayalı; anlatı kırılırsa hızlı çöker.
- **Düzenleme:** Yasal çerçeve ülkeden ülkeye değişir ve değişebilir.

**Disiplin:** Pozisyon boyutlandırma ve "kaybetmeyi göze alabileceğin kadar" kuralı kriptoda klasik hisseden bile kritiktir. FOMO ile zirveden almak en sık yapılan hatadır.''',
      ),
    ],
  ),
  _Category(
    name: 'Piyasa Psikolojisi',
    icon: Icons.psychology_alt,
    lessons: [
      _Lesson(
        id: 'fomo_suru',
        title: 'FOMO ve Sürü Davranışı',
        summary: 'Geç kalma korkusu — en pahalı duygu.',
        icon: Icons.groups,
        level: _Level.basic,
        body:
            '''**FOMO (Fear of Missing Out):** Herkes alırken, sen de almak istersin. Genelde zirvede.

**Sürü davranışı:** Topluluk hareketine kapılıp kendi analizini bırakmak.

**Klasik örnekler:**
- 2017 Bitcoin balonu: zirvede satın alanlar 1 yıl içinde %80 kaybetti
- GameStop 2021: viral haberle alanlar dakikalar içinde dipte kaldı

**Anti-pattern:** "Warren Buffett'in tersi" — başkalarının açgözlü olduğunda korkak ol, korktuğunda açgözlü ol.

**Pratik:** Almak istediğinde 24 saat bekle. Hâlâ mantıklı geliyorsa al.''',
        quiz: [
          _QuizQ(
            'FOMO ile alım genelde ne zaman yapılır?',
            [
              'Dipte',
              'Herkes alırken, çoğunlukla zirvede',
              'Piyasa kapalıyken',
              'Temettü gününde'
            ],
            1,
            'Geç kalma korkusu fiyat zaten yükselmişken devreye girer — '
                'çoğu kez tepe noktası.',
          ),
          _QuizQ(
            'Buffett\'in sürüye karşı ilkesi nedir?',
            [
              'Herkesle birlikte hareket et',
              'Başkaları açgözlüyken korkak, korkakken açgözlü ol',
              'Hep nakitte kal',
              'Sadece kripto al'
            ],
            1,
            'Sürünün tersine pozisyon, uzun vadede daha sağlıklı '
                'sonuçlar üretir.',
          ),
        ],
      ),
      _Lesson(
        id: 'anchoring',
        title: 'Anchoring Bias',
        summary: 'İlk fiyata sapma — alış fiyatına takılıp kalma.',
        icon: Icons.anchor,
        level: _Level.mid,
        body:
            '''Aldığın fiyat (anchor), sonraki tüm değerlendirmelerini etkiler.

**Örnek:** AAPL'yi 200\$'dan aldın. Şu an 150\$.
- Mantıksız tepki: "200'e gelene kadar bekleyeyim, satmam"
- Doğru soru: "Bugün 150'den satıp X'e mi yatırsam?"

**Geçmiş alış fiyatı ALAKASIZ.** Sadece bugünkü beklentin önemli.

**Çözüm:** Pozisyonlarına "ilk kez şimdi alıyormuş gibi" değerlendir. Tutmak istemediğin şeyi sat — kâr/zarar durumuna bakma.''',
      ),
      _Lesson(
        id: 'recency',
        title: 'Recency Bias',
        summary: 'Son hareketi gelecek sanmak.',
        icon: Icons.update,
        level: _Level.mid,
        body:
            '''Son 2 hafta yükseliş gördüysen, devam edecek sanırsın. Son 2 hafta düştüyse, çökmüş sanırsın.

**Gerçek:** Kısa vadeli fiyat hareketleri genelde rastgeledir. Geleceğin tahmincisi DEĞİLDİR.

**Veri:** ABD borsasının 1990-2020 arası getirisinin %50'si, sadece **en iyi 25 günde** gerçekleşti. Yani "panik satışta dışarıda kal" — bu günleri kaçırırsın.

**Pratik:** Uzun vadeli ortalamalara bak. 1 yıllık trend > 1 aylık > 1 günlük.''',
      ),
    ],
  ),
  _Category(
    name: 'Pratik Stratejiler',
    icon: Icons.lightbulb,
    lessons: [
      _Lesson(
        id: 'dca',
        title: 'Dollar-Cost Averaging (DCA)',
        summary: 'Düzenli aralıklarla sabit tutarla alım.',
        icon: Icons.calendar_today,
        level: _Level.basic,
        body:
            '''**DCA:** Belirli aralıklarla (örn. her ay) aynı miktarda alım yap. Fiyat baktığın için değil, takvim için al.

**Avantajlar:**
- Tepe alımdan korur (yüksek fiyatta az lot, düşük fiyatta çok lot)
- Duygusal "şimdi mi alsam?" stresi yok
- Düşük volatilite tolerans

**Örnek:** Aylık 1000 TL S&P 500 ETF'ine. 12 ay sonra:
- Bazı aylarda 1000 TL = 5 lot
- Diğer aylarda 1000 TL = 7 lot
- **Ortalama maliyetin piyasa ortalamasından düşük olur** (matematiksel olarak)

**Kim için?** Borsayı düzenli takip edemeyenler. Çoğu çalışan için ideal. Uygulamadaki "Senaryo" ekranında DCA simülasyonunu deneyebilirsin.''',
        quiz: [
          _QuizQ(
            'DCA stratejisinde alım kararını ne belirler?',
            [
              'Fiyatın o anki seviyesi',
              'Takvim (düzenli, sabit tutar)',
              'Haberler',
              'RSI'
            ],
            1,
            'DCA fiyata değil takvime göre alır; bu duygusal zamanlamayı '
                'devre dışı bırakır.',
          ),
          _QuizQ(
            'Sabit tutarla DCA neden tepe alımdan korur?',
            [
              'Fiyat hep sabittir',
              'Düşükte çok lot, yüksekte az lot alınır',
              'Komisyon yoktur',
              'Temettü ikiye katlanır'
            ],
            1,
            'Aynı para düşük fiyatta daha çok pay alır; ortalama maliyet '
                'aşağı çekilir.',
          ),
        ],
      ),
      _Lesson(
        id: 'buy_hold',
        title: 'Buy and Hold (Al ve Tut)',
        summary: 'En sıkıcı strateji, çoğu kez en kârlı.',
        icon: Icons.lock_clock,
        level: _Level.basic,
        body:
            '''**Strateji:** Kaliteli şirketleri al, uzun süre tut. Trade etme.

**Veri:** Warren Buffett 1965-2023 arası yıllık %19.8 ortalama getiri. Aynı dönemde S&P 500 %10. Aktif yöneticilerin %85'i S&P'yi yenemedi.

**Neden işe yarar?**
- Vergi ertelemesi (satmadığın sürece vergi yok)
- Düşük işlem maliyeti
- Bileşik faiz tam çalışır

**Yanılgı:** "Borsada heyecan olmalı" — yok. İyi yatırım sıkıcıdır.

**Pratik:** Düzenli aralıklarla portföyünü dengele (rebalance), gerisine karışma.''',
      ),
      _Lesson(
        id: 'pay_vs_etf',
        title: 'Pay vs. Endeks Fonu',
        summary: 'Tek hisse mi, ETF mi?',
        icon: Icons.compare_arrows,
        level: _Level.mid,
        body: '''**Tek hisse:**
- Yüksek getiri potansiyeli (10x'ler)
- Yüksek risk (sıfırlama)
- Araştırma ister

**ETF (Endeks Fonu):**
- 100-500 şirkete eşzamanlı yatırım
- Daha düşük getiri ama daha düşük risk
- Bireysel araştırma minimum

**Hangisi sana uygun?**
- Vaktin/ilgin var → karma (örn. %70 ETF + %30 seçili hisseler)
- Vaktin yok → %100 ETF
- Genç + riskli → daha çok tek hisse OK

**Türkiye'de popüler ETF'ler:** İş Yatırım Endeks 100, Garanti Portföy Big Tech.''',
      ),
      _Lesson(
        id: 'rebalance',
        title: 'Portföy Dengeleme (Rebalancing)',
        summary: 'Hedef ağırlıklara periyodik dönüş.',
        icon: Icons.balance,
        level: _Level.adv,
        body: '''Zamanla kazanan varlık portföyde şişer, riski bozar.

**Örnek:** Hedef %60 hisse / %40 tahvil-altın. Hisse iyi gitti → %75/%25 oldu. Artık planladığından çok daha risklisin.

**Rebalancing:** Şişeni sat, geri kalanı al → hedefe dön. Bu "yüksekten sat, düşükten al" davranışını **otomatik ve duygusuz** yaptırır.

**Yöntemler:**
- **Takvim:** Yılda 1-2 kez bak, ayarla.
- **Eşik:** Bir varlık hedeften ±%5 saparsa düzelt.

**Faydası:** Getiriyi büyük ölçüde artırmaz; asıl işi **riski kontrol altında tutmak** ve disiplini korumaktır. Uygulamadaki "Sağlık Skoru" konsantrasyon uyarısı bu ihtiyacı yakalar.''',
        quiz: [
          _QuizQ(
            'Rebalancing aslında otomatik olarak ne yaptırır?',
            [
              'Yüksekten al, düşükten sat',
              'Şişeni sat, düşeni al (yüksekten sat, düşükten al)',
              'Her şeyi sat',
              'Hiç işlem yapma'
            ],
            1,
            'Hedefe dönerken kazananı kısıp geride kalanı alırsın — '
                'disiplinli "pahalıyı sat, ucuzu al".',
          ),
          _QuizQ(
            'Rebalancing\'in asıl işi nedir?',
            [
              'Getiriyi katlamak',
              'Riski kontrol altında tutmak',
              'Vergi kaçırmak',
              'Komisyon kazanmak'
            ],
            1,
            'Getiriyi büyük ölçüde artırmaz; riski ve disiplini korur.',
          ),
        ],
      ),
    ],
  ),
  _Category(
    name: 'Yatırım Araçları',
    icon: Icons.category,
    lessons: [
      _Lesson(
        id: 'tahvil_bono',
        title: 'Tahvil & Bono',
        summary: 'Borç verip faiz almak — hissenin sakin kardeşi.',
        icon: Icons.receipt_long,
        level: _Level.basic,
        body:
            '''**Tahvil/Bono:** Bir şirkete veya devlete borç verirsin; karşılığında belirli bir faiz (kupon) + vade sonunda anaparayı alırsın.

**Hisseden farkı:**
- Hisse = ortaklık (kâr/zarara ortaksın). Tahvil = alacaklılık (sabit ödeme).
- Şirket batarsa tahvil sahipleri hisse sahiplerinden ÖNCE ödenir → daha düşük risk, daha düşük getiri.

**Fiyat–faiz ilişkisi (kritik):** Piyasa faizi YÜKSELİRSE, elindeki düşük kuponlu tahvilin değeri DÜŞER. Ters yönlü çalışır.

**Rolü:** Portföyde "balast" — hisse çakılırken görece sakin kalır, çeşitlendirme sağlar.''',
        quiz: [
          _QuizQ(
            'Tahvil sahibi şirkete göre kimdir?',
            ['Ortağı', 'Alacaklısı (borç vermiştir)', 'Çalışanı', 'Müşterisi'],
            1,
            'Tahvil ortaklık değil borç ilişkisidir; sabit ödeme '
                'beklersin.',
          ),
          _QuizQ(
            'Piyasa faizi yükselince mevcut tahvilin değeri ne olur?',
            ['Yükselir', 'Düşer', 'Değişmez', 'İkiye katlanır'],
            1,
            'Faiz ve tahvil fiyatı ters yönlüdür: faiz çıkarsa eski '
                'düşük kuponlu tahvil değer kaybeder.',
          ),
        ],
      ),
      _Lesson(
        id: 'fon_etf_derin',
        title: 'Yatırım Fonu & ETF',
        summary: 'Tek tıkla onlarca varlığa sahip olmak.',
        icon: Icons.inventory_2,
        level: _Level.basic,
        body:
            '''**Yatırım fonu:** Bir profesyonelin yönettiği, birçok yatırımcının parasını birleştirip varlık sepeti oluşturan yapı.

**ETF (Borsa Yatırım Fonu):** Borsada hisse gibi anlık alınıp satılan fon. Genelde bir endeksi taklit eder (pasif).

**Aktif vs Pasif:**
- **Aktif fon:** Yönetici "piyasayı yenmeye" çalışır, gider oranı yüksektir.
- **Pasif (endeks) ETF:** Sadece endeksi izler, masrafı çok düşüktür.

**Veri:** Uzun vadede aktif fonların büyük çoğunluğu, masraflar sonrası endeksi yenemez. Bu yüzden düşük maliyetli endeks ETF'i çoğu yatırımcı için sağlam bir temeldir.

**Gider oranı (TER):** Yıllık yüzde kesinti. %0,1 ile %2 arası fark, 20 yılda devasa bir tutara dönüşür.''',
        quiz: [
          _QuizQ(
            'ETF\'in klasik yatırım fonundan farkı nedir?',
            [
              'Borsada hisse gibi anlık alınıp satılır',
              'Hiç masrafı yoktur',
              'Devlet garantilidir',
              'Sadece kurumlara satılır'
            ],
            0,
            'ETF gün içinde borsada işlem görür; klasik fonlar günde tek '
                'fiyattan işlenir.',
          ),
          _QuizQ(
            'Uzun vadede çoğu aktif fon endeksi neden yenemez?',
            [
              'Yöneticiler tembeldir',
              'Yüksek masraf + zamanlama zorluğu',
              'Endeks hile yapar',
              'Aktif fon yasaktır'
            ],
            1,
            'Yüksek gider oranı ve sürekli doğru zamanlamanın zorluğu '
                'birikerek endeksin gerisinde bırakır.',
          ),
          _QuizQ(
            'Gider oranı (TER) neden önemlidir?',
            [
              'Önemsizdir',
              'Küçük yüzdeler uzun vadede büyük tutara döner',
              'Sadece ilk yıl alınır',
              'Getiriyi artırır'
            ],
            1,
            'Bileşik etki masrafa da çalışır; %1\'lik fark on yıllarda '
                'ciddi kayıptır.',
          ),
        ],
      ),
      _Lesson(
        id: 'altin_emtia',
        title: 'Altın & Emtia',
        summary: 'Enflasyon ve kriz sığınağı — ama temettüsü yok.',
        icon: Icons.diamond,
        level: _Level.mid,
        body:
            '''**Emtia:** Altın, gümüş, petrol, bakır, buğday gibi fiziksel mallar.

**Altının rolü:**
- Uzun vadede enflasyona karşı alım gücünü görece korur.
- Kriz/belirsizlik dönemlerinde "güvenli liman" talebi artar.
- Hisselerle düşük korelasyon → çeşitlendirme sağlar.

**Dezavantaj:** Altın kâr/temettü/faiz ÜRETMEZ. Değeri tamamen "başkası daha pahalıya alır mı" beklentisine bağlıdır. Şirket hissesi gibi içsel büyüme yoktur.

**Türkiye bağlamı:** Gram altın hem ons altına hem USD/TRY kuruna bağlıdır. Çoğu zaman TL bazında "altın kazandırdı" derken aslında kur etkisini ölçersin. Uygulamadaki "Kıyasla" gram altını ayrı gösterir.''',
        quiz: [
          _QuizQ(
            'Altının hisse senedinden temel bir farkı nedir?',
            [
              'Daha yüksek temettü öder',
              'Kâr/temettü üretmez, içsel büyümesi yoktur',
              'Hiç değer kaybetmez',
              'Devlet garantilidir'
            ],
            1,
            'Altın nakit akışı üretmez; getirisi yalnızca fiyat '
                'değişiminden gelir.',
          ),
          _QuizQ(
            'Altın portföyde neden çeşitlendirici sayılır?',
            [
              'Hisselerle yüksek korelasyonlu',
              'Hisselerle düşük korelasyonlu, krizde talep görür',
              'Faiz öder',
              'Hiç oynamaz'
            ],
            1,
            'Düşük korelasyon, hisseler düşerken portföyü görece '
                'dengeleyebilir.',
          ),
        ],
      ),
      _Lesson(
        id: 'turev_kaldirac',
        title: 'Türev & Kaldıraç (Dikkat)',
        summary: 'Opsiyon, vadeli, kaldıraç — kâr da zarar da büyür.',
        icon: Icons.warning,
        level: _Level.adv,
        body:
            '''**Türev:** Değeri başka bir varlığa (hisse, endeks, döviz) bağlı sözleşmeler — opsiyon, vadeli (futures), CFD.

**Kaldıraç:** Küçük teminatla büyük pozisyon. 10x kaldıraçta %10 ters hareket = sermayenin tamamı gider.

**Neden tehlikeli?**
- Zarar yatırdığından fazlasına ulaşabilir.
- Zaman aşımı (opsiyonda) ve gecelik taşıma maliyetleri vardır.
- Duygusal baskı katlanır; çoğu bireysel kaldıraçlı hesap zararla kapanır.

**Meşru kullanım:** Profesyonellerde **hedge** (riskten korunma) amaçlı kullanılır — spekülasyon için değil.

**Ders:** Yeni yatırımcı için doğru yaklaşım, türev ve yüksek kaldıraçtan uzak durmaktır. Önce spot/nakit hesapta disiplini oturt.''',
        quiz: [
          _QuizQ(
            '10x kaldıraçta varlık %10 ters giderse ne olur?',
            [
              '%1 kaybedersin',
              'Sermayenin tamamına yakınını kaybedersin',
              'Hiçbir şey',
              'Kâr edersin'
            ],
            1,
            'Kaldıraç hareketi büyütür; 10x\'te %10 ters = ~%100 sermaye '
                'kaybı.',
          ),
          _QuizQ(
            'Türevlerin profesyonellerdeki meşru ana kullanımı nedir?',
            [
              'Riskten korunma (hedge)',
              'Garantili kâr',
              'Vergi kaçırma',
              'Temettü artırma'
            ],
            0,
            'Asıl meşru amaç mevcut riskleri dengelemektir, kumar '
                'değil.',
          ),
        ],
      ),
    ],
  ),
  _Category(
    name: 'İşlem & Maliyetler',
    icon: Icons.receipt,
    lessons: [
      _Lesson(
        id: 'emir_tipleri',
        title: 'Emir Tipleri',
        summary: 'Piyasa, limit, stop — doğru emir doğru anda.',
        icon: Icons.swap_vert,
        level: _Level.basic,
        body:
            '''**Piyasa emri (market):** "Şu an neyse o fiyattan hemen al/sat." Hız garantisi var, fiyat garantisi YOK (volatilde kayar).

**Limit emri:** "En fazla X'ten al / en az Y'den sat." Fiyat garantisi var, gerçekleşme garantisi YOK (fiyat gelmezse dolmaz).

**Stop emri:** Belirli seviye görülünce devreye giren tetikleyici (zararı kesmek/koruma için).

**Pratik:**
- Likit, oynak hisse + acele → piyasa.
- Belirli bir fiyat hedefin var → limit.
- Pozisyonu korumak → stop-loss.

Uygulamada hem alım/satımda hem de limit emir/alarmda bu mantığı kullanırsın.''',
        quiz: [
          _QuizQ(
            'Limit emrin garantisi nedir?',
            [
              'Kesin gerçekleşir',
              'Fiyatı garanti eder ama dolmayabilir',
              'Hem fiyat hem dolum garantili',
              'Hiçbir garanti yok'
            ],
            1,
            'Limit fiyatı korur ama o fiyat görülmezse emir '
                'gerçekleşmez.',
          ),
          _QuizQ(
            'Çok oynak bir hissede piyasa emrinin riski nedir?',
            [
              'Hiç dolmaz',
              'Beklediğinden farklı (kötü) fiyattan dolabilir',
              'Komisyon alınmaz',
              'Vergi artar'
            ],
            1,
            'Piyasa emri hızı garanti eder, fiyatı değil; oynaklıkta '
                'kayma olur.',
          ),
        ],
      ),
      _Lesson(
        id: 'maliyet_spread',
        title: 'Komisyon, Spread & Gizli Maliyetler',
        summary: 'Getirini sessizce yiyen kalemler.',
        icon: Icons.money_off,
        level: _Level.mid,
        body: '''Her işlemin görünen ve görünmeyen maliyeti vardır:

**Komisyon:** Aracı kurumun işlem başına kestiği ücret.

**Spread:** Alış (bid) ile satış (ask) fiyatı arasındaki fark. Likit olmayan varlıkta geniştir → daha alır almaz "zarardasın".

**Slipaj (kayma):** Emrin beklenen fiyattan farklı dolması.

**Sık işlem tuzağı:** Küçük kazançlar peşinde çok işlem yapmak, komisyon + spread + vergi ile net getiriyi eritir. Araştırmalar en çok işlem yapan bireysel yatırımcıların genelde en düşük net getiriyi elde ettiğini gösterir.

**Ders:** Maliyet, kontrol edebildiğin nadir değişkenlerden biridir. Az ve planlı işlem, düşük maliyetli araç = uzun vadede büyük fark.''',
        quiz: [
          _QuizQ(
            'Spread nedir?',
            [
              'Komisyonun adı',
              'Alış ve satış fiyatı arasındaki fark',
              'Vergi oranı',
              'Temettü verimi'
            ],
            1,
            'Bid–ask farkıdır; geniş spread, alır almaz dezavantaj '
                'demektir.',
          ),
          _QuizQ(
            'Çok sık işlem yapmak net getiriyi neden düşürür?',
            [
              'Komisyon + spread + vergi birikir',
              'Borsa ceza keser',
              'Temettü iptal olur',
              'Hisseler değer kaybeder'
            ],
            0,
            'Maliyet kalemleri her işlemde birikir; en aktif bireyseller '
                'genelde en düşük net getiriyi alır.',
          ),
        ],
      ),
      _Lesson(
        id: 'vergi_temel',
        title: 'Vergi Mantığı (Genel)',
        summary: 'Brüt değil net getiri önemli — temel çerçeve.',
        icon: Icons.gavel,
        level: _Level.adv,
        body:
            '''Yatırım kazancı çoğu yerde vergilenir; kuralları ülke/araç/süreye göre değişir. Burada **genel mantık** verilir (yatırım/vergi danışmanlığı değildir).

**İki tip kazanç:**
- **Sermaye kazancı:** Al-sat farkı. Satınca realize olur.
- **Gelir:** Temettü, faiz, kupon.

**Önemli ilkeler:**
- **Realize etmedikçe** sermaye kazancı genelde vergilenmez → "al ve tut" doğal bir vergi ertelemesidir.
- Zararlar bazı sistemlerde kazançtan düşülebilir (mahsup).
- Sık al-sat = daha erken/sık vergi = bileşik büyümeye köstek.

**Ders:** Kararını yalnızca vergiye göre verme ama net getiriyi (vergi sonrası) düşün. Güncel oran/istisnalar için resmî kaynağa veya uzmana bak.''',
        quiz: [
          _QuizQ(
            'Hisseyi satmadan değer artışı genelde ne zaman vergilenir?',
            [
              'Her gün',
              'Genelde satışta (realize olunca)',
              'Hiç vergilenmez',
              'Alımda'
            ],
            1,
            'Kâğıt üstü kazanç çoğunlukla satışta realize olur; "tut" '
                'doğal erteleme sağlar.',
          ),
          _QuizQ(
            'Yatırım kararını sadece vergiye göre vermek doğru mu?',
            [
              'Evet, tek kriter',
              'Hayır; net getiriyi düşün ama tek kriter değil',
              'Vergi önemsiz',
              'Sadece kripto için'
            ],
            1,
            'Vergi önemli bir girdidir ama yatırım mantığının yerini '
                'almaz.',
          ),
        ],
      ),
    ],
  ),
  _Category(
    name: 'Yatırımcı Disiplini',
    icon: Icons.flag,
    lessons: [
      _Lesson(
        id: 'bilesik_getiri',
        title: 'Bileşik Getirinin Gücü',
        summary: 'Dünyanın 8. harikası — zaman + sabır.',
        icon: Icons.auto_graph,
        level: _Level.basic,
        body:
            '''**Bileşik getiri:** Kazancın da kazanç üretmeye başlaması. Kar üzerine kâr.

**72 Kuralı:** Paranın 2'ye katlanma süresi ≈ 72 / yıllık getiri yüzdesi.
- %8 getiride ≈ 9 yıl
- %12 getiride ≈ 6 yıl

**Çarpıcı örnek:** Yılda %15 ile büyüyen 10.000 TL → ~5 yılda 2x, ~10 yılda 4x, ~20 yılda 16x. Asıl patlama son yıllarda olur.

**En kritik değişken: ZAMAN.** Erken başlayıp az yatıran, geç başlayıp çok yatıranı sıklıkla geçer. Bu yüzden "ne zaman başlamalı?" sorusunun cevabı neredeyse her zaman "mümkün olan en erken".

**Düşman:** Erken bozmak, panikle çıkmak, yüksek maliyet — bileşiğin zincirini kırar.''',
        quiz: [
          _QuizQ(
            '72 Kuralı\'na göre %9 getiride para kaç yılda 2x olur?',
            ['Yaklaşık 4', 'Yaklaşık 8', 'Yaklaşık 18', 'Yaklaşık 36'],
            1,
            '72 / 9 = 8 yıl (yaklaşık ikiye katlanma süresi).',
          ),
          _QuizQ(
            'Bileşik büyümede en kritik değişken nedir?',
            ['Şans', 'Zaman (erken başlamak)', 'Komisyon', 'Hisse sayısı'],
            1,
            'Süre uzadıkça etki üstel büyür; erken başlamak çoğu zaman '
                'tutarı yener.',
          ),
        ],
      ),
      _Lesson(
        id: 'yatirim_plani',
        title: 'Yazılı Yatırım Planı',
        summary: 'Plan olmadan piyasa duygularını yönetir.',
        icon: Icons.checklist,
        level: _Level.mid,
        body:
            '''Profesyonellerin amatörlerden en büyük farkı: **önceden yazılmış bir plan** ve ona sadakat.

**Bir plan şunları içermeli:**
- **Amaç & vade:** Ne için, kaç yıl? (emeklilik, ev, vs.)
- **Varlık dağılımı:** Hisse / tahvil / altın / nakit hedef yüzdeleri.
- **Kural:** Ne zaman alırım, ne zaman satarım, ne zaman dengelerim.
- **Risk sınırı:** Maksimum kabul edilebilir düşüş.

**Neden yazılı?** Piyasa düşerken beyin "sat, kaç" der. Önceden yazılmış kural, o anki duygunun kararını ele geçirmesini engeller.

**Ders:** İyi bir vasat plan + disiplin, mükemmel ama uygulanmayan stratejiyi her zaman yener. Planını sakin bir günde yaz, kötü günde uygula.''',
        quiz: [
          _QuizQ(
            'Yatırım planı neden YAZILI olmalı?',
            [
              'Yasal zorunluluk',
              'Kötü günde duygunun kararı ele geçirmesini engeller',
              'Komisyonu düşürür',
              'Vergi avantajı'
            ],
            1,
            'Önceden yazılan kural, panik/açgözlülük anında pusula '
                'görevi görür.',
          ),
          _QuizQ(
            'Hangisi daha iyi sonuç verir?',
            [
              'Mükemmel ama uygulanmayan strateji',
              'Vasat ama disiplinle uygulanan plan',
              'Plansız sezgi',
              'Sürekli strateji değiştirmek'
            ],
            1,
            'Uygulanabilirlik ve disiplin, teorik mükemmellikten daha '
                'değerlidir.',
          ),
        ],
      ),
      _Lesson(
        id: 'acil_fon',
        title: 'Acil Durum Fonu',
        summary: 'Yatırıma başlamadan önceki sıfırıncı adım.',
        icon: Icons.health_and_safety,
        level: _Level.basic,
        body:
            '''Yatırımın ön koşulu: **3–6 aylık zorunlu giderini** likit, güvenli bir yerde tutmak.

**Neden?** Acil bir ihtiyaçta (iş kaybı, sağlık) elinde nakit yoksa, **en kötü zamanda** (piyasa düşükken) hisse satmak zorunda kalırsın. Bu, bileşik büyümeyi kalıcı kırar.

**Acil fon nerede durmalı?**
- Anında erişilebilir, değeri oynamayan: vadesiz/kısa vadeli mevduat, likit fon.
- Hisse/kripto/uzun vade tahvil DEĞİL — tam ihtiyaç anında düşük olabilir.

**Sıralama:**
1. Acil fon kur.
2. Yüksek faizli borcu kapat.
3. Sonra yatırıma başla.

**Ders:** Acil fon "düşük getirili" diye küçümsenir; aslında portföyünü zorunlu satıştan koruyan sigortadır. Getirisi, kurtardığı kayıpta gizlidir.''',
        quiz: [
          _QuizQ(
            'Acil durum fonu nerede tutulmalı?',
            [
              'Volatil hisselerde',
              'Likit ve değeri oynamayan bir yerde',
              'Kriptoda',
              'Uzun vade tahvilde'
            ],
            1,
            'Tam ihtiyaç anında erişilebilir ve değer kaybetmemiş '
                'olmalı.',
          ),
          _QuizQ(
            'Acil fonun asıl koruma işlevi nedir?',
            [
              'Yüksek getiri',
              'Kötü zamanda zorunlu satışı önlemek',
              'Vergi indirimi',
              'Komisyon iadesi'
            ],
            1,
            'Nakit tamponu, piyasa dipteyken yatırımı satmaya '
                'mecbur kalmanı engeller.',
          ),
        ],
      ),
      _Lesson(
        id: 'yeni_yatirimci_hatalari',
        title: 'Yeni Yatırımcının 7 Hatası',
        summary: 'Çoğu kayıp aynı tekrar eden hatalardan gelir.',
        icon: Icons.report_problem,
        level: _Level.mid,
        body: '''Acemi kayıplarının büyük kısmı şu kalıplardan gelir:

1. **Plansızlık:** Amaç/kural yok, habere göre al-sat.
2. **Aşırı işlem:** Sürekli giriş-çıkış → maliyet eritir.
3. **Tek varlığa yığılma:** "Bu kesin patlar" → çeşitlendirme yok.
4. **Zarara âşık olmak:** Düşeni "geri gelir" diye sonsuz tutmak (anchoring + loss aversion).
5. **Kaldıraç/türevle başlamak:** Öğrenmeden büyük risk.
6. **FOMO ile tepe alımı:** Herkes konuşurken girmek.
7. **Acil fonsuz yatırım:** Kötü günde zorunlu satış.

**Ortak kök:** Duygu + plansızlık. Çözüm tek cümle: **yaz, çeşitlendir, az işlem yap, sabret.**

**Ders:** Yeni yatırımcının ilk hedefi "çok kazanmak" değil, **bu 7 hatadan kaçınmak** olmalı. Hatayı önlemek, getiri kovalamaktan daha güvenilir bir kazançtır.''',
        quiz: [
          _QuizQ(
            'Acemi kayıplarının ortak kökü nedir?',
            [
              'Şanssızlık',
              'Duygu + plansızlık',
              'Düşük komisyon',
              'Çok fazla çeşitlendirme'
            ],
            1,
            'Hataların çoğu plansız ve duygusal kararlardan doğar.',
          ),
          _QuizQ(
            'Yeni yatırımcının ilk hedefi ne olmalı?',
            [
              'En yüksek getiriyi kovalamak',
              'Bilinen temel hatalardan kaçınmak',
              'Kaldıraç kullanmak',
              'Günlük trade'
            ],
            1,
            'Hata önlemek, getiri kovalamaktan daha güvenilir ve '
                'kalıcıdır.',
          ),
        ],
      ),
    ],
  ),
];

/// Akademi içerik sayıları — profil ekranı alt-başlığı dinamik göstersin diye
/// dışa açık (eski sabit "19 ders, 4 kategori" içerik büyüdükçe bayatlamıştı).
int get academyCategoryCount => _categories.length;
int get academyLessonCount =>
    _categories.fold(0, (sum, c) => sum + c.lessons.length);

class EducationScreen extends StatefulWidget {
  const EducationScreen({super.key});

  @override
  State<EducationScreen> createState() => _EducationScreenState();
}

class _EducationScreenState extends State<EducationScreen> {
  static const _prefsKey = 'academy_read_v1';
  static const _quizKey = 'academy_quiz_v1';

  final _searchCtrl = TextEditingController();
  final Set<String> _read = {};
  final Set<String> _quizDone = {};
  String _query = '';

  static final List<_Lesson> _allLessons =
      _categories.expand((c) => c.lessons).toList();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q != _query) setState(() => _query = q);
    });
    _loadRead();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRead() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey) ?? const [];
    final savedQ = prefs.getStringList(_quizKey) ?? const [];
    if (!mounted) return;
    setState(() {
      _read
        ..clear()
        ..addAll(saved);
      _quizDone
        ..clear()
        ..addAll(savedQ);
    });
  }

  Future<void> _setRead(String id, bool read) async {
    setState(() {
      if (read) {
        _read.add(id);
      } else {
        _read.remove(id);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _read.toList());
  }

  Future<void> _markRead(String id) => _setRead(id, true);
  Future<void> _toggleRead(String id) => _setRead(id, !_read.contains(id));

  Future<void> _markQuizDone(String id) async {
    if (_quizDone.contains(id)) return;
    setState(() => _quizDone.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_quizKey, _quizDone.toList());
  }

  // Türkçe-duyarsız basit normalizasyon (arama eşleştirmesi için).
  static String _norm(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .replaceAll('Ş', 's')
      .replaceAll('ş', 's')
      .replaceAll('Ç', 'c')
      .replaceAll('ç', 'c')
      .replaceAll('Ö', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('Ü', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('Ğ', 'g')
      .replaceAll('ğ', 'g')
      .toLowerCase();

  bool _matches(_Lesson l, String q) {
    final n = _norm(q);
    return _norm(l.title).contains(n) || _norm(l.summary).contains(n);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final searching = _query.isNotEmpty;
    final total = _allLessons.length;
    final readCount = _read.length;
    final pct = total == 0 ? 0.0 : readCount / total;
    final quizTotal = _allLessons.where((l) => l.quiz.isNotEmpty).length;
    final quizDone = _quizDone.length;

    final lesson = _allLessons; // alias for daily pick
    final dayIdx =
        DateTime.now().difference(DateTime(2024)).inDays % lesson.length;
    final daily = lesson[dayIdx];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: AppColorsExt.of(context)
            .bg, // opak: şeffaf AppBar açık temada ghost bırakıyor
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Eğitim Akademisi',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                if (!searching) ...[
                  _ProgressHero(
                      readCount: readCount,
                      total: total,
                      pct: pct,
                      quizDone: quizDone,
                      quizTotal: quizTotal),
                  const SizedBox(height: 22),
                ],
                IOSGroupedCard(
                  children: [
                    IOSField(
                      controller: _searchCtrl,
                      label: 'Ders ara…',
                      icon: Icons.search,
                      suffix: searching
                          ? GestureDetector(
                              onTap: () => _searchCtrl.clear(),
                              child: Icon(Icons.close,
                                  color: c.textSubtle, size: 18),
                            )
                          : null,
                    ),
                  ],
                ),
                if (!searching) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 22, 4, 8),
                    child: _MiniHeader('GÜNÜN DERSİ', Icons.auto_awesome),
                  ),
                  _DailyCard(
                    lesson: daily,
                    read: _read.contains(daily.id),
                    onTap: () => _open(daily),
                  ),
                ],
                ..._buildCategories(c, searching),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCategories(AppColorsExt c, bool searching) {
    final out = <Widget>[];
    var anyMatch = false;
    for (final cat in _categories) {
      final lessons = searching
          ? cat.lessons.where((l) => _matches(l, _query)).toList()
          : cat.lessons;
      if (lessons.isEmpty) continue;
      anyMatch = true;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
        child: _MiniHeader(cat.name.toUpperCase(), cat.icon),
      ));
      out.add(IOSGroupedCard(
        children: lessons
            .map((l) => IOSListRow(
                  icon: l.icon,
                  title: l.title,
                  subtitle: l.summary,
                  onTap: () => _open(l),
                  trailing: _RowTrailing(
                      level: l.level,
                      read: _read.contains(l.id),
                      hasQuiz: l.quiz.isNotEmpty,
                      quizDone: _quizDone.contains(l.id)),
                ))
            .toList(),
      ));
    }
    if (searching && !anyMatch) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 40, 4, 0),
        child: Center(
          child: Text('“$_query” için ders bulunamadı',
              style: TextStyle(color: c.textSubtle, fontSize: 14)),
        ),
      ));
    }
    return out;
  }

  void _open(_Lesson l) {
    _markRead(l.id);
    showIOSBottomSheet(
      context: context,
      title: l.title,
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, controller) => _LessonSheet(
          lesson: l,
          controller: controller,
          isRead: () => _read.contains(l.id),
          isQuizDone: () => _quizDone.contains(l.id),
          onToggleRead: () => _toggleRead(l.id),
          onQuizPassed: () => _markQuizDone(l.id),
          bodyBuilder: (ctx) => _renderBody(ctx, l.body),
        ),
      ),
    );
  }

  // Zengin render — başlık, madde listesi, numaralı liste, "Etiket:" callout
  // kartı (gold vurgu) ve düz paragraf.
  Widget _renderBody(BuildContext context, String body) {
    final blocks = body.split('\n\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _block(context, b),
          ),
      ],
    );
  }

  Widget _block(BuildContext context, String raw) {
    final c = AppColorsExt.of(context);
    final p = raw.trim();
    if (p.isEmpty) return const SizedBox.shrink();
    final lines = p.split('\n');

    bool isBul(String l) => l.trimLeft().startsWith('- ');
    bool isNum(String l) => RegExp(r'^\s*\d+\.\s').hasMatch(l);

    // Opsiyonel: ilk satır tek başına **kalın başlık**
    String? heading;
    var rest = lines;
    final hm = RegExp(r'^\*\*(.+?)\*\*\s*$').firstMatch(lines.first.trim());
    if (hm != null && lines.length > 1) {
      heading = hm.group(1);
      rest = lines.sublist(1);
    }
    final items = rest.where((l) => l.trim().isNotEmpty).toList();
    final allBul = items.isNotEmpty && items.every(isBul);
    final allNum = items.isNotEmpty && items.every(isNum);

    if (allBul || allNum) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null) _heading(context, heading),
          for (final l in items)
            allBul
                ? _bulletLine(context, l.trim().substring(2))
                : _numLine(context, l.trim()),
        ],
      );
    }

    // "**Etiket:** açıklama" → vurgulu callout kartı
    final cm =
        RegExp(r'^\*\*([^*\n]{1,30}[:?])\*\*\s*([\s\S]+)$').firstMatch(p);
    if (cm != null) {
      return _calloutCard(context, cm.group(1)!, cm.group(2)!.trim());
    }

    return SelectableText.rich(
      _parseInline(context, p),
      style: TextStyle(color: c.textMuted, fontSize: 14, height: 1.6),
    );
  }

  Widget _heading(BuildContext context, String text) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text.replaceAll('*', ''),
          style: TextStyle(
              color: c.warmAccent,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1)),
    );
  }

  Widget _bulletLine(BuildContext context, String text) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, right: 10, left: 2),
            width: 5,
            height: 5,
            decoration:
                BoxDecoration(color: c.warmAccent, shape: BoxShape.circle),
          ),
          Expanded(
            child: SelectableText.rich(
              _parseInline(context, text),
              style: TextStyle(color: c.textMuted, fontSize: 14, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numLine(BuildContext context, String line) {
    final c = AppColorsExt.of(context);
    final m = RegExp(r'^(\d+)\.\s*(.*)$').firstMatch(line);
    final n = m?.group(1) ?? '•';
    final txt = m?.group(2) ?? line;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1, right: 10),
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: c.warmAccentSoft,
                borderRadius: BorderRadius.circular(6)),
            child: Text(n,
                style: TextStyle(
                    color: c.warmAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: SelectableText.rich(
              _parseInline(context, txt),
              style: TextStyle(color: c.textMuted, fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calloutCard(BuildContext context, String label, String rest) {
    final c = AppColorsExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: c.warmAccent,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: c.warmAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1)),
                    const SizedBox(height: 5),
                    SelectableText.rich(
                      _parseInline(context, rest),
                      style: TextStyle(
                          color: c.textMuted, fontSize: 13.5, height: 1.55),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _parseInline(BuildContext context, String text) {
    final c = AppColorsExt.of(context);
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*([^*]+)\*\*');
    int start = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
      ));
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return TextSpan(children: spans);
  }
}

/// Ders detay sayfası — gövde + mini test + okundu/okunmadı kontrolü.
class _LessonSheet extends StatefulWidget {
  final _Lesson lesson;
  final ScrollController controller;
  final bool Function() isRead;
  final bool Function() isQuizDone;
  final VoidCallback onToggleRead;
  final VoidCallback onQuizPassed;
  final Widget Function(BuildContext) bodyBuilder;
  const _LessonSheet({
    required this.lesson,
    required this.controller,
    required this.isRead,
    required this.isQuizDone,
    required this.onToggleRead,
    required this.onQuizPassed,
    required this.bodyBuilder,
  });

  @override
  State<_LessonSheet> createState() => _LessonSheetState();
}

class _LessonSheetState extends State<_LessonSheet> {
  late bool _read = widget.isRead();

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final l = widget.lesson;
    return SingleChildScrollView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: c.warmAccentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(l.icon, color: c.warmAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l.summary,
                    style: TextStyle(
                        color: c.textMuted, fontSize: 13, height: 1.4)),
              ),
              const SizedBox(width: 10),
              _LevelTag(l.level),
            ],
          ),
          const SizedBox(height: 18),
          widget.bodyBuilder(context),
          if (l.quiz.isNotEmpty) ...[
            const SizedBox(height: 10),
            _QuizBlock(
              questions: l.quiz,
              alreadyPassed: widget.isQuizDone(),
              onPassed: widget.onQuizPassed,
            ),
          ],
          const SizedBox(height: 20),
          // ── Okundu / okunmadı kontrolü ──────────────────────────
          GestureDetector(
            onTap: () {
              widget.onToggleRead();
              setState(() => _read = !_read);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _read ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: _read ? c.warmAccent : c.textSubtle,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _read ? 'Okundu olarak işaretli' : 'Henüz okunmadı',
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1),
                    ),
                  ),
                  Text(
                    _read ? 'Okunmadı işaretle' : 'Okundu işaretle',
                    style: TextStyle(
                        color: c.warmAccent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// İçinde tek tek cevaplanan, anında geri bildirimli mini test.
class _QuizBlock extends StatefulWidget {
  final List<_QuizQ> questions;
  final bool alreadyPassed;
  final VoidCallback onPassed;
  const _QuizBlock({
    required this.questions,
    required this.alreadyPassed,
    required this.onPassed,
  });

  @override
  State<_QuizBlock> createState() => _QuizBlockState();
}

class _QuizBlockState extends State<_QuizBlock> {
  late List<int?> _picked = List<int?>.filled(widget.questions.length, null);

  int get _answered => _picked.where((e) => e != null).length;
  int get _correct {
    var n = 0;
    for (var i = 0; i < widget.questions.length; i++) {
      if (_picked[i] == widget.questions[i].correct) n++;
    }
    return n;
  }

  void _pick(int qi, int oi) {
    if (_picked[qi] != null) return; // kilitli
    setState(() => _picked[qi] = oi);
    if (_answered == widget.questions.length) {
      final ratio = _correct / widget.questions.length;
      if (ratio >= 0.6) widget.onPassed();
    }
  }

  void _reset() => setState(
      () => _picked = List<int?>.filled(widget.questions.length, null));

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final total = widget.questions.length;
    final done = _answered == total;
    final passed = done && _correct / total >= 0.6;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_rounded, color: c.warmAccent, size: 18),
              const SizedBox(width: 8),
              Text('MİNİ TEST',
                  style: TextStyle(
                      color: c.warmAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
              const Spacer(),
              Text('$_answered/$total',
                  style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Öğrendiğini hızlıca sına. Bir şıkka dokun, anında doğruyu gör.',
            style: TextStyle(color: c.textSubtle, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < total; i++) ...[
            _question(c, i),
            if (i < total - 1) const SizedBox(height: 16),
          ],
          if (done) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color:
                    (passed ? c.positive : c.negative).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    passed ? 'Tebrikler! 🎓' : 'Tekrar dene',
                    style: TextStyle(
                        color: passed ? c.positive : c.negative,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text('$_correct / $total doğru',
                      style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _reset,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Testi sıfırla',
                      style: TextStyle(
                          color: c.warmAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ] else if (widget.alreadyPassed) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.verified_rounded, color: c.warmAccent, size: 15),
                const SizedBox(width: 6),
                Text('Bu testi daha önce geçtin',
                    style: TextStyle(color: c.textSubtle, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _question(AppColorsExt c, int qi) {
    final q = widget.questions[qi];
    final picked = _picked[qi];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${qi + 1}. ${q.q}',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.45,
                letterSpacing: -0.1)),
        const SizedBox(height: 10),
        for (var oi = 0; oi < q.options.length; oi++) _option(c, qi, oi, q),
        if (picked != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  picked == q.correct
                      ? Icons.check_circle_rounded
                      : Icons.info_rounded,
                  size: 15,
                  color: picked == q.correct ? c.positive : c.warmAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(q.explain,
                      style: TextStyle(
                          color: c.textMuted, fontSize: 12.5, height: 1.5)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _option(AppColorsExt c, int qi, int oi, _QuizQ q) {
    final picked = _picked[qi];
    final locked = picked != null;
    final isCorrect = oi == q.correct;
    final isPicked = picked == oi;

    Color bg = c.surfaceAlt;
    Color fg = c.textPrimary;
    IconData? mark;
    Color markCol = c.textSubtle;
    if (locked) {
      if (isCorrect) {
        bg = c.positive.withValues(alpha: 0.14);
        fg = c.positive;
        mark = Icons.check_rounded;
        markCol = c.positive;
      } else if (isPicked) {
        bg = c.negative.withValues(alpha: 0.14);
        fg = c.negative;
        mark = Icons.close_rounded;
        markCol = c.negative;
      } else {
        fg = c.textSubtle;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: locked ? null : () => _pick(qi, oi),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(q.options[oi],
                    style: TextStyle(
                        color: fg,
                        fontSize: 13.5,
                        fontWeight: locked && (isCorrect || isPicked)
                            ? FontWeight.w600
                            : FontWeight.w500,
                        height: 1.35)),
              ),
              if (mark != null) ...[
                const SizedBox(width: 8),
                Icon(mark, size: 17, color: markCol),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressHero extends StatelessWidget {
  final int readCount;
  final int total;
  final double pct;
  final int quizDone;
  final int quizTotal;
  const _ProgressHero(
      {required this.readCount,
      required this.total,
      required this.pct,
      required this.quizDone,
      required this.quizTotal});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AKADEMİ İLERLEMEN',
            style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$readCount',
                style: TextStyle(
                    color: c.warmAccent,
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5)),
            const SizedBox(width: 4),
            Text('/ $total ders',
                style: TextStyle(
                    color: c.textSubtle, fontSize: 15, letterSpacing: -0.2)),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: c.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(c.warmAccent),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          readCount >= total && total > 0
              ? 'Tüm dersleri tamamladın 🎓'
              : '%${(pct * 100).round()} tamamlandı · okudukça işaretlenir',
          style:
              TextStyle(color: c.textSubtle, fontSize: 13, letterSpacing: -0.1),
        ),
        if (quizTotal > 0) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.quiz_rounded, color: c.textSubtle, size: 14),
              const SizedBox(width: 6),
              Text('$quizDone / $quizTotal mini test geçildi',
                  style: TextStyle(
                      color: c.textSubtle, fontSize: 13, letterSpacing: -0.1)),
            ],
          ),
        ],
      ],
    );
  }
}

class _MiniHeader extends StatelessWidget {
  final String text;
  final IconData icon;
  const _MiniHeader(this.text, this.icon);

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Row(
      children: [
        Icon(icon, color: c.textMuted, size: 17),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.6)),
      ],
    );
  }
}

class _LevelTag extends StatelessWidget {
  final _Level level;
  const _LevelTag(this.level);

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(level.label,
          style: TextStyle(
              color: c.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2)),
    );
  }
}

class _RowTrailing extends StatelessWidget {
  final _Level level;
  final bool read;
  final bool hasQuiz;
  final bool quizDone;
  const _RowTrailing(
      {required this.level,
      required this.read,
      this.hasQuiz = false,
      this.quizDone = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasQuiz) ...[
          Icon(
            quizDone ? Icons.verified_rounded : Icons.quiz_outlined,
            color: quizDone ? c.warmAccent : c.textSubtle,
            size: 15,
          ),
          const SizedBox(width: 8),
        ],
        _LevelTag(level),
        const SizedBox(width: 8),
        read
            ? Icon(Icons.check_circle_rounded, color: c.warmAccent, size: 18)
            : Icon(Icons.chevron_right_rounded, color: c.textSubtle, size: 22),
      ],
    );
  }
}

class _DailyCard extends StatelessWidget {
  final _Lesson lesson;
  final bool read;
  final VoidCallback onTap;
  const _DailyCard(
      {required this.lesson, required this.read, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: c.warmAccentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(lesson.icon, color: c.warmAccent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(lesson.title,
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2)),
                      ),
                      const SizedBox(width: 8),
                      _LevelTag(lesson.level),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(lesson.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12,
                          letterSpacing: -0.1)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            read
                ? Icon(Icons.check_circle_rounded,
                    color: c.warmAccent, size: 20)
                : Icon(Icons.chevron_right_rounded,
                    color: c.textSubtle, size: 22),
          ],
        ),
      ),
    );
  }
}
