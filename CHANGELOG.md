# Portly Geliştirme Geçmişi

Tüm büyük özellik ve düzeltmeler aşağıda tarihsel sırayla listelenmiştir.
Başka bir bilgisayarda projeyi devam ettirirken bu dosyayı oku — neyin nerede
olduğunu hızlıca hatırlarsın.

---

## v1 — Üretim Hazırlığı (Kritik Eksikler)

Detaylı teknik rapor: [`KRITIK_EKSIKLER_RAPORU.pdf`](./KRITIK_EKSIKLER_RAPORU.pdf)

- **Logout endpoint** — token blacklist + refresh iptali (`/auth/logout`)
- **JWT Refresh Token (tam akış)** — Access 1h + Refresh 30d, DB SHA-256 hash'li, rotation, server-side iptal
- **Şifre sıfırlama** — Gmail SMTP, 6 haneli kod, user enumeration koruması, `forgot_password_screen.dart`
- **yfinance arka plan görevi** — Stale-while-revalidate + startup prewarm (10sn → 22ms)
- **PostgreSQL + Alembic** — SQLite → PostgreSQL 16, migration yönetimi
- **Redis rate limiter** — slowapi Redis backend, in-memory fallback
  
## v2 — Trading + Görselleştirme

- **Trade sekmesi** (`screens/trade_screen.dart`) — sembol arama, AL/SAT, anlık fiyat, lot adedi
- **Limit emirler** (`limit_order_service.py`, `models/pending_order.py`) — 30 sn'lik otomatik tetikleme worker
- **Stop-Loss / Take-Profit** — `order_kind` kolonu (LIMIT/STOP_LOSS/TAKE_PROFIT), chart üzerinde yatay seviye çizgileri
- **İşlem geçmişi** (`screens/transaction_history_screen.dart`) — CSV indir
- **Profesyonel grafik widget'ı** (`widgets/price_chart.dart`) — CustomPainter ile:
  - Çizgi / Mum / Heikin Ashi modları
  - MA20/MA50/MA200 hareketli ortalama overlay'leri
  - Crosshair tooltip
  - Son fiyat indikatörü (sağda amber etiket)
  - Intraday için yumuşatılmış mum gradient'i
- **Haberlerde "Etkilenen Varlıklar"** (`asset_extractor_service.py`) — 80+ sembol anahtar kelime eşleme
- **Hisseye özel haber sorgusu** (`utils/symbol_display.dart`)
- **Sembol gösterim haritası** — GC=F → "Altın", THYAO.IS → "Türk Hava Yolları"

## v3 — AI Tabanlı Analiz

- **AI Teknik Tahmin** (`technical_analysis_service.py`, `/coach/predict/{symbol}`)
  - SMA20/50/200, RSI, MACD, Bollinger Bands, Stochastic, ATR
  - Destek/direnç (1ay+3ay), hacim trendi, 1g/5g/30g getiri
  - LLM JSON: yön + güven + hedef + stop-loss + trend gücü + sinyaller + riskler
- **AI Temel Analiz** (`fundamental_analysis_service.py`, `/coach/fundamental/{symbol}`)
  - P/E, PD/DD, PEG, ROE, kâr marjı, gelir büyümesi, borç/özkaynak, beta
  - LLM JSON: 3 skor (Değerleme/Büyüme/Sağlık) + AL/TUT/SAT tavsiyesi + güçlü/zayıf yönler
- **AI Portföy Oluşturucu** (`ai_portfolio_service.py`, `/coach/build-portfolio`)
  - Risk profili × vade × tutar → LLM tahsisat + yfinance ile backtest
- **AI Haber Analizi** (`news_analysis_service.py`, `/news/analyze`)
  - Her habere: etkilenen varlıklar (yön + yüzde) + sektörler + 3 vade yorumu

## v4 — UX + Pratik Özellikler

- **Risk Profili Testi** (`screens/risk_profile_test_screen.dart`) — 7 soru → Muhafazakar/Dengeli/Agresif
- **Sanal bakiye düzenleme** — Portföy ekranında kalem ikonu, kısayollu dialog
- **Mum Tahmin Pratiği** (`screens/ta_quiz_screen.dart`)
  - Geçmiş veriden mum grafiği, devamı gizli
  - "Hangi seviye önce tetiklenir? Hedef (yeşil) / Stop (kırmızı) / Hiçbiri (yatay)"
  - Kısa/Orta/Uzun vade seçimi
