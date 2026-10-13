# Portly — Session Devir Dokümanı

> **Yeni session: önce aşağıdaki ⚡ AÇILIŞ bloğunu oku (30 satır), İŞE ORADAN
> BAŞLA.** Gerisi referans: yalnız o iş için gerekiyorsa ilgili bölüme atla —
> dosyayı baştan sona okuma, token israfı. Kod yazmadan önce **🛡 KALICI
> KURALLAR** bölümüne bak. Detaylı backlog: `GELISTIRME_ONERILERI.md`.
> Tarihsel turlar: `docs/HANDOFF_ARSIV.md` · `CHANGELOG.md` · `git log`.
> `~/.claude` memory'leri otomatik yüklenir — kod davranışı iddialarını
> **koddan doğrula**, buradaki notu yeterli sayma.
>
> **[KURAL — dosya bakımı]** Her turun sonunda: (1) ⚡ AÇILIŞ bloğunu **baştan
> yaz** (eklemeyle büyütme), (2) turun anlatısını AÇILIŞ'ın altına tek bölüm
> olarak koy, (3) burada **en fazla son üç tur** dursun — daha eskisi
> `docs/HANDOFF_ARSIV.md`'ye TAŞINIR (silinmez) ve "Sıkıştırılmış tur özeti"ne
> bir satır bırakılır. Hedef: bu dosya **~700 satırın altında** kalsın.

---

## ⚡ AÇILIŞ — yeni session buradan başlar
> Son güncelleme: **8 Eylül 2026, 12. tur sonu.**

**Durum:** çalışma ağacı temiz, **11. ve 12. tur PUSH'LANDI** (9 commit:
`4666a05` BIST sektör haritası · `de5e162` şifre değiştirme · `76376b6` fiziki
altın · `86a8005` Android paket kimliği + PWA metni · `4d03e99` güvenlik
sertleştirmesi · `f44011e` hesap silme + `users.created_at` · `37a0217`
spark ile toplu kapanış · `db488d6` vekil çerezi (toplu fiyat 401'i) ·
`3f91a58` fiziki altın ekran cilası).
Testler: backend **802** · flutter **101** · `flutter analyze` temiz.
Kaynak: 11. tur = ilk dış kullanıcının (Batuhan) 7 maddesi · 12. tur = Kerem'in
*"arkadaşlarım kullanıyor, güvenliklerini sağlayalım"* isteği.

**Canlıda 5 hesap var, 2'si gerçek dış kullanıcı** (Batuhan aktif, Yağmur bir
kez girip dönmemiş). Kerem kararı: **hesaplar silinmeyecek, `umut@mail.com`'un
`123456` şifresine şimdilik dokunulmayacak.**

**⚠️ COMMIT/PUSH SORMADAN** (Kerem kalıcı izin verdi) — koşul: iş bitmiş +
testler yeşil. Push sonrası `/health`'ten commit'i ve değişen ucu doğrula.

**SIRA (üstten aşağı):**

