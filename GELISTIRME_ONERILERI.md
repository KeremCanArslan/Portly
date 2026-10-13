# Portly Geliştirme Önerileri / Yapılacaklar

> **Kanonik DETAYLI backlog.** Güncel durum, açık işler ve kalıcı kurallar için
> **SESSION_HANDOFF.md** (o üsttür — çelişirse handoff geçerlidir). Tarihsel
> tur-tur anlatım **CHANGELOG.md** + `git log`'da.
>
> **Son ayıklama: 3 Eylül 2026.** Pivotla ölen sanal-emir/trade maddeleri
> SİLİNDİ (aşağıda "Kapanmış konular"da tek satır olarak duruyorlar), biten
> işler koddan doğrulanıp listeden çıkarıldı, öncelik sırası bugüne göre
> yeniden yazıldı.

**Uygulama:** Flutter Web + FastAPI — gerçek **portföy takibi + haber + kural
tabanlı AL/TUT/SAT sinyal asistanı**. Sanal borsa DEĞİL: uygulama emir vermez,
işlem geçmişi kullanıcının kendi alış/satışını yazdığı **kayıt defteridir**.

**Bağlam:** Bitirme projesi, hoca demosu YAPILDI. Öncelik: **cila + dayanıklılık
> yeni özellik**.

---

## 🔲 Açık işler — öncelik sırasıyla

### 1. Cihaz doğrulaması (yalnız Kerem yapabilir)
Tek liste: **CIHAZ_DOGRULAMA.md**. Telefonda/PWA'da hiç görülmemiş ekranlar ve
3 Eylül düzeltmelerinin (A0) gerçek cihaz karşılığı orada. PWA cache temizliği
+ `?cb=` şart.

### 2. Tarayıcıda hâlâ görülmemiş ekranlar
Haberler UI · hisse detay (pre/post rozeti · AI Temel Analiz · BIST oran
tablosu · fon grafiği · çizim araçları) · pozisyon ekle/sat · izleme senkronu ·
Notlarım. Not: Chrome eklentisi Portly'de **kaydıramıyor** → listenin altını
görmek için Kerem kaydırır, Claude ekran görüntüsü alır.

### 3. ✅ Oturum içi 401 → refresh (3 Eyl 5. turda YAPILDI)
`ApiService._AuthRetryClient` 401'de token'ı bir kez yenileyip isteği
tekrarlıyor (`AuthProvider.handleUnauthorized`, tek-uçuş kilidi). SSE sohbet
akışı ayrıca elle yakalıyor; multipart yüklemede yalnız oturum tazeleniyor.
**Kalan: cihazda 60+ dakika açık bırakıp doğrulamak** (`CIHAZ_DOGRULAMA.md`
A000).

### 3b. ✅ Haber sayısı / hızı (3 Eyl 5. turda YAPILDI)
Kök sebep üç katmandı ve üçü de ölçüldü: istemci alaka filtresi gelenin %47'sini
eliyordu · Google News kısıtlaması sessiz (200 + boş feed) · sembol sınırı 24 <
38 pozisyon. Düzeltmeler: `matched_query` etiketi · sorgu-başına ham cache +
çekim bütçesi + düşük eşzamanlılık · `_MAX_SYMBOLS` 40 · çıplak ticker sorgusunun
şirket adıyla genişlemesi · enrich `max_tokens` ölçekli + kesik JSON kurtarma.
Ayrıntı ve sayılar: `SESSION_HANDOFF.md` 5. tur. **4 Eylül'de push edildi**
(`6a0f149`), deploy canlı. **Kalan: canlı ölçümün tekrarı** (auth'lu uç → token
gerek) **+ cihazda doğrulama**.

### 3c. ✅ Gemini modelleri kalkmıştı — TÜM AI ölüydü (4 Eyl, 6. turda düzeltildi)
`gemini-2.5-flash` ve `gemini-2.5-flash-lite` 404 "no longer available to new
users" vermeye başlamış; Groq yedeğinin de erişimi yok → sohbet · haber enrich ·
piyasa etkisi · temel analiz · makro takvim hep birden sessizce düşüyordu.
Model adları takma ada (`gemini-flash-latest` / `-lite-latest`) çevrildi,
alternatif modele düşme 404 + 503'ü de kapsayacak şekilde genişletildi,
`thinking_budget=0` (güncel modellerde 400) yerine `thinking_level` kondu.
**Kalan: canlıda AI Koç'a mesaj atıp cevap geldiğini görmek** (cihaz listesi
A0000).