- **Eğitim Akademisi** (`screens/education_screen.dart`)
  - 19 ders, 4 kategori: Temel Kavramlar, Teknik Analiz, Risk Yönetimi, Piyasa Psikolojisi, Pratik Stratejiler
- **Ya Almış Olsaydım?** (`screens/what_if_screen.dart`) — geçmişte tutar yatırıp bugünkü değer hesabı + CAGR
- **Görevler & Rozetler** (`screens/missions_screen.dart`) — XP sistemi, 5 görev + 5 rozet, gerçek portföy verisinden otomatik kontrol

## v5 — Piyasa Verisi + Bildirimler

- **Fear & Greed Index** (`fear_greed_service.py`) — VIX 40% + S&P momentum 35% + haber sentiment 25% kompozit
- **Makro Takvim** (`macro_calendar_service.py`) — bu haftaki ekonomik olaylar (LLM destekli)
- **Banka Altın Karşılaştırma** (`gold_rates_service.py`, `screens/gold_rates_screen.dart`)
  - Gerçek serbest piyasa: truncgil.com (gram, çeyrek, yarım, tam, cumhuriyet, ata, 14/18 ayar, ons, platin)
  - Banka makasları: 10 banka tipik spread'lerle (bigpara.com linkiyle doğrulama)
- **Fiyat Alarmları** (`models/price_alert.py`, `services/price_alert_service.py`, `screens/alerts_screen.dart`)
  - 45 sn'lik worker, eşik aşılınca otomatik
  - **Gmail SMTP üzerinden HTML mail bildirimi**
- **Benchmark karşılaştırma** (`benchmark_service.py`)
  - Portföy vs BIST100/S&P500/Nasdaq/Altın
  - **Sharpe oranı** (yıllık, 252 işgünü)
- **Filtreli arama** — BIST/ABD/Kripto/ETF chip'leri

## v6 — Sosyal & Yönetim

- **Profil Ekranı** (`screens/profile_screen.dart`) — Tüm araç ve ayarların merkezi hub'ı
- **İzleme Listesi Drag-to-Reorder** — Uzun bas + sürükle
- **Açık/Koyu Tema** (`providers/theme_provider.dart`) — Profil → Ayarlar'da toggle (kısmi; hardcoded renkler için geçişli)
- **Skeleton loader'lar** (`widgets/skeleton.dart`) — shimmer animasyonlu yükleme placeholder
- **E-posta format validation** — login + register
- **"Tekrar Dene" butonları** — boş haber state vb.

---

## Mimari Notlar

- **Backend yapısı:**
  - `app/api/v1/` — REST route'lar
  - `app/services/` — iş mantığı katmanı (yfinance, LLM, SMTP, vb.)
  - `app/models/` — SQLAlchemy ORM
  - `app/schemas/` — Pydantic request/response şemaları
  - `alembic/versions/` — DB migration tarihçesi

- **Background worker'lar** (`app/main.py` lifespan):
  1. `_prewarm()` — startup'ta watchlist sembollerini ısıt
  2. `_limit_order_loop()` — 30 sn'de bir bekleyen limit/SL/TP emirleri tetikle
  3. `_price_alert_loop()` — 45 sn'de bir fiyat alarmlarını kontrol et + mail gönder

