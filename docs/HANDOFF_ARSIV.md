# Portly — Handoff Arşivi

> `SESSION_HANDOFF.md` şişmesin diye buraya taşınan **bitmiş turlar**.
> Güncel durum, açık işler ve kalıcı kurallar HÂLÂ `SESSION_HANDOFF.md`'de —
> burası yalnız geçmiş kayıt. Yeni session bu dosyayı okumak ZORUNDA DEĞİL;
> "bu neden böyle yapılmıştı" sorusu çıkarsa bakılır.

> **Arşive alınma tarihi:** 4 Eylül 2026 (8. tur). Taşınanlar: 3 Eylül 4./3./2./1. tur
> ve 2 Eylül üç turu ile 4 Temmuz büyük pivot bölümü.

---

> **Ek arşiv:** 7 Eylül 2026 (11.-12. tur) — aşağıdaki **8. ve 9. tur** oradan taşındı.

## 9. TUR (4 Eylül 2026) — ölçüm, üç darboğaz, bir gözlem eksiği
> Sıradaki iş için AÇILIŞ yeter; bu bölüm "bu neden böyle" sorusu içindir.

Kerem "devam edelim" dedi; tur canlı ÖLÇÜMLE başladı ve iki hipotez (biri
benim, ikisi başka bir modelin) ölçümle çürüdü.

### Canlı ölçüm (deploy doğrulaması, 8. turun sonucu)
| Uç | Soğuk | Sıcak |
|---|---|---|
| `/health` | — | 0,13 sn |
| `/market/prices` (3 sembol, 3 ayrı kaynak) | — | 0,15 sn |
| `/portfolio/1` (38 pozisyon) | — | 0,36 sn |
| `/portfolio/1/health` | **7,50 sn** | 0,28 sn |
| `/signals` (51 sembol) | **10,0 sn** | 0,27 sn · force tam tarama 0,41 sn |
| AI Koç SSE (`chat/send`) | 14,1 sn | — |

AI Koç canlı çalışıyor ve 8. turun dürüstlük düzeltmesi de canlı: *"Portföyünde
**38** farklı varlık bulunuyor."* (eskiden "beş" diyordu). CORS hâlâ `*`.

### 1. `/signals` soğuk 10 sn — kök sebep ısıtma DEĞİL, seri cache'i (`aabad7d`)
İlk hipotez (temel oran ısıtmasının kapsamı) ölçümle çürüdü: 10 sn'lik çağrının
hemen ardından **tam tarama 0,41 sn** sürdü → temel oranlar zaten cache'teydi,
üstelik 7. turdan beri SWR'li (bayat oran bloklamaz).
Gerçek sebep: `get_daily_closes` / `get_daily_ohlcv` **stale-while-revalidate
değil "stale-if-error"du** — 15 dakikayı geçen kayıt istek yolunda BLOKLAYAN
batch çekim tetikliyor, eski kayıt yalnızca çekim PATLARSA servis ediliyordu.
Arka plan yenileyici 30 dk boşlukta durduğu için faturayı her sessizlik
sonrası ilk kullanıcı ödüyordu. Aynı kural bu iki cache'e de uygulandı (bkz.
KALICI KURALLAR). Tek soğuk sembol ölçümü sebebi doğruluyor: `signals/SBUX`
**2,46 sn** → aynı sembol ikinci çağrıda 0,14 sn.

### 2. `/portfolio/1/health` soğuk 7,5 sn — sektör çözümü (`4f76d32`)
`health` yalnız iki şey yapıyor (portföy + sektör dağılımı); portföyün kendisi
0,36 sn olduğuna göre bedel sektörde. Canlı dağılım: 14 sektör, yalnız **1
sembol "Diğer"** → harita çalışıyor, sorun kalıcılık: süreç-içi sözlük her
uyanışta sıfırlanıyor ve paylaşılan cache'te olmayan sembol KULLANICI
isteğinde çözülüyordu (Finnhub profili → yfinance `.info`). İki düzeltme:
arka plan turuna **sektör ısıtma** işi eklendi (tur başına en fazla 10 eksik
sembol; sıcakken bedava) ve `_resolve_sector` artık ortak **`.info` devre
kesicisine bakıyor** — aynı uç Render IP'sinde bloklu ve her deneme boşuna
0,6-3 sn yiyor; kesici 7. turda temel oranlar için konmuştu, sektör yolu
ondan habersizdi.

### 3. Haber enrich eleme oranı artık log'da (`58d2c7f`)
6. turdan devreden gözlem eksiği. Eskiden yalnız **%50 üstü** eleme uyarı
basıyordu; altındaki kayıp ve hangi KATMANIN yediği görülemiyordu. Artık her
turda tek satır: `N ham -> M kaldi (%X elendi; dil kapisi A - LLM dil B -
alaka C)`, toplu yol ayrıca uçtan uca özet basıyor (`ham -> enrich -> telafi
-> servis`). **LLM boş yanıt döndüğünde de uyarı var** — 6. turdaki "tüm AI
ölü ama kimse görmüyor" deseninin aynısı sessizce oluyordu.