### 3d. ✅ Canlı geri bildirim turu (4 Eyl, 6. tur — hepsi kapandı)
Kerem uygulamayı kullanıp beş şey bildirdi, beşi de düzeltildi: AI cevabında
ham sembol (`GC=F` → **Altın**; modele artık ham sembol verilmiyor) · Türk
haberi azlığı (havuz tavanı adil paylaşılıyor, **TR 18 → 40**) · portföyün geç
yüklenmesi (fiyat kaydı 10 dk'da siliniyordu → bloklayan çekim; canlıda 5,8
sn ölçüldü, artık bayat-ama-gerçek fiyat anında dönüyor) · sohbette yanıt
göstergesi ("Yanıt hazırlanıyor…" + "yazıyor") · uyuyan sunucuda giriş hatası
(45 sn timeout + bir kez otomatik tekrar). Ayrıca konsolda görülen
"Null check operator used on a null value" gerçek bir yarış hatası çıktı
(oturum düşerken portföy yükleme) ve düzeltildi.

### 4. Dayanıklılık (kalan)
- ✅ **Sinyal taraması — ÖLÇÜLDÜ ve DÜZELTİLDİ (4 Eyl, 7. tur; `95b05c4`).**
  Kök sebep ısıtma da tarama da DEĞİLDİ: kripto sembolü soğuk 0,3 sn, ABD
  hissesi soğuk 2,8-5,3 sn → fark tamamen **temel oran çekimi**. 12 saatlik
  TTL 44 hissenin hepsini aynı anda düşürüyordu (hepsi aynı taramada yazılıyor)
  → 44 × ~3 sn / 6 işçi ≈ 21 sn, faturayı Sinyaller'e ilk giren kullanıcı
  ödüyordu, günde iki kez. Düzeltme: kayıt 7 gün durur, 12 saat yalnız tazelik
  eşiği (sembole göre 9-12 sa'ya dağıtılmış), bayat oran anında servis edilir +
  arka planda tazelenir (eşzamanlı en fazla 3; geçici hata iyi kaydın üstüne
  yazmaz); ısıtma bayatı da yeniler; tarama OHLCV'yi işçi başına tekrar okumaz.
  Ayrıntı: `SESSION_HANDOFF.md` 7. tur.
- ✅ **Haber tazeliği / whiplash — ÖLÇÜLDÜ ve DÜZELTİLDİ (4 Eyl, 6. tur).**
  Gerçek ölçüm (24 sorgu, gerçek RSS + gerçek LLM): enrich 90 haberin 32'sini
  (%36) eliyor ve 16 sembolün 5'inin (AAPL · THYAO · TUPRS · KCHOL · KARCL)
  haberi TAMAMEN kayboluyordu. Eşik yerine daha dar bir garanti kondu:
  `_restore_silenced_symbols` — enrich bir sembolün tüm haberlerini elediyse en
  yenisi geri gelir (kalabalık sembollerde eleme aynen sürer). Sonuç: 90 → 63,
  kaybolan sembol 0. Eleme yarıyı geçerse uyarı log'u var; **canlı log'da bu
  oranın izlenmesi kaldı**.
- **TEFAS vekili** — Worker TEFAS yolunu POST olarak da vekilliyor; Render'a
  `TEFAS_PROXY_BASE` HENÜZ eklenmedi (TEFAS Render IP'sini kısarsa gerekecek).

### 5. Eski Neon verisinin birleştirilmesi
`backend/scripts/merge_old_neon.py` hazır (kuru çalışma varsayılan, üstüne
yazmaz). Kerem'den İKİ bağlantı dizesi gelmeden başlanamaz.

### 6. Şifre sıfırlama maili
Uç 200 dönüyor, mail gitmiyor. Kod hazır (Brevo HTTP API — Render SMTP'yi
blokluyor). **Bloker: Umut Render'a `BREVO_API_KEY` + `BREVO_SENDER_EMAIL`
eklemeli.** Not (7 Eyl, 11. tur): oturum açık kullanıcı artık maile ihtiyaç
duymuyor — `POST /auth/change-password` + Profil → Ayarlar → Şifre Değiştir
canlıda çalışıyor. Bu bloker yalnız **şifresini unutan** kullanıcıyı etkiliyor.

### 6b. ✅ Boş-durum ≠ hata (4 Eyl, 8. turda YAPILDI)
Tarama bulgusu: `ApiService` hata durumunda `null`/boş liste döndürüyor,
ekranlar bunu boş-durumla aynı sayıyordu → ağ hatasında 38 pozisyonu olan
kullanıcıya "BAŞLANGIÇ — ilk hisseni ekle", dolu izleme listesine "Listen boş",
alarmları olana "henüz alarm yok", notları olana "Günlüğün boş" deniyordu.
`PortfolioProvider._lastError` hiçbir ekran tarafından okunmuyordu.
Düzeltme: bölüm bazlı `portfolioError`/`marketError`/`newsError` + ortak
`widgets/load_error_card.dart` ("… yüklenemedi" + Tekrar Dene); `NotesProvider`
ve alarm ekranı da bağlandı. Yan bulgu: `fut.whenComplete(...)` türev future'ı
yakalanmıyordu → her başarısız istekte konsola "unhandled exception" düşüyordu
(`.ignore()`). **Kalan: cihazda görmek** (sunucu uykudayken / uçak modunda).

### 6c. ✅ CORS kilidi (7 Eyl, 12. turda canlıda DOĞRULANDI)
Canlı ölçüm: rastgele `Origin` başlığına `access-control-allow-origin: *`
dönüyordu. `main.py`'de CORS çözümü saf `resolve_cors_settings()` fonksiyonuna
alındı (7 test), `ALLOWED_ORIGIN_REGEX` desteği + prod'da `*` kalırsa açılış
uyarısı eklendi; `render.yaml` frontend adresine kilitlendi. ~~Render dashboard'daki `ALLOWED_ORIGINS` değeri güncellenmeden etkisi yok.~~
**Kapandı:** 7 Eyl'de canlı ölçüm — yabancı origin preflight'ta **400** ve
`access-control-allow-origin` başlığı YOK; gerçek frontend adresi **200**.

### 7. Ürün cilası (kota-bağımsız, küçük)
- ✅ **AI sheet'lerinde "Tekrar Dene"** (4 Eyl, 6. tur) — ortak `AiSheet`
  widget'ı; haber "AI Piyasa Etkisi" sheet'i de bağlandı. Ayrıca retry'i
  debug/profile derlemede sessizce öldüren `setState` assert'i düzeltildi.
- ✅ **Onboarding / boş ekran rehberi** (4 Eyl, 8. tur) — "ekran görüntüsünden
  aktar" CTA'sı hem "BAŞLANGIÇ" listesinin birinci sırasına hem de boş-durum
  kartına kondu (yalnız web; OCR yolu `dart:html`'e bağlı, mobilde zaten gizli).
  **Kalan: cihazda bir kez denemek.**
- ✅ **İlk dış kullanıcı turu** (7 Eyl, 11. tur) — Batuhan'ın 7 maddesi:
  BIST sektör haritası 90 → 623 hisse (BNTAS→Ambalaj, canlıda doğrulandı) ·
  fiziki altın portföye giriyor (11 ürün, ₺, alış fiyatıyla) · şifre
  değiştirme · PWA/Android paket kimliği · arama ipucu. Katılım fonları
  ZATEN vardı (270 fon) — "yok" değil "bulamadım"mış. **Kalan: cihazda
  doğrulama** (AÇILIŞ tablosu 1. madde).
- **Temettü ekranı** — çekirdek düzeltildi, cihazda bir kez oynanmadı.
- **Mum Tahmin Pratiği** — çalışıyor, yalnız öznel ince ayar kalmış olabilir.
- **Çökme/boş-durum taraması** — her ekran veri yokken/hata varken düzgün mü.

### 7b. Güvenlik — kalanlar (7 Eyl 12. turda açılan liste)
Yapılanlar 12. turda: şifre politikası · giriş limiti 5/dk · prod'da `/docs`
kapalı · güvenlik başlıkları · hesap silme (KVKK) · `users.created_at`.
Kalanlar:
- **Kayıtta e-posta doğrulaması yok** — isteyen istediği adresle kayıt olur.
  Arkadaş çevresinde sorun değil, **halka açılırken şart** (kod: kayıt sonrası
  tek kullanımlık bağlantı; Brevo anahtarı geldiğinde aynı altyapı).
- **Token web'de `localStorage`'da** — XSS olursa çalınır. Flutter web canvas'a
  çizdiği için yüzey dar; CSP eklemek canvaskit'i bozma riski taşıyor →
  denenecekse `flutter build web` çıktısıyla ölçülerek yapılmalı.
- **`umut@mail.com` şifresi `123456`** (16 canlı oturum). Kerem "şimdilik
  dokunma" dedi; değiştirilirse `CLAUDE.md`'deki test kullanıcı satırı da
  güncellenmeli.
- **Neon rol şifresi** 12. turda oturum kaydından geçti → Umut'a haber verip
  döndür (Neon reset → Render `DATABASE_URL` → deploy).

### 8. AI-ağır (kota-farkında: cache + kullanıcı-başı limit)
- **Ekran görüntüsü → AI sohbet** ("Midas ekranımı at, yorumlayayım";
  portföye aktarım ayrı ve bitti).
- **AI sohbete araç ekle** — anlık fiyat, portföyü okuma (grounding var).
- **AI portföy oluşturucu** — daha zengin gerekçe + risk profili eşlemesi.
- **"AI bugün yoğun" degradasyonu** her özellikte tek tip olsun (OCR dersi).

### 9. Büyük epikler (en sona)
- **Web push bildirimi** — önemli haber + koç özeti + alarm tetiği + sinyal
  değişimi. `price_alert` altyapısı genişler; saf altyapı işi.
- **Haber ↔ sinyal ilişkilendirme** + hisse detayına sinyal kartı.
- **Fon getiri karşılaştırma** (TEFAS verisi artık var, karşılaştırma yok).
- **Fiziki altın geçmiş grafiği** — bugün seri YOK (kaynak yalnız anlık fiyat
  veriyor). Ons altın × USDTRY'den türetmek mümkün ama o başka bir varlığın
  grafiği olur (kuyumcu makası girmez) → uydurma sayılır. Yapılacaksa gram
  altının kendi geçmişi bir kaynaktan toplanmalı ve ürün oranıyla ölçeklenmeli;
  ekranda "türetilmiş" diye işaretlenmeli.

### 10. Düşük öncelik
Anasayfa son dakika haber şeridi · anasayfa özelleştirme · roadmap/changelog
ekranı · portföy analitik derinliği (K/Z kırılımı, temettü takvimi) ·
rozet/streak (`missions` ekranı var, genişletilebilir).

---

## 🔒 Production'a açarken
- 🔴 **Secret'lar git'te** — `.env` + `backend/.env` izleniyor (repo private,
  bilerek): SECRET_KEY (JWT!), Gemini/News anahtarları, DB kimliği. Dağıtımdan
  önce anahtarları döndür, `.env`'i git'ten çıkar, prod'da ortamdan oku.
- 🔴 **AI ücretsiz kota** — flash günde 20 istek; birkaç kullanıcı dakikada
  bitirir → kullanıcı-başı limit ya da billing.
- **CORS** — kod + blueprint kilitlendi (bkz. 6c); **Render env'i hâlâ `*`**
  (`render.yaml`), frontend URL'ine kilitlenmeli.
- ~~**Token blacklist** süreç-içi `set` → Redis~~ ✅ **YAPILDI (3 Eyl, 4. tur)**
  — kara liste + şifre sıfırlama kodları `app.core.cache`'te.
- HTTPS ✅ · managed Postgres ✅ (Neon) · yedek · Sentry · CI/CD · Docker.

---

## ✅ Kapanmış konular (tekrar açma)

**Pivotla geçersiz (49. tur):** sanal emir motoru (market/limit/SL-TP/OCO/
bracket) · sanal bakiye · oto-trade denemesinin "emir ver" kısmı. Sinyal-only
kısmı YAPILDI (`signal_service` + Sinyaller sekmesi). Bu maddeler backlog'dan
SİLİNDİ — kod ve testleri de sökülmüştü.

**Biten işler (koddan doğrulandı; ayrıntı CHANGELOG.md + `git log`):**
TEFAS fon desteği (`.FON` sembolü, katalog, fiyat/grafik/sinyal) ·
izleme listesi backend senkronu · yatırımcı günlüğü (backend + `notes_provider`
+ `investor_journal_screen` + hisse detayında "Notlarım") · grafikte not ·
çizim kalıcılığı · fiyat alarmı (tetik + okunmamış rozeti) · ekran görüntüsünden
portföy aktarımı + Pillow doğrulaması · AI koç sohbet duplikasyonu · TR haber
duygu analizi · İlgili Haberler kalite revizyonu (LLM enrich + dil kapısı +
Türkçe ticker sorgusu) · dürüst boş-durum (`price_available` / `change_available`)
· Cloudflare Worker Yahoo vekili · kripto (Coinbase/Binance) ve **BIST (İş
Yatırım)** yedek kaynakları · fon kataloğunun günlük tazelenmesi · temel oran
arka plan ısıtması · küsüratlı adet · benchmark karşılaştırması · AI portföy
oluşturucu · JWT refresh/rotation/logout · rate limiter · Alembic göçleri.

---

## 🛠 Süregelen
**Veri hızı** — Redis + stale-while-revalidate + arka plan işçisi kuruldu;
kullanıcı isteği artık Yahoo beklemiyor. Soğuk cache yolunda hâlâ senkron-bloklu
kalan yer var mı, fırsat oldukça doğrula.
