# Cihaz Doğrulama Listesi

> **Ne bu:** 42–53. turlardan birikmiş, telefonda/tarayıcıda elle doğrulanması gereken
> işlerin tek listesi. Kod tarafı bitti, canlıda gözle görülmedi.
> **Kim:** Yalnız Kerem (cihaz gerektirir).
> **Kaynak:** `SESSION_HANDOFF.md` tur özetleri + `GELISTIRME_ONERILERI.md`, koddan doğrulanarak ayıklandı.
> **Güncelleme:** 7 Eylül 2026 (11. tur). Kutuyu işaretledikçe ilerle; biten bölümü sil.

---

> **3 Eylül 2026 — Claude tarayıcıdan bir kısmını doğruladı.** İşaretli `[x]`
> maddeler canlı web'de (Chrome eklentisi) veya backend ucundan görüldü; ayrıntı
> ve ölçümler `SESSION_HANDOFF.md` 3 Eylül bölümünde. **Telefon/PWA + dokunma
> kontrolü hâlâ Kerem'de** — işaretliler de gerçek cihazda bir kez görülmeli.
> Ayrıca o turda **6 yeni bulgu** çıktı (emtia "%0,00", `.FON` soneki sızması,
> yinelenen açılış isteği vb.) — **hepsi 3 Eylül ikinci turda DÜZELTİLDİ**;
> deploy sonrası bakılacaklar aşağıda "A0" bölümünde.

---

## B12. 7 Eylül 12. tur — güvenlik (EN YENİ)

> Kod canlıda (`f44011e`). ⚠️ **Hesabımı Sil'i GERÇEKTEN silmek için kullanma**
> — kendi hesabın gider. Ekranı gör, şifre alanını boş bırakıp hata mesajını
> dene, sonra Vazgeç.

- [ ] Profil → en altta sönük **"Hesabımı Sil"** bağlantısı görünüyor
      (çıkış butonu kadar dikkat çekmiyor ama saklı da değil)
- [ ] Basınca açılan sheet neyin silineceğini yazıyor (portföy, işlem geçmişi,
      izleme, notlar, alarmlar) ve **şifre** istiyor
- [ ] Şifre boşken "Şifreni gir", yanlış şifreyle **"Şifre yanlış"** çıkıyor
- [ ] **Vazgeç** ile çıkılıyor, hesap duruyor
- [ ] Kayıt ekranında şifre kuralı artık **8 karakter** diyor; 6 karakterlik
      şifre kabul edilmiyor
- [ ] `password` / `12345678` gibi bir şifreyle kayıt denendiğinde
      "Bu şifre çok yaygın kullanılıyor" uyarısı geliyor
- [ ] Mevcut hesabınla giriş **hâlâ çalışıyor** (kural geçmişe dönük değil —
      `umut@mail.com` / `123456` girişi bozulmamalı)

---

## B11. 7 Eylül 11. tur — ilk dış kullanıcının maddeleri (EN YENİ)

> Kod canlıda (`86a8005` deploy edildi, uçlar curl ile doğrulandı). Kalan:
> **telefonda gözle görmek**. PWA'da önce **cache temizliği + `?cb=`** şart.