### 4. Deploy sonrası ilk kullanıcı — sinyal cache'i startup'ta ısıtılıyor
`_signal_cache` süreç-içi (15 dk). Deploy sonrası ölçüm: `/signals` **3,88 sn**
→ ikinci çağrı **0,25 sn**; `/portfolio/1/health` **2,27 sn** → 0,28 sn (aynı
uçlar deploy ÖNCESİ 10,0 ve 7,50 sn'ydi). Kalan 3,9 sn ağ değil HESAP: taze
süreçte 51 sembolün göstergeleri yeniden hesaplanıyor. Startup'taki arka plan
ısıtmasına `signal_service.prewarm_signals` eklendi (OHLCV tek batch, zaten
cache'te olan sembol atlanır) → fatura kullanıcıya değil boot'a biniyor.

### 5. `/health` artık canlı commit'i söylüyor (`162de26`)
Deploy doğrulaması "push ettim, herhalde çıkmıştır"a dayanıyordu (8. turda tam
bu yüzden doğrulanamadı). Render'ın verdiği `RENDER_GIT_COMMIT` ilk 7 hanesiyle
dönülüyor; yerelde `"local"`.

### CORS canlıda kapandı (bekleyen madde değil artık)
8. turda kod + `render.yaml` kilitlenmişti ama canlı hâlâ `*` dönüyordu ve
"Render dashboard env'i elle değişmeli" diye bekliyordu. Bu turun deploy'undan
sonra ölçüldü: yabancı origin'e `access-control-allow-origin` başlığı **hiç
dönmüyor**, gerçek frontend'e kendi adresi + `allow-credentials: true` dönüyor
→ blueprint değeri geçmiş. Elle müdahale gerekmedi.

### Başka bir modelin (Gemini) listesi — koddan denetim
Kerem üç maddelik bir liste getirdi; ikisi ölçümle çürüdü, biri doğruydu:

| Madde | Sonuç |
|---|---|
| "Çalışma ağacı kirli, 8. tur commit'siz — commit'le" | **ÇÜRÜK.** Ağaç temizdi; boş-durum · CORS · `iterate_in_threadpool` 8. turda push'lanmıştı. `flutter_*.txt`/`python_*.txt` de zaten `.gitignore`'daydı |
| "Sinyaller soğuk 10 sn → `prewarm_fundamentals`'ı agresifleştir" | **ÇÜRÜK.** Ölçüm: force tam tarama 0,41 sn → oranlar cache'te; asıl bloklayan seri cache'iydi (yukarıda) |
| "AI Koç 'Failed to fetch' → RAG bağlamı büyük, OOM olabilir" | **ÇÜRÜK (ikinci kez).** 5. turda Render log'uyla çürütülmüştü: `chat/send` 200, restart yok; sebep LLM zincirinin komple düşmesiydi, 6. turda kapandı. Bugün canlıda SSE akışı sorunsuz |
| "Sektör çözümünü arka plan yenilemesine dahil et" | **DOĞRU** — uygulandı (`4f76d32`) |

Ders (2. kez): bu model **bayat bir kod dökümünden** konuşuyor
([[portly-baska-model-listesi]]). Getirdiği durum iddiasını (`git status`,
test sayısı, "şu düzeltme yok") önce koddan doğrula.


---

## 8. TUR (4 Eylül 2026) — boş-durum · CORS · AI akışı
> Sıradaki iş için AÇILIŞ yeter; bu bölüm "bu neden böyle" sorusu içindir.

### DEVİR NOTU — çalışma ağacı KİRLİ, commit/push YOK (Kerem'in onayı bekleniyor)
Kerem "handoff oku, yapmamız gerekenleri yapalım" dedi ve dört maddeyi birden
seçti: boş-durum taraması · canlı ölçüm · CORS · onboarding CTA'sı.

**Yapıldı (yerel, commit'siz):**

| # | İş | Dosyalar |
|---|---|---|
| 1 | 🔴 **"Veri YOK" ≠ "veri ALINAMADI"** — 4 ekranda hata boş-durum gibi gösteriliyordu | `portfolio_provider` · `portfolio_screen` · `home_screen` · `alerts_screen` · `investor_journal_screen` · `news_screen` · yeni `widgets/load_error_card.dart` |
| 2 | **Yakalanmayan async hata** — istek her patladığında konsola "Unhandled exception" düşüyordu | `portfolio_repository` · `market_repository` · `portfolio_provider` |
| 3 | **CORS kilidi** (kod + blueprint; **Render env'i Kerem/Umut uygulamalı**) | `backend/app/main.py` · `render.yaml` |
| 4 | **"Ekran görüntüsünden aktar" CTA'sı** boş portföy ekranında | `portfolio_screen` |
| 5 | **AI Koç akışı olay döngüsünü bloklamıyor** (Gemini listesi md. 2, sebebi düzeltilerek) | `backend/app/api/v1/chat.py` |
| 6 | **Satış kaydı**: buton yükleme durumu + sheet cevaptan sonra kapanıyor (md. 3) | `stock_detail_screen` |
| 7 | **Günlük K/Z**: bozuk günlük değişimde sahte kazanç yok (md. 4, iddia düzeltilerek) | `portfolio_provider` |
| 8 | **Handoff 1590 → ~670 satır** (md. 5) | `SESSION_HANDOFF.md` · yeni `docs/HANDOFF_ARSIV.md` |

**Testler:** backend **704** (695'ti, +9) · flutter **101** (88'di, +13) · `flutter analyze` temiz.

### 1) 🔴 Boş-durum ≠ hata (tarama bulgusu, dördü de düzeltildi)
Kök sebep tek bir kalıptı: `ApiService` hata durumunda `null`/boş liste
döndürüyor, ekranlar bunu "veri yok" sayıyordu. Sonuç:

| Ekran | Ağ hatasında ne diyordu | Artık |
|---|---|---|
| Portföy | "BAŞLANGIÇ — ilk hisseni ekle" (kullanıcının **38 pozisyonu var**) | "Portföy yüklenemedi" + Tekrar Dene |
| Ana ekran izleme listesi | "Listen boş · + ile ilk hisseyi ekle" | "Fiyatlar alınamadı" + Tekrar Dene |
| Alarmlar | "henüz alarm yok" | "Alarmlar yüklenemedi" + Tekrar Dene |
| Notlarım | "Günlüğün boş" | "Notlar yüklenemedi" + Tekrar Dene |
| Haberler (Tümü) | "Haber bulunamadı" | "Haberler yüklenemedi" (retry zaten vardı) |

`PortfolioProvider._lastError` **hiçbir ekran tarafından okunmuyordu** (grep ile
doğrulandı) → bölüm bazlı `portfolioError` · `marketError` · `newsError`
eklendi; başarı yolları bayrağı temizliyor. `NotesProvider.error` zaten vardı,
sadece kullanılmıyordu.

**KALICI KURAL:** boş liste iki farklı dünyadır — "kullanıcı hiç eklememiş" ve
"istek patladı". Yeni bir liste ekranı yazarken üçüncü bir durum (hata) da
tasarla; `null` dönen `ApiService` çağrısını `?? []` ile ezme, önce hatayı
bayrakla. Bu, [[portly-uretim-kalitesi]]'ndeki "sahte/sıfır veri gösterme"
kuralının boş-durum karşılığı.

### 2) Yakalanmayan async hata (tarama sırasında çıktı, gerçek)
`fut.whenComplete(() => _inFlight.remove(key));` — `whenComplete` **türev** bir
future döndürür; `fut` patlarsa o türevin hatasını kimse yakalamaz. Hata asıl
bekleyen tarafta ele alınsa bile Dart bunu "unhandled" sayıyordu → her başarısız
portföy/fiyat isteğinde konsola istisna düşüyordu (testte de kırmızı verdi,
bulunma yolu buydu). Üç çağrı noktasına `.ignore()` kondu.

### 3) CORS — ⚠️ KOD HAZIR, RENDER ENV'İ BEKLİYOR
**Canlıda ölçüldü:** `curl -H "Origin: https://kotu-site.example" .../health` →
`access-control-allow-origin: *`. Yani herhangi bir site Portly API'sini kendi
sayfasından çağırabiliyor (token localStorage'da olduğu için oturum çalınmaz,
ama ücretsiz katman kotasını başkası tüketebilir).

- `main.py`: CORS çözümü saf `resolve_cors_settings()` fonksiyonuna alındı
  (7 test), `ALLOWED_ORIGIN_REGEX` desteği eklendi, prod'da `*` kalırsa
  **açılışta uyarı log'u** basılıyor.
- `render.yaml`: `ALLOWED_ORIGINS` → `https://portly-frontend.onrender.com`.
- ⚠️ **Kod tek başına yetmez:** Render dashboard'daki env değeri `*`. Blueprint
  senkronu değeri güncellemezse elle değiştirilmeli. Yerelden **prod** backend'e
  bağlanılacaksa `ALLOWED_ORIGIN_REGEX=^http://(localhost|127\.0\.0\.1)(:\d+)?$`
  eklenmeli, yoksa `flutter run -d chrome` prod API'ye çıkamaz.

### 4) Onboarding CTA'sı
Ekran görüntüsünden içe aktarma yalnızca `ImportPortfolioScreen`'in içinde
görünüyordu. Boş portföy ekranındaki hem "BAŞLANGIÇ" listesine hem de boş-durum
kartına birinci sıradan CTA kondu (yalnız web — OCR yolu `dart:html`'e bağlı,
mobil derlemede o buton zaten gizli).

### 5) 🤖 Başka bir modelin (Gemini) 5 maddelik listesi — koddan denetlendi
Kerem listeyi getirdi ("mantıklı olanları değiştirebilirsin"). **Üçü gerçek
çıktı, biri çürütüldü, biri gerçek ama önerilen formül YANLIŞTI.** Denetim
kuralı: [[portly-baska-model-listesi]].

| # | İddia | Karar | Gerekçe (koddan) |
|---|---|---|---|
| 1 | Frontend refresh mutex yok → eşzamanlı 3×401 → 3 ayrı `/refresh` → haksız logout | ❌ **REDDEDİLDİ** | Mutex ZATEN var, sadece başka katmanda: `ApiService.refreshSessionOnce` statik `_refreshFlight` ile tek-uçuş yapıyor (`api_service.dart:80`), ikinci çağıran aynı future'ı bekliyor. **Tek 401 girişi bu fonksiyon** (`_AuthRetryClient` sat. 56 ve SSE yolu sat. 1268 — grep'le doğrulandı). `handleUnauthorized`'daki `staleToken` kontrolü ikinci kalkan (uçuş bittikten sonra gelen geç 401). Gemini yalnız `auth_provider.dart`'a bakmış |
| 2 | SSE'de kopma kontrolü yok → sekme kapanınca LLM arkada üretmeye devam eder | ⚠️ **KISMEN — sebep başka** | `request.is_disconnected()` GEREKMİYOR: sse_starlette 3.3.4 `_listen_for_disconnect` ile `http.disconnect`'i dinleyip görev grubunu iptal ediyor (`sse.py:331,433`). **Ama gerçek bir kusur vardı:** `stream_chat_response` baştan sona SENKRON (DB + RAG + LLM) ve `async def` içinde düz `for` ile dönülüyordu → tüm akış **olay döngüsünde** koşuyordu; sohbet sürerken aynı işçideki portföy/fiyat/sinyal istekleri sıraya giriyordu. `iterate_in_threadpool` + `finally: stream.close()` kondu |
| 3 | Satış sheet'i: `Navigator.pop` istekten ÖNCE, çift dokunuşta çoklu satış | ⚠️ **KISMEN** | "Çoklu istek" koddan doğrulanamadı (pop sonrası rota ters animasyonda pointer'ları yutar). **Gerçek olan:** sheet istek gönderilmeden kapanıyordu → Render uykudayken kullanıcı 40+ sn geri bildirimsiz kalıyordu. Buton artık `isLoading`, sheet cevaptan SONRA kapanıyor, ikinci gönderim de imkânsız |
| 4 | `dailyPnl`'de `d == 0` (tam -%100) → "devasa zarar gizleniyor" | ⚠️ **KISMEN — tarif edilen zarar YOK, komşu hata GERÇEK** | **Ölçüldü (test eski kodda koşturuldu):** `d == 0` ancak fiyat 0'ken olur, o zaman değer de 0 → ₺ K/Z eski kodda da yeni kodda da 0. Gizlenen zarar YOK. **Asıl bozuk durum `d < 0`** (kaynak -%100'den kötü değişim gönderirse): bölme NEGATİF "dünkü değer" üretip **sahte KAZANÇ** yazıyordu — testte günlük K/Z 10 ₺ yerine **93,33 ₺**. Bir de tutarsız veride (değer > 0, değişim -%100) eski kod o değeri yüzde paydasına katıp günlük yüzdeyi seyreltiyordu (%10 → %4,76). Gemini'nin formülü (`prev = totalCostTry`) UYGULANMADI: günlük K/Z'yi sessizce TOPLAM K/Z'ye çevirirdi (maliyet ≠ dünkü değer). Doğrusu: çıkarılamıyorsa pozisyon hesap dışı |
| 5 | `SESSION_HANDOFF.md` 1500+ satır, bağlam şişiyor | ✅ **GERÇEK** | 1590 → **~670 satır**; eski turlar `docs/HANDOFF_ARSIV.md`'ye TAŞINDI (silinmedi), özete birer satır bırakıldı. "150 satıra sıfırdan yaz" uygulanmadı: KALICI KURALLAR (136 satır) bu dosyanın en değerli kısmı, silinmesi kazandığından fazlasını kaybettirirdi. Üste kalıcı bakım kuralı eklendi |

> ⚠️ Listedeki "222 backend / 24 Flutter testi yeşil kalsın" ifadesi **eski bir
> dökümden** geliyor (o sayılar 36-37. turdan). Güncel: backend **704**,
> flutter **101**. Model bayat bir kopya üzerinden konuşmuş — sayıları
> doğrulamadan tekrarlama.

**KALICI KURAL (buradan çıktı):** `async def` içinde senkron bir üreteci düz
`for` ile dönme. Senkron I/O (LLM akışı, `requests`, SQLAlchemy) olay
döngüsünde koşarsa **tek işçideki tüm istekler** onu bekler.
`iterate_in_threadpool` kullan; üreteci `finally`'de `close()` et.

**KALICI KURAL:** "bilinmeyen"i uydurulmuş bir değerle doldurma. Dünkü değer
çıkarılamıyorsa pozisyonu hesaba KATMA — maliyeti dünkü değer yerine koymak
sayıyı "çalışır" gösterip anlamını değiştirir ([[portly-uretim-kalitesi]]).

### 6) 🔴 SIRADA NE VAR
| # | İş | Kim |
|---|---|---|
| 1 | **Bu turun commit/push kararı** — push Render deploy'u tetikler; CORS kilidi ancak Render env'i de değişince etkili olur | Kerem |
| 2 | **`/signals` düzeltmesinin gerçek kanıtı** — oranlar bayatlayınca (4 Eyl akşamı / 5 Eyl sabahı) Sinyaller'i aç; yavaşsa access token ver, yeniden ölçeyim | Kerem → Claude |
| 3 | **CİHAZDA doğrulama** — `CIHAZ_DOGRULAMA.md` A0000000 + A000000 + A0000; bu turun hata kartları ancak uçak modunda (ya da sunucu uykudayken) görülür. Ayrıca **AI Koç akışı** + **satış kaydı** bir kez denenmeli | Kerem |
| 4 | Eski Neon merge (iki bağlantı dizesi) · Brevo (Umut) | Bloke |
| 5 | Ürün cilası kalanı: temettü ekranı cihazda · kaydırma gereken ekranlar · haber enrich eleme oranının canlı log'da izlenmesi | Sırada |

**Not:** repo kökünde takip edilmeyen `flutter_yeni.txt` (1,2 MB, frontend
dosyalarının birleştirilmiş dökümü) duruyor — başka bir modele verilmek üzere
çıkarılmış görünüyor. Silinmedi, commit'e de girmemeli.

---

## 🟡 (ÖNCEKİ) 3 Eylül 2026, 5. tur — 401 kurtarması + "haberler çok az"

> ⚠️ Bu turun "commit YOK / push YOK" notu ARTIK GEÇERSİZ: **6. turda iki
> commit olarak push edildi** (`75efa91` auth/401, `6a0f149` haber). Aşağıdaki
> dosya tablosu ne değiştiğinin kaydı olarak duruyor.

### ⚠️ (TARİHSEL) DEVİR NOTU — çalışma ağacı KİRLİ, commit/push YOK
Bu turun işi tamamlandı ve testleri geçti ama **commit edilmedi** (Kerem yeni
session'a geçti). Yeni session'da ilk iş: aşağıdaki dosyaları gözden geçir,
Kerem "commit'le/push'la" derse **tek seferde** gönder — frontend + backend
BİRLİKTE gitmeli (`matched_query` alanı iki tarafı da ilgilendiriyor; yalnız
biri deploy edilirse haber filtresi eski davranışa döner).

| Dosya | Ne değişti |
|---|---|
| `lib/services/api_service.dart` | `_AuthRetryClient` (401→yenile→tekrarla) · tüm çağrılar `http.` yerine `_client` (auth uçları hariç) · SSE 401 kurtarması · haber timeout 30→45 sn |
| `lib/providers/auth_provider.dart` | `handleUnauthorized` kancası + constructor'da bağlama |
| `lib/screens/news_screen.dart` | `matched_query` ile alaka eşlemesi · sembol 24→40 · gösterim 40→60 |
| `test/auth_retry_401_test.dart` (YENİ) | 401 kurtarmasının 9 durumu |
| `backend/app/services/nlp_sentiment_service.py` | sorgu-başına ham cache + kısıtlama kalkanı · çekim bütçesi/eşzamanlılık · `matched_query` etiketi · şirket adıyla sorgu genişletme · enrich max_tokens + kesik JSON kurtarma |
| `backend/app/schemas/news_schema.py` | `matched_query` alanı |
| `backend/tests/conftest.py` | haber cache'lerini testler arası temizleyen autouse fixture |
| `backend/tests/test_news_symbol_coverage.py` | bütçe sözleşmesine göre güncellendi + 3 yeni durum |
| `backend/tests/test_news_enrich_budget.py` (YENİ) | kesik JSON · `matched_query` · ad genişletme (9 durum) |
| `SESSION_HANDOFF.md` · `CIHAZ_DOGRULAMA.md` · `GELISTIRME_ONERILERI.md` | bu tur + cihaz listesi A000 + backlog |

**Commit önerisi (iki commit):**
1. `feat(auth): oturum içi 401 → token yenile + isteği tekrarla` (api_service,
   auth_provider, auth_retry_401_test)
2. `fix(haber): az haber gelmesinin üç kök sebebi — eşleme, kısıtlama kalkanı, sembol kapsamı`
   (nlp_sentiment_service, news_schema, news_screen, testler, dokümanlar)

**Push sonrası İLK iş (Claude):** canlıda ölç →
`/news/for-symbols` süresi + dönen haber sayısı + Render log'unda
"Google News: N/M sorgu boş döndü" uyarısı var mı. Öncesi (3 Eyl, deploy
öncesi): 8,7 sn · 34 haber · ekranda 18.

**Devraldığın durum:** 4. turun açık bıraktığı **oturum içi 401→refresh** işi
YAPILDI; ayrıca Kerem'in "haberler çok az geliyor + uygulama yavaş" şikâyeti
CANLI ÖLÇÜMLE kök sebebine indirildi ve düzeltildi. **Commit YOK, push YOK** —
çalışma ağacı kirli, Kerem "commit'le/push'la" derse yapılacak (push = Render
deploy; frontend + backend birlikte gitmeli, `matched_query` iki tarafı da
ilgilendiriyor).

**Doğrulandı (yerel):** backend `venv/bin/python -m pytest` → **639 passed**
(618'di) · `flutter test` → **79 passed** (70'ti) · `flutter analyze` temiz.

### 1) Oturum içi 401 → refresh (4. turdan devreden madde, BİTTİ)
`ApiService` içinde `_AuthRetryClient` (http.BaseClient): token'lı bir istek 401
alırsa `ApiService.onUnauthorized` kancasıyla access token BİR KEZ yenilenir ve
istek **yeni token'la tekrarlanır**. `AuthProvider` kancayı constructor'da
bağlıyor (`handleUnauthorized`).
- **Tek uçuş (single-flight):** aynı anda 401 alan N istek TEK yenileme turu
  paylaşır — refresh token tek kullanımlık (sunucuda atomik iptal), iki tur
  birbirini geçersiz kılardı.
- **Bayat token karşılaştırması:** kancaya 401 alan isteğin token'ı geçilir;
  elde farklı bir token varsa (başka istek yenilemiş) ağa çıkılmadan o döner.
- **Döngü yok:** tekrar isteği doğrudan iç istemciye gider (tek deneme).
- **Kapsam dışı bırakılanlar:** `login/register/refresh/fetchMe/logout` düz
  `http` üzerinden gider (refresh'in kendisi yeniden 401 döngüsüne girmesin,
  çıkışta oturum dirilmesin). `fetchMe` 401'ini açılış akışı zaten yönetiyor.
- **Multipart (ekran görüntüsü/ekstre yükleme):** gövde replay edilemez →
  tekrar YOK, ama token yine de yenilenir (sonraki istekler kurtulur).
- **SSE sohbet akışı** kendi istemcisini kullanıyor (iptal edilebilirlik) →
  401'i elle yakalayıp bir kez yeniden bağlanıyor.
- Testler: `test/auth_retry_401_test.dart` (9 durum).

### 2) 🔴 "HABERLER ÇOK AZ" — kök sebep ölçüldü, üç katman da düzeltildi
Canlı ölçüm (3 Eyl, 38 pozisyonlu gerçek portföy, `/news/for-symbols`):
**24 sembol soruldu → sunucudan 34 haber → ekranda 18.** Üç ayrı darboğaz:

| # | Bulgu (ölçülmüş) | Düzeltme |
|---|---|---|
| 1 | **İstemci gelen haberin %47'sini eliyordu** (34→18). Filtre başlıkta TICKER arıyordu; "Lockheed Martin ... " başlığında "LMT" geçmiyor, `affected_assets` sözlüğü de elle yazılmış ~100 popüler şirket (LMT/PLTR/GLRMK yok). Fon satırları (`.FON`) hiç eşleşmiyordu | Sunucu her haberi **`matched_query`** ile etiketliyor (haberi hangi sembol sorgusu getirdi); istemci önce buna bakıyor. Şema alanı + istemci filtresi |
| 2 | **Google News RSS kısıtlaması SESSİZ**: 429 değil, **HTTP 200 + BOŞ feed**. Ölçüm: aynı IP'den ~30 sorgudan sonra spesifik sorgular boş dönüyor (Google'ın kendi cache'indeki popüler sorgular dönmeye devam ediyor). Backend bunu "haber yok" sanıyordu → 24 sembolün yalnız 4'ünden haber geliyordu | **Sorgu-başına ham cache** (`_raw_cache`): boş yanıt eldeki haberi SİLMEZ (6 saate kadar korunur) · tur başına **çekim bütçesi** (`_FETCH_BUDGET=24`) · eşzamanlılık **16→6** · boş oran yarıyı geçince **uyarı log'u** |
| 3 | **Sembol sınırı 24 < 38 pozisyon** → 14 sembolün haberi hiç çekilmiyordu | `_MAX_SYMBOLS` 24→**40**; sınır artık sembol sayısında değil, tur başına çekimde. Bütçe dışı kalan sembol sonraki turda çekilir, o ana kadar cache'ten gelir |

**Ölçülen sonuç (yerelde, üstelik KISITLANMIŞ bir IP'den):**
`_collect_raw_for_symbols` 30 sorgu → **1. çağrı 3,2 sn / 61 haber**,
**2. çağrı 1,5 sn / 76 haber** (öncesi: 8,7 sn / 34 haber, ekranda 18).

**Ek düzeltmeler (aynı kök):**
- **Çıplak ticker sorgusu şirket adıyla genişliyor**: istemci ABD sembolü için
  yalnız "LMT" gönderebiliyor (portföy ucu şirket adı döndürmüyor). Sunucu adı
  ZATEN cache'inde tutuyor (`market_data_service._known_name`, ağ istemez) →
  sorgu `LMT OR "Lockheed Martin"` olur. Etiket (`matched_query`) ham sembol
  kalır, istemci eşlemesi bozulmaz.
- **LLM enrich `max_tokens` sabit 1800'dü**, toplu yol 90 öğeye çıkabiliyor
  (~26 token/öğe) → JSON ortasından kesilip parse patlıyor, enrich HİÇ
  uygulanmıyordu (kota yanıyor, sonuç yok). Artık öğe sayısıyla ölçekleniyor +
  **kesik JSON'dan kurtarma** (`_salvage_verdicts`) var.
- İstemci `/news/for-symbols` timeout'u 30→**45 sn** (uç soğukken 30'a
  dayanıyordu: haber gelse bile ekran BOŞ kalıyordu), gösterim sınırı 40→60.

### 3) "Uygulama yavaş" — ölçüm
Canlı, ISINMIŞ backend (3 Eyl): `/portfolio/1` **0,3 sn** · `/market/prices`
**1,2 sn** · `/news/latest` **2,5 sn** · `/market/fear-greed` **2,5 sn** ·
`/portfolio/1/health` **5,1 sn** (19,6 sn'di) · `/portfolio/1/benchmark`
**0,5 sn**. Yani ısınmış uçlar yavaş DEĞİL. Yavaşlık hissinin kaynağı:
1. **Render ücretsiz katman soğuk başlangıcı** (~30-50 sn) — mimari sınır.
2. **Haber sekmesi**: `/news/for-symbols` soğuk cache'te 8,7 sn'ydi (şimdi
   ~3 sn) ve sekmeye basınca başlıyor (ön-yükleme yok) → bekleme tam görünür.
3. `/portfolio/1/health` hâlâ 5 sn.

### 4) Gemini'nin haber teşhisi — ne alındı, ne alınmadı
| İddia | Karar |
|---|---|
| "Kesik JSON haberleri YUTUYOR" | **Yarı doğru.** Kesilme gerçek (1800 token) ama haber yutulmuyor: parse patlayınca liste DOKUNULMADAN dönüyor (VADER skoruyla). Sessiz kayıp enrich'in kendisiydi → max_tokens ölçeklendi + kısmi kurtarma eklendi |
| "LLM'i 5-10'arlı chunk'la" | **YAPILMADI.** Chunking LLM çağrısını 2-3'e katlar; canlı arıza kaydı zaten kota zinciri çöküşü (flash-lite 429 → flash 503 → Groq 404). Tek çağrıyı **sığacak boyuta** ayarlamak doğru olan |
| "Google News 429 ban" | **Yarı doğru.** 429 DEĞİL: 200 + boş feed (ölçüldü). Bütçe + eşzamanlılık sınırı + kısıtlama kalkanı uygulandı |
| "Render 60 sn timeout'u aşıyor" | **Hayır.** Sunucu tarafı 8,7 sn ölçüldü; ilk açılış zaten LLM'i BEKLEMİYOR (3. turda arka plana alınmıştı). Gerçek risk İSTEMCİ tarafındaki 30 sn'ydi → 45 sn |
| "Sembol bazlı cache" | **Alındı** — Gemini'nin en isabetli maddesi; kısıtlama kalkanı da bunun üstüne kuruldu |
| (Gemini'nin GÖRMEDİĞİ) | En büyük kayıp **istemcideki alaka filtresiydi** (%47) ve sembol sınırıydı (24<38) |

### 5) 🔴 SIRADA NE VAR
| # | İş | Kim |
|---|---|---|
| 1 | **Commit + push** (Kerem onayı gerekli; push = deploy). Frontend + backend BİRLİKTE gitmeli | Kerem der, Claude yapar |
| 2 | **CİHAZDA doğrulama** — `CIHAZ_DOGRULAMA.md` **A00** (4. turun para/erişim maddeleri) + yeni **A000** (401 + haber sayısı) | Kerem |
| 3 | Deploy sonrası: canlı `/news/for-symbols` yeniden ölçülmeli (kaç haber, kaç sembol, log'da "boş döndü" uyarısı var mı) | Claude |
| 4 | `/portfolio/1/health` 5 sn · AI Piyasa Etkisi "tekrar dene" · Eski Neon merge · Brevo anahtarları · kaydırma gereken ekranlar | 3-4. turdan devam |

---

## 🟡 (ÖNCEKİ) 3 Eylül 2026, 4. tur — Gemini listesinin denetimi + ₺ maliyet

> Bir önceki tur (3. tur) aşağıda "(ÖNCEKİ) 3. tur" başlığında.

**Devraldığın durum:** Kerem Gemini'ye kod dökümü verip bir "production
sertleştirme" listesi (13 madde) aldı; bu turda o liste **koddan tek tek
doğrulandı**, gerçek olanlar düzeltildi, gerçek OLMAYANLAR gerekçesiyle
reddedildi. **9 commit PUSH'LANDI** (`2d6c473`…), Render deploy **canlı**,
**iki migration da koştu ve canlıda doğrulandı**. Çalışma ağacı temiz.

**Sıradaki iş = CİHAZDA doğrulama** (`CIHAZ_DOGRULAMA.md` → yeni **A00**
bölümü) + aşağıdaki madde 2. Kod tarafında bekleyen bir şey YOK.

**Doğrulandı (yerel):** backend `venv/bin/python -m pytest` → **618 passed**
(601'di) · `flutter test` → **70 passed** (67'ydi) · `flutter analyze` temiz.
⚠️ pytest özet satırı ("N passed") bu kurulumda basılmıyor — nokta saymak ya da
exit kodu kullanmak gerekiyor.

**Doğrulandı (CANLI, deploy sonrası curl ile):**
- `/health` 200 → konteyner ayakta, yani `alembic upgrade head` sorunsuz koştu
- `/api/v1/news/latest` token'sız **401**, token'la **200** (yeni auth kapısı)
- `/api/v1/portfolio/1`: 38 pozisyon (25 USD) · `fx_gain_try` alanı geliyor ·
  **alış kuru işlenmiş USD pozisyonu 25/25** (backfill tam)
- Toplam ₺ K/Z **₺318.864**, bunun **₺13.862'si (%4,3) kur payı** → "Kur payı"
  satırı arayüzde görünme eşiğinin üstünde. Değişim ölçülü, demoda şaşırtmaz.

### 1) Bu turda YAPILANLAR (commit'li, push YOK)
| # | İş | Commit |
|---|---|---|
| 1 | **Pozisyon satırında kayıp yazma** — lot/maliyet oku-değiştir-yaz korumasızdı (çift dokunuşta lot kayboluyor, satır yokken iki INSERT yarışınca aynı sembolden İKİ satır). `_locked_position` (FOR UPDATE) + `portfolios(user_id,symbol)` benzersiz kısıtı + çakışmada SAVEPOINT geri alıp birleştirme. Dört yazma yolu da geçti | `2d6c473` |
| 2 | **Auth sertleştirme** — refresh token iptali koşullu UPDATE ile ATOMİK (çift kullanım reddedilir) · sıfırlama kodunda **3 deneme sınırı** · logout kara listesi + sıfırlama kodları süreç belleğinden **paylaşımlı cache'e** (her deploy'da çıkış yapılmış token'lar geri geçerli oluyordu) | `3e3a332` |
| 3 | **`/news/*` giriş istiyor** (üçü de LLM tetikliyordu, kimliksiz kota yakılabiliyordu) + **hız sınırı gerçek istemciyi görüyor** (Render vekili arkasında herkes TEK kovadaydı → bir kullanıcı herkesi banlıyordu; X-Forwarded-For'un EN SAĞ girdisi) | `7db2000` |
| 4 | **Alarm e-postası DB oturumu kapandıktan sonra** (yavaş SMTP açık transaction'ı ve Neon bağlantısını tutuyordu) | `217de15` |
| 5 | **Fiyatı hiç gelmeyen pozisyon "bugün %0" demiyor** — `change_available` artık `price_available` ile birlikte; 3 Eylül'ün dürüst boş-durum kuralının eksik ucu | `1cb9435` |
| 6 | **Flutter sızıntı + yarış** — sohbet `flushTimer` yerel değişkendi, iptal/dispose ulaşamıyordu (süresiz 60ms timer + atılmış provider'da notifyListeners); `Completer` de iptalde tamamlanmıyordu. `logout` sırasında arka plandaki `_revalidateSession` kapanmış oturumu GERİ YAZIYORDU (kullanıcı çıkış yaptığı halde girişli görünüyordu) | `42e83d6` |
| 7 | **₺ maliyet ALIŞ kuruyla** (↓ ayrı bölüm) | `147a202` |

### 2) İKİ MİGRATION — koştu, ama ne yaptıklarını bil
Dockerfile `alembic upgrade head && uvicorn` koşuyor; migration patlasaydı
**konteyner hiç ayağa kalkmazdı**. İkisi de bu riske karşı yazılmıştı ve
canlıda sorunsuz koştu:

- **`c9e4b1a8f7d2`** — `portfolios(user_id, symbol)` benzersiz kısıtı. Kısıttan
  ÖNCE varsa çift satırları BİRLEŞTİRİR (adet toplanır, maliyet ağırlıklanır).
- **`d1f6a3c8b924`** — `fx_rate_at_cost` kolonu + mevcut pozisyonların
  `transactions` geçmişinden doldurulması (her BUY'ın günündeki kur).
  Backfill ağ ister (frankfurter); **ağ düşerse migration ÇÖKMEZ**, satır NULL
  kalır ve eski davranış sürer.

İkisi de izole SQLite'ta upgrade+downgrade doğrulandı (çift birleştirme ve
kur ağırlıklandırma gerçek kurlarla kontrol edildi), sonra canlıda koştu.

⚠️ **Backfill'in okuduğu tarih = `transactions.timestamp`.** Pozisyon
"edinim tarihi" verilmeden içe aktarıldıysa o damga **içe aktarma günüdür**,
gerçek alış günü değil. Canlıdaki kur payının %4,3'te kalmasının sebebi bu:
pozisyonlar yakın tarihte kaydedilmiş. Gerçek alış tarihleri girilirse kur
payı büyür — bu bir hata değil, veri sınırı. Kerem sorarsa böyle açıkla.

### 3) 💱 YENİ KALICI SÖZLEŞME — ₺ maliyet alış kuruyla
USD varlığın ₺ maliyeti **bugünkü kurla çevrilmez**; `portfolios.fx_rate_at_cost`
(lotların NATIVE maliyetiyle ağırlıklı USDTRY) ile çarpılır. Sebep: canlı kurla
çevrilirse kur yükseldiğinde maliyet de büyür ve **kurdan gelen reel kâr K/Z'de
hiç görünmez**. ₺ K/Z artık `değer − (alış kuruyla) maliyet`.
- Yeni bir pozisyon YAZMA yolu eklersen kuru işaretle:
  `fx_service.rate_at_cost(currency_of(canonical(sembol)), tarih)`.
  Tarih verilmezse bugünkü kur; **para birimi kararı KANONİK sembolden** verilir
  (kayıt "THYAO" olabilir, okuma "THYAO.IS" der).
- `fx_rate_at_cost` **NULL = kur bilinmiyor** → eski davranış (iki taraf da
  canlı kurla). Bu yüzden eski kayıtlarda hiçbir rakam değişmedi.
- `fx_gain_try` = `native_maliyet × (canlı kur − alış kuru)`. Kur payı + varlık
  kazancı = ₺ K/Z. Portföy hero'sunda "Kur payı" satırı (etki %1'in altındaysa
  gösterilmez).
- **Geçmiş kur kaynağı frankfurter** (ECB, anahtarsız, tarih ucu), Yahoo DEĞİL —
  Render IP'si zaten 429 yiyor. Geçmiş kur değişmez → 30 gün cache.
- Testte geçmiş kur **kapalı** (`conftest._no_network_fallbacks`
  `usdtry_rate_on → None`); kendi testi monkeypatch ile seri verir.

### 4) Gemini'nin listesinden REDDEDİLENLER (tekrar açılmasın)
| Madde | Neden yapılmadı |
|---|---|
| "37. tur testlerini commit'le" | **Uydurma.** Çalışma ağacı temizdi; 37. tur 15 Haziran'da `48c4bae` ile commit'lenmişti. Gemini CHANGELOG'daki eski satırdan hüküm kurmuş ("222 pytest / 24 flutter" da öyle — gerçek 601/67) |
| Multi-worker "Leader Election" (Redlock) | **Uygulanmaz.** Dockerfile TEK uvicorn worker'ı çalıştırıyor (`--workers` yok, gunicorn yok), Render free zaten tek instance. Var olmayan soruna Redis kilidi eklemek karmaşıklık |
| `SECRET_KEY` fail-fast | **Zaten var.** `config._resolve_secret_key` production'da `sys.exit` ediyor |
| SSE "hayalet çağrı" (`request.is_disconnected`) | **Zaten var.** `sse_starlette` 3.3.4 `_listen_for_disconnect` ile bağlantı kopunca task group'u iptal ediyor. Üstüne `is_disconnected` eklemek AYNI receive kanalını iki tüketiciye böler — zarar verir. Render idle-timeout için `ping=20` de zaten kurulu |
| Frontend çift-dokunuş koruması | **Zaten var.** `manual_position_sheet` ve `import_portfolio_screen` `_isSubmitting` + `onPressed: null` kullanıyor; satış sheet'i `await` ÖNCESİ `Navigator.pop` yapıyor (buton ortadan kalkıyor) |
| `dailyPnl`'de `d == 0` dalı | **Davranış değişmiyor.** `d==0` ancak günlük değişim tam −%100 iken olur; o durumda `valueTry` de 0 → katkı zaten 0. Mevcut `d != 0` guard'ı sıfıra bölmeyi önlüyor. Gemini'nin "maliyetten hesapla" önerisi finansal olarak YANLIŞ olurdu |

### 5) 🔴 SIRADA NE VAR
| # | İş | Kim |
|---|---|---|
| 1 | **CİHAZDA doğrulama** — `CIHAZ_DOGRULAMA.md` **A00** bölümü (kur payı satırı · haber sekmesi açılıyor mu · çıkışta içeride kalmıyor mu · sohbeti akarken kapatma) | Kerem |
| 2 | ~~Oturum içi 401→refresh YOK~~ → **5. turda YAPILDI** (yukarı bak) | ✅ |
| 3 | Kaydırma gereken ekranlar · AI Piyasa Etkisi "tekrar dene" · Eski Neon merge · Telefon/PWA turu · Brevo anahtarları | 3. turdan devam |

**Cihazda en olası regresyon noktası: HABER SEKMESİ.** Uçlar artık giriş
istiyor; token gitmiyorsa haberler sessizce BOŞ gelir (istemci 200 dışını
yutuyor). Açılmıyorsa önce `ApiService.authToken`'a bak, `/news/*` auth'unu
geri almaya kalkma.

**3 numaralı madde — oturum içi 401→refresh yok (yeni bulgu, açık):**
`api_service`'te global 401 yakalayıcı YOK. Token yenilemesi yalnız açılışta
(`_bootstrap`/`_revalidateSession`) yapılıyor. Access token 60 dk → uygulama
60 dk'dan uzun açık kalırsa portföy·sohbet·izleme·haber HEPSİ 401'e düşer ve
kullanıcı ancak uygulamayı yeniden başlatınca düzelir. Web'de sayfa yenileme
kurtarıyor, telefonda PWA arka plandan dönünce KURTARMIYOR. Bu turda haber
uçlarına giriş şartı eklendiği için haber de artık aynı kaderi paylaşıyor
(yeni bir arıza sınıfı değil, mevcut boşluğun kapsamı genişledi).
Çözüm: `api_service`'e 401'de bir kez refresh + isteği tekrarlama sarmalayıcısı.
Kesişen bir değişiklik olduğu için Kerem'in onayı beklendi.

---

## 🟡 (ÖNCEKİ) 3 Eylül 2026, 3. tur — dayanıklılık + açılış artığı

> Önce bunu oku, sonra "MEVCUT DURUM (3 Eylül, 3. tur)".

**Devraldığın durum:** 3 Eylül'ün 6 bulgusu düzeltilip canlıda doğrulanmıştı
(`3839743`). 3. turda **açılış isteği artığı + dayanıklılık + backlog ayıklama**
yapıldı ve tarayıcı turu sürdürüldü. **Çalışma ağacı KİRLİ ve HENÜZ COMMIT
EDİLMEDİ** (aşağıdaki tablo) — Kerem "commit'le/push'la" derse yap; push Render
deploy'unu tetikler.

**Tarayıcı doğrulaması yaparken:** eklenti Portly'de **KAYDIRAMIYOR** (6. yol da
denendi: `body.style.zoom` + resize — Flutter canvas yeniden yerleşmiyor, işe
yaramıyor). **Tıklama · sekme geçişi · ekran görüntüsü · `read_network_requests`
ÇALIŞIYOR. Metin YAZMA da çalışmıyor** (arama kutusuna tıklanıyor ama yazı
girmiyor). **Escape modal kapatmıyor**, modalın DIŞINA tıkla. Listenin altını
görmek için Kerem'den kaydırmasını iste. Ağ sayımı için `read_network_requests`
ÖNCE çağrılmalı (izleme o an başlıyor).

### 1) Bu turda YAPILANLAR (commit bekliyor)
| # | İş | Dosyalar |
|---|---|---|
| 1 | **Açılıştaki fazla `/market/prices` GİTTİ (5→4 istek)** — giriş bilgisi gelmeden önce izleme listesi genel `watchlist` anahtarından (varsayılan 8 sembol) okunuyordu; artık "beni hatırla" oturumunun kullanıcı kimliği diskten okunup `watchlist_<id>` kullanılıyor. Çıkış/oturum yok → eski davranış (yeni `AuthProvider.rememberedUserId`, 7 test) | `lib/providers/auth_provider.dart` · `lib/providers/portfolio_provider.dart` · `test/remembered_user_id_test.dart` |
| 2 | **BIST artık Yahoo'ya tek bağlı DEĞİL** — İş Yatırım'ın açık günlük serisi (`HisseTekil`, anahtarsız) yeni yedek kaynak: kapanış · OHLCV · grafik · (seans KAPALIYKEN) fiyat. Seans açıkken fiyat vermez — o kaynakta gün içi fiyat yok, dünkü kapanışı canlı diye basmayız. Kaynak açılış fiyatı vermiyor → mumda open=close (fon yolundaki kabul), hacim TL | `backend/app/services/bist_source_service.py` (YENİ) · `market_data_service.py` (4 yol) · `tests/test_bist_source.py` (17 test) |
| 3 | **Fon kataloğu kendini tazeliyor** — arka plan işçisi günde bir TEFAS liste ucundan YENİ fon kodlarını ekliyor (yalnız ekler, dosyayı bozmaz; kısa liste gelirse yok sayar). Katalog dosyası da yeniden üretildi (2138→2139, yeni: ZTS) | `fund_catalog.py` · `fund_source_service.fetch_catalog` · `market_refresh_service.py` · `tests/test_fund_catalog_refresh.py` (8 test) |
| 4 | **Temel oran cache'i arka planda ısınıyor** — ilk sinyal taramasının ~32 sn'sinin çoğu buydu. Yalnız EKSİK + yalnız HİSSE, tur başına en fazla 8 sembol, sıralı | `signal_service.prewarm_fundamentals` · `market_refresh_service.py` · `tests/test_fundamental_prewarm.py` (6 test) |
| 5 | **`GELISTIRME_ONERILERI.md` ayıklandı** — pivotla ölen sanal-emir maddeleri silindi, biten işler koddan doğrulanıp çıkarıldı, öncelik sırası bugüne göre yazıldı (172→118 satır) | `GELISTIRME_ONERILERI.md` |
| 6 | **Tarayıcı turu (kaydırmasız kısım)** — bulgular ↓ | — |

**Doğrulandı:** backend `venv/bin/python -m pytest` → **601 passed** (570'ti) ·
`flutter test` → **67 passed** (60'tı) · `flutter analyze` temiz.

### 2) Tarayıcı turunda GÖRÜLENLER (3 Eyl, canlı)
| Ekran | Sonuç |
|---|---|
| **Haberler** | ✅ Piyasa Nabzı (Korku&Açgözlülük 64/100 · VIX/Momentum/Haber Sentiment çubukları) · "Bu Hafta Önemli Olaylar" (bayrak + Orta/Yüksek rozeti) · Tümü/Portföyüm/İzleme Listem filtreleri · liste rozeti **"Nötr" (sönük nokta) / "Pozitif 0.35"** — rozette "Ton" YAZMIYOR, soru kapandı |
| **AI Piyasa Etkisi sheet'i** | ✅ Çalışınca: "Olumlu Etki" kartı + özet + **Etkilenen 3 varlık · Ort. etki +%0,9 · Sektör** + "haber tonundan farklı olabilir" notu. 🔴 **ARA SIRA HATA** (≈3/10): "AI analizi şu an üretilemedi" — aynı istek curl'de 8/8 başarılı, yani geçici. Sheet'te **"tekrar dene" yok** → kullanıcı kapatıp yeniden açmak zorunda |
| **Hisse detay (MU)** | ✅ **Piyasa Öncesi $951.40 −%0,49** rozeti · zaman dilimi çipleri + **Pro** · **çizim araçları şeridi** (çizgi/mum/bar · imleç · fib · metin · trend · LIN/LOG · zoom) · OHLC başlığı + hacim · "Pozisyon Ekle" ve "İzlemeden Çıkar" satırları · AI ANALİZ bölümü başlıyor |
| **Pozisyon Ekle sheet'i** | ✅ "MU — Maliyetimle Ekle" · güncel fiyat kartı · Lot (adet) · Birim maliyet (güncel fiyatla ön-dolu). **Kaydetmedim** (Kerem'in verisi) |
| **İzleme listesi ilk boyama** | 🔴 **Madde 1'in görsel kanıtı**: ilk boyamada **varsayılan 8 sembol** (Altın·USD/TRY·EUR/TRY·Bitcoin·THYAO·Aselsan) görünüyor, saniyeler sonra gerçek liste (USD/TRY·Altın·MU·GOOG·EUR/TRY·DRAM) ile değişiyor. Sadece fazla istek değil, **yanlış liste yanıp sönüyordu** → bu turda düzeltildi |
| **"İzlemeden Çıkar" alt yazısı** | 🔴→✅ Başlık duruma göre değişiyor ama alt yazı sabit "Haber + sinyal taramasına **dahil et**"ti → düzeltildi (`stock_detail_screen.dart`) |
| Yanlış alarm | "Roundhill Memory ETF $56,21" ile "EUR/TRY ₺56,21" aynı rakam — **rastlantı**, uçtan doğrulandı (DRAM gerçekten $56,21) |

### 2b) AI KOÇ — Kerem'in ekran görüntülerinden çıkan İKİ bulgu (3 Eyl 10:58)

**Bulgu A — model portföyü YANLIŞ anlattı (düzeltildi).** Ekranda "Portföyünde
**beş** farklı varlık bulunuyor" deyip GOOG %41,3 · TUPRS.IS %29,8 · LMT %21,4 ·
DRAM %6,7 · KARCL.IS %0,9 saydı (toplam %100). Oysa portföy **38 pozisyon**.
Kök sebep: `chat_service.build_user_context` fiyatı alınamayan pozisyonları
"(güncel fiyat alınamadı)" diye yazıyor ama **ağırlıkları yalnız fiyatı bilinen
pozisyonlar üzerinden** hesaplıyor ve modele "eksik veri var" DEMİYORDU →
model kalan 5 satırı portföyün tamamı sandı. **Düzeltme:** bağlama
"UYARI: N pozisyonun güncel fiyatı ALINAMADI … ağırlıklar yalnız M pozisyondan
hesaplandı, portföy toplam K pozisyondur" satırı + sistem prompt'una 9. kural
("N varlıktan oluşuyor" deme, önce eksik veriyi söyle). 3 test.
Not: bu turun BIST yedeği (İş Yatırım) zaten eksik fiyat sayısını düşürüyor —
iki düzeltme aynı kökün iki ucu.

**Bulgu B — "Bağlantı hatası: ClientException: Failed to fetch, uri=…" (kısmen).**
Sohbet balonunda HAM istisna + uç URL'i (`?user_id=1&message=…`) görünüyordu.
**Yapılan:** kullanıcıya sade mesaj ("Bağlantı koptu — cevap tamamlanamadı.
Tekrar dener misin?"), ham hata `debugPrint`'e.
**RENDER LOG'U GELDİ (3 Eyl 11:52-11:54 ekran görüntüleri) — KÖK SEBEP BULUNDU:**
OOM/restart YOK (önceki hipotez yanlıştı). Log'da 10:57:32'de
`GET /api/v1/chat/send?...message=sence+portföyüm+nasıl` **200 (1102 ms)** —
yani istek backend'e ULAŞTI. Asıl arıza LLM zincirinde:
```
10:58:08 WARNING Gemini hatası (503 UNAVAILABLE ... high demand) → Groq'a düşülüyor
10:58:08 ERROR   Haber LLM enrich düştü (404 - The model `llama-3.3-70b-versatile`
                 does not exist or you do not have access to it)
11:40:17 WARNING gemini-2.5-flash-lite kotası doldu (429) → gemini-2.5-flash'a düşülüyor
```
Yani zincir: **flash-lite 429 → flash 503 → Groq 404** = TÜM AI özellikleri
(sohbet · haber analizi · makro takvim) aynı anda düşüyor. Groq dokümanında
model üretim listesinde DURUYOR → sorun modelin yokluğu değil, **hesabın
erişimi**. **Düzeltildi:** Groq artık tek modele bağlı değil — sıralı aday
zinciri (env `GROQ_MODEL` > llama-3.3-70b > gpt-oss-120b > gpt-oss-20b >
llama-3.1-8b-instant); 404/`model_not_found` alan model süreç boyunca ölü
işaretlenir, sıradaki denenir; kota/ağ hataları YUTULMAZ. 6 test.
Sohbet başlığındaki sabit "Llama 3.3 70B · RAG" etiketi de kaldırıldı
(yanlış model adı gösteriyordu).
**Kalan soru:** "Failed to fetch" mesajlarının kendisi log'da GÖRÜNMÜYOR
(o isteklerin backend kaydı yok) — AI zinciri düzelince tekrarlanıp
tekrarlanmadığına bakılacak.

**Log'dan çıkan DİĞER açık işler (henüz yapılmadı):**
- `Finnhub /stock/profile2 HTTP 403` (tekrarlıyor) → ücretsiz tier bu ucu
  kapatmış olabilir; sektör/şirket adı çözümü etkileniyor.
- Yahoo `quoteSummary` **401 Invalid Crumb / "User is unable to access"** —
  vekil YALNIZ chart yolunda; `.info`/quoteSummary hâlâ doğrudan gidiyor.
- Yahoo'ya **fon sembolü soruluyor** (`TLY.FON`, `LTL.FON` → 404 + "possibly
  delisted"); Yahoo TEFAS'ı kapsamıyor, bu istekler hiç atılmamalı.
- `BCHT · MOB · UROY` "possibly delisted; no price data found" — sembol
  doğruluğu Kerem'le teyit edilmeli.
- Yavaş uçlar: `/portfolio/1/health` 19,6 sn · `/news/for-symbols` 29,9 sn ·
  `/portfolio/1/benchmark` 8,6 sn.
- İYİ HABER: `Prewarm OK (53/53)` + `Piyasa yenilendi: 53 sembol` + `Yedek
  fiyat kaynağı kullanıldı (2): LTL.FON, TLY.FON` → arka plan işçisi sağlıklı.

**(ESKİ HİPOTEZ, ÇÜRÜTÜLDÜ):** aynı uç şu an sağlıklı (taze token + curl ile
SSE akışı sorunsuz döndü, CORS başlığı var, 200). "Failed to fetch" tarayıcı
seviyesinde bağlantının KOPMASI demek; en olası aday backend'in o sırada
yeniden başlaması (Render ücretsiz katman, 512 MB — sohbet RAG bağlamı büyük).
**Kerem'den istenen:** Render → portly-backend → **Logs**, 3 Eyl ~10:55-11:00
aralığı; "Out of memory" / "Exited with status" / restart satırı var mı?
Varsa çözüm bellek tarafında (bağlam küçültme / worker ayarı), yoksa ağ
tarafında aranacak.

### 3) SIRADA NE VAR
| # | İş | Durum |
|---|---|---|
| 1 | **Commit + (Kerem isterse) push** | Çalışma ağacı kirli; push = Render deploy |
| 2 | **Kaydırma gereken ekranlar** — hisse detayın altı (AI Temel Analiz · BIST oran tablosu · Notlarım · İlgili Haberler) · fon grafiği (TLY.FON) · satış kaydı · Notlarım ekranı | **Kerem kaydırır**, Claude okur |
| 3 | **AI Piyasa Etkisi'ne "tekrar dene" butonu** | Küçük, tarayıcıda kanıtlandı |
| 3b | **AI Koç "Failed to fetch" kök sebebi** | Render log'u bekliyor (↑ Bulgu B) |
| 4 | **Eski Neon merge** | Kerem'den İKİ bağlantı dizesi lazım |
| 5 | **Telefon/PWA turu** | Yalnız Kerem |
| 6 | **Şifre sıfırlama maili** | Bloker Umut'ta (Brevo anahtarları) |
| 7 | **Sinyal ilk tarama süresi** | Isıtma eklendi → canlıda yeniden ÖLÇ |

### 4) Bir ÖNCEKİ turda (2. tur) ne yapılmıştı (dosya + davranış)
| Bulgu | Nerede | Ne yapıldı |
|---|---|---|
| 1 · Emtia "Bugün +%0,00" | `market_data_service._fallback_quotes` · `yahoo_chart_service.get_quotes` · `portfolio_service` + `portfolio_schema` · `chat_service` · frontend `holding.dart` · `stock_model.dart` · `portfolio_provider` · `portfolio_screen` · `stock_card` · `stock_detail_screen` · `search_result_row` | Yeni sözleşme alanı **`change_available`** (`price_available` ikizi). Altın/gümüşün fiyatı spot'tan, **günlük değişimi Yahoo chart barlarından** tamamlanır; gelmezse bayrak False → "Bugün" satırı GÖSTERİLMEZ, rozet sönük "—", günlük toplam o pozisyonu HARİÇ tutar, AI bağlamına "bilinmiyor" yazılır. **Tek bar** dönen tüm yollar da (chart + yfinance tekil/batch) artık bilinmiyor işaretler |
| 2 · Yinelenen açılış isteği | `lib/data/market_repository.dart` · `portfolio_provider._initWatchlist` | `fetchMany`'ye uçuş-içi dedup; izleme listesi kurulumu kullanıcı kimliğine göre dedup'lu (kimliği baştan sabitler) |
| 3 · `.FON` sızması | `lib/utils/symbol_display.dart` | `label()` `.FON` kırpıyor; **`.IS`/`.TR` DEĞİŞMEDİ** (testle sabit) |
| 4 · Sinyal fon fiyatı | `lib/screens/signals_screen.dart` | `priceDecimals` ile hassas gösterim |
| 5 · EN kumar spamı | `nlp_sentiment_service._NOISE_RE` | Dar EN promosyon kalıpları; gerçek kumar-sektörü haberleri (Las Vegas Sands · DraftKings · Wynn) 10 örnekle korunduğu doğrulandı |
| 6 · "MU / MU" | `portfolio_provider._scheduleNameRefresh` | 5 ve 10 sn'de en fazla iki **sessiz** tazeleme; adı bilinen sembollerde hiç tetiklenmez |

**Uygulama:** Flutter Web + FastAPI — **🔄 PİVOT (49. tur):** gerçek **portföy takibi +
haber + kural tabanlı AL/TUT/SAT sinyal asistanı**. Backend PostgreSQL (Neon) + Alembic +
Gemini/Groq AI. Test kullanıcı: **umut@mail.com / 123456**.

🎓 **BAĞLAM:** Bitirme projesi; **hoca demosu YAPILDI** → öncelik: pivotu tamamlamak >
cila > güvenlik/deploy. Backlog: `GELISTIRME_ONERILERI.md` (⚠️ trade maddeleri eskidi).

### 📁 DOKÜMAN HARİTASI (hangi dosya ne için — karıştırma, çoğaltma)
- **SESSION_HANDOFF.md** (BU) — **TEK ileri-plan kaynağı**: güncel durum + açık işler + kalıcı kurallar + çalıştırma. Yeni session SADECE bunu okur.
- **GELISTIRME_ONERILERI.md** — kanonik **DETAYLI backlog** (öncelikli yapılacaklar). Handoff'a tabidir.
- **CIHAZ_DOGRULAMA.md** — 🔴 **cihazda elle doğrulanacak işlerin TEK listesi**. 3 Eylül düzeltmeleri "A0" bölümünde (çoğu tarayıcıda işaretlendi, telefon bekliyor).
- **CHANGELOG.md** — **tarihsel geçmiş** (tur-tur narrative + v1–v6).
- **README.md** — kurulum/çalıştırma (geliştirici).
- **Portly_SDD.md** / **PROJE_DOKUMANI.md** — ⚪ **DONMUŞ akademik teslim** (v1.0). Güncel kodu YANSITMAZ; istenmedikçe DOKUNMA.

---

## 🟢 MEVCUT DURUM (3 Eylül 2026, 3. tur — DAYANIKLILIK + AÇILIŞ ARTIĞI)

**Durum:** Yukarıdaki "BURADAN BAŞLA" bu turun özetidir. Kısaca: açılıştaki
fazla `/market/prices` gitti (5→4 istek, yanlış-liste yanıp sönmesi de bitti) ·
BIST'e Yahoo'dan bağımsız ikinci kaynak geldi (İş Yatırım) · fon kataloğu
kendini tazeliyor · temel oran cache'i arka planda ısınıyor · backlog ayıklandı.
**601 backend + 67 flutter testi geçiyor, analyze temiz. HENÜZ COMMİT YOK.**

**Yeni kalıcı kural — BIST yedeği:** İş Yatırım ucu GÜN İÇİ fiyat vermez.
`bist_source_service.get_quotes` yalnız seans KAPALIYKEN doldurur; seans
açıkken boş döner (kullanıcı "Fiyat —" görür, uydurma rakam görmez). Yeni bir
BIST kaynağı eklerken bu sınırı koru.

---

## 🟢 (ÖNCEKİ) 3 Eylül 2026, 2. tur — 6 BULGU DÜZELTİLDİ

> ⚠️ **Bu bölüm artık en güncel DEĞİL** (üsttekiler geçerli). Aşağıdaki "3 Eylül — TARAYICI DOĞRULAMASI"
> bölümü bu turun GİRDİSİDİR (bulguların ölçüm/gerekçe ayrıntısı orada);
> çelişirse burası geçerlidir.

**Durum:** 6 bulgunun hepsi düzeltildi · commit `3839743` · **push'landı** ·
**Render deploy CANLI DOĞRULANDI** · **tarayıcıda görüldü** (Kerem kaydırdı).
Kalan: telefon/PWA turu + aşağıdaki tek artık (fazla `/market/prices`).

**Canlı doğrulama (3 Eylül, `portly-frontend.onrender.com` + backend ucu):**
Altın "Bugün **+%2,37**" (sahte %0,00 gitti, ad "Altın") · portföyde **LTL/TLY**
ve sinyal kartında **LTL** (sonek yok), BIST hâlâ **ZOREN.IS/KARSN.IS** ·
sinyalde fon fiyatı **₺1,0893** · izleme listesi ilk boyamada **"Micron
Technology Inc"/"Alphabet Inc"** · `/watchlist` **×1** (açılış 6→5 istek) ·
`en|bitcoin` **14 haber, 0 kumar başlığı** · sinyaller **51 = 7 AL + 43 TUT +
1 SAT**. Uç yanıtı artık `change_available` taşıyor (fonlar taşımıyor → TEFAS
gerçek günlük değişim veriyor, istemcide varsayılan `true` doğru davranış).
**Artık:** `/market/prices` açılışta hâlâ 2 kez (sebep ve çözüm ↑ madde 1).

**Doğrulanan:** backend `venv/bin/python -m pytest -q` → **570 passed** ·
`flutter test` → **60 passed** · `flutter analyze` → temiz ·
`flutter build web --release --pwa-strategy=none --no-tree-shake-icons` → OK.
Ne yapıldığının dosya-dosya dökümü ↑ "BURADAN BAŞLA" madde 2'de.

**Yeni kalıcı sözleşme — `change_available`:** `price_available` ile aynı
mantık, ama GÜNLÜK DEĞİŞİM için. Fiyatı bilinip değişimi bilinmeyen kaynaklar
var (altın/gümüş spot: fiyat verir, dünkü kapanışı vermez) ve tek-bar dönen
her yol (borsa kapalıyken) aynı duruma düşer. **Kural: değişim bilinmiyorsa
0 BASMA** — bayrağı taşı, arayüz "Bugün" satırını hiç göstermesin, rozet sönük
"—" olsun, portföy günlük toplamı o pozisyonu hesaba KATMASIN. Yeni bir fiyat
kaynağı eklerken bu alanı doldur (varsayılan `True` = eski davranış).

### ⏳ AÇIK İŞLER (öncelik sırasıyla)
1. **Commit + push + deploy** → sonra `CIHAZ_DOGRULAMA.md` **A0** listesi
   (bu turun 6 düzeltmesinin canlı karşılığı).
2. **🔴 Tarayıcıda GÖRÜLEMEYEN ekranlar** (eklenti koptu) — ↑ madde 3.
3. **Eski Neon merge** — Kerem'den İKİ bağlantı dizesi lazım
   (`backend/scripts/merge_old_neon.py`).
4. Worker tek dayanak (Yahoo) · fon kataloğu tazeliği · temel oran prewarm
   (isteğe bağlı) — ↓ önceki turlar.

---

## 🟢 MEVCUT DURUM (3 Eylül 2026 — TARAYICI DOĞRULAMASI + 6 yeni bulgu)

> ⚠️ **ARTIK EN GÜNCEL DEĞİL** — üstteki "3 Eylül, 2. tur" bölümü geçerlidir.
> Bu, bulguların ÇIKTIĞI doğrulama turudur (ölçümler + gerekçeler burada);
> **6 bulgunun hepsi 2. turda düzeltildi**, aşağıdaki "hiçbiri düzeltilmedi"
> ifadesi tarihsel. Bu turda kod değişmemişti.

Claude for Chrome eklentisi bu turda **bağlandı** (geçen turun blokeri kalktı) ve
canlı frontend'de (`portly-frontend.onrender.com`) oturum açılıp ekran ekran
gezildi. **Eklenti tur ortasında koptu** → Haberler sekmesi ve hisse detay
ekranı TARAYICIDA görülemedi; onlar backend uçlarından doğrulandı.

### ✅ TARAYICIDA DOĞRULANDI (canlı, ekran görüntüsüyle)
| Kontrol | Sonuç |
|---|---|
| **İkon budaması (tree-shake)** | ✅ **Eksik ikon YOK.** Onboarding'in 4 ikonu (`auto_awesome`·`account_balance_wallet`·`insights`·`menu_book`), logo, giriş formu (@·kilit·göz·onay kutusu), alt sekme çubuğu, Portföy hub'ının ~12 satır ikonu, AI FAB, tema/profil/çıkış — hepsi çiziliyor |
| Açılış istek sayısı | **6** (`/watchlist`×2 · `/market/prices`(16 sembol)×2 · `/portfolio/1` · `/performance`) — hedef ~5 tutturuldu ama 2'si YİNELENEN (↓ Bulgu 2) |
| Portföyde fiyatsız satır | **0/38** ✅ ("Fiyat —" hiç yok) |
| Fon satırları | ✅ **Fon · 2** grubu: `TLY.FON` ₺910.805,52 · +%47,08 (birim ₺9.293,93) · `LTL.FON` ₺15.508,98 · −%2,13 (birim **₺1,0962** — hassas gösterim ÇALIŞIYOR) |
| Borsa dağılımı | ✅ **Fon %38,9** · ABD %27,1 · Emtia %17,8 · BIST %16,2 (4 borsa) |
| Sektör dağılımı | ✅ Fon/ETF %40,4 · Altın %17,8 · Enerji %11,9 · Savunma %10,3 · **Diğer %5,5** (13 sektör) · donut taşmıyor |
| Sinyaller sekmesi | ✅ **<2 sn** açıldı (sıcak) · **TÜMÜ 51 = AL 6 + TUT 43 + SAT 2** (sayaçlar tutarlı) · `failed` YOK · "yatırım tavsiyesi değildir" en altta · fonda "Temel veri yok" (teknik-only) · BIST'te de dürüstçe "Temel veri yok" |
| Sağlık skoru / benchmark | ✅ 74/100 · Portföy vs. Endeksler (Sharpe 5.19) · Bugün/Toplam iki ayrı satır |
| Sanal bakiye kalıntısı | ✅ Portföy hub'ında ve hero'da "Bakiye"/"Nakit" YOK |

### ✅ BACKEND'DEN DOĞRULANDI (tarayıcı koptuktan sonra, curl ile)
- **BIST haber çöp filtresi ÇALIŞIYOR**: `tr|THYAO OR "Türk Hava Yolları"` + `tr|ASELS OR Aselsan` → 10 haber, **0 TradingView / "teknik analiz"**, hepsi gerçek Türk basını (Anadolu Ajansı · Bloomberght · CNBC-e · Investing.com TR · Paratic · Savunma Hattı).
- **ABD/kripto haberi İngilizce orijinal kaynak**: Morningstar · FXStreet · Benzinga · Robinhood, bugünün tarihli. (↓ Bulgu 5)
- **Fon grafiği**: `/market/history/TLY.FON?range=3mo` → 24 günlük nokta, son kapanış ₺9.348,23.
- **Fon araması**: `/market/search?q=TLY` → `TLY.FON` "TERA PORTFÖY BİRİNCİ SERBEST FON · TEFAS" ilk sırada.
- Uçlar hızlı: `/market/price/TLY.FON` 0,13 sn · `THYAO.IS` 0,16 sn · frontend ilk yükleme 0,50 sn.

### 🔴 YENİ BULGULAR (hepsi yeniden üretilebilir; hiçbiri düzeltilmedi)

**1. Emtia günlük değişimi HER ZAMAN %0 — "dürüst boş-durum" kuralı ihlali**
`GC=F` ve `SI=F` `change_percent: 0.0` dönüyor, fiyat ise canlı oynuyor
(4.358,43 → 4.378,05 dakikalar içinde). Arayüz bunu **yeşil "+%0,00" ve
"Bugün +%0,00"** diye basıyor → kullanıcı "altın bugün hiç hareket etmemiş"
okuyor. Kök sebep: `backend/app/services/market_data_service.py:465-471` —
altın/gümüş `gold_rates_service.spot_metal_usd` spot kaynağından geliyor,
kaynak günlük değişimi vermediği için kasten `0.0` yazılıyor; ama bu
"bilinmiyor" bilgisi arayüze taşınmıyor. **Veri VAR**: `/market/history/GC=F`
Worker üzerinden günlük kapanışları veriyor (doğrulandı) → değişim oradan
hesaplanabilir. Alternatif: `price_available` gibi bir `change_available`
bayrağı + arayüzde "Bugün" satırını hiç göstermemek.

**2. Açılışta yinelenen istek: `/market/prices` ve `/watchlist` İKİ kez gidiyor**
6 açılış isteğinin 2'si fazlalık (16 sembollük batch iki kez). Kök sebep:
`lib/data/market_repository.dart` — uçuş-içi dedup yalnız `fetchOne`'da var,
**`fetchMany`'de YOK**; iki tüketici aynı anda çağırınca ikisi de ağa çıkıyor.
`fetchOne`'daki `_inFlight` desenini `fetchMany`'ye de uygula (anahtar =
sıralı sembol listesi).

**3. `.FON` soneki kullanıcıya SIZIYOR (kural: sonek gösterilmez)**
Portföy satırı ve sinyal kartı başlığı "TLY.FON" / "LTL.FON" yazıyor.
Kök sebep: `lib/utils/symbol_display.dart` — portföy satırı
(`portfolio_screen.dart:617`) `SymbolDisplay.label()` kullanıyor ve `label()`
sonek KIRPMIYOR; kırpan `compact()`. (Aynı sebeple BIST satırları da
"KARCL.IS/PAPIL.IS" görünüyor — `_labels` haritasında olanlar "Tüpraş/Aselsan"
diye güzel çıkıyor. `.IS` eski davranış, `.FON` ise açıkça söz verilmişti.)

**4. Sinyal kartında fon fiyatı yuvarlanıyor**
Portföyde ₺1,0962 doğru gösterilirken sinyal kartında **₺1,10**.
`lib/screens/signals_screen.dart:297` → `formatMoney(price)` çağrısında
`decimals: SymbolDisplay.priceDecimals(symbol, price)` eksik.

**5. İngilizce haber akışında kumar spamı**
`en|bitcoin` sonucunda "Best Crypto Casinos 2026 …" başlığı **iki kez** geldi.
`nlp_sentiment_service._NOISE_RE` yalnız Türkçe çöpü (tradingview / teknik
analiz) eliyor; İngilizce tarafta casino/gambling/"best crypto" kalıbı yok.

**6. İlk girişte şirket adı yerine sembol görünüyor (küçük)**
Giriş sonrası izleme listesi "MU / MU", "GOOG / GOOG" gösterdi; **sayfa
yenilenince** "Micron Technology Inc" / "Alphabet Inc" geldi. Batch uç adı
ağdan çözmeyip arka plana bıraktığı için tasarım gereği, ama ilk açılışta
kullanıcı sembolü görüyor. İstenirse: ad cache'i soğukken batch yanıtı
dönmeden önce tek sefer ısıtılabilir (veya arka plan çözümü bitince istemci
sessizce tazelenebilir).

### ⏳ AÇIK İŞLER (öncelik sırasıyla)
1. **Yukarıdaki 6 bulgu** — Kerem hangisini istiyorsa. Öneri sırası:
   Bulgu 1 (dürüstlük kuralı) > Bulgu 3 (söz verilen davranış) >
   Bulgu 2 (açılış maliyeti) > Bulgu 4 > 5 > 6.
2. **🔴 Tarayıcıda GÖRÜLEMEYEN ekranlar** (eklenti koptu): **Haberler sekmesi
   arayüzü** (rozetler: "Ton" vs "AI Piyasa Etkisi", nötr sönük nokta, etkilenen
   varlık çipi) · **hisse detay** (pre/post chip · AI Temel Analiz · BIST oran
   tablosu "—" gösterimi · fon grafiği arayüzde · çizim araçları) · **pozisyon
   ekle/sat akışı** · **izleme listesi senkronu** · **Notlarım**.
   Yeni session: eklenti bağlıysa buradan devam et; **parolayı Claude yazamaz**,
   Kerem `umut@mail.com / 123456` ile elle giriş yapmalı.
3. **Eski Neon merge** — iş bölümü değişmedi (↓ 2 Eylül GECE turu, madde 2).
   Script hazır: `backend/scripts/merge_old_neon.py`. Kerem'den İKİ bağlantı
   dizesi lazım.
4. Worker tek dayanak (Yahoo) · fon kataloğu tazeliği · temel oran prewarm
   (isteğe bağlı) — ↓ önceki tur.

---

## 🟢 MEVCUT DURUM (2 Eylül 2026, GECE turu — TEFAS yatırım fonu desteği)

> ⚠️ **ARTIK EN GÜNCEL DEĞİL** — üstteki "3 Eylül" bölümü geçerlidir; bu, son
> KOD turudur (HEAD hâlâ burada). Aşağıdaki "AKŞAM turu" aynı günün önceki turu;
> çelişirse burası geçerlidir. **4 commit push'landı, canlı deploy DOĞRULANDI**
> (`d5a6f06` fon · `1ed500a` handoff · `085c779` sinyal perf · `c7817b6` Neon
> birleştirme scripti). Testler: backend **550** yeşil · flutter **55** yeşil ·
> `flutter analyze` temiz · web build OK.

### Kapatılan iş: fon desteği (eski açık iş #2)
`TLY` ve `LTL` **TEFAS yatırım fonu**ydu; ekstre içe aktarımı kur TRY diye
sonlarına ".IS" ekleyip BIST hissesi sanıyordu. Yahoo TEFAS fonlarını **hiç
kapsamıyor** (erişim değil, KAPSAM sorunu — Cloudflare Worker bunu çözmez) →
iki satır "Fiyat —" görünüyor, sinyal taramasında `failed[]`'e düşüyor, portföy
değeri **maliyetle** sayılıyordu.

**Kaynak bulundu ve canlı doğrulandı.** ⚠️ Handoff'ta yazan
`/api/DB/BindHistoryInfo` ucu **KAPALI** ("Method not found or disabled!") —
TEFAS 2026-04'te Next.js mimarisine geçmiş. Güncel uç:
`POST https://www.tefas.gov.tr/api/funds/fonFiyatBilgiGetir`
(JSON gövde: `{"fonKodu":"TLY","dil":"TR","periyod":36}` — serbest tarih
aralığı KABUL ETMİYOR, sabit dönem kodları: 1=1A · 6=6A · 12=1Y · 36=3Y · 60=5Y).
Fon listesi: `fonGetiriBazliBilgiGetir` (2.138 fon, hepsi 3 harfli kod).

**Ölçülen etki (canlı fiyatlarla):**

| | Önce | Sonra |
|---|---|---|
| TLY (98 adet, maliyet ₺6.318,98) | Fiyat — · K/Z %0 | ₺9.293,93 → **₺910.805 · +%47,08** |
| LTL (14.148 adet, maliyet ₺1,12) | Fiyat — · K/Z %0 | ₺1,096196 → ₺15.509 · −%2,13 |
| Portföyde görünmeyen K/Z | — | **₺+291.209** |

### Ne eklendi
- **`backend/app/services/fund_catalog.py` + `app/data/tefas_funds.json`** —
  2.138 fonun kod→(unvan, şemsiye tür) yerel kataloğu. Üretici:
  `backend/scripts/generate_tefas_catalog.py` (yılda birkaç kez çalıştır).
  Ağsız olması şart: göç, ekstre çözümü ve arama buna bakıyor.
- **`fund_source_service.py`** — TEFAS istemcisi. Fon başına **TEK istek**
  3 yıllık seriyi verir; fiyat + günlük değişim + kapanış serisi + OHLCV +
  grafik hepsi o seriden türetilir. Cache 3 sa taze / 5 gün bayat (fon fiyatı
  günde bir açıklanır), istekler sıralı+aralıklı, 429'da 5 dk devre kesici.
- **Sembol biçimi `.FON`** (TLY → `TLY.FON`): ".IS" ile karışmaz, Yahoo'ya
  boşuna sorulmaz, URL'de güvenli, mevcut sonek kurallarıyla aynı desen.
- **Veri göçü** `b7d1f4c2e8a9` — eski `TLY.IS`/`LTL.IS` satırları 6 tabloda
  `.FON`'a taşınır. Ağa çıkmaz, YALNIZ 3 harfli kodlara dokunur (TEFAS kodları
  3 harf, BIST pay kodları 5 harf → çakışma yok). Testi var, geri alınabilir.
- **Kur/sektör/varlık sınıfı**: `.FON` → ₺ (fx · benchmark · temettü · stres),
  sektör "Fon/ETF", `_classify` → `fund`, borsa dağılımında yeni "Fon" grubu.
- **Sinyal dürüstlüğü**: fonda F/K-ROE uygulanmaz (teknik-only). Ayrıca
  **birikimli fon koruması**: para piyasası tarzı fonlar hiç düşmediği için
  RSI/Stochastic daima 100 çıkıyor ve motor bunu "aşırı alım, geri çekilme
  riski" diye okuyordu — düşüş günü oranı %5'in altındaki fonda mean-reversion
  kuralları HİÇ uygulanmaz, gerekçe bunu açıkça yazar.
- **Arama**: fon kodu/unvanıyla aranabilir (Yahoo'da yok, yalnız yerel
  katalogdan gelir). Yan düzeltme: Yahoo araması patlarsa uç eskiden `[]`
  dönüyordu → artık yerel sonuçlar (BIST + fon) yine döner.
- **Frontend**: `.FON` → ₺, "TLY · Fon" ikincil etiketi, sonek kullanıcıya
  gösterilmiyor, borsa dağılımında "Fon" dilimi, **birim pay değeri hassas
  gösterim** (1,096196'yı 1,10 diye yuvarlamıyor: fonda <1 → 6, <100 → 4 basamak).
- **Worker + `TEFAS_PROXY_BASE`** — TEFAS'ın Render IP'sini kısıtlayıp
  kısıtlamadığı ÖLÇÜLEMEDİ (deploy gerekiyor). Kısıtlarsa kod değişikliği
  gerekmez: Worker artık TEFAS yolunu POST olarak da vekilliyor, tek iş
  Worker'ı yeniden yayına alıp Render'a `TEFAS_PROXY_BASE` eklemek
  (`infra/cloudflare-worker/README.md`).

### ⚠️ Bu turda anlaşılan kural
Aynı 3 harfli kod HEM fon HEM ABD tickerı olabilir: **`URA`** hem bir TEFAS
fonu hem Kerem'in portföyündeki Global X Uranium ETF'i. Bu yüzden çıplak koda
ASLA otomatik fon muamelesi yapılmaz — karar ya kur bilgisiyle (ekstrede TRY)
ya kullanıcının aramadan seçmesiyle verilir. `canonical()` yalnız `XXX.IS`
(3 harf + katalogda var) biçimini `.FON`'a çevirir.

### ✅ CANLI DOĞRULANDI (deploy sonrası, prod'a curl ile)
| Ölçüm | Önce | Sonra |
|---|---|---|
| `/market/price/TLY.FON` | "Sembol bulunamadı" | ✅ ₺9.293,933893 · adıyla |
| Portföyde fiyatsız satır | 2/38 (iki fon) | **0/38** |
| TLY pozisyonu | maliyetle ₺619.260 | **₺910.805 · +%47,08** |
| Sinyal taraması | 49 sinyal / 2 başarısız | **51 / 0** |
| `/signals` SOĞUK (süreç yeniden başladıktan sonra) | **24,5 sn** | **6,1 sn** (Redis boşken) · sonraki restart **4,1 sn** · sıcak **0,6 sn** |
| Fon grafiği · fon araması · sektör · benchmark | yok | ✅ (fon benchmark bileşeni: TLY +%63,89/3A) |
| Sektör dağılımı | — | "Fon/ETF" %40,5 (fonlar dahil) |

**TEFAS Render'ın IP'sinden DOĞRUDAN çalışıyor** — vekile gerek kalmadı
(`TEFAS_PROXY_BASE` boş; gerekirse hazır, README'de).

Alembic göçü `b7d1f4c2e8a9` deploy'da koştu: DB'de `TLY.IS`/`LTL.IS` kalmadı.

### ⏳ AÇIK İŞLER (öncelik sırasıyla)
1. **🔴 CİHAZ / TARAYICI DOĞRULAMASI — tek kalan iş.**
   Doğrulanacaklar: **ikon eksiği** (tree-shake sonrası) · açılış süresi ·
   sekmeye ilk geçişte veri geliyor mu · "Fiyat —/fiyat yok" satırları ·
   fon satırları (₺ + hassas birim pay değeri) · "TLY · Fon" etiketi · borsa
   dağılımında **Fon** dilimi · fon grafiği. **PWA cache temizle + `?cb=` şart.**

   **⚠️ YENİ SESSION — ÖNCE ŞUNU İSTE:** Kerem'den **Claude for Chrome
   eklentisini bağlamasını** iste (https://claude.ai/chrome; Claude Code ile
   AYNI hesapla giriş yapılmış olmalı, kurulumdan sonra Chrome yeniden
   başlatılmalı). Bu turda denendi ama eklenti bağlı değildi
   ("Browser extension is not connected") → doğrulama Kerem'e kaldı.
   Eklenti bağlıysa doğrulamanın **büyük kısmını session kendisi yapabilir**:
   `portly-frontend.onrender.com`'a girip `umut@mail.com / 123456` ile
   oturum açar, ekran görüntüsü alıp ikonları/fon satırlarını gözle kontrol
   eder, konsol hatalarını okur. **Telefonda** (gerçek PWA + dokunma) son
   kontrol yine Kerem'de kalır.

2. **Eski Neon merge — İŞ BÖLÜMÜ NET:**
   - **Kerem**: İKİ bağlantı dizesini bulup session'a verir.
     (a) **ESKİ** Neon projesi ("portly", kota resetiyle uyandı) → Neon
     konsolu → eski proje → Connection string. (Neon/Render girişi Umut'ta.)
     (b) **YENİ** hedef (`portly-2`) → Render → portly-backend → Environment →
     `DATABASE_URL`. ⚠️ **Bu şart:** lokalde `.env` YOK, `DATABASE_URL`
     varsayılanı `sqlite:///./portly.db` → `--new` verilmezse boş bir yerel
     SQLite'a birleştirir, canlıya değil.
   - **Session (Claude)**: scripti çalıştırır, önce KURU çalışma çıktısını
     gösterir, Kerem onaylayınca `--apply` yapar, sonra canlıdan doğrular.
     ```bash
     cd backend
     venv/bin/python -m scripts.merge_old_neon --old "<ESKİ>" --new "<portly-2>"
     venv/bin/python -m scripts.merge_old_neon --old "<ESKİ>" --new "<portly-2>" --apply
     ```
     Script üstüne YAZMAZ (Kerem'in sonradan eklediği satırlar korunur), iki
     kez çalıştırmak çift satır üretmez, eski `TLY.IS` → `TLY.FON` çevirir.
   - Dizeler **parola içerir**: dosyaya yazma/commit'leme, iş bitince
     Kerem'e söyle (gerekirse Neon'da rotasyon).

3. **Worker tek dayanak** (Yahoo tarafı) — BIST'in ücretsiz alternatifi yok.
4. **Fon kataloğu tazeliği** — yeni kurulan fon katalogda yoksa
   `scripts/generate_tefas_catalog.py` çalıştırılıp commit'lenir.
5. **İsteğe bağlı (yapılmadı):** temel oranları arka plan işçisinde önceden
   ısıtmak → 12 saatte bir ödenen 6 sn de kullanıcıya hiç yansımaz. Sinyaller
   sekmesi zaten tembel yüklendiği için şart görülmedi.

---

## 🟢 MEVCUT DURUM (2 Eylül 2026, AKŞAM turu — açılış hızı + veri dayanıklılığı + dürüst boş-durum)

> ⚠️ **EN GÜNCEL BÖLÜM BURASI.** Aşağıdaki "2 Eylül (veri altyapısı)" bölümü aynı
> günün ÖNCEKİ turu; çelişirse burası geçerlidir. **Commit YOK, push YOK** (Kerem
> istemedi) — çalışma ağacı bu turun değişiklikleriyle KİRLİ. Testler: backend
> **506** yeşil · flutter **49** yeşil · `flutter analyze` temiz · web build OK.

### 🔴 CANLI DURUM ÖLÇÜLDÜ (bu turda, prod'a curl ile)
| Ölçüm | Sonuç |
|---|---|
| `/health` (soğuk sanılan backend) | **0,27 sn** — UptimeRobot uyanık tutuyor, "50 sn cold start" ŞU AN YAŞANMIYOR |
| `/market/price/AAPL` | 200 ✅ (Finnhub yedeği çalışıyor) |
| `/market/price/THYAO.IS` · `/BTC-USD` | **400 "Too Many Requests"** ❌ |
| `/market/history/{AAPL,THYAO.IS,BTC-USD}` | **400 429** — Yahoo'nun grafik ucu da bloklu, yani **grafikler her sembolde ölü** |
| `/api/v1/signals` | 15 sn, **0 sinyal / 51 failed** ❌ |
| `/portfolio/1` · `/performance` · `/health` · `/benchmark` (cache SICAK) | 4,2 · 10,6 · 8,7 · 4,8 sn — hepsi yavaş |

**Kerem'in ekran görüntüsü (11:47):** BIST satırlarının tamamı "Fiyat ₺35,00 ·
Maliyet ₺35,00 · +%0,00 · Bugün +%0,00" — yani **fiyat alınamayınca maliyet
fiyat yerine geçiyor** ve kullanıcı bunu "hiç değişmemiş" diye okuyor.

### ✅ BU TURDA YAPILANLAR

**A. Açılış hızı (asıl şikâyet: "ilk açılım çok yavaş")**
Kök sebep tek şey değildi, **dört ayrı tıkanma** vardı:
1. **4 sekme de açılışta kuruluyordu** (`main.dart` IndexedStack eager) → daha ilk
   karede Haber (24 sembol RSS+LLM), **Sinyaller (15 sn tarama)**, Portföy kartları
   (sağlık+benchmark) dahil ~12 istek atılıyordu; kullanıcı Ana Sayfa'ya bakarken
   0,5 CPU'luk ücretsiz örnek bunları paralel işliyordu. → **Sekmeler artık TEMBEL**
   (`_visited` seti; ilk ziyarette kurulur, sonra IndexedStack'te kalır → state korunur).
2. **Token doğrulaması TÜM uygulamayı bloke ediyordu** (`auth_provider._bootstrap`
   `fetchMe`'yi await ediyordu, AuthGate boş spinner) → backend uykudaysa kullanıcı
   50 sn boş ekran. → **Cache'teki kullanıcıyla ekran HEMEN açılıyor**, doğrulama
   arkadan (`_revalidateSession`); 401+refresh de tutmazsa oturum kapanır, ağ
   hatası oturumu KAPATMAZ.
3. **İzleme listesi sembol BAŞINA ayrı istek atıyordu** (`MarketRepository.fetchMany`
   → N× `/market/price/{sym}`; her biri sunucuda ad çözümü için ek Yahoo çağrısı).
   → YENİ uç **`GET /api/v1/market/prices?symbols=A,B,C`** (batch + yedek zinciri +
   `missing[]`); istemci buna geçti, uç yoksa eski yola düşer.
4. **Açılışta çift/gereksiz yükleme:** fiyatlar iki kez çekiliyordu (provider
   constructor + `updateUserAuth`) → liste değişmediyse ikincisi atlanıyor;
   **haber açılışta hiç çekilmiyor** (yalnız Haber sekmesi kullanıyor →
   `ensureNewsLoaded()`).

**Açılıştaki istek sayısı: ~26 → ~5** (Ana Sayfa'da; haber/sinyal/sağlık/benchmark
artık yalnız o sekmeye geçilince).

**B. Statik dağıtım (`render.yaml`)**
- `--no-tree-shake-icons` KALDIRILDI → **MaterialIcons 1.645.184 → 34.224 bayt**
  (+ CupertinoIcons 257.628 → 1.172). Gerekçe "ikon eksik gelmesin"di ama kodda
  **dinamik `IconData` YOK** (grep'lendi) → budama güvenli. ~1,8 MB daha az indirme.
- **Cache-Control başlıkları eklendi.** Render varsayılanı `max-age=0` idi →
  tarayıcı HİÇBİR ŞEYİ saklamıyordu, her açılış main.dart.js (1,1 MB br) + canvaskit
  + font için ağ turu demekti. Artık `canvaskit/*` immutable, `assets|icons/*` 1 gün,
  JS + index.html `no-cache` (ETag → 304, gövde inmez; deploy'da bayat JS riski yok).
- `index.html`: gstatic **preconnect** (canvaskit oradan iniyor) + pivot artığı
  meta açıklaması ("sanal borsa simülatörü") düzeltildi.

**C. Veri dayanıklılığı — BIST/kripto boşluğu**
- YENİ `crypto_source_service.py` — **keysiz** borsa API'leri: **Coinbase Exchange
  (gerçek USD paritesi, kur sapması yok)** → olmazsa **Binance (USDT, yaklaşık)**.
  Fiyat + **6 aylık günlük mum** verir → kripto sinyalleri ve kripto grafiği
  Yahoo'suz çalışır.
- YENİ `yahoo_chart_service.py` — yfinance'siz, yalnız Yahoo'nun **açık chart ucu**;
  `YAHOO_PROXY_BASE` tanımlıysa **Cloudflare Worker vekili** üzerinden gider
  (Render'ın cezalı IP'si devre dışı). **429 görürse 15 dk kendini kapatır** (devre
  kesici — cezayı uzatmamak için).
- Her ikisi de **üç yola** bağlandı: fiyat (`_fallback_quotes`), kapanış serisi
  (`refresh_daily_closes`), OHLCV (`refresh_daily_ohlcv`) **+ grafik ucu**
  (`get_stock_history`, yalnız günlük aralıkta; intraday'de eski davranış).
- **Arka plan prewarm artık yedekleri de ısıtıyor** — eskiden yalnız Yahoo'yu
  deniyordu, yedek maliyeti kullanıcı isteğinde ödeniyordu.
- **Negatif cache (10 dk):** hiçbir kaynaktan gelmeyen sembol her istekte baştan
  denenmiyordu → `/portfolio` 4,2 sn, `/performance` 10,6 sn buradan geliyordu.
  Arka plan işçisi bu bayrağa BAKMAZ (kaynak açılınca veri kendiliğinden döner).
- **Ad cache'i paylaşılana taşındı** (Redis, 30 gün) + BIST kataloğu + Finnhub
  profili; batch fiyat yolu ad için **ağa çıkmaz**, bilinmeyeni arka planda çözer.

**D. Dürüst boş-durum (KALICI KURAL ihlali düzeltildi)**
Backend artık her pozisyonda **`price_available`** gönderiyor (şemada da var —
yoksa `response_model` siler, 40. turun `change_percent` regresyonu). Fiyat
canlı değilse satır: **"Fiyat —"**, rozet **"fiyat yok"** (sönük), **"Bugün"
satırı hiç çıkmıyor**; hero altında **"N pozisyonun güncel fiyatı alınamadı —
bu satırlar maliyetle sayıldı"**. Sayılar aynı (toplamlar bozulmadı), yalnız
uydurma "+%0,00" gitti.

### ✅ CLOUDFLARE WORKER KURULDU — CANLI DOĞRULANDI (15:00-15:20)

Kerem Worker'ı yayına aldı (`portly-yahoo.keremcanarslan27.workers.dev`),
Render'a `YAHOO_PROXY_BASE` eklendi. **Yahoo erişimi tamamen geri geldi.**

| | ÖNCE | SONRA |
|---|---|---|
| BIST fiyatı (THYAO) | 429 | ✅ ₺295,50 · adıyla |
| Kripto (BTC) | 429 | ✅ $76.824 |
| Grafikler (5 dilim × 3 sembol) | HEPSİ 429 | ✅ 15/15 (5m·15m·1h·2h·1d) |
| Sinyaller | 0 sinyal / 51 başarısız | ✅ **49 sinyal / 2 başarısız** |
| Fiyatsız pozisyon | çoğu | **2/38** (ikisi de geçersiz sembol) |
| /portfolio · /benchmark | 4,2 · 4,8 sn | 2-3 sn · 0,9 sn |
| /performance · /health (sıcak) | 10,6 · 8,7 sn | **0,49 · 0,29 sn** |

Deploy sonrası ek düzeltmeler (hepsi canlı doğrulandı):
- **Intraday grafikler**: vekil kurulduktan sonra fiyat düzeldi ama grafik
  hâlâ 400'dü — yedek yolu yalnız GÜNLÜK mumu kapsıyordu, oysa grafik
  ekranının varsayılanları intraday (1mo→1h). `get_history_rows` her aralığı
  destekler; 2h/4h 1h'ten toplanır (`_aggregate_hours`).
- **Haber tazeliği**: ölçüldü, portföy haberinin **%19'u bir aydan eskiydi**
  (en eski 11 Şubat) — Google News dar sorguda yeni haber bulamayınca eskisini
  döndürüyor, sembol kotası onlarla doluyordu. `_MAX_NEWS_AGE_DAYS=30`, filtre
  KOTADAN ÖNCE. Canlı: 50 haber/13 bayat → **38 haber/0 bayat** (en eski 28 gün).
- **Sektör cache'i paylaşılana taşındı** (Redis 30 gün): süreç-içiydi, her
  deploy'da sıfırlanıp /health'i 6-8 sn'ye çıkarıyordu.
- **Yanıltıcı hata mesajı**: yfinance HER hatada "Too Many Requests" diyor →
  OLMAYAN sembolde de kullanıcı "çok fazla istek" görüyordu (uydurma
  ZZZZTEST.IS ile LTL.IS aynı yanıtı veriyordu). Artık `probe()` ayrımı yapıyor:
  404 "Sembol bulunamadı" vs 503 "kaynağa ulaşılamıyor".

### ⏳ AÇIK İŞLER (öncelik sırasıyla)
1. **🔴 CİHAZ DOĞRULAMASI (Kerem)** — bu turun FRONTEND işleri yalnız build+test
   ile doğrulandı, telefonda görülmedi: açılış süresi · sekmeye ilk geçişte veri
   geliyor mu · **ikon eksiği var mı** (tree-shake sonrası) · "Fiyat —/fiyat yok"
   satırları · hero altındaki "N pozisyonun fiyatı alınamadı" notu.
   PWA cache temizle + `?cb=` şart.
2. **✅ YATIRIM FONU DESTEĞİ — KAPANDI (2 Eyl gece turu).** Kaynak,
   sembol biçimi, göç ve testler için en üstteki bölüme bak.
3. **Worker tek dayanak** — Yahoo Cloudflare'i de kısarsa BIST yine düşer
   (devre kesici 15 dk susar; kripto Coinbase/Binance ile ayakta kalır, ABD
   fiyatı Finnhub'la). BIST'in ücretsiz alternatifi HÂLÂ YOK.
   Intraday grafik de tamamen vekile bağlı (kripto yedeği yalnız günlük).
4. **Sinyal ilk tarama ~32 sn** — sekme artık tembel olduğu için yalnız
   Sinyaller'e girince ödeniyor; yine de uzun. Kısmi/cache'li sonuç servis
   edilebilir (ileride).
5. **Eski Neon merge** — Kerem eski projenin bağlantı dizesini verince.
6. **Cold start** — UptimeRobot uyanık tutuyor (0,27 sn ölçüldü). Ping düşerse
   ücretsiz katmanda 50 sn geri gelir.

---

## 🟢 MEVCUT DURUM (2 Eylül 2026 — veri altyapısı + ürün turu)

> ⚠️ **Bu bölüm en günceldir.** Aşağıdaki 4 Temmuz bölümü tarihseldir (pivot anlatısı).

**Kerem'in çerçevesi (2 Eyl):** "Bunu demo olarak düşünme, **profesyonel bir iş**
yapmaya çalışıyoruz." Kodda kalan "demo üst sınırı" tarzı kısıtlar gerçek portföy
ölçeğine (50+ pozisyon) göre açılacak.

### Kök sorun: Yahoo Finance, Render IP'sini rate-limit'liyor (429)
Canlı doğrulandı: `GET /api/v1/market/price/AAPL` → `"Too Many Requests. Rate limited."`
Sebebi kodda: bazı yollar sembol başına ayrı istek atıyordu; 40 pozisyonlu portföyde
tek sayfa açılışı **~125 Yahoo isteği** demekti. Hepsi tek batch'e indirildi:

| Yol | Önce | Sonra |
|---|---|---|
| Bölünme mutabakatı (HER portföy okumasında) | 40 | **1** |
| Benchmark (portföy + endeksler) | 44 | **1** |
| Sinyal taraması / teknik göstergeler | 40 | **1** |
| Benchmark dönemleri (1A/3A/6A/1Y) | 4 | **1** (tek uzun pencere dilimlenir) |

### Tek kaynak bağımlılığı kırıldı (yedek zincirleri)
- **USDTRY** — `fx_service`: Yahoo → **truncgil** → **frankfurter** → sabit.
  ⚠️ Bu CANLI BİR HATAYI düzeltti: Yahoo düşünce sabit **41.0**'e düşüyor ve TTL'siz
  cache'liyordu; gerçek kur ~48,30 iken **her USD pozisyonu ₺ karşılığında ~%15 eksik**
  görünüyordu (toplam değer, sektör ağırlıkları, sağlık skoru dahil).
- **ABD hissesi fiyatı** — Finnhub `/quote` (anahtar Render'da kurulu, IP-bağımsız).
- **Altın/gümüş** — truncgil spot. ⚠️ truncgil SPOT, `GC=F` VADELİ → ölçülen fark
  altın %1,2 · gümüş %1,0. Yaklaşık ama "fiyat=maliyet, K/Z %0"dan iyi.
- **BIST + kripto: yedeği YOK** — ücretsiz güvenilir alternatif bulunamadı
  (Stooq artık JS doğrulaması istiyor, sunucudan kullanılamaz). Yahoo'ya bağlı.
- Yedekler hem batch (`get_stock_prices`) hem tek sembol (`get_stock_data`) yolunda.

### Arka plan yenileme + Redis
- `market_refresh_service`: tek işçi 5 dk'da bir izlenen TÜM sembolleri **sabit 3
  batch** ile tazeler (fiyat + kapanış + OHLCV) — kaç sembol olursa olsun. 30 dk
  kimse kullanmıyorsa atlar. Yahoo'nun gördüğü hız artık trafikten BAĞIMSIZ.
- `render.yaml`'a **`portly-cache` (keyvalue, free, Frankfurt)** + `REDIS_URL` eklendi.
  Blueprint senkronize edildi, servis **Available** (Valkey 8). Cache artık Render'ın
  15 dk uyku/uyanma döngüsünde sıfırlanmıyor.

### Bu turda kapatılan ürün işleri
- **Sektör "Diğer" %45 → küçüldü**: son ek kuralı (`-USD`→Kripto, `=X`→Döviz,
  `=F`→Emtia, `^`→Endeks), ETF→"Fon/ETF", BIST haritası 47→92 (katalogun tamamı,
  test nöbetçi), eksik Finnhub çevirileri.
- **Donut drill-down**: "Diğer" dilimine dokununca içi AYNI donut'ta açılır
  (`AllocationDonut.breakdowns`), merkeze dokununca geri. Vermeyen görünümler
  (Hisseler/Borsa) birebir eski davranışta.
- **Ana ekran hero: Toplam / Bugün / Hafta / Ay** — yeni uç
  `GET /portfolio/{id}/performance` (`portfolio_performance_service`). Kapanış
  serisi zaten cache'te → ek piyasa isteği yok. Veri yoksa "—" (0 basmıyor).
- **Pozisyon satırında günlük değişim** (`change_percent` vardı, basılmıyordu).
- **Açılış hızı**: portföy artık istemcide cache'leniyor
  (`portfolio_cache_v1_<userId>`), açılışta anında görünür. ⚠️ Render ücretsiz
  katman cold-start'ı **50sn+** (Render'ın kendi uyarısı) — bu kod değil plan meselesi.
- **Haber kapsamı 12 → 24 sembol** (istemci + sunucu eşitlendi), havuz 40 → 90.
- **Haber dili**: ABD sembolleri artık HEM İngilizce HEM Türkçe çekiliyor
  (`_expand_bilingual`). Ölçüm: 8 sembol → 90 haber (31 TR + 59 EN), 1,6 sn.
- **Türkçe duygu analizinde CİDDİ hata düzeltildi**: negatif sözlükteki `"kaza"`
  `"kazancı"` İÇİNDE eşleşiyordu → **her bilanço haberi negatif** çıkıyordu.
  Eşleştirme artık kelime-başı sınırlı + uzun-anahtar-önce (aralık tüketmeli);
  `"kazanç"` tek başına pozitiflikten çıkarıldı (nötr bilanço terimi).
  Regresyon korpusu: `backend/tests/test_turkish_sentiment.py`.
- **Dürüst boş-durumlar**: benchmark'ta veri yoksa "+0,00%" değil "—";
  Sinyaller'de portföy doluyken "pozisyon ekle" demek yerine "N sembolün piyasa
  verisi alınamadı" + Tekrar Dene.
- **Banka Altın makası** ₺ + % (backend `spread_pct` vardı, kullanılmıyordu).
- Yan bulgu: Dart `toUpperCase()` locale bilmiyor → "Diğer"→"DIĞER". Türkçe
  duyarlı büyütme eklendi (`AllocationDonut._upperTr`).

**Commit'ler (hepsi `main`'de, push'landı):** `2659cf9` · `8626e8b` · `1737fec` · `b569c20`
**Testler:** backend **486**, frontend **49**. `flutter analyze` temiz, web build OK.

### ⏳ AÇIK İŞLER (öncelik sırasıyla)
1. **Sinyaller Yahoo'ya bağlı** — 6 aylık OHLC gerektiriyor, Finnhub ücretsiz tier
   mum vermiyor. 429 sürerken "Sinyal üretilemedi" gösteriyor (doğru davranış).
   Kalıcı çözüm ancak (a) ceza kalkması, (b) çıkış IP değişimi, (c) ücretli veri.
2. **Çıkış IP** — kök sebep Render free tier'ın PAYLAŞILAN IP'si; aynı IP'den
   yfinance kullanan başkaları da kotayı yakıyor. Seçenekler: Render ücretli
   sabit çıkış IP'si · Yahoo önüne Cloudflare Worker proxy. Kerem'e sunuldu, karar YOK.
3. **Cold start 50sn+** — ücretsiz katman. Portföy cache'i algıyı düzeltti ama
   ilk gerçek veri yine bekliyor. Çözüm: ücretli plan ya da dış pinger.
4. **BIST/kripto yedek kaynağı yok** — araştırma gerek (ücretsiz + Render'dan
   erişilebilir + güvenilir üçlüsü bulunamadı).
5. **Eski Neon merge** (aşağıdaki 2026-09-01 maddesi) hâlâ bekliyor.

---

## 🟢 MEVCUT DURUM (4 Temmuz 2026, 49. tur — 🔄 BÜYÜK PİVOT devam ediyor)

**🔄 PİVOT KARARI (49. tur, 4 Tem, Kerem):** Uygulama **sanal borsa simülatöründen →
gerçek portföy takip + haber + AL/TUT/SAT sinyal asistanına** dönüşüyor; trade (sanal
alım-satım) katmanı sökülüyor. **4 karar:** (1) bitirme demosu GEÇTİ → **TAM pivot**,
sanal borsa kalıntısı kalmayacak; (2) işlem geçmişi **KAYIT DEFTERİ** olarak KALIYOR
(kullanıcı gerçek alış/satışını kaydeder; maliyet + temettü mutabakatı + davranış
analizi bunlara dayanmaya devam eder); (3) yan modüller (akademi · mum quiz · risk
profili · What-If · stres · AI portföy) **KALIYOR** (AI portföy kurucu "öneri" moduna
çevrilecek); (4) sinyal teslimatı **önce ekran** (YAPILDI), uygulama içi bildirim Faz 4.

**✅ PİVOT — YAPILANLAR (49. tur; henüz COMMIT YOK, git kirli):**
- **Sinyal motoru backend:** YENİ `backend/app/services/signal_service.py` — **kural
  tabanlı, LLM YOK** (tarama başına AI kotası yanmasın): teknik göstergeler
  (`technical_analysis_service._compute_indicators`: fiyat-vs-SMA50/200, golden/death
  cross, RSI, MACD, Bollinger %B, Stochastic, hacim onayı) + temel oranlar
  (`fundamental_analysis_service._compute_fundamentals`: F/K, PEG, ROE, marj, büyüme,
  borç/özkaynak, temettü, analist konsensüsü, 52h konum; `data_limited`/kripto-döviz-emtia
  → teknik-only + gerekçede not) → **skor 0-100 (yüksek=alım lehine; teknik %55 + temel
  %45), AL ≥65 / SAT ≤35 / arası TUT** + ağırlığa göre sıralı Türkçe gerekçeler. Sinyal
  cache 15 dk, temel cache 12 sa; kullanıcı taraması = portföy(qty>0)+watchlist paralel
  (6 worker), patlayan sembol `failed[]`'e (tarama çökmez), güçlü sinyal (|skor−50|) üstte.
  YENİ `backend/app/api/v1/signals.py`: `GET /api/v1/signals` (+`?force=true`) +
  `GET /api/v1/signals/{symbol}`; `main.py`'a kayıtlı. YENİ `tests/test_signal_service.py`
  (23 test, ağsız) → **pytest 302 YEŞİL**.
- **Sinyaller sekmesi:** YENİ `lib/screens/signals_screen.dart` — ana nav 3. sekme
  (`main.dart`: TradeScreen→SignalsScreen, "İşlem"→"Sinyaller", insights ikonu). Filtre
  pilleri (TÜMÜ/AL/TUT/SAT + sayaç), kart = sinyal rozeti (AL yeşil / SAT kırmızı / TUT
  sönük — data-ink) + kaynak (Portföy/İzleme) + fiyat + skor + gerekçeler (>2 ise
  dokun-genişlet) + "Teknik X · Temel Y" satırı; `failed` sembolleri + disclaimer
  ("yatırım tavsiyesi değildir") liste altında; pull-refresh `force=true`.
  `api_service`: `getSignals` (60 sn timeout — soğuk tarama uzun) + `getSymbolSignal`.
- **Trade UI sökümü (frontend TAM):** `lib/screens/trade_screen.dart` **SİLİNDİ**.
  Hisse detay "Emir Gir" → **"Portföyüm"** bölümü: Pozisyon Ekle (manual sheet) ·
  held>0 ise **Satış Kaydet** sheet'i (lot + "Tümü" çipi → `recordSell`) · **İzlemeye
  Al/Çıkar** toggle; SL/TP grafik çizgileri (`_slTpLines` + `_loadActiveProtectionOrders`)
  kaldırıldı. **Sanal bakiye UI'dan tamamen çıktı:** portföy hero "Bakiye" düzenleme +
  "Sanal Bakiyeni Ayarla" sheet'i + "Nakit" bölümü · ana sayfa Nakit/Hisseler kırılım
  çipleri (`_BreakdownChip` silindi) · profil "Nakit Bakiye" satırı; artık
  **`totalAssetValue = totalHoldingsValue`**. `portfolio_provider`: `balance`/
  `loadUserBalance`/`executeBuyOrder`/`generateDemoTrades` kaldırıldı, `executeSellOrder`
  → **`recordSell`** (kayıt semantiği); `deduct_cash` HER yerden söküldü (manual sheet +
  toplu import toggle'ları dahil); `auth_provider.setBalance` kaldırıldı. `api_service`:
  `buyStock`/`_placeOrder`/`createLimitOrder`/`fetchPendingOrders`/`cancelLimitOrder`/
  `generateDemoTrades`/`updateBalance` SİLİNDİ; `sellStock` → "Satış kaydedildi".
  **Kimlik metinleri:** onboarding 4 sayfa yeni vizyona yazıldı (3. sayfa = Sinyaller;
  `test/onboarding_screen_test.dart` başlık güncellendi) · portföy başlangıç rehberi
  ("Portföyünü ekle" → import; "Sinyalleri gör" → sekme 2) + boş durum · temettü
  "bakiyene eklenir" → "temettü geliri kaydedilir" · stres "Bakiye" → "Değer".
  **Baseline: flutter analyze TEMİZ (5 eski info) · flutter 31 YEŞİL · pytest 302 YEŞİL.**

**✅ PİVOT — GÖREV #4/#5/#6 TAMAMLANDI (50. tur, 5 Tem — hâlâ COMMIT YOK, git kirli):**
- **Backend trade sökümü (Görev #4) BİTTİ:** `order_service` kayıt modu (SELL nakit
  kredi etmez) · `limit_order_service`+`pending_order` model+`test_limit_orders` SİLİNDİ ·
  `/trading/limit-order`+`/pending-orders`+`/trading/demo`+`/auth/balance` PATCH kalktı ·
  `User.balance` söküldü + migration `a7c3e9f1b5d2` (pending_orders DROP + users.balance
  DROP; downgrade var) · dividend tahsil bakiyesiz (DIVIDEND kaydı kalır) · chat/portfolio/
  health/coach nakit referansları ayıklandı. **50. turda kapatılan kalıntılar:**
  ⚠️ **`alembic/env.py` silinmiş `pending_order`'ı import ediyordu → HER alembic komutu
  ImportError (Render Docker CMD `alembic upgrade head && uvicorn...` → deploy açılışta
  ÇÖKERDİ). Düzeltildi** (+ eksik `note/watchlist/chart_drawing` importları eklendi) ·
  `price_alert_service` mail footer "Sanal Borsa"→"Portföy Takibi ve Yatırım Sinyalleri" ·
  `portfolio.py` temettü docstring güncellendi.
- **Test ayıklama (Görev #5) BİTTİ:** son kalan `test_sector_breakdown_uses_try_and_
  includes_cash` → `test_sector_breakdown_uses_try` (nakit dilimi yok assert'i).
  **Baseline: pytest 276 YEŞİL · flutter 31 YEŞİL · analyze temiz (5 eski info).**
- **Doküman/prompt (Görev #6) BİTTİ:** `GELISTIRME_ONERILERI.md` pivot banner'ı +
  eskiyen maddeler işaretlendi (oto-trade→sinyal DÖNÜŞTÜ, demo-hazırlık TARİHSEL,
  Manual-Deploy/SMTP notları düzeltildi, önerilen sıra 49-tur-sonrası yazıldı).
  `main.py` description zaten pivot diliydi; chat/coach prompt'larında sanal-para dili
  YOK (grep doğrulandı).
- **SÖZLEŞME CANLI doğrulandı (lokal backend):** `manual-position` `deduct_cash`'siz →
  BUY kaydı ✓ · `POST /trading/order` SELL → kayıt (canlı fiyat) ✓ · `GET /api/v1/signals`
  şekli `signals[]/failed[]/disclaimer` ✓ (AAPL TUT 57, teknik 50/temel 66).

**✅ PİVOT CANLI (50. tur, 5 Tem):** commit `64a3fd0` push'landı (Umut onayı) →
Render auto-deploy → **Neon migration KOŞTU** (pending_orders + users.balance düştü) →
**PROD CANLI DOĞRULANDI:** openapi'de `/api/v1/signals(+/{symbol})` VAR, eski trade
uçları (limit-order/pending-orders/demo/balance) YOK · login yanıtında `balance` yok ·
gerçek portföy+watchlist taraması **20 sinyal / 0 failed** (MU AL 73 · ETH-USD SAT 32 ·
THYAO TUT 58) · frontend bundle'da Sinyaller sekmesi canlı.

**⏳ PİVOT — KALAN AÇIK İŞLER (öncelik sırasıyla):**
1. **Faz 4 (pivot sonrası):** sinyal değişince uygulama içi bildirim (price_alert
   altyapısı genişler) · haber↔sinyal ilişkilendirme · hisse detayına sinyal kartı
   (`getSymbolSignal` hazır, UI yok).
2. **Cihaz doğrulaması (Kerem, PWA cache temizleyerek):** Sinyaller sekmesi (soğuk tarama
   süresi + boş/hata durumu + filtreler) · Pozisyon Ekle / Satış Kaydet akışı · İzlemeye
   Al toggle · onboarding yeni sayfalar · bakiyesiz hero/portföy/profil.

> ⚠️ **Pivotla ESKİYEN maddeler (aşağıda ve GELISTIRME_ONERILERI'nde):** 44. tur
> bracket/OCO cihaz-doğrulamaları · 47. tur "AL/SAT mesajı" doğrulaması · "SIRADAKİ #2
> bracket cilası" → **geçersiz** (özellikler kaldırılıyor/kaldırıldı). Haber/FAB/
> onboarding/watchlist/çizim cihaz işleri hâlâ geçerli.

---

**Özet (48. tur):** **Telefon canlı-demo hata düzeltmeleri (Kerem cihazda 3 kusur bildirdi, hepsi backend).** main origin'le **SENKRON** (3 commit `9316a0d`+`ae9fc6c`+`25c085a` push'landı → Render auto-deploy). Hiç frontend dokunulmadı → backend fix'leri canlı endpoint'ten DOĞRUDAN doğrulanabilir. (1) **Korku & Açgözlülük "veri alınamadı"** (`fear_greed_service`): yfinance `^GSPC` NaN son-kapanış → `sp500_5d_pct: NaN` sonuca sızıyor → Starlette `JSONResponse` **`allow_nan=False`** ile render edip `ValueError` → **HTTP 500** → frontend null. Fix: `_vix/_momentum_score` `Close`'a `dropna()`+0-bölme guard, `_sentiment` NaN filtre, `_json_safe` son savunma. **CANLI 200 doğrulandı** (`score 72, sp500 2.11`). (2) **AI Temel Analiz "yüklenemedi"** (`fundamental_analysis_service`): hisse yolu yfinance `.info` (Yahoo **quoteSummary/crumb**) zorunlu — Render datacenter IP'sinde **boş** (curl_cffi'ye rağmen bu endpoint bloklu) → `ValueError`→**404**. (Kripto/macro `t.history()` chart-endpoint kullandığı için çalışıyordu.) Fix: `_fast_price()` `.info` boşsa **`fast_info`** (chart-endpoint, Render'da çalışır)+history fallback → fiyat/52H/mcap al, **`data_limited=True`** ile devam, **404 atma**; oranlar None, prompt'a "canlı oran yok→kendi bilgin+fiyat çıpası, sayı uydurma" notu. **CANLI 200 doğrulandı** (AAPL/THYAO.IS/GARAN.IS, `data_limited`, reco geliyor). (3) **Grafik "verisi alınamadı"** (`market_data_service.get_stock_history`): **interval=1d (Günlük)** ucu 500 (1wk/5m çalışıyor) — yfinance günlük seride bugünün yarım barını **NaN OHLC** döndürüyor → `round(float(nan))` → Starlette 500. Fix: NaN OHLC satırını **ATLA** (null mum çizme) + NaN volume→0. **CANLI doğrulama deploy bekliyor** (push `25c085a`, poll çalışıyor). **+ GLOBAL GÜVENLIK AĞI:** `app/core/json_response.py` **`SafeJSONResponse`** → FastAPI `default_response_class`; her uçta render öncesi NaN/inf→null. Tek bir NaN artık **HİÇBİR ucu çökertemez** (son savunma; veri doğruluğu yine kaynakta). Baseline: backend **pytest 273** YEŞİL (+5 regresyon: fear-greed NaN·temel data_limited+NaN·grafik NaN-satır·global ağ·SafeJSONResponse birim). ⚠️ **Temel analiz "sınırlı" modda** (`.info` bloğu kalıcıysa derin oran yerine fiyat-çıpalı AI yorumu) — gerçek F/K/ROE için alternatif veri kaynağı (Finnhub/FMP) gerekir, büyük iş; demo için degrade-ama-çalışır yeterli.

**48b — Finnhub temel-veri kaynağı (devam, push `9b99d54`):** quoteSummary bloğunu BY-PASS etmek için Finnhub eklendi (`app/services/finnhub_service.py` + `FINNHUB_API_KEY` Render'a eklendi → **CANLI AKTİF**). `.info` boşsa `fundamental_analysis_service._compute_fundamentals` Finnhub `/stock/metric`+`/profile2`+`/quote`+`/recommendation`'tan **TAM oran setini** çeker (degrade DEĞİL) → **ABD hisseleri CANLI DOĞRULANDI** (NVDA F/K 31.46·ROE %111·marj %63·beta 2.24; AAPL F/K 35.65·ROE %146·temettü %0.36; ölçekler doğru: mcap×1e6, borç/öz oran×100, %'ler direkt, temettü direkt). `get_financials` de Finnhub'a düşer; sınırlı (`data_limited`) sonuç artık 15dk cache (12h değil) → kaynak açılınca otomatik tam veriye döner. config+render.yaml+.env.example güncellendi. pytest **279** (+6). **AÇIK GAP'LER (sıradaki):** (1) **BIST degrade** — Finnhub ücretsiz tier SADECE ABD borsaları; THYAO/GARAN/ASELS hâlâ `data_limited` (fiyat+AI yorumu+AL/TUT/SAT VAR, oran "—"). BIST oranları için **yfinance-proxy** (en kapsamlı: US+BIST+bilanço hepsi yfinance'ten) ya da Finnhub ücretli plan gerekir — **Kerem'e soruldu, karar bekliyor** (degrade+UI temizle / proxy / ücretli). (2) **Bilanço (`get_financials`) hâlâ boş** — Finnhub `/stock/financials` PREMIUM; ücretsiz **`/stock/financials-reported`** (SEC `report.ic` array, concept-eşleme) parse'ına çevrilmeli → ABD bilançosu dolar. (3) analist hedef fiyatı (`/stock/price-target`) premium → None ("$—"). (4) degrade modda UI'da ratio tablosu "——" diziliyor → "canlı oran verisi yok" notuyla değiştirmek demo'da daha temiz (frontend, cihaz doğrulaması ister).

**Özet (47. tur):** main origin'le **SENKRON** (git temiz; 47. tur **2 commit** `9d5aed6`+`5a66ba7` push'landı → Render auto-deploy; öncesinde Umut `ecb3499` ile şifre-sıfırlama mailini **Brevo HTTP API**'ye taşıdı). **47. tur: telefon geri bildirimi cilası (Umut)** — (1) **LOGO her yerde** (AppBar başlık + giriş ekranı + onboarding ilk sayfa + web favicon/PWA + Android mipmap + iOS AppIcon; `assets/images/logo.png`); (2) **AL/SAT işlem mesajı Türkçe** (`api_service` "BUY/SELL emri başarılı"→"AL/SAT"); (3) **piyasa satışı bekleyen SAT limit emrini İPTAL eder** (pozisyon kapanınca doldurulamayan LIMIT SELL/SL/TP "hayalet" kalmıyor; +2 test); (4) **CSV export mobilde share_plus** (token'lı çek→geçici dosya→native paylaşım; eski `launchUrl` 401 "Not authenticated" çözüldü); (5) **haber ton≠piyasa-etkisi ayrımı** (liste rozeti "Ton" + detay "AI Piyasa Etkisi" + açıklama satırı); (6) **FAB sürükleme gesture-arena fix** (tek GestureDetector tap+pan, FAB IgnorePointer/opaque). Baseline: backend **pytest 265** + **flutter 31** YEŞİL, analyze temiz. **TÜMÜ CİHAZ/CANLI DOĞRULAMA BEKLİYOR.** ⚠️ **#2 (AL/SAT mesajı) ve #5 (FAB sürükleme) önceki kodda ZATEN doğruydu** — telefon eski PWA cache'i gösterip "bozuk" sandırmıştı → doğrularken **PWA sil + website data temizle + cache-buster (`?cb=`)** ŞART. **APK:** 47. turda YENİDEN DERLENEMEDİ — bu makinede **Android SDK yok** (`flutter build apk` → "No Android SDK found"; Android Studio/sdkmanager/adb yok, `ANDROID_HOME` boş, `local.properties`'te yalnız `flutter.sdk`). #4 export + yeni ikon **APK'da** görünmesi için Android SDK'lı makinede `flutter build apk --release` gerekli (Umut'ta kurulu olabilir; release imzası debug-key, prod backend otomatik). PWA tarafı Render build'iyle gelir (SDK gerektirmez).

---

**Özet (46. tur):** 46. tur 5 commit (son `556ee9b`). **46. tur: HABER elden geçirme + demo denetimi** (telefon geri bildirimi) — haber **kaynak yönlendirme** (BIST→TR baskı / ABD-kripto-döviz-emtia→EN baskı), **batch taşma fix**, **nötr rozet → sönük nokta**, haber **HIZ+HACİM** (arka plan enrich + geniş niteleyici), **FAB hızlı-sürükleme fix**, **onboarding akış testi** (4 test). Baseline: backend **pytest 263** + **flutter 31** YEŞİL, `flutter analyze` temiz. **TÜM 46. tur işleri CİHAZ/CANLI DOĞRULAMASI BEKLİYOR** (haber telefon + canlı; FAB sürükleme telefon). Genel denetim sonucu: **çekirdek matematik/akış SAĞLAM** (para/PnL, stres, AI hata-durumu, işlem). Önceki açık işler hâlâ geçerli: 45. tur (onboarding/FAB/Bugün-Toplam/chat) · 44 bracket/OCO · 43 (What-If/stres/AI portföy/akademi/BIST) · 42(b) varlık-sınıfı AI · watchlist senkron · çizim Faz 2.

> **46. tur — yapılanlar (5 commit `818cb62`…`556ee9b`, push'landı, CİHAZ/CANLI bekliyor):** **Haber elden geçirme + denetim.**
> · **Haber kaynak yönlendirme** (`symbol_display.newsQuery` + `nlp_sentiment_service`): `newsQuery` artık bölge öneki koyar (`tr|`/`en|`); backend `_split_region` → `_REGION_PARAMS`'tan hl/gl/ceid seçer. **BIST→TR basını, ABD/kripto/döviz/emtia→EN orijinal** (Reuters/Bloomberg). Sebep: ABD/kripto TR baskıya gidince makine-çevirisi agregatör (Coinfomania/Investing TR) dönüp VADER okuyamıyor → "Nötr 0.00" seli. EN orijinal → VADER gerçek skor + kalite. (`818cb62`)
> · **Haber HIZ+HACİM** (`556ee9b`): toplu (Portföyüm/İzleme) haber ilk açılışta LLM enrich'i SENKRON bekliyordu (yavaş) + finans niteleyicisi recall'ı kısıyordu (az haber, "13 Mayıs'a iniyor"). → İlk açılış artık **ham sonucu HEMEN döner** (`_collect_raw_for_symbols` ayrıldı; RSS + bölge VADER/TR skoru + det. filtreler), **LLM enrich ARKA PLANDA** (`_refresh_multi_bg` thread) → skor/alaka sonraki açılışta rafine. Niteleyici genişledi (TR+EN ~13 terim), sembol-başı cap 6→**10**, RSS timeout 8→6.
> · **Batch taşma fix** (`818cb62`): enrich'e 100+ başlık + max_tokens=800 → JSON kesiliyor → tüm skorlar VADER 0.00'a düşüyordu. Cap'li batch + max_tokens **1800** + parantez fix (`f"({query}) {qualifier}"` — BIST OR'lı sorguda filtre boşa gidiyordu) + insider gürültü filtresi (`_NOISE_RE`) Google yoluna da.
> · **Nötr rozet** (`news_screen._buildNewsCard`, `550436f`): liste her nötr haberde dolu gri "Nötr 0.00" basıyordu → **sönük nokta + "Nötr" (skor yok)**; renkli rozet+skor yalnız Pozitif/Negatif (data-ink). 27. turda hisse-detayda yapılmıştı, listede unutulmuştu.
> · **FAB hızlı-sürükleme fix** (`main.dart`, `b580b85`): `onPanUpdate` delta'yı build-anı `pos`'a ekliyordu → bir frame'de çok pan olayı bayat `pos` okuyup ara delta'ları düşürüyordu (FAB parmağın gerisinde). Delta artık GÜNCEL `_fabPos`'a (setState senkron) ekleniyor.
> · **Onboarding akış testi** (`test/onboarding_screen_test.dart`, `ce88083`): 4 test — Atla→onDone · İleri sayfa ilerletir (onDone çağırmaz) · son sayfada Başla belirir/İleri kalkar · Başla→onDone. Ayrıca DOĞRULANDI: `logout` `onboarding_seen` flag'ini SİLMEZ → tur ömür-boyu 1 kez. flutter 27→31.
> · **#5 (AI chat'e canlı veri) ZATEN VAR:** `chat_service.build_user_context` portföy+canlı fiyat+PnL+nakit+toplam varlık+son işlemler enjekte ediyor + `grounding=True`. Yeni iş gerekmiyor.

> **45. tur — yapılanlar (`b2890e0`, push'landı, CİHAZ/CANLI bekliyor):** **Demo cilası.**
> · **Onboarding** (`onboarding_screen.dart` YENİ + `main.dart` AuthGate): ilk açılışta 4 kaydırmalı tanıtım kartı, atlanabilir; `onboarding_seen` prefs flag'iyle **ömür boyu 1 kez** (logout TETİKLEMEZ — yalnız token/refresh/user key siliniyor; flag ancak site verisi silme/yeniden kurulum ile sıfırlanır). AuthGate artık **Stateful**, auth'tan ÖNCE flag'e bakar.
> · **AI Koç FAB** (`main.dart`): Scaffold FAB → `LayoutBuilder`+`Stack`+`Positioned`+`GestureDetector(onPanUpdate)` → basılı tut + SÜRÜKLE (ekran içine clamp'li). Varsayılan sağ-alt; konum state'te (`_fabPos`), **her açılışta sıfırlanır** (kalıcı DEĞİL — Kerem kararı). Tek dokunuş chat'i açar (heroTag 'coachFab').
> · **Portföy hero** (`portfolio_screen.dart`): tek toplam-PnL satırı → **Bugün + Toplam** iki satır (`_pnlLine`: etiket+%badge+tutar; `dailyPnl`/`totalPnl`).
> · **AI chat** (`chat_service.py`): max_tokens 800→**1200** + prompt "kısa, markdown YOK, cümleyi yarıda kesme" (yarıda kalma fix). **Kural #1 DEĞİŞTİ:** artık eğitsel/sanal bağlamda **gerekçeli + alternatifli + 'tavsiye değil' uyarılı hisse önerisi VEREBİLİR** (eski "ASLA tavsiye verme" kaldırıldı).
> · **Haber** (`nlp_sentiment_service.py`): `_fetch_google_raw` sorgusu `_FINANCE_QUALIFIER` ("(hisse OR borsa OR stock OR earnings...)") ile sarıldı → ürün/oyun/etkinlik haberleri elenir (iki yol da: tekil + toplu).
> · **Stres mesajı** (`stress_test_screen.dart`): "(en şanssız %5)" parantezi kaldırıldı, ifade netleştirildi ("Kötü bir senaryoda ... ₺X'e kadar düşebilir ... Benzer 100 durumun 95'inde kaybın bundan daha azdır").
> · **Profil** (`profile_screen.dart`): footer "Portly v1.0" → "Portly". (UI'da başka v1.0 YOK; `pubspec.yaml 1.0.0+1` zorunlu build sürümü, dokunulmadı.)
> · **Şifre sıfırlama CANLI TEST EDİLDİ:** `forgot-password` → 200 generic mesaj (API ÇALIŞIYOR) ama **mail GİTMİYOR** → Render'da `SMTP_USER`/`SMTP_PASSWORD` set değil. Kod hazır; **Umut:** Gmail App Password üret + Render env'e `SMTP_USER`/`SMTP_PASSWORD`/`SMTP_HOST=smtp.gmail.com`/`SMTP_PORT=587` ekle.

> **🔧 DEPLOY GERÇEĞİ (17 Haz doğrulandı — eski "Manuel Deploy bloker" notu YANLIŞTI):** Render **frontend Auto-Deploy = "On Commit" AÇIK** (Settings'te görüldü; Events'te `587c542`/`483e2a0` "New commit via Auto-Deploy" ile canlı; push zamanları tutuyor). Yani **`git push` = ~3 dk sonra otomatik canlı**, elle Manual Deploy GEREKMEZ. 24. turdan beri yazılı "bloker" `render.yaml` `d390113` fix'iyle çözülmüş, handoff geç güncellenmiş.

> **⚠️ 49. tur PİVOT sonrası bu blok KISMEN ESKİDİ** — yeni session önce ↑ "PİVOT — AÇIK
> İŞLER"e bak (1: backend trade sökümü → 2: test ayıklama → 3: doküman). Aşağıdaki
> 46/47/48 doğrulama maddelerinden trade'e dokunanlar (AL/SAT mesajı, bekleyen-SAT,
> bracket) geçersiz; git artık KİRLİ (pivot commit'lenmedi).
>
> **YENİ SESSION İLK İŞ (48. tur sonu, tarihsel):** `git status` **temiz**, origin senkron (48. tur **5 commit** `9316a0d`+`ae9fc6c`+`25c085a`+`0449fea`+`9b99d54` push'landı → Render canlı; **hepsi CANLI DOĞRULANDI**: fear-greed `score 72` · grafik `2y/1d data_points=500` · temel analiz Finnhub'la **ABD hisseleri GERÇEK oran** NVDA F/K 31·ROE %111 / AAPL F/K 35·ROE %146). **48. tur kusurları (Korku&Açgözlülük · AI Temel Analiz · Grafik) ÇÖZÜLDÜ + canlı doğrulandı.** **AÇIK (48b, ↑ MEVCUT DURUM):** BIST temel oranı degrade (Finnhub free=US → "—", **Kerem'e soruldu karar bekliyor**: degrade+UI temizle / yfinance-proxy / ücretli) · ABD **bilançosu** boş (Finnhub `-reported`'a çevir) · analist-hedef premium. Kerem PWA cache temizleyip teyit etsin. **İLK İŞ:** (1) **Kerem/cihaz:** önce **PWA cache temizle** (PWA sil + website data + `?cb=`), sonra 47. tur fix'lerini doğrula (↓ "CİHAZ/CANLI doğrula — 47. tur": AL/SAT mesajı · bekleyen-SAT iptali · CSV paylaşımı · haber ton/etki · logo · FAB sürükleme) + 46. tur **haber fix'lerini canlıda** doğrula — Portföyüm/İzleme haberi **hızlandı mı + haber sayısı arttı mı + ABD/kripto İngilizce-kaliteli + BIST Türkçe + nötr azaldı mı** · **FAB hızlı sürüklemede parmağı takip ediyor mu** (↓ SIRADAKİ "CİHAZ/CANLI doğrula — 46. tur") + eski açık 45/44/43/42(b). (2) **Kod session:** Kerem kusur bildirdiyse **ÖNCE onu düzelt**. Kusur yoksa sıradaki iş: **#1 boş/hata-durumu taraması (Kerem'le — o gezer, sen düzelt)** ya da production sertleştirme (↓ SIRADAKİ #3). **#5 AI chat'e canlı veri ZATEN VAR** (build_user_context); **#6 çoğu var** (donut/sektör/temettü/görevler) — yeni özellik demo öncesi şişirme, "görünür kusur yok" önce. **#3 "Bugün piyasa-kapalı ipucu" ÖNERİLMEDİ** (borsa-saati altyapısı, düşük ROI). **NOT:** Render auto-deploy On Commit AÇIK → `git push` = ~3 dk sonra otomatik canlı (↑ "DEPLOY GERÇEĞİ"); yeni deploy backend'i restart eder → bellekteki haber cache temizlenir (ilk açılış taze). `flutter test`'i proje **KÖKÜNDEN** koş (yanlış cwd → "Test directory not found", sessizce koşmaz; **paralel Bash çağrılarında cwd paylaşıldığından her komuta açık `cd <kök>` ver — bu turda yine 1 kez yakalandı**); çıktıyı `|tail`/`|grep`'leme (exit kodu maskelenir → `> log 2>&1; echo $?`); backend venv shebang bozuk → `venv/bin/python -m pytest`.

### 🎯 SIRADAKİ (öncelik sırasıyla)

> **46. TUR (18 Haz) — haber elden geçirme CANLI (5 commit, son `556ee9b`), baseline pytest 263 + flutter 31 + analyze temiz. Detay ↑ MEVCUT DURUM "46. tur". TÜMÜ cihaz/canlı doğrulama bekliyor.**
> **47. TUR (18-19 Haz) — telefon geri bildirimi cilası CANLI (2 commit `9d5aed6`+`5a66ba7`), pytest 265 + flutter 31 + analyze temiz. Detay ↑ MEVCUT DURUM "47. tur". TÜMÜ cihaz/canlı bekliyor (PWA cache temizle).**
> **⏳ CİHAZ/CANLI doğrula (47. tur — önce cache temizle):** (a) **AL/SAT** piyasa emri → snackbar **Türkçe** mi · (b) **Piyasadan tüm pozisyonu sat** → BEKLEYEN LİMİT EMİRLER'de o sembolün **SAT emri kayboluyor mu** (hayalet kalmıyor; kısmi satışta hâlâ geçerli emir kalır) · (c) **İşlem Geçmişi → CSV indir/paylaş** → mobilde **native paylaşım sayfası** açılıyor mu (401 yok), webde dosya iniyor mu · (d) **Haber** liste rozetinde "**Ton**" + detayda "**AI Piyasa Etkisi**" + açıklama net mi · (e) **Logo** AppBar başlıkta + giriş + onboarding ilk sayfada + (yeni APK/PWA) **ana ekran ikonu** · (f) **FAB** cache temizledikten sonra **basılı tut+sürükle taşınıyor mu** (Android, IgnorePointer fix) + tek dokunuş sohbet açıyor mu. **NOT:** #2/#5 önceki kodda zaten doğruydu → cache temizlenmezse "düzelmedi" görünür ama kod doğru.
> **⏳ CİHAZ/CANLI doğrula (46. tur):** **Haber** (Portföyüm + İzleme) → (a) **hızlandı mı** (ilk açılış, arka plan enrich) · (b) **haber sayısı arttı mı** (cap 10 + geniş niteleyici; eskiden "13 Mayıs'a iniyordu") · (c) **ABD/kripto İngilizce-kaliteli kaynak** mı (Reuters/Bloomberg, gerçek +/− skor) · (d) **BIST Türkçe** mi · (e) **nötr azaldı + nötrler sönük nokta** (dolu "Nötr 0.00" yok). **FAB** → hızlı sürüklemede parmağı **takip ediyor mu** (geride kalmıyor). **NOT:** arka plan enrich → ilk açılış ham/hızlı, ikinci açılış skor/alaka rafine (hafif değişebilir, normal SWR).
> **⚠️ Haber açık takip:** Arka-plan enrich ikinci açılışta LLM alaka filtresiyle bazı haberleri eleyebilir → 2. açılış 1.'den biraz AZ haber gösterebilir (whiplash). Kerem hâlâ "az" derse: enrich'in alaka-elemesini multi-path'te gevşet ya da prewarm ekle.
> **⏳ CİHAZ/CANLI doğrula (45. tur):** **Onboarding** → ilk açılışta tur çıkıyor mu, Atla/Başla çalışıyor mu, bir daha çıkmıyor mu (tekrar görmek için site verisini sil) · **FAB** → basılı tut+sürükle taşınıyor mu + tek dokunuş chat açıyor mu + yeniden açılışta sağ-alta dönüyor mu · **Portföy** Bugün/Toplam doğru/işaretli mi · **AI chat** *"hangi hisseyi almalıyım?"* → somut öneri + uyarı geliyor mu + yanıt **TAM mı** (yarıda kalmıyor) · **Haber** ürün/oyun haberi azaldı mı, finansal ağırlık arttı mı · **Stres** mesajı net mi · **Profil** sadece "Portly".

> **44. TUR (18 Haz) — bracket order + OCO CANLI (son `12593e0`), baseline pytest 258 + flutter 27 + analyze temiz; openapi+/health ile canlı doğrulandı. Detay ↑ MEVCUT DURUM "44. tur".**
> **⏳ CİHAZ doğrula (yalnız Kerem — 44. tur):** **Limit + AL** → "Risk Yönetimi" kartı görünüyor mu; SL/TP girip emir ver → *"dolunca SL/TP koruması kurulacak"* mesajı. · Fiyat limite gelince (~30 sn worker) emir dolar → **Bekleyen Limit Emirler**'de STOP_LOSS + TAKE_PROFIT beliriyor mu. · Biri tetiklenince (ör. fiyat TP'ye) → **diğeri otomatik kayboluyor mu** (OCO). · **Market + AL** SL/TP → biri dolunca diğeri iptal (OCO). · Yanlış sınır (SL ≥ limit / TP ≤ limit) → net hata.
> **⏳ CİHAZ doğrula (43. tur, hâlâ açık):** What-If arama-sonrası-öneri + "Bitiş tarihi seç" sade · stres "Rusya-Ukrayna" + yeni "İran-Ortadoğu" tab + **zayıf halka senaryolar arası değişiyor mu** · AI portföy çeşitleniyor mu · BIST "Bugün" %0 değil · Akademi "45 ders, 12 kategori" · Haber 2. açılış anında.
> **(eski açık cihaz — devam):** 42(b) varlık-sınıfı AI analizi (BTC-USD/GC=F/USDTRY=X → sınıfa uygun mu) · watchlist senkron · çizim Faz 2 · Midas ₺↔$ dokunma · stres `savas_2022` kartı.

1. **🔴 CİHAZ doğrulama (telefonda, yalnız Kerem):** Önce **44. tur** bracket/OCO (↑) + **43. tur** + 42(b) AI analiz. Sonra eski açık cihaz işleri: **watchlist senkron** (ekle/sil/sırala→kapat-aç · çoklu cihaz · offline prefs) · **çizim Faz 2** · alarm rozeti · screenshot 415 · temettü · mum pratiği. **Mobil cila + boş/hata-durumu taraması.**
2. **✅ Bracket order — 44. tur BİTTİ (canlı):** limit fill → otomatik SL/TP + **OCO**; market alımına da OCO. Backend canlı doğrulandı; yalnız cihaz doğrulaması açık (↑ "CİHAZ doğrula — 44. tur"). _(opsiyonel cila: bekleyen LIMIT emir satırında "SL x / TP y" rozeti — `PendingOrderResponse` artık taşıyor.)_
3. **🟠 (KOD — sıradaki cihazsız iş) production sertleştirme:** CORS `*`→URL kilidi · AI kullanıcı-başı kota · token blacklist→Redis · **mail env** (47. tur öncesi `ecb3499`: SMTP→**Brevo HTTP API**; kod hazır → **Umut** Render'a `BREVO_API_KEY` + `BREVO_SENDER_EMAIL` eklemeli; ↑ "Render env vars"). _(Endpoint testleri ✅ 44. tur: coach/chat/market ZATEN kapsamlı. Kalan ince suite isteğe bağlı: behavior 4 · stress 3.)_
4. **Büyük epikler (sona):** web push bildirim → TEFAS fonları → oto-trade (sinyal-only başla).

### 📝 NOT-ALMA FRONTEND — ✅ TAMAMLANDI (39. tur); aşağısı tarihsel sözleşme
> **Yapıldı:** `models/note.dart` · `providers/notes_provider.dart` · `api_service` 4 metot (`getNotes`/`createNote`/`updateNote`/`deleteNote`, en-iyi-çaba) · `screens/investor_journal_screen.dart` (Profil>Araçlar girişi) · hisse detay `_buildNotesSection`/`_noteRow` (Elite diliyle, AI Analiz↔Haberler arası) · ortak `widgets/note_editor.dart` (`showNoteEditor`+`formatNoteDate`, iki ekran paylaşır) · `main.dart` ProxyProvider kaydı. flutter analyze temiz, 27 test. **Kalan: cihaz doğrulaması.** (Aşağıdaki özgün sözleşme referans olarak duruyor.)
- **`api_service.dart`** (auth header mevcut kalıpla):
  - `getNotes({String? symbol})` → `GET /api/v1/notes` (+`?symbol=`) → `List<Note>`
  - `createNote(String content, {String? symbol})` → `POST /api/v1/notes` body `{content, symbol?}`
  - `updateNote(int id, String content)` → `PUT /api/v1/notes/{id}` body `{content}`
  - `deleteNote(int id)` → `DELETE /api/v1/notes/{id}`
- **Sözleşme:** `NoteResponse = {id:int, symbol:String?, content:String, created_at, updated_at}`. Doğrulama: boş içerik→422 · yalnız-boşluk→400 · başkasının/olmayan not→404. `symbol` null = genel günlük; dolu = o hisseye not. Liste **en yeni önce** gelir.
- **`models/note.dart`** + **`providers/notes_provider.dart`** (auth-bağımlı proxy; chat/portfolio provider kalıbı): liste cache + CRUD + `notifyListeners`. `main.dart` MultiProvider'a ekle.
- **Giriş noktaları:** (1) **hisse detay** ekranına "Notlarım" bölümü (`getNotes(symbol: X)`), (2) genel **"Yatırımcı Günlüğü"** ekranı (`getNotes()` → tüm notlar) — Portföy/Profil araç merkezine kart. (opsiyonel: behavior ekranıyla bağ.)
- **KALICI KURALLAR geçerli:** data-ink/monokrom UI, `Border.all` yok. **Cihaz:** Render frontend Manual Deploy SONRASI telefonda doğrula (not ekle→kapat-aç kalıcı mı · symbol filtre · düzenle/sil).

---

---

## 🟡 (ÖNCEKİ) 4 Eylül 2026, 6. tur — AI arızası + haber whiplash + beş geri bildirim

### DEVİR NOTU — çalışma ağacı TEMİZ, SEKİZ commit PUSH'LANDI (deploy canlı)
Kerem "handoff'u oku, kalanları söyle, yapalım" dedi ve **tüm maddeler için
yetki verdi**; sonra canlı kullanımdan beş geri bildirim daha geldi (aşağıda
madde 5). Push edilen commit'ler:

| Commit | Ne |
|---|---|
| `75efa91` | 5. turun auth işi: oturum içi 401 → token yenile + isteği tekrarla |
| `6a0f149` | 5. turun haber işi: eşleme (`matched_query`) · kısıtlama kalkanı · sembol kapsamı |
| `b348a49` | AI sheet'lerine ortak "Tekrar Dene" + retry'i öldüren `setState` assert'i |
| `366e7c2` | 🔴 **Gemini modelleri kalkmış (404) — tüm AI ölüydü** + haber whiplash |
| `6c39b84` | dokümanlar (bu bölümün ilk hâli) |
| `51c8fa8` | oturum düşerken "Null check operator used on a null value" |
| `7076271` | AI cevabında ham sembol (GC=F) · TR haber payı · sohbette "yazıyor" |
| `608fe7e` | portföy gecikmesi (bayat fiyat anında servis) · uyku modunda giriş |

**Doğrulandı (yerel):** backend `venv/bin/python -m pytest` → **680 passed**
(639'du) · `flutter test` → **88 passed** (79'du) · `flutter analyze` temiz.

**Doğrulandı (CANLI, Kerem'in access token'ıyla, deploy sonrası):**

| Uç | Ölçüm |
|---|---|
| `/portfolio/1` | 38 pozisyon · **fiyatsız 0** · 0,96 sn (düzeltme öncesi 1,2 / **5,8** / 0,3 sn dalgalanıyordu) |
| `/portfolio/1/health` | **0,49 sn** — 3 Eylül'de 5,1 sn'ydi, sektör cache'i ısındığı için kendiliğinden düzelmiş |
| `/news/for-symbols` | **90 haber** (3 Eyl: 34) · ilk çağrı ~17-19 sn, ikinci **0,57 sn** · ikinci açılışta sayı DÜŞMÜYOR |
| Haber TR/ABD dengesi | düzeltme öncesi TR 18 / ABD 72 → **TR 40 / ABD 50**, temsil edilen sembol 18 → 22 |
| `/signals` | 🔴 **20,7 sn** · 51 sinyal, 0 başarısız — **açık kalan tek performans maddesi** |

### 1) 🔴 EN ÖNEMLİ BULGU — TÜM AI ÖZELLİKLERİ ÖLÜYDÜ (düzeltildi)
Haber ölçümü yapılırken çıktı: kodda **sabitlenmiş iki Gemini modelinin ikisi
de artık yok**.

```
gemini-2.5-flash      → 404 "no longer available to new users"
gemini-2.5-flash-lite → 404 (aynı)
Groq yedeği           → hesabın erişimi yok
```

Yani sohbet · haber enrich · AI Piyasa Etkisi · temel analiz · makro takvim
**hepsi birden** sessizce düşüyordu. Kerem'in bildirdiği "AI analizi şu an
üretilemedi (≈3/10)" muhtemelen çoktan 10/10 olmuştu.

**İkinci tuzak:** model adı düzeltilince istekler **400 INVALID_ARGUMENT**
vermeye başladı — güncel Flash modelleri `thinking_budget=0`'ı reddediyor
(yeni karşılığı `thinking_level`). Yani yalnız model adını değiştirmek
YETMİYORDU; iki kusur üst üsteydi.

| Düzeltme | Ayrıntı |
|---|---|
| Model adı = **takma ad** | `gemini-flash-latest` / `gemini-flash-lite-latest`. Sürüm kalkınca kendiliğinden sonrakine geçer → bu arıza tekrar etmez |
| Alternatif modele düşme genişledi | Yalnız kota (429) değil; **model yok (404)** ve **yoğunluk (503)** de düşürüyor. `stream` (AI Koç) yalnız 429'a bakıyordu → 404'te doğrudan boşluğa düşüyordu |
| Düşünme ayarı reddedilirse | Aynı model **ayarsız bir kez daha** denenir (tek config alanı yüzünden AI komple kaybedilmesin) |
| 404 artık **ERROR** log'u | Kotadan farklı: beklemekle geçmez, kod değişikliği ister |

**Canlı doğrulandı (gerçek anahtarla, yerelden):** lite JSON modu OK · flash düz
metin OK · stream OK · 503'te lite'a düşme log'da göründü.
Test: `backend/tests/test_llm_model_resilience.py` (14 durum).

### 2) Haber "whiplash" — ölçüldü ve düzeltildi
Backlog'un "oran ölçülsün" maddesi. **Gerçek ölçüm** (4 Eyl, 24 sorgu, gerçek
RSS + gerçek LLM):

| | Ham | Enrich sonrası |
|---|---|---|
| Haber sayısı | 90 | **58** (%36 elendi) |
| Haberi TAMAMEN kaybolan sembol | — | **5/16** (AAPL · THYAO · TUPRS · KCHOL · KARCL) |

Kullanıcı ilk açılışta ham listeyi, ikinci açılışta enrich'liyi görüyor → hem
sayı düşüyor hem de portföyündeki hisse için "haber yok" sanıyor.

**Düzeltme** (`_restore_silenced_symbols`): enrich bir sembolün BÜTÜN
haberlerini elediyse o sembolün **en yeni** haberi geri konur; kalabalık
sembollerde eleme aynen uygulanır. Eleme yarıyı geçerse uyarı log'u.
**Ölçüm sonrası: 90 → 63 haber, kaybolan sembol 0.**

### 3) AI sheet'lerinde "Tekrar Dene"
`_AiSheet` hisse detayından çıkarılıp `lib/widgets/ai_sheet.dart` → **`AiSheet`**
oldu; haber "AI Piyasa Etkisi" sheet'i de ona bağlandı (uç hatayı 200 +
`{"error": ...}` ile de bildirdiği için yeni `isFailure` kancası).
**Taşırken test gerçek bir kusur yakaladı:** `setState(() => _future = ...)` ok
gövdesi atamanın değerini (Future) döndürdüğü için framework assert atıyordu →
hisse detayındaki "Tekrar Dene" **debug/profile derlemede hiç çalışmıyormuş**.
Blok gövdeye çevrildi. Test: `test/ai_sheet_retry_test.dart` (5 durum).

### 4) Canlı kullanımdan gelen BEŞ geri bildirim (hepsi düzeltildi)

Kerem uygulamayı Safari'de açıp ekran görüntüleriyle bildirdi:

| # | Şikâyet | Bulgu / düzeltme |
|---|---|---|
| 1 | "cevap gelmiyormuş gibi hissettiriyor" | Sohbette gösterge vardı ama yalnız skeleton çubuklardı. Artık ilk token'a kadar **"Yanıt hazırlanıyor…"**, akış sürerken noktaların yanında **"yazıyor"** |
| 2 | **"bu GC=F her yerde karşıma çıkıyor, bu altın demek, hiçbir yerde çıkmasın"** | AI bağlamına HAM sembol veriliyordu, model birebir tekrarlıyordu. Arayüzdeki `SymbolDisplay` LLM çıktısını düzeltemez → **modele ham sembol artık hiç verilmiyor**. Yeni `backend/app/utils/symbol_display.py` (frontend `compact()` ile aynı sözleşme) + sistem prompt'una SEMBOL YAZIM KURALI |
| 3 | "türk haberleri az gibi geldi" | **Ölçüldü, haklıydı:** 90 haberin 72'si ABD'ye gidiyordu (portföyde 13 BIST/fon + 25 ABD). Havuz tavanı saf tarih sırasıyla doluyor, sık yayın yapan ABD kaynakları BIST'i dışarı itiyordu (bir sembol 10 alırken diğeri 1). Yeni `_fair_share`: tavan semboller arasında SIRAYLA paylaşılır → **TR 18 → 40** |
| 4 | "portföy hâlâ geç yükleniyor" | **Ölçüldü:** ardışık üç çağrı 1,2 / **5,8** / 0,3 sn. Fiyat kaydı cache'e 10 dk TTL ile yazılıyordu → kayıt silinince sonraki istek BLOKLAYAN çekime düşüyordu. Artık kayıt `_KEEP_TTL_SECONDS` (6 saat) duruyor; 10 dakikayı geçmişse bayat-ama-gerçek fiyat anında döner, tazeleme arka planda |
| 5 | "giriş yaparken önce sunucu hatası verdi, tekrar basınca girdim" | Render ücretsiz instance uyuyor, ilk istek ~30-50 sn; login timeout'u 30 sn'ydi → ham `TimeoutException` ekrana basılıyordu. `_postAwake`: timeout 45 sn + zaman aşımında **bir kez otomatik tekrar** (kullanıcının elle yaptığı ikinci basış) + dürüst mesaj |

Ayrıca Kerem'in ilk ekran görüntüsündeki konsol hatası **gerçek bir bug çıktı**:
`/auth/refresh` de 401 dönüp oturum kapandığında ekranda
**"Portföy yüklenemedi: Null check operator used on a null value"** yazıyordu.
`loadMyPortfolio` disk cache'ini `await` ederken `updateUserAuth(null)`
`_userId`'yi null'lıyor, sonraki `_userId!` patlıyordu. Kullanıcı kimliği artık
başta yerel değişkene alınıp her `await` sonrası doğrulanıyor; yan kazanç:
çıkıştan SONRA dönen yanıt state'e YAZILMIYOR (eski kullanıcının portföyü
ekranda kalamaz) ve çıkışta loading bayrakları iniyor (`_perfLoading` asılı
kalırsa tekrar girişte dönem getirisi HİÇ yüklenmiyordu). Test
`test/portfolio_session_race_test.dart` düzeltme öncesi kodda **tam olarak
canlıdaki mesajla** fail ediyor.

### 5) 🔴 SIRADA NE VAR
| # | İş | Kim |
|---|---|---|
| 1 | ✅ **`/signals` 20,7 sn — 7. TURDA KAPANDI** (`95b05c4`); kök sebep ısıtma da tarama da değil, **temel oran cache'inin toplu ölmesiydi** ↑ 7. tur | Claude |
| 2 | **CİHAZDA doğrulama** — `CIHAZ_DOGRULAMA.md` **A0000** (AI geri geldi mi) + **A000** + **A00**. Safari'de sert yenileme **⌥⌘R** (Cmd+Shift+R Safari'de YOK) ya da `?cb=` | Kerem |
| 3 | Eski Neon merge (iki bağlantı dizesi gerek) · Brevo anahtarları (Umut) · CORS `*` | Bloke |
| 4 | Ürün cilası: onboarding "ekran görüntüsüyle aktar" CTA'sı · temettü ekranı · boş-durum taraması · kaydırma gereken ekranlar | Sırada |

**Canlı ölçüm nasıl yapılır (bu turda kurulan yol):** haber/portföy/sinyal
uçları auth'lu → Kerem'den access token iste. Portly açıkken Safari
konsolunda: `Object.entries(localStorage).find(([k]) => k.includes('auth_token'))?.[1]`
Token 60 dakikalık; iş bitince dosyadan sil.


---

## 🟡 (ÖNCEKİ) 4 Eylül 2026, 7. tur — `/signals` 20,7 sn kök sebebi

> Bu bölüm kapandı; güncel görev listesi yukarıdaki 8. turda.

### DEVİR NOTU — çalışma ağacı TEMİZ, İKİ commit PUSH'LANDI (deploy canlı)
Kerem handoff'u okuttu, `/signals` maddesi için yetki verdi ("yap hepsini
düzelt"), canlı ölçüm için Safari konsolundan access token verdi.

| Commit | Ne |
|---|---|
| `95b05c4` | 🔴 **`/signals` 20,7 sn → ~0,4 sn** — temel oran cache'i bayat da olsa anında servis edilir |
| (bu bölüm) | dokümanlar |

**Doğrulandı (yerel):** backend `venv/bin/python -m pytest` → **695 passed**
(680'di, +15) · iki tur üst üste (arka plan thread'li testler flaky değil) ·
frontend dosyası DEĞİŞMEDİ (`flutter test` 88 aynen geçerli).

**Doğrulandı (CANLI, deploy sonrası 11:59):**

| Uç | Önce | Sonra |
|---|---|---|
| `/signals` (sıcak) | 0,70 sn | **0,27-0,54 sn** |
| `/signals?force=true` (TAM tarama) | 0,71 sn | **0,38 · 0,45 · 0,49 sn** |
| Sonuç | 51 sinyal · 0 başarısız · 31 temelli | **birebir aynı** (regresyon yok) |
| `/portfolio/1` | 0,96 sn | 0,28 sn |

### 1) 🔴 `/signals` 20,7 sn — ÖLÇÜLDÜ, kök sebep BEKLENEN YERDE DEĞİLDİ
6. tur "ısıtma mı tarama mı yavaş, önce ölç" demişti. Ölçüm ikisini de eledi.

**Canlı ölçüm (Kerem'in token'ıyla, 11:33-11:40):**

| Ölçüm | Süre |
|---|---|
| `/signals` (cache sıcak) | 0,70 sn · 51 sinyal · 0 başarısız |
| `/signals?force=true` (sinyal cache'i atlanmış TAM tarama) | 0,71 sn |
| Tek ABD hissesi **soğuk** (`KO` / `PEP`) | **2,78 / 5,30 sn** |
| Aynı hisse ısındıktan sonra | 0,15 sn |
| Tek kripto **soğuk** (`SOL-USD` / `DOGE-USD`) | **0,42 / 0,31 sn** |
| Tek BIST hissesi **soğuk** (`BIMAS` / `EREGL` / `TCELL`) | 2,11 / 1,28 / 1,02 sn |
| Yerelde 51 sembol soğuk OHLCV batch'i | 3,14 sn (51/51 geldi) |

**Ayrıştıran ölçüm kripto-hisse karşılaştırmasıydı:** kriptoda temel oran
kavramı yok → soğuk 0,3 sn; hissede aynı OHLCV yolu + **temel oran çekimi** →
2,8-5,3 sn. Yani soğuk maliyet OHLCV'de değil `_get_fundamentals_cached`
içinde (yfinance `.info` Render IP'sinde bloklu → Finnhub → degrade zinciri).

> 31 ABD hissesi × ~3,5 sn + 13 BIST × ~1,5 sn + 7 hisse-dışı × ~0,35 sn
> ≈ **130 sn iş / 6 işçi ≈ 21,7 sn** → ölçülen 20,7 sn'yi birebir açıklar.

**Neden hepsi BİRDEN soğuktu:** bir tarama 44 hissenin oranını aynı 20 saniye
içinde `cache.set(..., 12 saat)` ile yazıyor → **12 saat sonra hepsi aynı 20
saniye içinde düşüyor**. Fatura Sinyaller'e ilk giren kullanıcıya çıkıyordu,
günde iki kez, tam 20 saniye.

**Çürütülen ilk hipotez (kayda değer):** "aynı OHLCV Redis'ten 3 kez okunuyor,
51 sembolde ~150 gidiş-dönüş" — ölçüm bunu çürüttü (sıcak TAM tarama 0,71 sn).
Gerçek payı ~0,3 sn'ymiş. **Ölçmeden kod yazılmadı.**

### 2) Ne değişti (`backend/app/services/signal_service.py`)
| # | Değişiklik |
|---|---|
| 1 | **Kayıt ≠ tazelik penceresi:** kayıt `_FUND_KEEP_HOURS` (7 gün) durur, 12 saat yalnız TAZELİK eşiği. Bayat oran ANINDA döner, tazeleme arka planda (daemon thread; `market_data_service._schedule_batch_refresh` deseni). Kayıt hiç yoksa bloklayan çekim (ilk kurulum) |
| 2 | **Toplu düşüş kırıldı:** tazelik eşiği sembole özgü, deterministik (zlib.crc32), **yalnız AŞAĞI** kaydırılır (12 sa → 9-12 sa). Yukarı sapma YOK: eski sürümün yazdığı kayıtlar Redis'te hâlâ 12 saatlik TTL taşıyor, eşik 12 saati aşsaydı o kayıtlar tazelenmeden ölür ve geçiş turunda yine 20 sn olurdu |
| 3 | `prewarm_fundamentals` artık yalnız EKSİK değil **BAYAT** olanı da ısıtır (kayıt silinmediği için "eksik mi" diye bakan ısıtma hiçbir şeyi yenilemezdi) |
| 4 | **Tarama OHLCV'yi işçi başına tekrar okumaz:** ısıtmadan dönen seri `get_signal(bars=…)` ile taşınır (önce: ön-ısıtma 51 + `_compute_indicators` 51 + `_down_day_ratio` 51 okuma). Batch'ten dönmeyen sembol `bars=None` → eski davranış |
| 5 | **Eşzamanlılık emniyeti:** arka plan tazelemesi aynı anda en fazla `_FUND_REFRESH_MAX_INFLIGHT` (3) sembol — 44 bayat sembol 44 thread açıp Finnhub ücretsiz tier'ını (~60 istek/dk) 429'lardı |
| 6 | **Geçici hata iyi kaydın üstüne YAZMAZ:** elde gerçek oran varken `data_limited` sonucu cache'e yazılmaz (tek bir 429 hisseyi saatlerce "temel oran yok" bırakırdı); kayıt bayat damgasıyla durur, sonraki tur yeniden dener. Kayıtsız durumda negatif cache eskisi gibi yazılır |

Test: `backend/tests/test_signal_fundamental_stale.py` (**15 durum**).

### 3) 🔴 SIRADA NE VAR
| # | İş | Kim |
|---|---|---|
| 1 | **`/signals` düzeltmesinin GERÇEK kanıtı** — asıl 20 sn senaryosu ancak oranlar bayatlayınca (4 Eyl akşamı ~20:00'den sonra / 5 Eyl sabahı) oluşurdu. Kerem Sinyaller'i açıp **beklemediğini** görsün; yavaşsa `/signals` süresini yeniden ölç | Kerem → Claude |
| 2 | **CİHAZDA doğrulama** — `CIHAZ_DOGRULAMA.md` **A0000** (AI geri geldi mi) + **A000** + **A00**. Safari'de sert yenileme **⌥⌘R** (Cmd+Shift+R Safari'de YOK) ya da `?cb=` | Kerem |
| 3 | Eski Neon merge (iki bağlantı dizesi gerek) · Brevo anahtarları (Umut) · CORS `*` | Bloke |
| 4 | Ürün cilası: onboarding "ekran görüntüsüyle aktar" CTA'sı · temettü ekranı · boş-durum taraması · kaydırma gereken ekranlar | Sırada |
| 5 | Haber enrich eleme oranının canlı log'da izlenmesi (6. turdan devreden küçük madde) | Sırada |

**Canlı ölçüm nasıl yapılır (6. turda kurulan yol, 7. turda da işledi):**
haber/portföy/sinyal uçları auth'lu → Kerem'den access token iste. Portly
açıkken Safari konsolunda:
`Object.entries(localStorage).find(([k]) => k.includes('auth_token'))?.[1]`
Token 60 dakikalık; **hiçbir dosyaya yazma**, iş bitince kullanma.
**Soğuk/sıcak ayrıştırma tekniği (7. tur):** `?force=true` cache'i atlar; tek
sembol uçlarında **kripto vs hisse** karşılaştırması temel-oran maliyetini
izole eder (kriptoda temel oran yok).

---