| # | İş | Kim | Not |
|---|---|---|---|
| 1 | **Cihaz doğrulaması — 11.-12. tur** | Kerem | (a) Profil → Ayarlar → **Şifre Değiştir** (yanlış mevcut şifre → hata; doğru → yeni şifreyle giriş) · (b) pozisyon ekle → **"çeyrek"** ara → 5 adet, maliyet gir → portföyde **₺** değeri doğru mu (5 × ~11.100 ₺) · (c) sektör donut'unda küçük BIST hisseleri artık "Diğer" değil (BNTAS→Ambalaj) · (d) fiziki altın detayında grafik yerine gerekçe metni · (e) arama ipucu "çeyrek altın, katılım fonu" · (f) Profil altında **Hesabımı Sil** (şifre isteyen onay; SİLME, sadece ekranı gör) · (g) fiziki altın detayında **AI Teknik/Temel Analiz kartları ve zaman aralığı seçici GÖRÜNMEMELİ** |
| 2 | ✅ **Cloudflare Worker güncelmiş** | ~~Kerem~~ | 12. turda ÖLÇÜLDÜ, deploy GEREKMİYOR: `/v8/finance/spark` ve `/v7/finance/quote` vekilden **200**, izin dışı yol (`/v10/quoteSummary`) **403 "Bu yol vekillenmiyor"** → izin listesi güncel. **Ama vekil yine de kullanılmıyordu** → `db488d6` (aşağıda) |
| 3 | ✅ **spark ile toplu kapanış** | ~~Claude~~ | 12. turda YAPILDI (`37a0217`): 20'şerli gruplar, 51 sembol → 3 istek. Canlı ölçüm (deploy sonrası): benchmark 1y **1,56 sn soğuk / 0,21 sn sıcak**, signals **3,80 / 0,35**, health 0,86. **Kalan:** OHLCV (mum) yolu hâlâ sembol başına — sinyal motoru oradan besleniyor, spark mum vermiyor (yalnız kapanış) |
| 4 | **Render loglarından 3 satır** | Kerem → Claude | Render → portly-backend → Logs, arama kutusuna sırayla: (a) **`Toplu quote`** — `db488d6` sonrası hâlâ 401 mi 200 mü (`/health`'te `quote_source` HÂLÂ BOŞ görünüyor, sebebi ancak logda) · (b) **`spark toplu`** — kapanış gerçekten spark'tan mı, kaç istek · (c) **`Haber enrich [...]: N ham -> M kaldi`** — eleme oranı · (d) Environment sekmesinde `YAHOO_PROXY_BASE` değeri |
| 5 | **Neon rol şifresini döndür** | Kerem + Umut | Bağlantı dizesi 12. turda oturum kaydından geçti. Neon → rol → Reset password → Render'da `DATABASE_URL` güncelle → deploy. Umut'a haber vermeden yapma |
| 6 | Eski Neon merge · Brevo | Bloke | Kerem iki bağlantı dizesi · Umut `BREVO_API_KEY` (şifre **sıfırlama** maili hâlâ gitmiyor; **değiştirme** artık maile ihtiyaç duymuyor) |
| 7 | Play Store / APK | Kerem (opsiyonel) | Paket kimliği hazır (`com.portly.app`) ama bu makinede **Android SDK YOK** → APK hiç derlenmedi. Bugünkü gerçekçi cevap: **PWA** (Chrome → "Uygulamayı yükle"). Mağaza ayrı iş: Android Studio + keystore + Play Console |
| 8 | Ürün cilası kalanı | Sırada | Temettü ekranı cihazda · kaydırma gereken ekranlar (hisse detayın altı · fon grafiği · Notlarım · satış kaydı) |

**Canlı ölçüm yolu:** token'ı test kullanıcısıyla kendin al (**hiçbir dosyaya
yazma**): `curl -s -X POST .../api/v1/auth/login -H "Content-Type: application/json"
-d '{"email":"umut@mail.com","password":"123456"}'` → `access_token` (60 dk).
Uç: `https://portly-backend-5jii.onrender.com/api/v1` · `?force=true` cache'i atlar.
**Ölçümden ÖNCE `/health`'e bak** (bu uç aktivite SAYILMAZ, koşulu bozmaz):
`idle_s` ≥1800 ise arka plan yenileyici durmuş = gerçek soğuk senaryo ·
`uptime_s` küçükse deploy ısıtması sürüyor (ölçme) · `cache` = `redis`
(canlıda öyle → cache deploy'a ve uyanışa dayanıyor).

**⚠️ Kerem'in ağı (12. turda teşhis edildi):** ZTE modemin DNS'i **zincirli
(CNAME) adreslerde tökezliyor** — `api.anthropic.com` ve
`portly-frontend.onrender.com` BOŞ dönüyor, `github.com` gibi düz adresler
çalışıyor; aynı isimler 8.8.8.8'de 10/10 doğru. Mac'in Wi-Fi DNS'i
`8.8.8.8/8.8.4.4/9.9.9.9`'a sabitlendi (geri al: `networksetup -setdnsservers
Wi-Fi Empty`). **Telefon/tablet hâlâ modemin DNS'ini kullanıyor** → modemden
DHCP DNS'i değiştirmek ya da cihaz bazında elle DNS girmek gerek. `1.1.1.1` bu
hatta ENGELLİ. Belirti: "SSL certificate verification failed", Chrome'da
"Gizlilik hatası", `git push` SSL hatası — hepsi aynı kök sebep.

**Repo kökünde duran, commit'e GİRMEYECEK dosyalar:** `flutter_*.txt`,
`python_*.txt` (başka modele verilen kod dökümleri) — **zaten `.gitignore`'da**
(satır 79-80), git bunları görmüyor.

**Bu dosyada nereye bakılır:** 12. tur ayrıntısı ↓ hemen altta · "(ÖNCEKİ)
11./10. tur" başlıkları · canlı altyapı/blokerler · sıkıştırılmış tur özeti ·
🛡 **KALICI KURALLAR** (kod yazmadan önce) · ▶️ ÇALIŞTIRMA (test komutları).

---

## 🔐 12. TUR AYRINTISI (7 Eylül 2026) — güvenlik denetimi, canlı kullanıcılar, hesap silme

Kerem: *"şu an dışarıdan da bazı arkadaşlarım kullanıyor, güvenliklerini
sağlayalım"*. Önce kod denetlendi, sonra Neon'daki canlı veriye bakıldı.

### Kimler kullanıyor (7 Eyl, Neon)
5 hesap: `umut@mail.com` (ana demo — 36 pozisyon/44 işlem/16 canlı oturum) ·
**`guzelbatu46@gmail.com` (Batuhan, gerçek kullanıcı — 5 pozisyon, aynı gün
girmiş)** · `av.yagmurdemircan@gmail.com` (21 Ağu'da bir kez, 8 izleme,
dönmemiş) · `a@hotmail.com` (test) · `dogrulama11tur@example.com` (11. turda
doğrulama için açıldı). **Kerem kararı: hiçbiri silinmesin, umut'un `123456`
şifresine şimdilik dokunulmasın** (repo private, sızmış değil).

### Denetimde temiz çıkanlar (tekrar bakılmasın)
`user_id` alan 36 ucun hepsinde sahiplik kontrolü var (IDOR yok) · not/alarm
gibi kaynak-id'li uçlar kullanıcıya göre filtreli · şifreler bcrypt (`$2b$`,
60) · sıfırlama kodu TTL + deneme limitli · süresi geçmiş token birikmesi yok
(0) · rotation çalışıyor · loglarda şifre/token yok · repo private ·
**CORS canlıda ARTIK kilitli** (yabancı origin preflight'ta 400, frontend 200)
→ backlog 6c KAPANDI.

### Düzeltilen dört açık (`4d03e99`)
1. **Şifre politikası**: tek kural 6 karakterdi, `123456` kabul ediliyordu.
   Yeni/değiştirilen şifrelerde min 8 + en yaygın 20 şifre + e-posta ile
   aynılık + tek karakter tekrarı engelli. **Geçmişe dönük DEĞİL** — mevcut
   kullanıcı girişte kilitlenmiyor (testle kilitli). Flutter tarafı da 8.
2. **Giriş oran sınırı** 10/dk → 5/dk.
3. **`/docs` + `/redoc` + `/openapi.json` prod'da kapalı** — canlıda 200
   dönüyordu, yani tüm uç listesi + gövde şemaları herkese açıktı. Artık 404
   (geliştirmede açık kalıyor).
4. **Güvenlik başlıkları**: nosniff · X-Frame-Options DENY · Referrer-Policy ·
   Permissions-Policy · prod'da HSTS.

### Hesap silme + kayıt tarihi (`f44011e`)
Canlı veriye bakınca çıktı: **hesabı kapatmanın hiçbir yolu yoktu** ve
veritabanı da izin vermiyordu (`users`'a bakan 8 yabancı anahtarın hepsi
NO ACTION). Gerçek kullanıcı varken KVKK silme hakkı zorunlu.
- `POST /auth/delete-account` (3/dk) — **şifre şart** (token tek başına
  yetmez, işlem geri alınamaz), sonrasında access token kara listeye.
- `account_service` alt satırları AÇIKÇA siliyor; göç `b8d4f6c2a713` ayrıca
  `ON DELETE CASCADE` koyuyor. İki katman bilerek: cascade'siz bir ortamda
  kullanıcı silinip portföyü yetim kalmasın.
- Göç `a7c3e5b19d40`: `users.created_at`. **Eski satırlar NULL** — bilinmeyen
  tarihi uydurmaktansa "bilinmiyor" demek doğru.
- UI: Profil altında sönük "Hesabımı Sil" bağlantısı → neyin silineceğini
  yazan + şifre isteyen onay sheet'i.

Canlı doğrulama: `alembic_version = b8d4f6c2a713` · 8 FK'nın hepsi CASCADE ·
`users.created_at` var ve eski satırlarda NULL · uç token'sız 401 · `/docs`
404 · başlıklar yanıtta · `"password"` ile kayıt 400.

### spark ile toplu kapanış serisi (`37a0217`)
10. turda ölçülmüştü ama yapılmamıştı: `yf.download` adı "batch" olsa da
sembol başına ayrı `/v8/finance/chart/` isteği atıyor. `/v8/finance/spark`
aynı seriyi tek istekte veriyor — 7 Eyl'de canlı ölçüldü: **20 sembol · 400
günlük pencere · 0,48 sn · ~140 KB**.

**Ölçülen sınır:** spark istek başına **en fazla 20 sembol** kabul ediyor;
21'de `"Number of symbols needs to be less than or equal to 20"` dönüyor.
Bu yüzden 20'lik gruplar → 51 sembollük tarama **51 istek yerine 3**.

`refresh_daily_closes` önce spark'ı deniyor, vermediği sembolde eski
`yf.download` yolu YEDEK duruyor (davranış kaybı yok). Fon ve fiziki altın
spark'a hiç gitmiyor. **Yan bulgu:** `test_market_batch_history` ve
`test_bist_source` spark eklenince gerçekten ağa çıktı — mock'ları
tamamlandı, ikisi de artık ağsız.

⚠️ **Kalan:** OHLCV (mum) yolu hâlâ sembol başına. Sinyal motoru 6 aylık mum
istiyor ve spark yalnız KAPANIŞ veriyor → mumlar için ayrı bir çözüm gerek
(ya chart ucuna paralel istek, ya kapanıştan türetilmiş sınırlı gösterge).

### Vekil kuruluydu ama toplu fiyat ondan HİÇ geçmiyormuş (`db488d6`)
Worker önce ölçüldü (Cloudflare paneline girilerek değil, **canlı davranışla**):
`/v8/finance/spark` ve `/v7/finance/quote` **200**, izin dışı `/v10/quoteSummary`
**403 "Bu yol vekillenmiyor"** → izin listesi güncel, **yeniden deploy
GEREKMİYOR** (SIRA'nın 2. maddesi böyle kapandı).

Ama `/v7/finance/quote` vekilden çağrılınca Yahoo **401 Unauthorized**
veriyordu. Kök sebep Worker değil, **çerezin alan adı kuralı**: yfinance'in
çerezi `.yahoo.com` için saklanıyor; istek `…workers.dev`e gidince kavanoz onu
takmıyor → Yahoo kimliksiz istek görüp reddediyor → backend sessizce doğrudan
Yahoo'ya (Render'ın CEZALI IP'sine) düşüyor. Yani 10. turda kurulan vekilin
varlık sebebi bu uçta hiç işlememiş, üstelik her turda boşuna bir 401
gidiş-dönüşü yeniyormuş.

Düzeltme: vekile giderken çerez ELLE `Cookie` başlığına, crumb açıkça
parametreye konuyor (ikisi eşleşmek zorunda). Kanıt: aynı istek çerezsiz
**401**, çerezle **200** (AAPL + THYAO.IS + BTC-USD eksiksiz).
⚠️ **Kapanmadı:** deploy sonrası `/health` → `quote_source` HÂLÂ boş. Muhtemel
sebep, crumb el sıkışmasının (fc.yahoo.com/getcrumb) Render'dan DOĞRUDAN
gitmesi ve orada engellenmesi — doğrulaması Render logundaki `Toplu quote`
satırı (SIRA 4). Doğrulanırsa çözüm Worker'ın çerezi+crumb'ı KENDİ alması.

### Uygulamayı gezerek bulunan cila (`3f91a58`)
Kerem "uygulamada dolaşabilirsin" dedi; canlı web'de (umut oturumu) fiziki
altın akışı baştan sona denendi. Arama ✓, detay başlığı ✓, ₺ fiyat ✓, grafik
yerine gerekçe metni ✓. Dört kusur çıktı:
1. **Zaman aralığı seçici + "Pro" tam ekran** fiziki altında duruyordu — serisi
   olmayan varlığa aralık seçtirmek boş grafiğe götürüyordu.
2. **"AI Teknik Tahmin (SMA/RSI/MACD)" ve "AI Temel Analiz (F/K, ROE)"**
   kartları görünüyordu. Çeyrek altının ne mumu ne bilançosu var; backend zaten
   `physical` sayıp sinyal üretmiyor — ekran da aynı şeyi söylemeliydi.
3. **"lot"** ifadesi (fiziki altında birim adet/gram).
4. **Ana ekran araması HAM sembol** basıyordu (`CEYREK.ALTIN`); artık
   `compact()` → "Çeyrek Altın", fonlar da `TLY.FON` yerine `TLY`.

**Ders:** üç turdur eklenen özellikler testten geçiyordu ama ekranda anlamsız
kontroller kalıyordu — canlı uygulamada gezmek testin yakalamadığını yakaladı.

### Kerem'in ağı (kod dışı, ama işi durduruyordu)
"SSL certificate verification failed" (Claude Code), `git push` SSL hatası ve
Chrome'da "Gizlilik hatası" **aynı kök sebep**: ZTE modemin WAN'ı düşünce her
alan adına kendi IP'sini (192.168.1.1) döndü, macOS bunu önbelleğe aldı
(`api.anthropic.com` → 192.168.1.1). Flush + Wi-Fi DNS'inin modemden alınıp
`8.8.8.8 / 8.8.4.4 / 9.9.9.9`'a sabitlenmesiyle çözüldü.

İkinci ve KALICI sorun ayrıca ölçüldü: modemin DNS'i **zincirli (CNAME)
adreslerde tökezliyor**. 8 isimle soğuk deneme: `api.anthropic.com` ve
`portly-frontend.onrender.com` BOŞ döndü, `github.com`/`console.neon.tech`
gibi düz adresler çalıştı; aynı iki isim 8.8.8.8'de 10/10 doğru. Kerem'in
telefonu hâlâ modemin DNS'ini kullandığı için mobilde sorun sürüyor →
çözüm modemin DHCP DNS'ini değiştirmek (ya da cihazda elle DNS).
`1.1.1.1` bu hatta ENGELLİ (8.8.8.8 ve 9.9.9.9 çalışıyor).
Makine denetlendi: **araya giren sahte kök sertifika YOK**, sistem proxy'si
boş — sorun ağda, cihazda değil.

### Kalan güvenlik işleri (yapılmadı, bilerek)
- **Kayıtta e-posta doğrulaması yok** — isteyen istediği adresle kayıt olur.
  Arkadaş çevresinde sorun değil, halka açılırken şart.
- **Token web'de `localStorage`'da** — XSS olursa çalınır. Flutter web canvas'a
  çizdiği için yüzey dar; CSP eklemek canvaskit'i bozma riski taşıdığından
  bilerek yapılmadı.
- **Brevo anahtarı** hâlâ yok → şifresini UNUTAN kullanıcının çaresi yok
  (giriş yapabiliyorsa "Şifre Değiştir" var).
- **Neon rol şifresi** bu turda oturum kaydından geçti → döndürülmesi öneriliyor
  (Umut'a haber vererek; Render'daki `DATABASE_URL` de güncellenmeli).

---

## 🟡 (ÖNCEKİ) 11. TUR (7 Eylül 2026) — ilk dış kullanıcının 7 maddesi
> Sıradaki iş için AÇILIŞ yeter; bu bölüm "bu neden böyle" sorusu içindir.

Kerem "cilaları yap, bu konuşmaları gözden geçir, sonra bana yapılacakları
söyle" dedi ve **Batuhan'la WhatsApp yazışmasının** ekran görüntülerini verdi.
Bu, projenin **ilk gerçek dış kullanıcı geri bildirimi** — 10 turdur cila
Kerem'in kendi kullanımından geliyordu. Yedi madde çıktı; her biri koddan
doğrulandı (bir tanesi zaten vardı, o kodlanmadı).

### 1. "BNTAS var bende, ambalaj diye ayırsa" — sektör haritası 90 sembolde kalmış (`4666a05`)
Şikâyet aynen: *"hisselerimi girdiğimde taşımacılık ya da diğer sektörlerden
hisseleri ayrıştırmıyor"*. Koddan bakınca sebep açık: `_BIST_SECTORS` **elle
yazılmış ~90 sembollük** bir sözlüktü ve BIST'te ~630 hisse var. Haritada
olmayan her hisse sessizce **"Diğer"** dilimine düşüyordu; Finnhub ücretsiz tier
BIST'i kapsamıyor, yfinance `.info` Render'da bloklu → ağ yolu da yok.

Elle 600 satır yazmak yerine **kaynak bulundu**: TradingView'in açık ekran
(screener) ucu borsanın tüm hisselerini `sector` + `industry` ile TEK istekte
veriyor. `industry` daha ayırt edici ("Process Industries" değil
"Containers/Packaging" → **Ambalaj**). 102 sanayi elle **~25 Türkçe etikete**
eşlendi (donut'ta 100 dilim okunmaz), `scripts/generate_bist_sectors.py`
`app/data/bist_sectors.json`'u üretti: **623/626 hisse**. Eşlenmeyen sanayi
sessizce yanlış etiket almıyor, "Diğer"e düşüyor (script uyarıyor).

Elle kürasyon ÜSTTE bırakıldı: TradingView SISE'yi "Tüketim", AGHOL'ü "Gıda"
diyor; FENER→Spor, AKCNS→Çimento gibi tercihler otomatik eşlemeyle ezilmesin.

### 2. "Altınımı somut tutuyorum, portföye ekleyebilsek" — fiziki altın (`76376b6`)
En büyük madde ve en haklısı: uygulamanın vaadi *"tüm birikimi tek yerde
görmek"* ama fiziki altın yalnız "Banka Altın Karşılaştırma" ekranında
**izlenebiliyordu**, portföye giremiyordu. Batuhan'ın sorusu tam olarak
*"fiziki altınlarımın değeri kaç şuanda, hepsini satsam ne kadar gelir"*.

Çeyrek/tam/bilezik **Yahoo'da yok** (GC=F ons cinsinden VADELİ altındır, Türkiye
serbest piyasa fiyatı değil) → fon (`.FON`) deseninin aynısı kuruldu: sonek +
yerel katalog + kendi fiyat kaynağı. 11 ürün: `GRAM/HAS/CEYREK/YARIM/TAM/
CUMHURIYET/ATA/BILEZIK22/AYAR18/AYAR14.ALTIN` + `GRAM.GUMUS`. İki sonek çünkü
"GUMUS.ALTIN" saçma olurdu: sonek **cins**, kod **biçim**.

Kararlar ve gerekçeleri:
- **Değerleme ALIŞ (bozdurma) fiyatıyla.** Soru "satsam ne kadar gelir";
  satarken eline geçen alıştır. Satış fiyatıyla değerlemek portföyü makas
  kadar şişirirdi (çeyrekte ~%1,6). Yeni alım fiyatı `ask_price` ile taşınıyor.
- **Para birimi ₺** — `fx_service` · `stress_test_service` · `benchmark_service`
  · `dividend_service` + Flutter `currencyOf`/`isTurkish`. Bu turun EN PAHALI
  hata adayıydı: USD sayılsaydı kur 40 iken çeyrek altın portföyde **40 katına**
  çıkardı. Uçtan uca testle kilitlendi (5 çeyrek → 55.549 ₺, 2.221.960 ₺ değil).
- **Yahoo'ya hiç sorulmaz** — toplu quote, kapanış serisi ve OHLCV
  indirmelerinden çıkarıldı (her istek boşuna 429 riski).
- **Geçmiş seri UYDURULMAZ.** Ons altın × dolar kurundan seri türetmek mümkün
  ama o BAŞKA bir varlığın grafiği olurdu (kuyumcu makası oraya girmez). Uç boş
  seri + `unavailable_reason` dönüyor, ekran grafiği gizleyip sebebini yazıyor.
- **Sinyal ve temettü atlanıyor**: mumu/bilançosu olmayan varlığa AL/TUT/SAT
  skoru üretmek uydurma olurdu (`_classify` → yeni sınıf `physical`).
- **Miktar birimi**: çeyrek/yarım/tam/cumhuriyet/ata **adet**, gram/has/bilezik/
  ayar ürünleri **gram** (serbest piyasa öyle kote ediyor) → sheet etiketi
  sembole göre değişiyor. Yanlış birim maliyeti kat kat yanlış gösterirdi.

### 3. "Şifreyi sonradan değiştirebilme yok sanırım" — doğruymuş (`de5e162`)
Tek yol e-posta kodlu sıfırlamaydı ve o yol **hâlâ Brevo anahtarını bekliyor**
(uç 200 dönüyor, mail gitmiyor) → pratikte şifre değiştirmek imkânsızdı.
`POST /auth/change-password`: mevcut şifre **şart** (access token'ı ele geçiren
biri şifreyi değiştirip hesabı kilitleyebilirdi), sonrasında tüm refresh
token'lar iptal — ama yanıtta **bu cihaz için taze bir refresh token** dönüyor,
yoksa kullanıcı 60 dk sonra kendi telefonundan da düşerdi.

### 4. "Bankaların katılım fonları var, onları da ekleyebilir miyiz" — ZATEN VAR
Kodlanmadı, çünkü kontrol edildi: TEFAS kataloğunda **270 katılım fonu** var ve
arama "katılım" ile bunları buluyor. Sorun keşfedilebilirlik → arama ipucu metni
`'Ara — THYAO, Apple, çeyrek altın, katılım fonu…'` yapıldı. **Ders:** dış
kullanıcının "yok" dediği şey bazen "bulamadım" demek.

### 5. "İndirip uygulama gibi kullanabiliyoz mu" (`86a8005`)
İki bulgu: (a) PWA manifest açıklaması hâlâ **"yapay zekâ destekli sanal borsa
simülatörü"** diyordu — pivot biteli aylar oldu ve bu metin kullanıcının "ana
ekrana ekle" derken gördüğü şey. (b) Android paketi şablon değerinde:
`applicationId`/`namespace` = `com.example.portly` — **Play Store bu öneki
reddeder**; `com.portly.app`'e taşındı (MainActivity paketi dahil), etiket
"portly" → "Portly", `key.properties`/`*.jks` `.gitignore`'a eklendi.
⚠️ Bu makinede **Android SDK yok** (flutter doctor) → APK derlenip
DOĞRULANMADI. Bugünün gerçekçi cevabı PWA; mağaza ayrı bir iş.

### Bu turda YAPILMAYAN, bilerek
- **Fiziki altın grafiği** (türetilmiş seri) — yukarıdaki gerekçe.
- **Play Store yayını** — hesap/keystore/ücret Kerem'de, kodda yapılacak iş yok.
- Handoff 6. maddesindeki cila kalemleri (temettü ekranı, kaydırma gereken
  ekranlar) — hepsi **cihazda doğrulama**, kod işi değil.

---

## 🟡 (ÖNCEKİ) 10. TUR (4 Eylül 2026) — silme yolu, 50 kat istek düşüşü, başka modelin listesi
> Sıradaki iş için AÇILIŞ yeter; bu bölüm "bu neden böyle" sorusu içindir.

Kerem "devam edelim" dedi, sonra üç iş verdi (kaydırıp silme + uyarı · fiyatı
ücretsiz hızlandırma · benim önerim); tur ortasında **Gemini'nin 5 maddelik
cila listesi** geldi ve hepsi koddan doğrulandı.

### 1. Pozisyon silme — eksik olan UI değil, YOLUN TAMAMIYDI (`b6f5fc5`)
Portföyden bir pozisyonu kaldırmanın hiçbir yolu yoktu: uzun-basma sheet'inde
yalnız "AI Koç'a Sor" + "Detayları Gör" vardı, backend'de de silme ucu yoktu
(`order` ve `manual-position` dışında hiçbir mutasyon). Kullanıcı yanlış
girdiği pozisyondan ancak **olmayan bir satışı kaydederek** kurtulabiliyordu —
o da deftere sahte bir SELL yazıyordu.
`DELETE /portfolio/{uid}/positions/{symbol}`: portföy satırı **+ o sembolün
işlem kayıtları** birlikte silinir. Yarım bırakmak (portföyde yok ama geçmişte
alış var) davranış/performans servislerine sahte bir açık pozisyon gösterirdi.
UI'da iki giriş noktası (kaydırma keşfedilemez): sola kaydır → onay → sil,
ayrıca sheet'te "Portföyden Kaldır". Onay ŞART çünkü geri alınamaz; diyalog
gerçekten satıldıysa satış kaydını öneriyor.
`confirmDismiss` bilerek hep `false` döner — satır portföy yeniden yüklenince
gider; `true` dönmek "dismissed widget still in tree" hatasına açıktı.

### 2. `yf.download` "batch" DEĞİLMİŞ — 54 istek → 1 (`abc60c7`)
Kodun kendi yorumu "TEK HTTP isteğinde N sembol" diyordu. İstek sayacı takıp
ölçtüm: **5 sembol = 5 istek, 10 = 10** (`/v8/finance/chart/{symbol}`, paralel
thread). Yani 51 sembollük sinyal taraması = **51 Yahoo isteği**; Render'ın
paylaşılan çıkış IP'sindeki 429'un asıl kaynağı buymuş.
Ölçülen alternatif — `/v7/finance/quote`: **54 sembol (ABD + BIST + kripto +
altın + FX) TEK istekte 1,09 sn**, eksiksiz; fiyat, önceki kapanış, değişim
yüzdesi ve **şirket adı** dahil. Çıplak istek 429 alıyor (crumb+çerez şart) →
oturum yfinance'in kendi `YfData`'sından ödünç alınıyor. Eski yol
`_fetch_many_via_download` adıyla YEDEK duruyor: uç kapanırsa davranış bugünkü
hâline döner. Ad bedava geldiği için `.info` çağrısı da gereksizleşti (o uç
Render'da bloklu ve sembol başına 0,6-3 sn yiyordu).

### 3. `/health` artık ölçüm koşullarını söylüyor (`7c9743a`, `a491c39`)
9. turun ölçümleri deploy'dan hemen sonra alındığı için saçılmıştı ve "soğuk
muydu?" sorusu tahmine kalmıştı. Uç artık `idle_s` (son `/api` isteğinden beri;
**`/health` aktivite SAYILMAZ** → doğrulama isteği ölçümü bozmaz), `uptime_s`
ve `cache` döndürüyor. Canlıda **`cache: redis`** çıktı: cache deploy'a ve
uyanışa dayanıyor. `idle_s` ilk deploy'da 11.465.986 sn göründü (hiç istek
gelmemişken monotonic saatin ham değeri) → süreç yaşıyla sınırlandı.

### 4. Gemini'nin 5 maddesi — koddan doğrulandı, üçü düzeltilerek uygulandı
| Madde | Ölçüm/kod ne dedi |
|---|---|
| Haptic | Kodda yoktu, doğru. **Ama Flutter Web'de `HapticFeedback` NO-OP** — dağıtım PWA. Vibration API'ye düşen sarmalayıcı yazıldı (Android Chrome'da çalışır, **iOS Safari'de titreşim API'si yok**) |
| `marketState` oku | Veri "hazır" değildi: alan **yalnız ABD hissesinde** doluydu (pre/post overlay'in yan ürünü). Her sınıfa yayıldı. **Hata bulundu:** `_us_market_state` ham `hour` okuyor → saat dilimi çevrilmeden TSİ 14:00'te ABD borsasını "REGULAR" sanıyordu |
| Watchlist'e Dismissible | **Zaten vardı** (`stock_card.dart`). Eksik olan Geri Al'dı → eklendi, silinen sembolün **sırası** da korunuyor |
| Sıralama menüsü | Geçerli iş. Ağırlıkta **`total_value_try`** kullanıldı: ham `total_value` karışık para biriminde, sıralansa TSLA $1.266 ≈ ₺1.266 sayılırdı |
| Proxy uyarısı | **En isabetli maddesi** ama iki gizli engel vardı: Worker izin listesinde `/v7/finance/quote` yoktu **ve Worker `Cookie` başlığını iletmiyordu** (v7/quote çerez+crumb ister → düz vekilleme 401/429 alırdı). Üstelik `/v7/finance/spark` yolu yanlış yazılmış, gerçeği `/v8/...` — hiç eşleşmiyormuş |

Ek olarak canlı doğrulamada `GC=F` için Yahoo'nun **kontrat adı** ("Gold Dec
26") geldiği görüldü → şifreli sembollerin Türkçe adı backend'e de kondu
(`2afac35`): frontend `SymbolDisplay` bunu zaten çeviriyor ama backend adı AI
Koç'a ve haber sorgularına gidiyor, 6. turdaki "ham sembol yerine anlaşılır
ad" düzeltmesi emtia/dövizde yeniden bozulacaktı.

### 5. Ölçülüp yapılmayan (sıradaki iş)
`get_daily_closes` / `get_daily_ohlcv` hâlâ `yf.download` kullanıyor → sembol
başına istek. `v8/finance/spark` ölçüldü: **10 sembol tek istekte 0,85 sn**,
5 günlük kapanış serisi + `previousClose` veriyor. Sinyal ve benchmark buradan
besleniyor; Worker izin listesine `/v8/finance/spark` bu turda eklendi.

---



## 🔌 CANLI ALTYAPI & AÇIK BLOKERLER (operasyonel — arşivden taşındı, GÜNCEL)

**Cloud deploy (20. turdan beri, Umut kurdu):** Render + Neon Postgres.
- Frontend: `https://portly-frontend.onrender.com` (Static, Flutter web build)
- Backend: `https://portly-backend-5jii.onrender.com` (Docker, Frankfurt, FastAPI) — `autoDeploy: true` (main'e push = otomatik deploy)
- UptimeRobot backend `/health`'i 5 dk'da ping'liyor (free instance uyumasın; HEAD destekli — 21. tur). Render free cold-start ~30-60sn.
- **Render dashboard login = Umut (`ualtn8@gmail.com`).** Kerem'i team'e eklemesi gerekiyor.

**✅ ÇÖZÜLDÜ — Render frontend Auto-Deploy ÇALIŞIYOR (17 Haz doğrulandı):** Eski "build-cache bloker" notu artık GEÇERSİZ. Settings → Deploy → **Auto-Deploy = "On Commit" AÇIK**; Events'te son commit'ler ("New commit via Auto-Deploy") canlı; push→deploy zamanları tutuyor. Yani **main'e `git push` = ~3 dk sonra otomatik canlı**, elle Manual Deploy GEREKMEZ. (`render.yaml` `d390113` fix'i — `--web-renderer html` kaldırıldı, kalan `--release --pwa-strategy=none --no-tree-shake-icons` — bloker'ı çözmüş, handoff geç güncellendi.) **YAPMA:** Build Command'i manuel override (Umut'un render.yaml'ını fork eder). ⚠️ Telefon PWA cache'i hâlâ inatçı (↓ ayrı not) — deploy doğrularken cache-buster şart.

**⚠️ Render env vars (Umut set etmeli):** **Şifre-sıfırlama maili artık Brevo HTTP API üzerinden** (47. tur öncesi `ecb3499`): Render giden SMTP portlarını (25/465/587) blokluyor → `smtplib` "Network is unreachable" veriyordu, mail cloud'da HİÇ gitmiyordu (lokalde SMTP çalıştığı için fark edilmemişti). Kod `BREVO_API_KEY` tanımlıysa Brevo transactional API'ye (HTTPS/443) gider, boşsa lokal için Gmail SMTP'ye düşer. **Umut Render'a `BREVO_API_KEY` + `BREVO_SENDER_EMAIL` eklemeli** (`render.yaml`'da `sync:false`). Eski "SMTP_USER/PASSWORD ekle" notu GEÇERSİZ. Diğer env (`sync:false`): `DATABASE_URL` (Neon), `SECRET_KEY`, `GEMINI_API_KEY`, `NEWS_API_KEY`, `GROQ_API_KEY`.

**⚠️ Telefon PWA cache:** `--pwa-strategy=none` sonrası eski Service Worker telefonda inatla cache'liyor. Yeni deploy sonrası: PWA sil → Safari Settings → Advanced → Website Data → `portly` sil → iPhone restart → URL'i aç → Ana Ekrana Ekle. Deploy doğrularken cache-buster (`?cb=...`) şart (Render `main.dart.js` CDN edge-cache).

**Android APK (alternatif demo cephesi):** `build/app/outputs/flutter-apk/app-release.apk` (~54.9 MB, debug-signed sideload). Prod Render backend'e bağlı (release manifest INTERNET izni eklendi — 25. tur). Telefona kurulu.

**Lokal demo notu:** `.env` + `backend/.env` repo'dan çıkarıldı (20. tur); `.env.example`'dan kopyala. `backend/portly.db` (SQLite) silindi — Postgres kullanılıyor ([[reference_local_run_postgres]]). Telefon (LAN) için: `.env`'de `API_BASE_URL_LOCAL`=Mac LAN IP + backend `--host 0.0.0.0` + rebuild + `serve_web :8091`; **commit öncesi `.env` geri al**.

---

## 📦 SIKIŞTIRILMIŞ TUR ÖZETİ (detay → `docs/HANDOFF_ARSIV.md` · CHANGELOG.md · git log)

**Arşive taşınanlar (7 Eyl 11.-12. turda, tam metin `docs/HANDOFF_ARSIV.md`):**
- **4 Eyl 9. tur** — soğuk açılışın ölçülmesi, üç darboğaz (SWR seri cache ·
  sektör ısıtma · sinyal prewarm) ve gözlem eksiğinin kapatılması.
- **4 Eyl 8. tur** — boş-durum ≠ hata (bölüm bazlı hata durumu + ortak
  `load_error_card`) · CORS kilidi (kod hazır, Render env'i bekliyor) · AI
  akışının bloklamaması · onboarding boş-ekran rehberi.

**Arşive taşınanlar (4 Eyl 9. turda, tam metin `docs/HANDOFF_ARSIV.md`):**
- **4 Eyl 6. tur** — TÜM AI özellikleri ölüydü (Gemini modelleri 404 → takma ad
  kuralı) · haber whiplash'ının ölçülmesi ve `_restore_silenced_symbols` ·
  Kerem'in canlı kullanımından gelen beş geri bildirim (ham sembol `GC=F` →
  "Altın" · TR haber 18→40 · portföy gecikmesi 5,8 sn → fiyat kaydı 6 saat ·
  sohbette yanıt göstergesi · uyuyan sunucuda giriş).

**Arşive taşınanlar (4 Eyl 8. turda, tam metin `docs/HANDOFF_ARSIV.md`):**
- **3 Eyl 5. tur** — oturum içi 401 → token yenile + isteği tekrarla; "haberler
  çok az" şikâyetinin üç katmanlı kök sebebi (istemci filtresi · Google News'in
  sessiz kısıtlaması · sembol sınırı).
- **3 Eyl 4. tur** — başka bir modelin (Gemini) düzeltme listesinin koddan denetimi
  (bir kısmı gerçek çıktı, bir kısmı çürütüldü) + ₺ maliyet/kur ayrımı.
- **3 Eyl 3. tur** — açılış artığı, BIST yedek kaynağı (İş Yatırım), fon kataloğu
  kendi kendini tazeleme, AI Koç fiyatsız-pozisyon dürüstlüğü.
- **3 Eyl 2. tur + 1. tur** — tarayıcı doğrulaması ve çıkan 6 bulgunun düzeltmesi
  (`change_available` sözleşmesi buradan çıktı).
- **2 Eyl (üç tur)** — Cloudflare Worker Yahoo vekili, batch/yedek-kaynak veri
  mimarisi, TEFAS fon desteği, açılış hızı.
- **4 Tem 49. tur** — sanal borsa → portföy takip + sinyal asistanı BÜYÜK PİVOT.


- **48** (19 Haz): **telefon canlı-demo hata düzeltmeleri** (Kerem cihazda 3 kusur, hepsi backend, 3 commit `9316a0d`+`ae9fc6c`+`25c085a`) — (1) **Korku & Açgözlülük 500→200**: `^GSPC` NaN son-kapanış → `sp500_5d_pct: NaN` → Starlette `allow_nan=False` 500; `dropna()`+guard+`_json_safe`. (2) **AI Temel Analiz 404→200**: `.info` (quoteSummary) Render IP'sinde bloklu → `_fast_price()` `fast_info`/history fallback, `data_limited=True`, 404 atma. (3) **Grafik 1d 500→200**: günlük seride NaN OHLC satırı → atla + NaN vol→0. **+ global `SafeJSONResponse`** (`default_response_class`) NaN/inf→null → hiçbir uç NaN'dan çökmez. pytest 273 (+5). #1/#2/#3 hepsi CANLI 200 doğrulandı. **48b: Finnhub** (`9b99d54`) — `.info` bloğunu by-pass: `finnhub_service` + `FINNHUB_API_KEY` (Render'da aktif) → **ABD hisselerinde gerçek F/K/ROE/marj CANLI DOĞRULANDI** (NVDA/AAPL). pytest 279. Açık: BIST degrade (Finnhub free=US), bilanço `-reported`'a çevrilmeli, analist-hedef premium.
- **47** (18-19 Haz): **telefon geri bildirimi cilası** (Umut, 2 commit `9d5aed6`+`5a66ba7`; öncesinde Umut `ecb3499` mail→Brevo) — **logo** her yerde (AppBar+giriş+onboarding ilk sayfa + web favicon/PWA + Android mipmap + iOS AppIcon; `assets/images/logo.png`, emblem PIL ile kırpıldı) · **AL/SAT mesajı Türkçe** (`api_service`) · **piyasa satışı bekleyen SAT limit emrini iptal eder** (`order_service._cancel_unfillable_sell_orders`, pozisyon kapanınca doldurulamayan SELL/SL/TP; +2 test) · **CSV export mobilde share_plus** (token'lı çek→geçici dosya→native paylaşım, conditional-import `share_file.dart`; eski `launchUrl` 401 çözüldü) · **haber ton≠etki** (liste "Ton" rozeti + detay "AI Piyasa Etkisi" + açıklama) · **FAB gesture-arena fix** (IgnorePointer+opaque, Android sürükleme). **TAKİP düzeltmeleri (cihaz testi sonrası, push'landı, CANLI doğrulandı):** web açılış **splash logosu** (`b49192b`); haber **"Ton" etiketi geri alındı** (saçma duruyordu) + benchmark null→"hesaplanamadı" frontend dürüstlüğü (`6e5b7ed`); **CSV dostu sembol** GC=F→Altın (`7e8ed26`); **NaN/BIST-kapalı fix** — benchmark "Portföyün %0" + TÜPRAŞ /price 500 (`414bd32`, ↓ KALICI "NaN son-kapanış"). pytest 265 · flutter 31 · analyze temiz. ⚠️ #2/#5 önceki kodda zaten doğruydu (telefon eski PWA cache'i). APK Android SDK yokluğundan bu makinede derlenemedi → Umut derleyecek.
- **46** (18 Haz): **HABER elden geçirme + demo denetimi** (telefon geri bildirimi, 5 commit `818cb62`…`556ee9b`) — haber **kaynak yönlendirme** (`newsQuery` bölge öneki `tr|`/`en|` → backend `_split_region`+`_REGION_PARAMS`; BIST→TR basını, ABD/kripto/döviz/emtia→EN orijinal; makine-çevirisi agregatör "Nötr 0.00" seli çözüldü) · haber **HIZ+HACİM** (ilk açılış ham-HEMEN döner `_collect_raw_for_symbols`, **LLM enrich arka planda** `_refresh_multi_bg`; niteleyici TR+EN ~13 terim genişledi, cap 6→10, RSS 8→6) · **batch taşma fix** (enrich max_tokens 800→1800 + parantez fix + insider gürültü Google yoluna) · **nötr rozet → sönük nokta** (`news_screen`, data-ink) · **FAB hızlı-sürükleme fix** (`main.dart` delta güncel `_fabPos`'a) · **onboarding akış testi** (4 test, flutter 27→31) · genel denetim: çekirdek matematik/akış SAĞLAM (#5 chat canlı-veri ZATEN VAR). pytest 263 · flutter 31 · analyze temiz.
- **45** (18 Haz): **demo cilası** (telefon geri bildirimi, push `b2890e0`) — ilk-açılış **onboarding turu** (`onboarding_screen` + AuthGate Stateful, `onboarding_seen` flag, ömür-boyu 1 kez, logout TETİKLEMEZ) · **sürüklenebilir AI Koç FAB** (Stack+Positioned+GestureDetector, varsayılan sağ-alt, her açılışta sıfırlanır) · portföy hero **Bugün+Toplam** (`_pnlLine`) · AI chat **yarıda-kalma fix** (max_tokens 800→1200 + prompt) + **hisse önerisine izin** (kural #1 gevşedi: eğitsel/sanal, gerekçe+uyarı) · haber **finansal filtre** (`_FINANCE_QUALIFIER` Google News) · stres mesajı sadeleştirme ("en şanssız %5" parantezi kaldırıldı) · "Portly v1.0"→"Portly" · şifre sıfırlama CANLI test (API ✓, SMTP env yok → Umut). pytest 262 · flutter 27 · analyze temiz.
- **44** (18 Haz): **LIMIT bracket (otomatik SL/TP) + OCO** — eski Madde 2 kapandı (yapı taşları zaten vardı; eksik olan limit-fill halkasıydı). `pending_orders`+`sl_price`/`tp_price`/`parent_order_id` + migration `f4a9c2b7d1e3` · `check_and_fill`: LIMIT BUY dolunca `_arm_protection_children` + koruma dolunca `_cancel_bracket_siblings` (OCO, çapa=`parent_order_id or id`, kullanıcı-bazlı) · market koruma da OCO (SL çapa / TP referans) · frontend limit'te SL/TP kartı+geçiş. Ayrıca news endpoint test boşlukları kapatıldı (force/for-symbols şekil+boş; coach/chat/market zaten kapsamlıydı). pytest 262 (+9) · flutter 27 · analyze temiz. **CANLI doğrulandı** (openapi+/health). push `12593e0`+`170379b`.
- **43** (18 Haz): **telefon geri bildirimi cilası** (7 commit) — What-If arama-sonrası-öneri + "(bugüne kadar)" sil · stres zayıf-halka ₺→**%-düşüş** + yeni **"2024 İran-Ortadoğu"** senaryosu (Nisan 2024 gerçek pencere) + Rusya-Ukrayna rename · haber `get_news_for_symbols` **SWR** · **BIST "Bugün %0" fix** (`2d→5d`; CANLI doğrulandı THYAO +0.23/ASELS +4.86) · AI portföy havuzu **~10→~45** (doğrulanmış ticker)+shuffle+sıcaklık0.8+çeşitlilik · akademi sayacı **dinamik** (gerçek 45/12). pytest 253 · flutter 27 · analyze temiz. push `9496ca4`…`bf88744`.
- **42** (18 Haz): **41. turun KALAN a/b/c** (kod+test TAM, cihaz doğrulaması bekliyor) — (a) What-If başlangıç/bitiş tarihleri (`calculate`/`calculate_dca` `end_date`/`start_date` + `_slice_*`; `/what-if`+`/dca` param; `what_if_screen` çift tarih seçici) · (b) **varlık-sınıfı AI analizi** (`_classify` -USD/=X/=F → `_analyze_macro`: kripto=benimsenme/forex=makro/emtia=arz-talep, `_overview` çıpa verisi; `_buildMacroAnalysis` dinamik skor, 3. eksen yüksek=iyi) · (c) **haber toplu-çağrı** (`get_news_for_symbols` paralel+tek batch enrich, `/news/for-symbols`; 12 HTTP+12 LLM→1+1). pytest 253 · flutter 27 · analyze temiz. push `6e1d268`/`e8e3c74`/`6318e6b`.
- **41** (17 Haz): **#1 "Bugün=₺0" fix** (`change_percent` `PortfolioItemResponse` şemasına + guard `test_schema_contracts`, canlı doğrulandı) + UI: Midas ₺↔$ dokunma · İşlem Geri butonu · snackbar floating→fixed · =X tam temizlik · hisse detay dostu snackbar · stres `savas_2022`+toparlanma+zayıf-halka. push `db2905d`/`aca5642`/`7f2f94c`/`c058e27`.
- **40** (17 Haz): **canlı demo cilası** (telefon test→fix→push döngüsü, ~15 push) — haber `&nbsp;` decode · **ham sembol→dostu ad HER YERDE** (`SymbolDisplay.compact`; GC=F=Altın: not/haber/trade/stres) · işlem **AL/SAT segmented** + limit SL bilgi notu · **tema-uyumlu snackbar** (`utils/snackbar.dart`) + Türkçe emir mesajı · ana sayfa **Bugün/Toplam** perf (backend holding `change_percent` + `dailyPnl`) · stres terim sadeleştirme + "Normal/Siyah Kuğu" UI gizleme (`_HIDDEN_SCENARIOS`) · haber **stale-while-revalidate** · What-If **net tarih** (`/what-if` `start_date`). flutter 27 · pytest 236 · analyze temiz.
- **39** (17 Haz): **not-alma FRONTEND** — `Note` modeli + `NotesProvider` + `api_service` 4 metot + **Yatırımcı Günlüğü** ekranı (Profil>Araçlar) + hisse detay **"Notlarım"** + ortak `note_editor.dart` helper; flutter 24→27, analyze temiz; canlı CRUD curl ile doğrulandı; **commit+push (auto-deploy canlı)**. Ayrıca **deploy gerçeği netleşti**: auto-deploy On Commit AÇIK; eski "Manuel Deploy bloker" notu yanlıştı → düzeltildi. ⏳ cihaz doğrulaması
- **38** (16 Haz): **yatırımcı günlüğü (not alma) BACKEND — CANLI** — `notes` tablo (kendi id PK; symbol NULL=genel) + `/api/v1/notes` CRUD + 14 test (pytest 236) + migration `e3f9b2c5a1d7` (Neon'da koştu, curl ile doğrulandı).
- **37** (15 Haz): kalan endpoint testleri +55 (pytest 222) · commit+push `48c4bae`/`6d37373`
- **36** (14 Haz): **watchlist → backend** (`watchlist_items` tablo + `/api/v1/watchlist` CRUD + frontend senkron, CANLI; cihaz bekliyor) · test +47 (trading/portfolio/behavior/stress HTTP + ilk Flutter testleri) · Flutter suite onarıldı (24 yeşil) · `news_analysis` max_tokens fix
- **35** (13 Haz): çizim kalıcılığı **backend** (`chart_drawings` tablo + API, CANLI) + **frontend** Faz 2 (timestamp-bazlı, analyze/release temiz, **cihaz bekliyor**)
- **34** (13 Haz): chart çizim araçları (kanal/ışın/not/pozisyon/vline) + masaüstü yatay-tekerlek + haber filtresi (Tümü/Portföyüm/İzleme) + nav AI Koç FAB
- **33** (5 Haz): alarm uygulama-içi teslimat + okunmamış rozeti + screenshot Pillow decode-doğrula (415) + flaky test fix
- **32** (5 Haz): chart overhaul (11 tester maddesi: renk/mıknatıs/kalıcılık/zoom/canlı yenileme) + cache-first açılış
- **31**: CI (GitHub Actions) + auth testleri (27) + frontend UX + **sekme yeniden düzenleme** (AI Koç FAB, "Piyasalar"→"Ana Sayfa", araçlar Portföy'de merkezi)
- **30**: para-yolu test omurgası (52 test, sıfır prod kod) — 28. turun FX "sahte servet" bug'ının nöbetçisi
- **27–29**: benchmark makro 2026 + "dönem boyu sabit" notu + replay "tarihe git" + **İlgili Haberler kalite revizyonu** (LLM enrich + TR/EN dil kapısı + BIST Türkçe ticker sorgusu)
- **20–26**: **cloud deploy** (Render+Neon, Umut) + AI Koç sohbet duplikasyon fix (`flutter_client_sse` kaldırıldı) + haber TR sentiment (VADER+TR sözlük) + Android APK + 47-endpoint canlı audit + forgot-password user-enum fix + portföy snap-back CSS fix
- **19**: screenshot OCR kota fix + haber NewsAPI→RSS (gerçek zamanlı TR/EN) + doküman temizliği (eski 2. handoff silindi)
- **1–18** (CHANGELOG v1–v6): büyük refactor + premium data-ink UI + AI birleşik `llm_service` (Gemini 2.5 + Groq fallback) + trade/limit emir/SL-TP + price_chart motoru + portföy import (manuel/toplu/OCR) + risk profili/akademi/görevler/what-if/mum-pratiği + fear&greed/makro/altın/alarm/benchmark + Postgres+Alembic+JWT refresh+Redis altyapı

---

## 🛡 KALICI KURALLAR (asla ihlal etme)

- **Para gösterimi:** `fontFeatures`/`tnum` YOK, `MoneyText` kullan ([[feedback_money_glyph_html_renderer]]).
- **CustomPainter'da metin YOK** — Stack/Positioned Text ([[feedback_canvas_text_unreliable]]).
- **UI:** pure-black data-ink, `Border.all` yok, glow yok, monokrom; yeşil/kırmızı sadece veri ([[feedback_data_ink_design]]).
- **AppBar transparent YOK** → `c.bg` ([[feedback_appbar_transparent_ghost]]).
- **FX tek kaynak** `fx_service.py`, `*_try` alanları ([[feedback_fx_single_source]]); yerel kur yazma.
- **AI (6. turda GÜNCELLENDİ):** Model adı **SÜRÜM DEĞİL TAKMA AD** olmalı —
  `gemini-flash-latest` / `gemini-flash-lite-latest`. Eski "2.5'te kal" kuralı
  ÖLDÜ: `gemini-2.5-flash` ve `-flash-lite` 4 Eylül'de **404 "no longer
  available to new users"** demeye başladı ve TÜM AI özellikleri (sohbet · haber
  enrich · piyasa etkisi · temel analiz · makro takvim) aynı anda sessizce
  düştü. Takma ad sürüm kalkınca kendiliğinden geçer.
  · **`thinking_budget=0` KULLANMA** — güncel Flash modelleri **400
  INVALID_ARGUMENT** veriyor; `thinking_level` kullan (`_thinking_config()`).
  Model adı doğru olsa bile bu tek alan tüm çağrıları öldürüyordu.
  · Alternatif modele düşme koşulu `_should_try_alt_model`: kota (429) **+ model
  yok (404) + yoğunluk (503)**. Yeni bir Gemini çağrı yolu eklersen bunu
  kullan; yalnız 429'a bakan yol (eski `stream`) 404'te boşluğa düşer.
  · JSON modu + grounding birlikte olmaz ([[project_llm_provider_arch]]).
- **AI hata ekranı:** yükleniyor/hata/**Tekrar Dene** için `lib/widgets/ai_sheet.dart`
  → `AiSheet` kullan (kendi FutureBuilder'ını yazma). Uç hatayı 200 +
  `{"error": ...}` ile bildiriyorsa `isFailure` ver. `setState`'i **blok
  gövdeyle** yaz: `setState(() => _x = future)` ok gövdesi Future döndürür ve
  framework assert'i retry'i sessizce öldürür.
- **AI'ya HAM sembol verme (6. tur):** Modele giden her metinde
  `backend/app/utils/symbol_display.py` → `compact()` kullan (GC=F→Altın,
  USDTRY=X→USD/TRY, .IS/.FON kırpılır). Arayüzdeki `SymbolDisplay` LLM
  çıktısını düzeltemez — model bağlamda ne görürse cevabında onu yazar
  (Kerem: "bu GC=F her yerde karşıma çıkıyor, hiçbir yerde çıkmasın").
  Kayıt/sorgu/filtre HAM sembolde kalır; değişen yalnız gösterim.
- **Fiyat cache'i: kayıt ≠ tazelik penceresi (6. tur):** Kayıt
  `_KEEP_TTL_SECONDS` (6 saat) boyunca DURUR; tazelik kararı yaşa bakılarak
  verilir (60 sn taze · 10 dk'ya kadar sessizce yenile · üstü bayat-ama-servis
  edilir + arka planda tazele). Kaydı stale penceresi kadar yaşatma: 10 dakika
  sonra kayıt silinince kullanıcı isteği BLOKLAYAN çekime düşüyordu
  (`/portfolio/1` canlıda 5,8 sn). Yeni fiyat yazan yolda `_KEEP_TTL_SECONDS`
  kullan.
- **Temel oran cache'i de kayıt ≠ tazelik (7. tur — aynı dersin ikinci kez
  ödenmesi):** `signal_service` temel oranları `_FUND_KEEP_HOURS` (7 gün)
  saklar; 12 saat yalnız TAZELİK eşiğidir ve **sembole göre 9-12 saate
  dağıtılır** (`_fund_fresh_seconds`, zlib.crc32, yalnız aşağı — eşik kaydın
  kendi TTL'ini geçmemeli). Bayat oran anında servis edilir, tazeleme
  `_schedule_fund_refresh` ile arka planda olur. **Neden:** 12 saatlik düz TTL
  44 hisseyi aynı anda düşürüyordu (hepsi aynı taramada yazılıyor) → canlıda
  `/signals` **20,7 sn**, günde iki kez, bedeli Sinyaller'e ilk giren
  kullanıcıya. Yeni bir "pahalı ama yavaş değişen" veri cache'lerken (temel
  oran, sektör, katalog) bu deseni kullan: kaydı uzun tut, tazeliği ayrı ölç,
  eşiği sembole yay.
- **Seri cache'leri (kapanış/OHLCV) de kayıt ≠ tazelik (9. tur — aynı dersin
  ÜÇÜNCÜ kez ödenmesi):** `get_daily_closes` / `get_daily_ohlcv` "stale-if-error"
  yazılmıştı: bayat kayıt varken bile istek yolunda BLOKLAYAN batch çekim
  yapılıyordu (canlı: soğuk `/signals` 10,0 sn, ardından tam tarama 0,41 sn).
  Artık bayat seri anında servis edilir, tazeleme `_schedule_series_refresh`
  ile arka planda TEK batch olur, yalnız **hiç kayıt yoksa** bloklanır.
  ⚠️ Burada **JITTER YOK** (temel orandan farkı): semboller tek batch'te
  iniyor, senkron bayatlama = tek istek; eşiği yaymak batch'i parçalardı.
  Jitter yalnız **sembol başına ayrı istek** atan cache'lerde doğru.
- **Sessiz filtre yasak — oranı HER turda logla (9. tur):** bir katman veri
  eliyorsa (LLM enrich, alaka filtresi, dil kapısı) yalnız eşik aşılınca değil
  **her turda** kaç girdi/kaç çıktı olduğunu bas; hangi katmanın elediği
  ayrıştırılabilir olsun. Haber sayısının neden düştüğü aylarca görülemedi
  çünkü yalnız %50 üstü eleme uyarı basıyordu. Aynı kural "LLM boş yanıt
  döndü" gibi sessiz degradasyonlar için de geçerli: yut ama LOGLA.
- **Deploy doğrulaması tahminle yapılmaz (9. tur):** canlıdaki commit
  `/health`'ten okunur (`{"status":"healthy","commit":"162de26"}`). Push
  sonrası önce commit'i doğrula, sonra ölçüm yap — yoksa eski sürümü ölçersin.
- **Soğuk yol ölçümü sessizlik ister (9. tur):** arka plan yenileyici
  `_REFRESH_ACTIVE_WINDOW` (30 dk) içinde istek geldiyse çalışır ve cache'i
  taze tutar. "Soğuk" bir ucu ölçeceksen **30+ dk hiç istek atma** — ölçümden
  hemen önceki `/health` poll'u bile sonucu bozar.
- **Arka plan tazelemesi eklerken iki emniyet (7. tur):** (a) eşzamanlı tur
  sayısını sınırla (`_FUND_REFRESH_MAX_INFLIGHT=3`) — 44 bayat sembol 44 thread
  açıp Finnhub ücretsiz tier'ını (~60 istek/dk) 429'lar; (b) **geçici kaynak
  hatası eldeki İYİ kaydın üstüne yazmasın** — `data_limited`/None sonucu
  yalnız hiç kayıt yokken cache'lenir (negatif cache korunur), kayıt varsa
  bayat damgasıyla durur ve sonraki tur yeniden dener. Yoksa tek bir 429
  hisseyi saatlerce "temel oran yok" gösterir.
- **Performansta önce ÖLÇ, hipotezi çürütmeye hazır ol (7. tur):** `/signals`
  yavaşlığında ilk hipotez ("aynı OHLCV Redis'ten 3 kez okunuyor, ~150
  gidiş-dönüş") makuldü ve **yanlıştı** — sıcak TAM tarama 0,71 sn ölçüldü,
  gerçek payı ~0,3 sn. Kök sebebi ayıran ölçüm **kripto vs hisse** tek-sembol
  karşılaştırmasıydı (kriptoda temel oran yok → 0,3 sn; hissede 2,8-5,3 sn).
  Auth'lu uçta `?force=true` + tek-sembol uçları soğuk/sıcak ayrıştırır.
- **Uyuyan sunucuda giriş (6. tur):** Render ücretsiz instance boşta uyur, ilk
  istek ~30-50 sn. Giriş/kayıt `_postAwake` üzerinden gider: 45 sn timeout +
  zaman aşımında BİR kez otomatik tekrar. Kullanıcıya ham istisna gösterme
  ("Sunucu hatası: TimeoutException" yerine "uyanıyor olabilir").
- **Provider'da `await` sonrası kimlik doğrula (6. tur):** `_userId`'yi BAŞTA
  yerel değişkene al, her `await` sonrası `_userId != uid` ise sessizce dön.
  Yoksa (a) oturum düşünce `_userId!` patlar — canlıda "Portföy yüklenemedi:
  Null check operator used on a null value" görüldü, (b) çıkıştan sonra dönen
  yanıt eski kullanıcının verisini ekranda bırakır. Erken dönüş eklediğin her
  yerde çıkış dalında loading bayraklarını indir.
- **Haber enrich sembolü susturmasın (6. tur):** LLM alaka filtresi ölçümde
  haberlerin %36'sını eliyor ve 16 sembolün 5'ini listeden TAMAMEN siliyordu.
  `_restore_silenced_symbols` sessizleşen her sembolün en yeni haberini geri
  koyar. Yeni bir filtre eklersen bu garantiyi koru — kullanıcı için "hiç haber
  yok" ile "az haber var" çok farklı.
- **Türkçe hisse arama:** `bist_catalog.py` + `tr_fold`, yf.Search'e güvenme ([[feedback_turkish_search_yahoo_gotcha]]).
- **Sembol GÖSTERİMİ (40. tur dersi):** ham Yahoo sembolünü (`GC=F`/`=X`/`^`) kullanıcıya BASMA → `SymbolDisplay.compact` (GC=F→Altın). Kayıt/filtre HAM sembolde kalır, yalnız gösterim dostu. Yeni ekranda sembol gösterirken bunu uygula.
- **Snackbar (40. tur):** `utils/snackbar.dart`→`showAppSnackBar(context, msg, isError:)` kullan (tema-uyumlu floating/yuvarlak); ham `ScaffoldMessenger`+default `SnackBar` YOK. İşlem mesajları Türkçe ("AL emri gerçekleşti").
- **Skor barı rengi (42. tur dersi):** `IOSScoreBar` skoru renklendirir (**≥70 yeşil**, 40-69 amber, <40 kırmızı) → yeni skor ekseni **yüksek=iyi** olmalı (yoksa "yüksek risk yeşil" yanıltır); hisse-dışı analizde 3. eksen "Risk" DEĞİL → **Dayanıklılık/İstikrar**.
- **Varlık sınıfı tespiti (42. tur):** `fundamental_analysis_service._classify` — `-USD`→kripto · `=X`→forex · `=F`→emtia · else hisse. Hisse-dışında F/K/bilanço ANLAMSIZ → `_analyze_macro` (sınıfa özel prompt). "Varlık tipine göre" yeni mantıkta bunu kullan.
- **Toplu haber (42. tur):** çok-sembollü haberde (Portföyüm/İzleme) sembol-başına döngüyle `/news/latest` ÇAĞIRMA (N LLM = yavaş) → `/news/for-symbols?q=…&q=…` (`get_news_for_symbols`: paralel çek + TEK batch enrich, küme-cache).
- **BIST/.IS günlük değişim (43. tur):** quote `change_percent` için `period` ≥ **5d** kullan — `2d` gece/BIST kapalıyken tek bar döndürüp `prev=current` → "Bugün %0" (`market_data_service` `_fetch_stock_data`/`_fetch_many`).
- **NaN son-kapanış / BIST kapalı (47. tur — KRİTİK, tekrar düşme):** yfinance, BIST (.IS) **kapalıyken** `history()` SON barını **NaN** döndürebilir → ham `Close.iloc[-1]` NaN olur. Fiyat/getiri/seri hesaplayan HER yerde **NaN kapanışları AT** (`Close.dropna()` / NaN filtresi), son **GEÇERLİ** kapanışı kullan; hiç geçerli yoksa graceful **404**. Yakalanan bug'lar: `benchmark._fetch_series` yalnız `start`'ı NaN kontrol ediyordu → `end`=NaN → getiri NaN → **Pydantic NaN'ı JSON'da `null`'a çevirir** (şema `float` olsa bile geçer!) → "Portföyün %0/hesaplanamadı"; `market._fetch_stock_data` ham `iloc[-1]` → TÜPRAŞ `/price` **500**. (`_fetch_many` zaten `dropna` yapıyordu, o yüzden bazı yollar çalışıp bazıları çalışmıyordu — yanıltıcı.) **Ders:** "sayı null geliyor ama kod float üretmeli" → **NaN ara** (deploy eski sanma; benim ilk yanlış teşhisim buydu). Gündüz BIST açıkken son bar dolu → bug görünmez; gece tekrar eder. **48. tur (KRİTİK genişletme):** dict'i HAM dict olarak (Pydantic'siz) dönen uçlarda NaN **`null`'a çevrilmez** — **Starlette `JSONResponse` `allow_nan=False` ile render edip `ValueError` → HTTP 500** atar (Pydantic yolundan farklı!). Bu turda 3 uç böyle çöktü: fear-greed (`sp500 NaN`), grafik (`1d` günlük seride bugünün yarım barı NaN OHLC). **Artık GLOBAL AĞ VAR:** `app/core/json_response.py` **`SafeJSONResponse`** FastAPI `default_response_class` → her uçta render öncesi NaN/inf→null; tek NaN hiçbir ucu çökertmez. AMA bu son savunma — **veri doğruluğu yine kaynakta** (grafikte NaN satırı ATLA, null mum çizme; skorda NaN→nötr). · **yfinance `.info` (quoteSummary/crumb) Render datacenter IP'sinde BLOKLU/boş** (curl_cffi'ye rağmen) → hisse temel-analizi 404'lüyordu; **chart-endpoint** (`t.history()`, `fast_info`) AYNI IP'de çalışır → `.info`'ya bağımlı yerlerde `fast_info`/history fallback kur (bkz. `fundamental_analysis_service._fast_price`, `data_limited`).
- **Tarayıcı doğrulaması (3 Eyl):** Claude for Chrome eklentisi Portly'de **KAYDIRAMIYOR** (fare tekerleği · klavye · sürükleme · JS `WheelEvent` · Flutter `flt-semantics-placeholder` — beşi de denendi). Tıklama · sekme geçişi · ekran görüntüsü · `read_network_requests` çalışır; `find`/`read_page` canvaskit yüzünden boş. **Listenin altı için Kerem'den kaydırmasını iste**, ısrarla deneme. Ağ sayımı için sayfayı yeni `?cb=` ile yükle (izleme ilk tool çağrısında başlar).
- **Dürüst boş-durum — fiyat VE değişim (3 Eyl, 2. tur):** Sayı bilinmiyorsa **0 BASMA**, bayrak taşı. İki bayrak var: `price_available` (fiyat alınamadı → maliyete düşüldü) ve **`change_available`** (fiyat var ama GÜNLÜK DEĞİŞİM bilinmiyor — altın/gümüş spot kaynağı dünkü kapanışı vermez; ayrıca borsa kapalıyken **tek bar** dönen her yol). Arayüz: "Bugün" satırını hiç gösterme · rozeti sönük "—" yap · portföyün günlük toplamına o pozisyonu KATMA · AI bağlamına "bilinmiyor" yaz. Yeni fiyat kaynağı eklerken alanı doldur (varsayılan `True` = eski davranış). Sebep: canlıda altın fiyatı oynarken "Bugün +%0,00" yeşil yazıyordu.
- **Zayıf halka / AI öneri çeşitliliği (43. tur):** zayıf halka en sert **%-düşene** göre (₺ kaybına DEĞİL — büyük USD pozisyonlar ₺ kaybına baskın, senaryodan bağımsız hep aynı çıkar). AI portföy havuzunu **geniş tut + `random.shuffle`** (dar/sıralı havuz → LLM hep aynı mega-cap'i seçer; `ai_portfolio_service`).
- **Bracket / OCO (44. tur):** Limit alış dolunca koruma kuran TEK yer `check_and_fill_pending_orders` (`_arm_protection_children`; LIMIT BUY + `sl_price`/`tp_price` dolu). OCO çapası = `parent_order_id or id` (`_cancel_bracket_siblings`, **kullanıcı-bazlı**): limit'te çocuklar parent LIMIT id'sine, market'te ikinci leg (TP) ilk leg'in (SL) id'sine `parent_order_id` ile bağlanır. SL/TP yalnız LIMIT BUY'da (SL<limit<TP). Worker döngüsünde top-of-loop `status != "PENDING"` guard ŞART (OCO kardeşi tur ortasında iptal edebilir). Yeni emir tipinde bu kalıbı koru.
- **Onboarding / tek-sefer ekran (45. tur):** Gösterim `onboarding_seen` SharedPreferences flag'iyle kontrol edilir (`AuthGate`, auth'tan ÖNCE). **Logout flag'i SİLMEZ** (yalnız token/refresh/user key) → giriş-çıkış turu tekrar açmaz. Yeni tek-sefer ekranda bu kalıbı koru; logout'ta `prefs.clear()` ÇAĞIRMA (flag'i uçurur).
- **AI Koç FAB (45. tur):** Scaffold `floatingActionButton` DEĞİL — `main.dart` body'de `LayoutBuilder`+`Stack`+`Positioned`+`GestureDetector(onPanUpdate)` (sürüklenebilir). Konum `_fabPos` (state, KALICI değil — her açılışta sağ-alta döner). FAB'a dokunma/konum eklerken burayı düzenle; `heroTag:'coachFab'` çakışmayı önler.
- **AI chat önerisi (45. tur):** `chat_service.get_system_prompt` kural #1 artık hisse/sektör/ETF **önerisine İZİN VERİR** (eğitsel/sanal; gerekçe + 2-3 alternatif + "tavsiye değil" uyarısı zorunlu). "AI asla tavsiye vermez" varsayımıyla yeni kısıt EKLEME; max_tokens=1200 (yarıda kalmasın).
- **Haber bölge yönlendirme (46. tur):** `symbol_display.newsQuery` sembole **bölge öneki** koyar (`.IS`/`.TR`→`tr|`, gerisi→`en|`); backend `_split_region` çözüp `_REGION_PARAMS`'tan `hl/gl/ceid` seçer. **BIST→TR baskı, ABD/kripto/döviz/emtia→EN orijinal** (Reuters/Bloomberg → VADER okur, "Nötr 0.00" agregatör çöpü çözülür). Sorgu `f"({clean}) {qualifier}"` paranteziyle sarılır (parantezsiz → BIST OR'lı sorguda filtre boşa gider); niteleyici `_FINANCE_QUALIFIER[region]` (TR/EN ayrı). Yeni sembol-haberi yolunda öneki + parantezi KORU.
- **Haber toplu yol = ham-önce + arka plan enrich (46. tur):** `get_news_for_symbols` ilk açılışta `_collect_raw_for_symbols` (RSS + bölge VADER/TR + det. filtre, LLM YOK) **HEMEN** döner; LLM enrich `_refresh_multi_bg` thread'inde arka planda → sonraki açılış rafine görür. Enrich'i tekrar SENKRON yapma (ilk açılış yavaşlar + alaka-elemesi haber sayısını düşürür → Kerem "13 Mayıs'a iniyor" dedi). Sembol-başı cap=`_PER_SYMBOL_CAP`(10) ilk-açılış hacmini belirler — daraltma. (Tekil hisse-detay yolu `_fetch_google_news` enrich'i senkron tutar, sorun değil: tek sorgu küçük.)
- **FAB sürükleme (46. tur):** `main.dart` `onPanUpdate` delta'yı build-anı yerel `pos`'a DEĞİL **güncel `_fabPos`'a** ekler (`_fabPos ?? pos` taban) → bir frame'de çok pan olayı en taze konumu okur (setState closure senkron), ara delta düşmez. Sürüklenebilir öğede bu kalıbı koru.
- **Bekleyen SAT iptal (47. tur):** Pozisyon satışla küçülünce/kapanınca, eldeki lotun karşılamadığı bekleyen SAT emirleri (LIMIT SELL + STOP_LOSS + TAKE_PROFIT) `order_service._cancel_unfillable_sell_orders` ile CANCELLED olur (`execute_trade` SELL dalında; `db.commit` çağırana bırakılır → tek transaction). OCO/çapa mantığı GEREKMEZ — doldurulamayan tüm SAT doğrudan iptal. Yeni satış yolunda koru (yoksa "hayalet" bekleyen emir kalır — Umut bildirdi).
- **Dosya export/paylaşımı (47. tur):** Backend dosya endpoint'i auth'lu (`get_current_user`) → mobilde HAM URL'yi `launchUrl` ETME (Bearer token taşımaz → 401 "Not authenticated"). `api_service.fetchCsvBytes` ile token'lı çek, sonra: web → Blob (`file_download.dart`), mobil/masaüstü → `share_plus`+`path_provider` (`share_file.dart`). **`dart:io`'yu web'de derlenecek dosyada DOĞRUDAN import etme** → conditional import şart (`export '..._stub.dart' if (dart.library.io) '..._io.dart'`).
- **Haber ton ≠ piyasa etkisi (47. tur):** Liste rozeti haberin **TONUNU** ölçer (VADER/enrich, "Ton" etiketli); detay sheet "**AI Piyasa Etkisi**" (`analyzeNews` → `expected_impact_pct` → "…Etki") **başka şey** ölçer → ikisi çelişebilir ("petrol düştü" tonu+ ama petrol varlığına etkisi−). Yeni haber UI'da bu ayrımı koru, aynı sanma.
- **FAB sürükleme (47. tur — 46'yı tamamlar):** FAB butonunun kendi dokunma algılayıcısı (onPressed) sürükleme (onPanUpdate) ile **gesture arena**'da yarışır → Android'de pan kaybolur. TEK `GestureDetector` hem `onTap` (sohbet) hem `onPanUpdate` sahiplensin; FAB **`IgnorePointer`** ile sırf görsel + `behavior: HitTestBehavior.opaque`. Sürüklenebilir butonda bu kalıbı koru.
- **Logo (47. tur):** Marka logosu `assets/images/logo.png` (şeffaf emblem, AppBar/giriş/onboarding kullanır). **Web açılış splash'i** `web/index.html` `#splash .mark` → `web/logo.png` (Flutter boot ÖNCESİ; web-kökü statik dosya, Flutter asset yolu DEĞİL). Platform ikonları (web favicon/PWA maskable, android mipmap, ios AppIcon) emblem→**beyaz-zemin kare** üretilir (iOS **opak, alpha YOK**; maskable ~%18 güvenli kenar). Yeni ikon gerekirse aynı emblemden üret.
- `transactions.fee` kolonu YOK · Monte Carlo n=10000 sabit · `extra="allow"` + per-IP limit koru.
- **Flutter testi (36. tur dersi):** widget testinde `toImage`/`toByteData` **MUTLAKA `tester.runAsync()` içinde** (yoksa FakeAsync 10 dk timeout) · provider pump'layan testte `pumpAndSettle` YOK (gerçek ağ tetiklenir) → sınırlı `pump(Duration)` · `flutter test` çıktısını `| tail`/`| grep`'leme (**exit kodu maskelenir**; `> log 2>&1; echo $?` kullan).
- **Oturum içi 401 (5. tur):** Yeni bir backend çağrısı eklerken `ApiService` içinde **`_client`** kullan (`http.get/post` DEĞİL) — `_AuthRetryClient` 401'de token'ı bir kez yenileyip isteği tekrarlıyor. `login/register/refresh/fetchMe/logout` bilerek düz `http` (refresh döngüsü + çıkışta oturum dirilmesi). Yenileme kancası `ApiService.onUnauthorized`, `AuthProvider` dolduruyor; tek-uçuş kilidi var (refresh token tek kullanımlık).
- **Haber havuzu tavanı adil paylaşılır (6. tur):** `_fair_share` tavanı
  (`_SYMBOL_POOL_LIMIT`) semboller arasında SIRAYLA dağıtır. Saf tarih
  sıralaması sık yayın yapan ABD kaynaklarına yarıyordu: canlı ölçümde 90
  haberin 72'si ABD'ye gidiyor, 13 BIST/fon pozisyonuna 18 haber kalıyordu
  (Kerem: "türk haberleri az"). Yeni bir sıralama/kırpma eklersen bu adil
  dağıtımı bozma.
- **Google News kısıtlaması SESSİZDİR (5. tur):** RSS ucu 429 vermez, **HTTP 200 + BOŞ feed** döner. Boş yanıtı "haber yok" sayma → `_raw_cache`'teki eski sonucu koru (`_fetch_google_cached`), tur başına çekimi bütçele (`_FETCH_BUDGET`), eşzamanlılığı düşük tut (`_FETCH_CONCURRENCY=6`). Sembol sayısını artırmak serbest; **istek sayısını** artırmak değil.
- **Haber alaka eşlemesi (5. tur):** Toplu haber yanıtındaki **`matched_query`** (haberi getiren sembol sorgusu) alanını istemci filtresinde İLK kriter olarak kullan. Başlıkta ticker aramak yetmez ("Lockheed Martin" başlığında "LMT" yok) ve `affected_assets` yalnız ~100 popüler şirketi tanır — bu iki heuristik canlıda haberlerin %47'sini eliyordu.
- **₺ maliyet ALIŞ kuruyla (4. tur):** USD varlığın ₺ maliyeti canlı kurla
  çevrilmez — `portfolios.fx_rate_at_cost` ile çarpılır (yoksa kur kazancı K/Z'de
  görünmez). Yeni pozisyon yazma yolunda kuru işaretle:
  `fx_service.rate_at_cost(currency_of(canonical(sembol)), tarih)`. NULL = kur
  bilinmiyor → eski davranış. Geçmiş kur **frankfurter**'dan (Yahoo DEĞİL, 429).
  Ayrıntı ↑ "BURADAN BAŞLA" madde 3.
- **Pozisyon satırı yazma (4. tur):** `portfolios(user_id, symbol)` benzersiz;
  lot/maliyet güncelleyen HER yol `order_service._locked_position` (FOR UPDATE) +
  `_merge_buy_lot` üzerinden gitmeli. Ham `db.query(Portfolio)...first()` ile
  oku-değiştir-yaz YAPMA (kayıp yazma + çift satır). SQLite'ta FOR UPDATE
  sessizce düşer, test davranışı değişmez.
- **Oturum durumu paylaşımlı cache'te (4. tur):** logout kara listesi ve şifre
  sıfırlama kodları `app.core.cache`'te (`auth:bl:` / `auth:reset:` önekleri),
  süreç belleğinde DEĞİL — süreç restart'ında oturum durumu kaybolmasın. Kara
  listede ham token değil SHA-256 özeti durur. Yeni oturum durumu eklerken
  modül-global set/dict KULLANMA.
- **Hız sınırı anahtarı (4. tur):** `limiter.client_key` X-Forwarded-For'un EN
  SAĞ girdisini okur (her vekil listeye EKLER → son girdiyi güvendiğimiz vekil
  yazar; ilk girdi istemci tarafından sahtelenebilir). `get_remote_address`'e
  geri DÖNME — Render'ın arkasında herkesi tek kovaya sokar.
- **Süreç:** batch bitir → STOP → kullanıcı onayını bekle, churn yapma; cihazda doğrulanmadan
  "düzeldi" deme; niyeti daralt ([[feedback_session_overreach]]).

---

## ▶️ ÇALIŞTIRMA

- **🪟 Windows makine (Umut, 50. tur):** venv yolu `backend/venv/Scripts/` →
  `./venv/Scripts/python.exe -m pytest|uvicorn|alembic ...`. `backend/.env` lokalde
  **SQLite** kullanır (Neon'a dokunmaz). Eski `portly.db` pivot-öncesi şemaydı →
  `portly.db.bak-20260705` olarak yedeklendi; taze DB `Base.metadata.create_all` +
  `alembic stamp head` ile kuruldu (tam Alembic zinciri SQLite'ta koşmaz,
  `b48806822728` Postgres-özel). Test kullanıcı lokalde yeniden kayıtlı
  (umut@mail.com/123456, AAPL pozisyonlu). Frontend dev:
  `flutter run -d web-server --web-port 8091 --web-hostname 127.0.0.1` →
  http://127.0.0.1:8091 (kök `.env` USE_PROD_API=false → lokal backend).
- **⚠️ venv (Mac lokal gotcha):** Proje `Desktop/Projeler/` altına taşındı → venv konsol-script
  shebang'ları ESKİ yolu gösteriyor → `venv/bin/pytest`·`uvicorn`·`alembic` doğrudan **"bad interpreter"** verir.
  **Geçici:** `venv/bin/python -m pytest` · `venv/bin/python -m uvicorn app.main:app ...` · `venv/bin/python -m alembic upgrade head`.
  **Kalıcı:** venv'i yeniden kur (`python3 -m venv venv && venv/bin/pip install -r requirements.txt -r requirements-dev.txt`).
- **Testler:** backend `cd backend && venv/bin/python -m pytest -q` → **695 passed** (4 Eyl 7. tur: +15 — temel oran bayat servis/arka plan tazeleme/eşzamanlılık sınırı/tarama tek okuma) · eski: **680 passed** (4 Eyl 6. tur: +41 — LLM model dayanıklılığı 14, enrich sembol garantisi 4, havuz adil paylaşım 3, sembol gösterimi 13+3, fiyat cache servis 4) · eski: **618 passed** (3 Eyl 4. tur: +17; ⚠️ özet satırı "N passed" bu kurulumda basılmıyor → exit kodunu kullan) · eski not: **570 passed** (3 Eyl 2. tur: +20 — emtia değişim bayrağı, chart tek-bar, EN haber çöp filtresi) (47. tur +2: piyasa satışı bekleyen SAT iptali; ağ/Postgres yok; HTTP kapsam: auth/trading/portfolio/coach/chat/market/news/watchlist/notes/alerts/behavior/stress). Frontend `flutter test` → **88 passed** (4 Eyl 6. tur: +18 — 401 kurtarması 9, AiSheet retry 5, oturum yarışı 2, uyanma tekrarı 2) · eski: **70 passed** (3 Eyl 4. tur: +3) (3 Eyl 2. tur: +5 — `fetchMany` dedup 4, `.FON`/`.IS` etiket 1; **proje kökünden** koş, `backend/`'den DEĞİL — yanlış cwd "Test directory test not found" + exit 0 verip sessizce hiç koşmaz). Migration izole doğrulama: temp DB + `alembic stamp <önceki_head>` → `upgrade head` → `downgrade -1` (tam zincir SQLite'ta koşmaz, `b48806822728` Postgres-özel).
- **Backend:** `cd backend && source venv/bin/activate && uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload`
  (telefon testi için `--host 0.0.0.0`). Postgres canlı olmalı — login 500/timeout = Postgres down ([[reference_local_run_postgres]]).
- **Web:** `flutter build web --release --pwa-strategy=none --no-tree-shake-icons`
  → `python3 serve_web.py 8091` (`--web-renderer` YOK — Flutter 3.29+ desteklemiyor; [[feedback_web_build_flags]]).
- **Telefon (LAN):** `.env`'de `API_BASE_URL_LOCAL`'ı Mac LAN IP yap (`ipconfig getifaddr en0`),
  backend `--host 0.0.0.0`, web'i telefonda `http://<LAN-IP>:8091` aç. **Commit öncesi `.env` geri al.**

---
*37. tur sonrası kondanse edildi (15 Haz 2026): tur-tur narrative → CHANGELOG.md + git log; canlı altyapı/blokerler arşivden öne taşındı. Tam eski sürüm: `../SESSION_HANDOFF.full-backup-20260615.md`. 46. tur (18 Haz): haber elden geçirme + denetim. 47. tur (19 Haz): telefon geri bildirimi cilası (logo + AL/SAT mesajı + bekleyen-SAT iptali + CSV share_plus + haber ton/etki + FAB gesture-arena), Claude güncelledi.*