- **Frontend Provider hiyerarşisi:**
  - `ThemeProvider` (en üstte, kullanıcıdan bağımsız)
  - `AuthProvider`
  - `PortfolioProvider` (proxy: auth'a bağımlı)
  - `ChatProvider` (proxy: auth'a bağımlı)

- **Önemli dosyalar — bilgi bir başka PC'de açıldığında nereye bakmalı:**
  - Backend ana akış: `backend/app/main.py`
  - Tüm endpoint'ler: `backend/app/api/v1/`
  - Auth & token yönetimi: `backend/app/services/auth_service.py`
  - AI servisler: `backend/app/services/{ai_coach,technical_analysis,fundamental_analysis,ai_portfolio,news_analysis,fear_greed,macro_calendar,ta_quiz,what_if,gold_rates,price_alert}_service.py`
  - Frontend giriş: `lib/main.dart`
  - API client: `lib/services/api_service.dart`
  - State: `lib/providers/`
  - Ekranlar: `lib/screens/`
  - Widget'lar: `lib/widgets/` (özellikle `price_chart.dart`, `fear_greed_gauge.dart`, `benchmark_widget.dart`)

- **Sembol gösterim haritası:** `lib/utils/symbol_display.dart` — yeni hisse adı eklemek için tek yer

## v? — API Audit + Demo-Hazırlık (2 Haz 2026, 25. tur)

- **Android APK** — release manifest INTERNET izni eklendi (Render backend'e bağlanabilsin).
  `flutter build apk --release` → `app-release.apk` (54.8 MB, debug-signed, sideload).
- **AI Temel/Teknik analiz UI** — `FutureBuilder` sonsuz spinner fix (`connectionState.done`)
  + null durumunda "AI yoğun, tekrar dene" hata UI'ı (`stock_detail_screen.dart`).
- **Donut mobile responsive** (`widgets/allocation_donut.dart`) — `w < 480` ise yan
  lider-etiketleri kapatılır (lejant ad+% zaten gösteriyor), gutter 132→18, halka %32.
  Hisseler/Sektör/Borsa donut'larının üçü de etkilenir (tek widget).
- **forgot-password güvenlik fix** (`api/v1/auth.py`) — SMTP fail'de 500 yerine generic 200
  (user enumeration sızıntısı: saldırgan 500'den email'in kayıtlı olduğunu çıkarıyordu).
- **yf_session helper** (`core/yf_session.py`) — yfinance Ticker'lara explicit curl_cffi
  Chrome session. Render IP'lerinde Yahoo `quoteSummary` transient boş yanıt veriyordu;
  fundamental + financials + portfolio sector lookup bundan etkileniyordu.
- **API audit:** 47 endpoint canlı production'da test edildi (45 çalıştı, 2 transient/
  config — kod fix'leri yukarıda).

## v? — Portföy Girişi + AI Düzeltmeleri (27 May 2026)

- **Teknik analiz AI fix** — `technical_analysis_service.predict` `max_tokens=400`→`1000`; yanıt yarıda kesilip JSON bozuluyor, hep fallback dönüyordu.
- **Screenshot import çoklu görsel** — `image_pick_web.pickImagesWeb()` (`multiple`), tek seferde max 10; okunanlar mevcut dolu satırların **altına eklenir** (eskiden üstüne yazıyordu).
- **Nakit düşme opsiyonu** — toplu import + manuel sheet'te "Sanal bakiyemden düş" toggle (varsayılan kapalı). Backend `ManualPositionRequest.deduct_cash`, bakiye yetmezse 400 "Yetersiz bakiye". FX yok (`execute_trade` kalıbı).
- **Portföy giriş noktası tekilleştirildi** — liste altındaki ikinci "Portföyümü Gir" butonu kaldırıldı.
- **Sembol seçimi sağlamlaştırma** — dokununca bekleyen arama debounce'ı iptal (liste parmağın altından değişmesin).

---

## v? — Cihaz Geri Bildirimi Cilası (18 Haz 2026, 43. tur)

> 26–42. tur ayrıntısı: `git log` + SESSION_HANDOFF.md "tur özeti". Aşağısı 43. tur
> (telefon testinden gelen kusurlar; hepsi push'landı, auto-deploy canlı).

- **What-If** — hisse seçtikten sonra yeni aramada öneri çıkmıyordu (liste
  `_selectedSymbol==null` koşuluyla gizliydi; Hesapla da eski sembolle
  çalışabiliyordu) → kutuya yazınca önceki seçim sıfırlanır. "Bitiş tarihi seç
  (bugüne kadar)" → "Bitiş tarihi seç". (`9496ca4`)
- **Stres testi** — "Zayıf halka" ₺ kaybına göreydi → pozisyon büyüklüğü baskın,
  hep NVDA/MSFT çıkıyordu; artık en sert **%-düşene** göre (en kırılgan,
  senaryoya göre değişir, "En çok zarar gören" rozetiyle tutarlı). Senaryo adı
  "2022 Rusya-Ukrayna / Jeopolitik Şok" → **"2022 Rusya-Ukrayna Savaşı"**. Yeni
  **"2024 İran-Ortadoğu Gerilimi"** senaryosu (11–22 Nis 2024 gerçek penceresi;
  saf İran-ABD olayları piyasayı düşürmediği — Haz'25 savaşı ateşkes rallisi —
  için bu pencere seçildi). (`08be969`)
- **Haber (perf)** — toplu haberde (`get_news_for_symbols`) stale-while-revalidate:
  cache bayatsa eski veri anında döner + arkada yenilenir (tekrar açılış anında). (`4a64928`)
- **BIST günlük değişim** — gece/kapalıyken `period="2d"` tek bar döndürüp
  `prev=current` → "Bugün %0" gösteriyordu → `period="5d"`. **Canlı doğrulandı:**
  THYAO +0.23%, ASELS +4.86% (eskiden 0.00). (`07eaa99`)
- **AI portföy önerisi** — dar sabit havuz (~10) + "sadece bunlardan seç" → hep
  aynı mega-cap; sığ. Havuzlar **~45 sembole** genişledi (hepsi yfinance'te
  doğrulandı), her çağrıda karıştırılır, prompt sektör/varlık çeşitliliği ister,
  sıcaklık 0.5→0.8, 4-6→5-7 sembol. (`f6a405a` + `bf88744`)
- **Akademi sayacı** — profil "19 ders, 4 kategori" elle/bayat → **dinamik**
  (`academyLessonCount`/`academyCategoryCount`; gerçek 45 ders, 12 kategori). (`5cd2ecc`)

Baseline: backend **pytest 253** + **flutter 27** + `flutter analyze` temiz.

---

## v? — LIMIT Bracket (otomatik SL/TP) + OCO (18 Haz 2026, 44. tur)

> Handoff'un eski "Madde 2 bracket order"ı kapandı. Gerçekte yapı taşları (SL/TP
> emir tipleri, fill motoru, market alımda SL/TP girişi) zaten vardı; tek boşluk
> **limit-fill halkasıydı**. Hepsi push'landı (`12593e0`), canlı doğrulandı.

- **Bracket order** — limit ALIŞ emri dolunca, emre bağlı **Stop-Loss + Take-Profit**
  SELL emirleri otomatik kurulur (önceden yalnız market alımda + bilgi notu vardı).
  `pending_orders`'a `sl_price`/`tp_price` (parent LIMIT hedefleri) + `parent_order_id`
  (bracket çapası) + migration `f4a9c2b7d1e3` (nullable/additive; backend cold-start
  `alembic upgrade head` ile Neon'a koşar). `create_limit_order` sl/tp/parent_order_id
  alır + sınır validation: SL/TP yalnız LIMIT BUY'a, **SL < limit < TP**.
- **OCO (one-cancels-other)** — koruma emirlerinden biri tetiklenince kardeşi otomatik
  iptal edilir (pozisyon kapandı → ikinci emir geçersiz). `_cancel_bracket_siblings`,
  çapa = `parent_order_id or id`, yalnız aynı kullanıcı; worker döngüsünde top-of-loop
  `status != PENDING` guard. **Market alımdaki SL/TP de** aynı çapaya bağlandı
  (SL çapa, TP `parent_order_id=SL.id`) → iki yol tutarlı.
- **Frontend** — "Risk Yönetimi" kartı **limit alışta da** görünür; limit submit SL/TP'yi
  geçirir (anında değil, dolunca kurulur). (`trade_screen` + `api_service`)
- **Canlı doğrulandı:** `/openapi.json`'da yeni alanlar + `/health` 200 → migration
  cold-start'ta başarıyla koştu. ⏳ Limit-mod UI + canlı fill→bracket→OCO cihaz doğrulaması bekliyor.
- **Endpoint test kapsamı** — news HTTP testlerindeki boşluklar kapatıldı (`/latest` &
  `/for-symbols` `force` bayrağı servise geçiyor mu · `/for-symbols` boş-`q` + NewsResponse
  şekil uyumu). coach/chat/market suite'leri zaten kapsamlıydı (auth/200/404/500/422).

Baseline: backend **pytest 262** (+9: bracket 5 + news 4) + **flutter 27** + `flutter analyze` temiz.

---

## v? — Demo Cilası (18 Haz 2026, 45. tur)

> Telefon geri bildirimi. Push `b2890e0`. ⏳ cihaz doğrulaması bekliyor.

- **İlk-açılış onboarding turu** (`onboarding_screen.dart` + `main.dart` AuthGate Stateful) — 4 kaydırmalı tanıtım kartı, atlanabilir; `onboarding_seen` prefs flag'iyle **ömür boyu 1 kez** (logout TETİKLEMEZ — yalnız token/refresh/user key siler).
- **Sürüklenebilir AI Koç FAB** — Scaffold FAB → `Stack`+`Positioned`+`GestureDetector(onPanUpdate)`; varsayılan sağ-alt, her açılışta sıfırlanır, tek dokunuş sohbeti açar.
- **Portföy hero "Bugün + Toplam"** (`portfolio_screen._pnlLine`) — tek toplam-PnL satırı iki satıra ayrıldı.
- **AI chat yarıda-kalma fix** (`chat_service.py`) — max_tokens 800→1200 + prompt; **kural #1 gevşedi**: eğitsel/sanal bağlamda gerekçeli + alternatifli + "tavsiye değil" uyarılı **hisse önerisi verebilir**.
- **Haber finans filtresi** (`_FINANCE_QUALIFIER`) · **stres mesajı sadeleştirme** · "Portly v1.0"→"Portly".
- **Şifre sıfırlama CANLI test:** API çalışıyor (200) ama mail gitmiyor → SMTP env yok (47. turda Brevo'ya taşındı).

Baseline: backend **pytest 262** + **flutter 27** + `flutter analyze` temiz.

---

## v? — Haber Elden Geçirme + Demo Denetimi (18 Haz 2026, 46. tur)

> Telefon geri bildirimi. 5 commit `818cb62`…`556ee9b`. ⏳ cihaz/canlı doğrulaması bekliyor.

- **Haber kaynak yönlendirme** (`symbol_display.newsQuery` + `nlp_sentiment_service`) — sembole bölge öneki (`tr|`/`en|`); backend `_split_region` → `_REGION_PARAMS` (hl/gl/ceid). **BIST→TR basını, ABD/kripto/döviz/emtia→EN orijinal** (Reuters/Bloomberg → VADER okur; makine-çevirisi agregatör "Nötr 0.00" seli çözüldü).
- **Haber HIZ+HACİM** — toplu yol (`get_news_for_symbols`) ilk açılışta `_collect_raw_for_symbols` (RSS + bölge VADER/TR + det. filtre) **HEMEN** döner; LLM enrich `_refresh_multi_bg` thread'inde **arka planda** → sonraki açılış rafine. Niteleyici TR+EN ~13 terim, sembol-başı cap 6→10, RSS timeout 8→6.
- **Batch taşma fix** — enrich max_tokens 800→1800 + parantez fix (`f"({query}) {qualifier}"`) + insider gürültü filtresi Google yoluna.
- **Nötr rozet → sönük nokta** (`news_screen`) — dolu "Nötr 0.00" yerine sönük nokta + "Nötr" (data-ink).
- **FAB hızlı-sürükleme fix** (`main.dart`) — delta güncel `_fabPos`'a eklenir → hızlı sürüklemede geride kalmaz.
- **Onboarding akış testi** (4 test).

Baseline: backend **pytest 263** + **flutter 31** + `flutter analyze` temiz.

---

## v? — Telefon Geri Bildirimi Cilası (18-19 Haz 2026, 47. tur)

> Umut'un telefon geri bildirimi (logo + 5 kusur). 2 commit `9d5aed6`+`5a66ba7`. Öncesinde Umut `ecb3499` ile şifre-sıfırlama mailini **SMTP → Brevo HTTP API**'ye taşıdı (Render giden SMTP portlarını blokluyor → cloud'da mail hiç gitmiyordu). ⏳ cihaz/canlı doğrulaması bekliyor (PWA cache temizliği şart).

- **Logo her yerde** — masaüstü emblem PIL ile kırpıldı → `assets/images/logo.png`; **AppBar başlık + giriş ekranı + onboarding ilk sayfa**; **web favicon/PWA (maskable dahil) + Android mipmap (5 yoğunluk) + iOS AppIcon (15 boyut, opak)** yeniden üretildi.
- **AL/SAT işlem mesajı Türkçe** (`api_service`) — "BUY/SELL emri başarılı" → "AL/SAT" (gerçek başarı yolları zaten Türkçeydi; telefon eski PWA cache'i gösteriyordu).
- **Piyasa satışı bekleyen SAT limit emrini iptal eder** (`order_service._cancel_unfillable_sell_orders`) — pozisyon satışla küçülünce/kapanınca eldeki lotun karşılamadığı bekleyen SELL/STOP_LOSS/TAKE_PROFIT emirleri CANCELLED (+2 pytest). Piyasadan tümünü satınca "hayalet" limit SAT emri kalmıyor.
- **CSV export mobilde share_plus** — auth'lu endpoint'e `launchUrl` token taşımıyordu (401 "Not authenticated"). `share_plus`+`path_provider`: token'lı çek (`fetchCsvBytes`) → geçici dosya → native paylaşım. Web Blob yolu korundu; conditional-import `share_file.dart` (dart:io web'de yok).
- **Haber ton ≠ piyasa etkisi** — liste rozetine "**Ton**" etiketi + detay sheet "**AI Piyasa Etkisi**" + "ton ile etki farklı olabilir" açıklaması (çelişki algısı kalktı).
- **FAB sürükleme gesture-arena fix** (`main.dart`) — FAB'ın dokunma algılayıcısı pan ile arenada yarışıyordu (Android'de sürükleme kayboluyordu) → tek `GestureDetector` tap+pan, FAB `IgnorePointer`/`HitTestBehavior.opaque` ile sırf görsel.

**Cihaz testi sonrası takip düzeltmeleri (aynı tur, push'landı, canlı doğrulandı):**
- **Web açılış splash logosu** — `index.html` splash'inde "P" harfi yerine emblem (`web/logo.png`).
- **Haber "Ton" etiketi geri alındı** — listede saçma duruyordu; ton↔etki ayrımı zaten detay sheet'te. Benchmark getiri null/veri-yoksa "+0,00%" yerine "hesaplanamadı" (frontend dürüstlüğü).
- **CSV dostu sembol adı** — export'ta GC=F→Altın, EURTRY=X→EUR/TRY, ETH-USD→Ethereum, ASELS.IS→ASELS (`_csv_display_symbol`).
- **NaN / BIST-kapalı kök neden** — BIST kapalıyken yfinance son kapanışı NaN döndürüyor; Pydantic NaN'ı JSON'da `null` yapıyor. `benchmark._fetch_series` (yalnız start kontrol ediyordu → "Portföyün %0") ve `market._fetch_stock_data` (ham iloc[-1] → TÜPRAŞ /price 500) artık NaN kapanışları atıp son geçerli kapanışı kullanıyor. Canlı doğrulandı: Portföyün +8,53%, TÜPRAŞ 226,7₺.

Baseline: backend **pytest 265** (+2) + **flutter 31** + `flutter analyze` temiz. (APK Android SDK olmadığından bu makinede yeniden derlenemedi → Umut derleyecek.)

---

## v7 — 🔄 BÜYÜK PİVOT: Sanal Borsa → Portföy Takip + Sinyal Asistanı (4 Tem 2026, 49. tur)

Kerem kararı (bitirme demosu geçti): trade simülasyonu kaldırılıyor; uygulama artık
**gerçek portföy ekleme + haber takibi + teknik/temel analize dayalı AL/TUT/SAT
sinyalleri** veren bir asistan. Kararlar: **tam pivot** · işlem geçmişi **kayıt defteri**
olarak kalır · yan modüller (akademi/quiz/risk/What-If/stres/AI portföy) kalır ·
sinyal önce ekran, uygulama içi bildirim sonra (Faz 4).

- **Sinyal motoru** (`backend/app/services/signal_service.py` + `api/v1/signals.py` +
  23 test) — kural tabanlı, **LLM yok**: teknik %55 (SMA50/200 + golden/death cross,
  RSI, MACD, Bollinger %B, Stochastic, hacim) + temel %45 (F/K, PEG, ROE, marj, büyüme,
  borç, analist, 52h konum) → skor 0-100, **AL ≥65 / SAT ≤35 / TUT**; Türkçe gerekçeler;
  15 dk sinyal + 12 sa temel cache; portföy+watchlist paralel tarama.
- **Sinyaller sekmesi** (`lib/screens/signals_screen.dart`) — eski İşlem sekmesinin
  yerinde; TÜMÜ/AL/TUT/SAT filtre, gerekçeli kartlar, disclaimer, pull-refresh.
- **Trade UI söküldü** — `trade_screen.dart` silindi; hisse detay "Emir Gir" →
  "Portföyüm" (Pozisyon Ekle / Satış Kaydet / İzlemeye Al); **sanal bakiye** tüm
  ekranlardan + provider/api katmanından çıkarıldı (`totalAssetValue = pozisyon değeri`);
  limit/SL-TP/demo-trade istemci kodu silindi; onboarding + boş-durum + temettü
  metinleri yeni kimliğe yazıldı. Baseline: pytest 302 · flutter 31 · analyze temiz.
- **Kalan işler** (backend trade sökümü · test ayıklama · doküman/prompt temizliği ·
  Faz 4 bildirim) → **SESSION_HANDOFF.md "PİVOT — AÇIK İŞLER"**.
- **50. tur (5 Tem):** backend trade sökümü + test ayıklama + doküman temizliği
  **TAMAMLANDI** — `order_service` kayıt modu, `limit_order_service`/`pending_order`/
  balance söküldü, migration `a7c3e9f1b5d2` (pending_orders + users.balance DROP).
  Kritik fix: `alembic/env.py` silinmiş `pending_order`'ı import ediyordu → her alembic
  komutu (Render deploy `alembic upgrade head` dahil) çökerdi; düzeltildi. Son trade
  testi pivot semantiğine uyarlandı (`test_sector_breakdown_uses_try`, nakit dilimi yok);
  mail footer + docstring "sanal borsa" dili temizlendi; `GELISTIRME_ONERILERI.md`
  pivotla eskiyen maddeler ayıklandı. Sözleşme lokalde canlı doğrulandı (manual-position ·
  SELL kayıt · signals şekli). **pytest 276 · flutter 31 · analyze temiz (5 eski info).**

## Bilinen Eksikler / Sonraki Adımlar

> ⚠️ **Güncel yapılacaklar burada DEĞİL** → **SESSION_HANDOFF.md** (son durum) + **GELISTIRME_ONERILERI.md** (kanonik backlog). Aşağıdaki liste 3 Haz'da donmuştur (tarihsel).

- **Banka altın için gerçek per-bank kurları** — Public API'ler banka kurlarını yayınlamıyor; paid API (collectapi.com vb.) entegrasyonu gerekiyor. Şu an bigpara.com'a doğrulama linki var.
- **Light mode tam geçiş** — Theme provider var ama çoğu widget hardcoded koyu renkleri kullanıyor; AppColors helper'a tam migrasyon yapılmalı.
- **Web push notifications** — Service worker tabanlı bildirim; e-posta alarmları çalışıyor ama in-app push yok.
- **Multiplayer realtime quiz** — WebSocket altyapısı gerekiyor.
- **HTTPS + Nginx + production deploy** — Deploy ortamına özel; lokal geliştirme dışında.

---

## Ortam Değişkenleri (`backend/.env`)

```
DATABASE_URL=postgresql+psycopg://kullanici@localhost:5432/portly
SECRET_KEY=...
GROQ_API_KEY=...
NEWS_API_KEY=...
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=...@gmail.com
SMTP_PASSWORD=gmail_app_password
SMTP_FROM_NAME=Portly
REDIS_URL=redis://localhost:6379/0
PORTLY_ENV=development
```