**Fiziki altın (Batuhan'ın ana isteği)**
- [ ] Portföy → pozisyon ekle → aramaya **"çeyrek"** yaz → "Çeyrek Altın ·
      FİZİKİ" çıkmalı (ayrıca dene: "gram altın", "bilezik", "gram gümüş")
- [ ] Seç → miktar alanı **"Miktar (adet)"** demeli (gram altında **"(gram)"**),
      maliyet alanı "Adet maliyeti" / "Gram maliyeti"
- [ ] 5 adet + maliyet gir → portföyde satır **₺** ile görünmeli
      (5 × ~11.100 ≈ 55.500 ₺). **$ görürsen ya da 40 katı bir rakam görürsen
      DUR ve söyle** — para birimi hatası olur
- [ ] Sektör donut'unda **"Altın"** dilimine düşmeli (kâğıt altın GC=F ile aynı)
- [ ] Satıra bas → hisse detayında grafik yerine *"Fiziki altının geçmiş fiyat
      grafiği yok…"* yazmalı ("Grafik verisi alınamadı" DEĞİL)
- [ ] Sinyaller sekmesinde fiziki altın **çıkmamalı** (mumu yok, skor uydurulmaz)
- [ ] Pozisyonu sil (sola kaydır) → temiz gitmeli

**Fiziki altın ekranı — 12. turda düzeltilenler (canlı web'de görüldü, telefonda bakılacak)**
- [ ] Çeyrek Altın detayında **zaman aralığı seçici (1dk…Haftalık) ve "Pro"
      butonu OLMAMALI** (serisi yok, boş grafiğe götürüyordu)
- [ ] Aynı ekranda **"AI Teknik Tahmin" / "AI Temel Analiz" kartları
      OLMAMALI** (mumu ve bilançosu yok)
- [ ] "Pozisyon Ekle" alt yazısı "lot" değil **"Elindeki miktarı"** demeli
- [ ] Aramada satır başlığı ham sembol değil **"Çeyrek Altın"** olmalı
      (fon aramasında da "TLY.FON" değil "TLY")
- [ ] Hisse/kripto detayında aralık seçici ve AI kartları **eskisi gibi
      DURMALI** (regresyon kontrolü)

**Sektör ayrıştırma**
- [ ] Portföyünde küçük bir BIST hissesi varsa (BNTAS, KLKIM, ISDMR…) sektör
      donut'unda artık **"Diğer"de olmamalı** (BNTAS → Ambalaj; canlıda
      doğrulandı, cihazda gözle bak)
- [ ] Donut'ta dilim sayısı arttı — okunabilir mi, "Diğer" küçüldü mü

**Şifre değiştirme**
- [ ] Profil → Ayarlar → **Şifre Değiştir**
- [ ] Yanlış mevcut şifre → "Mevcut şifre yanlış"
- [ ] Doğru şifre + eşleşen yeni şifre → başarı mesajı, **ekrandan atılmamalısın**
- [ ] Çıkış yap → **yeni** şifreyle gir (eski şifre çalışmamalı)

**Arama ipucu**
- [ ] Arama kutusunun gri metni "Ara — THYAO, Apple, çeyrek altın, katılım fonu…"
- [ ] "katılım" yaz → TEFAS katılım fonları listelenmeli (270 fon zaten vardı)

**PWA / "indirip kullanma" (Batuhan'a cevap vermeden önce)**
- [ ] Android Chrome → menü → **"Uygulamayı yükle"** görünüyor mu; kurulunca
      adres çubuğusuz, kendi ikonuyla açılıyor mu
- [ ] iPhone Safari → Paylaş → **Ana Ekrana Ekle** → aynı kontrol
- [ ] Kurulu uygulamanın adı **"Portly"** ve açıklaması artık "sanal borsa
      simülatörü" DEĞİL

---

## A0000000. 4 Eylül 8. tur — hata kartları + ekran görüntüsü CTA'sı (en yeni)

> ⚠️ **Bu bölüm ancak commit + push + deploy sonrası bakılabilir** (8. tur
> henüz commit'siz). Kod: boş-durum ile hatayı ayıran `LoadErrorCard`.
> **Nasıl denenir:** uygulama açıkken telefonu **uçak moduna** al ve ekranı
> aşağı çekerek yenile (ya da sunucu uykudayken ilk açılışı dene).

- [ ] **Portföy** yenilenemezse "Portföy yüklenemedi" + **Tekrar Dene** çıkmalı —
      "BAŞLANGIÇ / ilk hisseni ekle" rehberi ÇIKMAMALI
- [ ] **Ana ekran** izleme listesi çekilemezse "Fiyatlar alınamadı" + Tekrar
      Dene — "Listen boş" DEMEMELİ
- [ ] **Alarmlar** ve **Notlarım** aynı şekilde "… yüklenemedi" + Tekrar Dene
- [ ] Tekrar Dene'ye bas → ağ geri geldiğinde veri gelmeli, kart kaybolmalı
- [ ] **Gerçekten boş** durumda (yeni hesap / hiç not yok) eski boş-durum metni
      AYNEN durmalı — hata kartı çıkmamalı
- [ ] **Boş portföy ekranında** "Ekran Görüntüsünden Aktar" butonu görünüyor;
      basınca Portföyümü Gir ekranı açılıyor ve oradaki OCR akışı çalışıyor
- [ ] **AI Koç'a soru sor** → cevap eskisi gibi akıyor (backend akışı iş
      parçacığına taşındı; regresyon olmamalı). Bonus: AI yazarken başka bir
      sekmeye geç (Portföy/Sinyaller) — **artık beklememeli**
- [ ] **Satış kaydet** (hisse detay → Satış Kaydet) → buton "Kaydediliyor…"
      diye dönmeli, sheet cevap gelince kapanmalı; iki kez basılamamalı

## A000000. 4 Eylül 7. tur — SİNYALLER hızlandı mı

> Kod canlıda (`95b05c4`). Soğuk `/signals` **20,7 sn** ölçülmüştü; kök sebep
> temel oran cache'inin 12 saatte toplu ölmesiydi. Artık bayat oran anında
> servis edilip arka planda tazeleniyor.
> **ZAMANLAMA ÖNEMLİ:** deploy günü (4 Eyl öğlen) cache sıcaktı, yavaşlık zaten
> görünmezdi. Gerçek sınav **4 Eylül akşamı 20:00'den sonra ya da 5 Eylül
> sabahı** — oranlar o zaman bayatlıyor.

- [ ] **Sinyaller** sekmesini aç (uygulamayı bir süre kullanmadıktan sonra) →
      liste **birkaç saniye içinde** gelmeli, 20 saniye BEKLETMEMELİ
- [ ] Listede sembol sayısı eskisi gibi (**51**) ve "sinyal üretilemedi" uyarısı
      YOK
- [ ] Hisselerde temel oran gerekçeleri (F/K, ROE) hâlâ görünüyor — hepsi birden
      "Temel oran verisi şu an yok" DEMEMELİ (öyleyse Claude'a söyle: geçici
      kaynak hatası iyi kaydın üstüne yazıyor olabilir)
- [ ] Yavaşsa: süreyi söyle, Claude token'la `/signals` ölçümünü tekrarlasın

## A00000. 4 Eylül 6. tur — canlı geri bildirim düzeltmeleri (en yeni)

> Kod canlıda (`608fe7e`). **Safari'de sert yenileme `⌥⌘R`** (Cmd+Shift+R
> Safari'de yok) ya da adrese `?cb=` ekle — PWA cache inatçı.

- [ ] **AI Koç'a yeni bir soru sor** → cevapta `GC=F` · `TLY.FON` · `KARCL.IS`
      gibi ham kodlar GEÇMEMELİ ("Altın", "TLY", "KARCL" yazmalı)
- [ ] Cevap gelirken **"Yanıt hazırlanıyor…"**, yazarken **"yazıyor"** görünüyor
- [ ] **Haberler → Portföyüm**: BIST haberleri gözle arttı mı (ölçüm: TR payı
      18 → 40 haber). Hangi BIST sembollerinin haberi hâlâ yoksa not al
- [ ] **Portföy** daha çabuk geliyor (ölçüm: 5,8 sn'ye çıkabiliyordu → ~1 sn)
- [ ] **Çıkış yap → tekrar giriş**: ilk denemede "Sunucu hatası" ÇIKMAMALI
      (uyanma toleransı); çıkarsa mesaj "uyku modundan uyanıyor olabilir" gibi
      sade olmalı, ham `TimeoutException` DEĞİL
- [ ] Uzun süre açık bırakıp dön: oturum düşerse ekranda ham Dart hatası
      ("Null check operator...") ÇIKMAMALI

## A0000. 4 Eylül 6. tur — AI GERİ GELDİ Mİ (en yeni, en kritik)

> Kod canlıda (`366e7c2`, push 4 Eyl). Bu turda **tüm AI özelliklerinin ölü
> olduğu** ortaya çıktı: kodda sabitlenmiş iki Gemini modeli de 404 "no longer
> available to new users" veriyordu. Model adları takma ada çevrildi.
> **Aşağıdakiler AI'nın gerçekten döndüğünün kanıtı — hepsi kısa.**

- [ ] **AI Koç'a mesaj yaz** ("portföyüm nasıl?") → cevap **akıyor**
      (eskiden "Bağlantı koptu" ya da boş dönüyordu)
- [ ] Hisse detay → **AI Temel Analiz** ve **AI Teknik Tahmin** açılıyor,
      "yüklenemedi" demiyor
- [ ] Haber listesi → bir habere gir → **AI Piyasa Etkisi** çalışıyor
- [ ] Hata çıkarsa artık **"Tekrar Dene" butonu var** → basınca yeniden
      deniyor (sheet'i kapatıp açmak gerekmiyor). Hisse detayındaki AI
      sheet'lerinde de aynı buton çalışıyor (eskiden debug derlemede sessizce
      hiçbir şey yapmıyordu)
- [ ] Haberler → **Portföyüm**: aynı sekmeyi **iki kez** aç. İkinci açılışta
      haber sayısı **belirgin düşmemeli** ve ilk açılışta haberi görünen bir
      sembol ikincide **tamamen kaybolmamalı** (6. turun `_restore_silenced_symbols`
      garantisi)

## A000. 3 Eylül 5. tur — DEPLOY SONRASI bakılacaklar

> ✅ 4 Eylül'de push edildi (`75efa91` + `6a0f149`), deploy canlı — bölüm artık
> geçerli.

**Haber (asıl şikâyet: "çok az haber geliyor"):**
- [ ] Haberler → **Portföyüm** sekmesinde haber sayısı gözle **belirgin arttı**
      (ölçüm: sunucudan 34 → 61-76; ekranda 18 → çoğu). Az geldiyse hangi
      sembollerin haberi yok, not al
- [ ] Listede **BIST + ABD + fon** karışık görünüyor (eskiden yalnız birkaç
      sembol vardı: altın · PLTR · LMT · GLRMK)
- [ ] Haber sekmesi **ilk açılışta** makul sürede geliyor (~3-10 sn; Render
      uykudaysa ilk istek 30-50 sn — bu ayrı konu)
- [ ] İkinci açılış **hızlı** (cache) ve haber sayısı **DÜŞMÜYOR**
- [ ] Haber başlıkları gerçekten portföydeki şirketlerle ilgili (alakasız
      haber sızdıysa `matched_query` eşlemesi fazla geniş demektir → not al)

**Oturum içi 401 (uygulamayı UZUN süre açık bırakma testi):**
- [ ] Uygulamayı aç, **60 dakikadan fazla** açık bırak (telefonda PWA arka
      planda kalabilir), sonra dön → portföy · haber · izleme · AI Koç
      **yeniden başlatmadan** çalışıyor (eskiden hepsi 401'e düşüyordu)
- [ ] Aynı testte **AI Koç'a mesaj yaz** → "Sunucu hatası (401)" GELMEMELİ
- [ ] Çıkış yap → giriş ekranında **KALIYOR** (401 kurtarması oturumu geri
      diriltmemeli — 4. turdaki düzeltmeyle çakışmadığının kanıtı)

## A00. 3 Eylül 4. tur — canlıda İLK bakılacaklar (en yeni)

> Kod canlıda (`6890be7`, push 3 Eyl). Bu turda **iki migration** koştu ve
> **para gösterimi değişti** — aşağıdakiler bu yüzden öncelikli.

**Para/portföy (en kritik — rakamlar DEĞİŞTİ):**
- [ ] Portföy hero'sunda **"Kur payı"** satırı görünüyor (USD pozisyonu olan
      kullanıcıda). Etkisi toplam K/Z'nin %1'inden azsa satır ÇIKMAZ — normal.
- [ ] **Toplam ₺ K/Z ARTMIŞ** olmalı (USD varlıklarda kur kazancı artık K/Z'ye
      giriyor). "Bugün" satırı değişmemeli.
- [ ] "Kur payı" + varlığın kendi kazancı ≈ Toplam K/Z (gözle tutarlı mı)
- [ ] **BIST/fon pozisyonlarında hiçbir rakam değişmedi** (₺ varlık kur yolunu
      hiç kullanmaz — regresyon nöbetçisi)
- [ ] Portföyde **aynı sembol iki kez GÖRÜNMÜYOR** (benzersiz kısıt + migration
      çift satırları birleştirdi; varsa migration birleştirmiş olmalı)

**Erişim:**
- [ ] Haber sekmesi **açılıyor** (uçlar artık giriş istiyor — token gitmiyorsa
      haberler boş gelir; en olası regresyon noktası burası)
- [ ] Hisse detayda **AI Piyasa Etkisi** çalışıyor (aynı uç, artık auth'lu)
- [ ] Çıkış yap → **giriş ekranında KALIYOR** (eskiden arka plandaki oturum
      doğrulaması kullanıcıyı geri içeri alabiliyordu)
- [ ] Çıkış sonrası tekrar giriş sorunsuz

**Sohbet:**
- [ ] AI Koç'ta cevap akarken **ekranı kapat** → uygulama takılmıyor, sonraki
      açılışta sohbet normal (zamanlayıcı sızıntısı düzeltildi)

**Şifre sıfırlama (Brevo anahtarları girildiyse):**
- [ ] Kodu **3 kez yanlış** gir → 4. denemede DOĞRU kod da reddedilmeli,
      "yeni kod iste" gerekmeli

---

## A0. 3 Eylül düzeltmeleri — deploy sonrası ilk bakılacaklar

Kod canlıda (`3839743`, Render deploy doğrulandı) ve **3 Eylül'de tarayıcıda
(Chrome + Kerem'in kaydırmasıyla) doğrulandı** — aşağıdaki `[x]`'ler onun sonucu.
**Telefon/PWA'da bir kez daha görülmeli** (dokunma + küçük ekran); önce bölüm 0.

- [x] **Emtiada sahte "%0,00" gitti**: portföyde `Emtia · 1` → **Altın
      $4.469,60 · Bugün +2,37%** (gerçek değişim; "GC=F" değil "Altın")
      _(3 Eyl, tarayıcı)_
- [x] Emtianın günlük değişimi **makul** (izleme listesinde de +2,39%)  _(3 Eyl)_
- [x] Hero'daki **"Bugün"** toplamı gerçek: +0,98% · +₺23.365,07  _(3 Eyl)_
- [x] **`.FON` soneki hiçbir yerde yok**: portföyde "LTL"/"TLY", sinyal kartı
      başlığı "LTL". ⚠️ BIST satırları eskisi gibi "ZOREN.IS"/"KARSN.IS"
      kalmış (bilinçli davranış korunuyor)  _(3 Eyl)_
- [x] **Sinyal kartında fon fiyatı** portföydekiyle AYNI: `LTL` → **₺1,0893**
      (₺1,09 değil)  _(3 Eyl)_
- [~] **Açılış istek sayısı**: `/watchlist` artık **×1** ✅ · toplam 6→**5** ·
      ama `/market/prices` hâlâ **2 kez** — dedup kaçırması DEĞİL, ilk istek
      giriş ÖNCESİ yanlış listeyle gidiyor (8 sembollük varsayılan; sonra 16
      sembollük gerçek liste). Kalan iş handoff'ta madde 1  _(3 Eyl)_
- [x] **İlk girişte şirket adı**: izleme listesi ilk boyamada "Micron
      Technology Inc" / "Alphabet Inc" — sembol-sembol görünmedi  _(3 Eyl)_
- [x] **İngilizce haberde kumar spamı yok**: `en|bitcoin` → 14 haber, 0 kumar
      başlığı, kaynaklar gerçek (Bloomberg · Fortune · Benzinga · Investing ·
      crypto.news); haber sayısı düşmedi  _(3 Eyl, backend ucu)_
- [ ] **Telefonda** (PWA): yukarıdakilerin hepsi küçük ekranda da doğru mu

## 0. ÖN KOŞUL — önce bunu yap

Bu adım atlanırsa **çalışan kod bozuk görünür**. 47. turda tam olarak bu oldu:
iki madde zaten doğruydu, eski PWA cache yüzünden "düzelmedi" sanıldı.

- [ ] Ana ekrandaki Portly PWA kısayolunu **sil**
- [ ] Tarayıcı → site verilerini temizle (Safari: Ayarlar > Safari > Gelişmiş > Web Sitesi Verileri > portly sil)
- [ ] Adresi **cache-buster ile** aç: `https://<frontend-url>/?cb=1`
- [ ] Backend'in uyandığını doğrula (Render free tier soğuk başlangıç ~30-50 sn) — ilk istek yavaşsa normal

---

## A. Sinyaller sekmesi (pivotun ana ürünü — en kritik bölüm)

- [x] Sekme açılıyor, **soğuk tarama** makul sürede bitiyor (timeout 60 sn; portföy+izleme sembol sayısına bağlı)  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [x] Filtre pilleri çalışıyor: TÜMÜ / AL / TUT / SAT + her pilde **sayaç doğru**  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [x] Kart içeriği tam: sinyal rozeti · kaynak (Portföy/İzleme) · fiyat · skor · "Teknik X · Temel Y"  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [ ] Gerekçe 2'den fazlaysa **dokun-genişlet** açılıyor
- [ ] Aşağı çekince yenileniyor (`force=true`) ve skor güncelleniyor
- [ ] **Boş durum**: portföy ve izleme listesi boşken ekran düzgün mü (çökme/boş beyaz yok)
- [ ] **Hata durumu**: uçak modunda açınca anlamlı mesaj mı
- [x] Veri çekilemeyen semboller liste altında `failed` olarak görünüyor, tarama çökmüyor  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [x] "Yatırım tavsiyesi değildir" uyarısı listenin altında görünüyor  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_

---

## B. Portföy ve pozisyon akışı

- [ ] **Pozisyon Ekle** (hisse detay > Portföyüm > manuel sheet): lot + maliyet girip kaydet → portföyde çıkıyor
- [ ] **Satış Kaydet**: elde varken sheet açılıyor, lot girilebiliyor, **"Tümü" çipi** tüm pozisyonu dolduruyor
- [ ] **İzlemeye Al / Çıkar** toggle hisse detayında doğru durumu gösteriyor
- [x] **Sanal bakiye kalıntısı YOK**: portföy hero'da "Bakiye" düzenleme, "Nakit" bölümü, ana sayfa Nakit çipi, profil "Nakit Bakiye" — hiçbiri görünmemeli  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [x] Toplam varlık = toplam pozisyon değeri (nakit eklenmiyor)  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [x] Hero'da **Bugün** ve **Toplam** PnL iki ayrı satır, işaret/yüzde doğru  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [x] **Sektör kırılımı** (Portföy > Sektör): "Diğer" oranı düşük mü (fix sonrası %48 → %3.6 bekleniyor)  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [x] Donut grafiği dar ekranda taşmıyor (Hisseler / Sektör / Borsa üçü de)  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [ ] **İzleme listesi senkronu**: ekle/sil/sırala → uygulamayı kapat-aç kalıcı mı · ikinci cihazda görünüyor mu

---

## C. Hisse detay ekranı

- [ ] **Piyasa Öncesi / Sonrası chip** — ABD hissesinde (AAPL) pre/post-market saatinde görünüyor mu, fiyat oynuyor mu
      _(Not: yalnız ABD + tek sembol yolunda var. Portföy/izleme listesinde YOK, bilinçli. BIST'te çıkmaması normal.)_
- [ ] Pre/post fiyatı **`current_price`'ı bozmuyor** (ana fiyat kapanış değeri kalıyor)
- [ ] AI Temel Analiz açılıyor, **sonsuz spinner yok**; hata durumunda "AI yoğun, tekrar dene" çıkıyor
- [ ] **BIST hissesinde** (THYAO.IS) oran tablosu: Finnhub ücretsiz katman ABD-only olduğu için "—" bekleniyor.
      Ekran bunu **anlamlı gösteriyor mu**, yoksa boş "——" dizisi mi? (dizi ise → düzeltilecek, `GELISTIRME_ONERILERI` 48b/4)
- [ ] ABD hissesinde (NVDA/AAPL) oranlar **gerçek** geliyor (F/K, ROE, marj)
- [ ] **Varlık sınıfı ayrımı**: `BTC-USD` · `GC=F` (Altın) · `USDTRY=X` → AI yorumu sınıfa uygun mu (hisse jargonu kullanmıyor mu)
- [ ] Grafik: **Günlük (1d)** aralığı açılıyor (eskiden 500 veriyordu), 1wk/5m de çalışıyor
- [ ] Grafik çizim araçları (Faz 2) telefonda kullanılabilir mi
- [ ] **Notlarım** bölümü: not ekle → kapat-aç kalıcı mı · sembol filtresi doğru mu · düzenle/sil çalışıyor mu

---

## D. Haberler

- [x] **BIST çöp filtresi**: TradingView / "teknik analiz" / "teknik ve temel analiz" başlıkları **gitti mi**  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [ ] İlk açılış **hızlı** (ham sonuç hemen geliyor, LLM zenginleştirme arka planda)
- [ ] Haber **sayısı yeterli** (sembol başına cap 10; eskiden "13 Mayıs'a iniyordu")
- [x] **ABD/kripto** haberleri İngilizce orijinal kaynak mı (Reuters/Bloomberg), makine çevirisi agregatör değil  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [x] **BIST** haberleri Türkçe basından mı  _(3 Eyl: Claude tarayıcıda/backendde doğruladı)_
- [ ] Nötr haberler **sönük nokta + "Nötr"** olarak mı (dolu gri "Nötr 0.00" rozeti kalmamalı)
- [ ] Liste rozetinde **"Ton"**, detayda **"AI Piyasa Etkisi"** ayrımı net mi
- [ ] Türkçe başlıklarda sentiment hep "Nötr" değil (TR sözlük devrede)
- [ ] Haberdeki "Etkilenen Varlıklar" çipine dokununca ilgili hisseye gidiyor mu

> **Bilinen davranış:** 2. açılışta LLM alaka filtresi bazı haberleri eleyebilir → ilkinden
> biraz AZ haber görünebilir. Bu normal (SWR). Sürekli "az" geliyorsa filtreyi gevşetmek gerekir.

---

## E. Onboarding, gezinme, genel UI

- [ ] İlk açılışta **onboarding turu** çıkıyor, Atla ve Başla çalışıyor
- [ ] Tur **bir daha çıkmıyor** (çıkış yapmak tetiklemiyor; tekrar görmek için site verisini silmek gerekir)
- [ ] Onboarding metinleri **pivot sonrası** doğru mu (sanal borsa/işlem anlatan sayfa kalmamalı)
- [ ] Alt menü 4 sekme: Ana Sayfa · Haberler · **Sinyaller** · Portföy ("İşlem" sekmesi kalmamalı)
- [ ] **Logo** her yerde: AppBar başlığı · giriş ekranı · onboarding ilk sayfa · ana ekran ikonu
- [ ] **AI Koç FAB**: basılı tut + sürükle taşınıyor · hızlı sürüklemede parmağı **takip ediyor** (geride kalmıyor) · tek dokunuş sohbeti açıyor · yeniden açılışta sağ-alta dönüyor
- [ ] **AI sohbet**: yanıt **tam** geliyor (cümle yarıda kesilmiyor) · aynı mesaj **iki kez** görünmüyor
- [ ] Sohbette *"hangi hisseyi almalıyım?"* → gerekçeli öneri + "tavsiye değil" uyarısı
- [ ] Profil altında yalnız **"Portly"** yazıyor (v1.0 yok)
- [ ] Karanlık/aydınlık tema geçişi her ekranda düzgün

---

## E2. Banka Altın ekranı (1 Eyl düzeltmeleri)

**Backend canlı uçtan doğrulandı:** sahte `%0,00` gizleme mantığı + kaynak
erişilemediğinde son iyi listenin korunması (14 birim testi). **Ekranın kendisi
cihazda görülmedi** — aşağısı senin kontrolün.

- [ ] Hero'da gram altın fiyatının **altında değişim yüzdesi** görünüyor (eskiden hiç yoktu)
- [ ] Banka tablosunda **Makas sütunu artık TL** (`₺136`), yüzde değil — kaydırıp başlık kaybolunca bile "günlük değişim" diye okunmuyor
- [ ] Liste TL makasa göre küçükten büyüğe sıralı, en iyi banka vurgulu
- [ ] **Alış/Satış sütunları nötr renkte** (yeşil/kırmızı kalktı)
- [ ] Bölüm başlığı **"Altın ve Gümüş (Serbest Piyasa)"**, listenin sonunda **Gümüş** var (gram fiyatı, ~100 TL)
- [ ] Altın Ürünleri'nde artık **sahte `%0,00` YOK**; kaynak o ürünü güncellememişse yerinde **"bugün güncellenmedi"** yazıyor
- [ ] Gram Has Altın / Cumhuriyet / Gram Platin gibi gerçekten değişen ürünlerde **yüzde görünmeye devam ediyor** (yanlışlıkla hepsi gizlenmemiş)
- [ ] Gram altın gerçekten yatay seyrederse (`%0,00`) o zaman yüzde **nötr renkte** görünüyor, yeşil değil

---

## F. Yan modüller (Profil > Araçlar)

- [ ] **What-If**: arama sonrası öneri çıkıyor · "Bitiş tarihi seç" sade mi
- [ ] **Stres testi**: Rusya-Ukrayna + İran-Ortadoğu sekmeleri · **zayıf halka senaryolar arası değişiyor mu** · sonuç cümlesi anlaşılır mı
- [ ] **AI Portföy Kurucu**: öneri çeşitleniyor mu (her seferinde aynı 5 hisse değil) · "öneri" dili kullanıyor mu
- [ ] **Akademi**: "45 ders, 12 kategori" doğru mu, dersler açılıyor mu
- [ ] **Temettü** ekranı: veri geliyor mu · hata ≠ boş portföy ayrımı doğru mu
- [ ] **Mum Tahmin Pratiği**: oynanabilir mi, skor/seri tutuyor mu
- [ ] **Fiyat alarmı**: alarm kur → tetiklenince rozet/bildirim geliyor mu
- [ ] **Screenshot ile portföy içe aktarma**: görsel yükleniyor mu (415 hatası yok), semboller doğru okunuyor mu
- [ ] **İşlem Geçmişi > CSV**: mobilde native paylaşım açılıyor mu (401 yok), webde dosya iniyor mu
- [ ] **Korku & Açgözlülük** göstergesi veri gösteriyor mu
- [ ] **Karşılaştırma** (BIST100/S&P/dolar/altın/mevduat/enflasyon) doğru çiziliyor mu

---

### Ekstreden İçe Aktarma (Portföy > "Ekstreden İçe Aktar")

**Web'de TARAYICIDA DOĞRULANDI (1 Eyl):** yerel backend + Chrome ile gerçek Midas
ekstreleri (Haziran+Temmuz 2026) uçtan uca yüklendi → 31 işlem · 25 pozisyon ·
6 iptal emri atlandı → 24 pozisyon aktarıldı (EOSER maliyetsiz olduğu için atlandı),
DB'de LHX `0,802980132 adet / 362,40 USD` ekstredekiyle birebir eşleşti.
**Telefonda doğrulanmadı** (özellik zaten yalnız web'de; mobilde buton gizli).

Kalan cihaz kontrolleri:

- [ ] Telefonda: Portföy > "Ekstreden İçe Aktar" açılıyor, buton YOK, "yalnız web sürümünde" açıklaması var
- [ ] Web'de kalem ikonuyla adet/maliyet düzenleme → kaydedince listeye yansıyor (Türkçe biçim: "362,40" yazıp kaydet)
- [ ] Bozuk/PDF olmayan dosya seçilince anlamlı hata, diğer dosyalar yine işleniyor
- [ ] Aynı ekstre ikinci kez aktarılınca "zaten güncel" diyor, lotlar katlanmıyor
- [ ] 36'dan fazla dosya seçilince sınır uyarısı çıkıyor
- [ ] **Midas dışı bir kurumun ekstresi**: okunabiliyorsa turuncu "Tahmini okuma" uyarısı çıkıyor ve özet kartında kurum adı görünüyor; okunamıyorsa kurumun adıyla net hata veriyor
- [ ] **Ekstre olmayan bir PDF** (fatura/fiş): "aracı kurum ekstresine benzemiyor" hatası, boş önizlemeye GEÇMİYOR
- [ ] **Aktar'a basınca**: buton spinner'da kalıyor → sonuç mesajı → portföy ekranına DÖNÜYOR. Arada ölü/siyah ekran YOK (yenileme artık beklenmiyor; portföy kendi yükleniyor durumunu gösterir)

---

## G. Kimlik doğrulama

- [ ] **Şifre sıfırlama maili GELİYOR mu** — endpoint 200 dönüyor ama mail gitmiyordu.
      Bloker: Umut'un Render'a `BREVO_API_KEY` + `BREVO_SENDER_EMAIL` eklemesi gerekiyor.
      _(Eski "SMTP_USER/PASSWORD ekle" notu geçersiz — Render SMTP portlarını bloklar.)_
- [ ] Kayıt ol → giriş → çıkış → tekrar giriş akışı sorunsuz
- [ ] Uzun süre kapalı kaldıktan sonra açınca **token yenileniyor** (login'e atmıyor)

---

## H. Boş / hata durumu taraması (her ekran)

Yeni hesapla gir, hiç pozisyon ekleme, sonra uçak moduyla tekrar gez:

- [ ] Ana Sayfa · Haberler · Sinyaller · Portföy — dördü de boş veriyle düzgün
- [ ] Yan modüllerin hepsi boş portföyde çökmüyor
- [ ] Ağ yokken her ekranda anlamlı hata mesajı var (sonsuz spinner veya beyaz ekran yok)

---

## Kapsam dışı — pivotla geçersiz oldu (yapma)

Kodda karşılığı kalmadı, doğrulamaya çalışma:

- Bracket order / OCO / SL-TP otomatik koruma (44. tur) — `pending_order.py`, `limit_order_service.py` **silindi**
- Limit emir verme, bekleyen emir listesi, tetiklenme
- "Piyasadan sat → bekleyen SAT emri iptal oluyor mu" (47/2)
- "AL/SAT emri snackbar Türkçe mi" (47/1) — emir ekranı yok
- Sanal bakiye ayarlama, Nakit bölümü
- Grafikte SL/TP çizgileri

---

## Bilinen tuzaklar

1. **PWA cache** — bölüm 0 atlanırsa çalışan kod bozuk görünür. En sık yaşanan hata bu.
2. **Render free tier soğuk başlangıç** — ilk istek 30-50 sn sürebilir, "backend çöktü" değil.
3. **BIST kapalıyken** fiyat/haber davranışı farklıdır; doğrulamayı seans saatinde yap.
4. **Pre-market chip** yalnız ABD borsası açılış öncesi/sonrası saatlerinde çıkar (TSİ ile 11:00-16:30 ve 23:00-03:00 civarı). Gündüz BIST saatinde bakarsan görünmez, bu hata değil.
5. **Android APK** bu makinede derlenemiyor (Android SDK kurulu değil). APK doğrulaması Umut'un makinesinde yapılmalı; PWA tarafı Render build'iyle gelir.
