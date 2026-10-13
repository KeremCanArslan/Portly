# Ankara Üniversitesi — Bilgisayar Mühendisliği Bölümü
## Yazılım Tasarım Belgesi (SDD)
### Proje Adı: Portly — Yapay Zeka Destekli Sanal Borsa Simülatörü

---

**Dersin Adı:** Araştırma Teknikleri  
**Konu Kodu:** BLM 4061 – BLM 4062 Araştırma Teknikleri I-II  
**Dönem:** Güz 2025  
**Standart:** IEEE 1016-2009  
**Tarih:** 3 Mayıs 2026  

---

## 1. Giriş

### 1.1 Amaç

Bu belge, **Portly** adlı yapay zeka destekli sanal borsa simülatörü uygulamasının yazılım tasarımını açıklamaktadır. Belge, daha önce hazırlanmış Yazılım Gereksinimleri Spesifikasyonu (SRS) belgesinde tanımlanan işlevsel ve işlevsel olmayan gereksinimleri teknik bir tasarıma dönüştürmektedir. IEEE 1016-2009 standardı esas alınarak hazırlanan bu Yazılım Tasarım Belgesi (SDD); sistemin mimari yapısını, bileşenlerini, modüllerini, veri yapılarını, arayüzlerini ve bileşenler arasındaki etkileşimleri ayrıntılı biçimde ortaya koymaktadır.

Portly, kullanıcıların gerçek piyasa verileri üzerinden sanal alım-satım yapabildiği, yapay zeka koçundan kişisel tavsiye alabildiği, davranışsal finans önyargılarını analiz edebildiği ve Monte Carlo simülasyonu ile portföy risk analizi yapabildiği bir mobil eğitim platformudur.

### 1.2 Kapsam

Bu SDD, Portly uygulamasının aşağıdaki bileşenlerini kapsamaktadır:

**Kapsama Dahil Olanlar:**
- Flutter tabanlı mobil istemci uygulama (iOS ve Android)
- FastAPI tabanlı RESTful arka uç sunucu
- SQLite veritabanı katmanı (SQLAlchemy ORM)
- Groq LLM entegrasyonu (yapay zeka koçluk ve sohbet)
- Yahoo Finance API entegrasyonu (gerçek zamanlı piyasa verileri)
- VADER Duygu Analizi entegrasyonu (haber NLP işleme)
- Monte Carlo simülasyon modülü (stres testi)
- Davranışsal finans analiz motoru
- Kullanıcı kimlik doğrulama sistemi (JWT tabanlı)

**Kapsam Dışında Olanlar:**
- Gerçek para işlemleri veya finansal işlem altyapısı
- Mobil push bildirimleri
- Sosyal özellikler (kullanıcılar arası etkileşim)
- Yönetici paneli / CMS

### 1.3 Referanslar

| No | Belge / Kaynak | Açıklama |
|----|---------------|----------|
| [1] | Portly SRS Belgesi | Yazılım Gereksinimleri Spesifikasyonu |
| [2] | IEEE Std 1016-2009 | Yazılım Tasarım Tanımları için IEEE Standardı |
| [3] | FastAPI Documentation (https://fastapi.tiangolo.com) | Backend çerçeve dokümantasyonu |
| [4] | Flutter Documentation (https://docs.flutter.dev) | Mobil çerçeve dokümantasyonu |
| [5] | Shefrin & Statman (1985) | Disposition Effect — Journal of Finance |
| [6] | Kahneman & Tversky (1979) | Prospect Theory — Econometrica |
| [7] | Barber & Odean (2001) | Overconfidence — Journal of Finance |
| [8] | yfinance Library (Yahoo Finance API) | Piyasa veri kaynağı |
| [9] | Groq LLM API — Llama 3.3 70B | Yapay zeka dil modeli |
| [10] | VADER Sentiment (Hutto & Gilbert, 2014) | Duygu analizi kütüphanesi |

### 1.4 Belge Önizleme

Bu SDD aşağıdaki bölümlerden oluşmaktadır:

- **Bölüm 2:** Tasarım hedefleri, kısıtlamalar ve mimari bağlam
- **Bölüm 3:** Üst düzey mimari model, bileşenler ve tasarım gerekçesi
- **Bölüm 4:** Her modülün iç yapısı, sınıf diyagramları ve durum/sıra diyagramları
- **Bölüm 5:** Veri modeli, veri yapıları ve veri akışı
- **Bölüm 6:** Kullanıcı arayüzü ve harici arayüz tanımlamaları
- **Bölüm 7:** SRS gereksinimlerinin tasarım bileşenleriyle eşleştirilmesi
- **Bölüm 8:** Sözlük ve ek bilgiler

---

## 2. Tasarıma Genel Bakış

### 2.1 Tasarım Hedefleri ve Kısıtlamaları

**Tasarım Hedefleri:**

| Hedef | Açıklama |
|-------|----------|
| **Erişilebilirlik** | Uygulama hem iOS hem Android platformlarında sorunsuz çalışmalıdır. |
| **Gerçek Zamanlılık** | Hisse fiyat verileri ve AI sohbet yanıtları düşük gecikmeyle sunulmalıdır. |
| **Eğitici Değer** | Davranışsal finans metrikleri ve risk analizleri akademik kaynaklara dayandırılmıştır. |
| **Ölçeklenebilirlik** | Backend modüler yapıda tasarlanmış; servisler bağımsız geliştirilebilir. |
| **Sürdürülebilirlik** | Katmanlı mimari (Clean Architecture) ile kod bağımlılığı minimize edilmiştir. |
| **Güvenlik** | JWT kimlik doğrulama, bcrypt parola hashleme ve rate limiting uygulanmıştır. |

**Tasarım Kısıtlamaları:**

| Kısıtlama | Detay |
|-----------|-------|
| **Platform** | Flutter 3.x, Dart 3.x — iOS 12+ ve Android 5.0+ hedeflenmektedir. |
| **AI Latency** | Groq LLM API çağrıları ağ gecikmeye bağımlıdır; SSE streaming ile minimize edilmiştir. |
| **Veri Kaynağı** | Yahoo Finance API'nin hız sınırlamaları ve zaman zaman yaşanan kesintileri göz önüne alınmıştır. |
| **Veritabanı** | Geliştirme ortamında SQLite kullanılmaktadır; üretim için PostgreSQL'e geçiş planlanmaktadır. |
| **Durumsuz Backend** | FastAPI arka ucu REST mimarisine uygun olarak durumsuz (stateless) tasarlanmıştır. |
| **Bütçe** | Groq ve Yahoo Finance API'lerinin ücretsiz katmanları esas alınmıştır. |

### 2.2 Mimari Bağlam

Portly, **istemci-sunucu (client-server)** mimarisine dayanan, üç katmanlı bir uygulama sistemidir:

```
┌─────────────────────────────────────────────────────────┐
│              KULLANICI (Mobil Cihaz)                    │
│         Flutter Uygulama — iOS / Android                │
└──────────────────────┬──────────────────────────────────┘
                       │ HTTPS / SSE
                       ▼
┌─────────────────────────────────────────────────────────┐
│              UYGULAMA SUNUCUSU                          │
│         FastAPI (Python) — REST API                     │
│         Servisler: Auth, Market, AI, Behavior, Stress   │
└──────────────────────┬──────────────────────────────────┘
          ┌────────────┼────────────┐
          ▼            ▼            ▼
  ┌──────────┐  ┌──────────┐  ┌──────────────┐
  │ SQLite DB│  │ Groq API │  │Yahoo Finance │
  │(Yerel DB)│  │(Llama LLM│  │ (Piyasa Ver.)│
  └──────────┘  └──────────┘  └──────────────┘
```

**Temel Varsayımlar:**
- Kullanıcının internet bağlantısı mevcuttur.
- Backend sunucu, aynı yerel ağda veya erişilebilir bir adreste çalışmaktadır.
- Groq ve Yahoo Finance API anahtarları `.env` dosyasında saklanmaktadır.
- Tüm finansal işlemler simülasyon amaçlıdır; gerçek para değeri taşımaz.

---

## 3. Mimari Tasarım

### 3.1 Mimari Model

Portly, **Katmanlı İstemci-Sunucu Mimarisi** ile geliştirilmiştir. Flutter istemcisinde **Provider Pattern** (State Management), backend'de ise **Clean Architecture** ilkeleri uygulanmaktadır.

**İstemci Tarafı Katmanları:**

```
┌──────────────────────────────────────────────┐
│  SUNUM KATMANI (Screens + Widgets)           │
│  HomeScreen, ChatScreen, BehaviorScreen...   │
└────────────────────┬─────────────────────────┘
                     │ dinler / bildirir
┌────────────────────▼─────────────────────────┐
│  DURUM YÖNETİMİ KATMANI (Providers)          │
│  AuthProvider, PortfolioProvider, ChatProvider│
└────────────────────┬─────────────────────────┘
                     │ çağırır
┌────────────────────▼─────────────────────────┐
│  SERVİS KATMANI (ApiService)                 │
│  HTTP istekleri, SSE streaming               │
└────────────────────┬─────────────────────────┘
                     │ HTTPS
┌────────────────────▼─────────────────────────┐
│  BACKEND REST API                            │
└──────────────────────────────────────────────┘
```

**Backend Tarafı Katmanları:**

```
┌──────────────────────────────────────────────┐
│  API KATMANI (/api/v1/...)                   │
│  auth.py, market.py, trading.py, chat.py...  │
└────────────────────┬─────────────────────────┘
                     │ çağırır
┌────────────────────▼─────────────────────────┐
│  İŞ MANTIĞI KATMANI (Services)               │
│  auth_service, market_data_service,          │
│  behavioral_finance_service, chat_service... │
└────────────────────┬─────────────────────────┘
                     │ sorgulamalar
┌────────────────────▼─────────────────────────┐
│  VERİ ERİŞİM KATMANI (Models + ORM)          │
│  SQLAlchemy modelleri — SQLite DB             │
└──────────────────────────────────────────────┘
```

### 3.2 Bileşenler ve Etkileşimleri

#### Flutter İstemcisi — Ana Bileşenler

| Bileşen | Sorumluluk | Etkileşimde Olduğu |
|---------|-----------|-------------------|
| `AuthProvider` | Kullanıcı oturumu, JWT token yönetimi, SharedPreferences | `ApiService`, `LoginScreen`, `RegisterScreen` |
| `PortfolioProvider` | Portföy verisi, bakiye, izleme listesi, haber ve koçluk verisi | `ApiService`, `HomeScreen`, `PortfolioScreen`, `NewsScreen` |
| `ChatProvider` | AI sohbet geçmişi, SSE stream yönetimi | `ApiService`, `ChatScreen` |
| `ApiService` | Tüm HTTP/SSE çağrıları için merkezi istemci | Backend `/api/v1/*` endpoint'leri |
| `HomeScreen` | Ana gösterge paneli; piyasa kartları, AI koç, stres testi giriş noktaları | `PortfolioProvider`, `StockDetailScreen`, `ChatScreen` |
| `StockDetailScreen` | Hisse grafiği, alım-satım arayüzü | `PortfolioProvider`, `fl_chart` |
| `ChatScreen` | Gerçek zamanlı AI sohbet (SSE streaming) | `ChatProvider` |
| `BehaviorScreen` | Davranışsal finans profili görüntüleme | `ApiService` |
| `StressTestScreen` | Monte Carlo risk analizi görüntüleme | `ApiService` |

#### FastAPI Backend — Ana Bileşenler

| Bileşen | Sorumluluk | Etkileşimde Olduğu |
|---------|-----------|-------------------|
| `auth_service` | Kullanıcı kaydı, giriş, JWT üretimi, doğrulama | User DB modeli |
| `market_data_service` | Gerçek zamanlı fiyat, tarihsel veri, arama | `yfinance` |
| `order_service` | Alım-satım emri işleme, bakiye/pozisyon kontrolü | Portfolio + Transaction DB |
| `portfolio_service` | Portföy hesaplamaları, sektör dağılımı | Portfolio DB |
| `chat_service` | Bağlam hazırlama, Groq API stream, sohbet kaydı | Groq API, Chat DB |
| `ai_coach_service` | Tek seferlik koçluk tavsiyesi üretimi | Groq API |
| `nlp_sentiment_service` | Haber duygu analizi | `vaderSentiment` |
| `behavioral_finance_service` | Disposition Effect, Loss Aversion, Overconfidence hesaplama | Transaction DB |
| `stress_test_service` | Monte Carlo simülasyonu, VaR hesaplama | `yfinance`, Portfolio DB |

### 3.3 Tasarım Gerekçesi

**Neden Flutter?**
Flutter, tek kod tabanıyla iOS ve Android'e deploy etme imkânı sunar. Dart dili, hem UI thread'inde yüksek performans hem de asenkron işlemler (async/await) için uygun bir yapı sağlar.

**Neden Provider Pattern?**
Provider, Flutter ekibi tarafından önerilen hafif bir state management çözümüdür. BLoC gibi alternatiflere kıyasla kurulum maliyeti düşük, test edilebilirliği yüksektir. Portly'nin küçük-orta ölçeğinde BLoC'un ek karmaşıklığı gereksizdir.

**Neden FastAPI?**
FastAPI, Python'un veri bilimi kütüphaneleriyle (numpy, VADER, yfinance) doğrudan entegrasyon sağlar. Otomatik OpenAPI dokümantasyonu, Pydantic doğrulama ve asenkron endpoint desteği (SSE için kritik) FastAPI'yi bu proje için ideal kılar.

**Neden Groq (Llama 3.3 70B)?**
Groq, OpenAI alternatiflerine kıyasla çok daha düşük gecikme süresi sunar; özellikle SSE token akışında bu fark belirgindir. Llama 3.3 70B, finansal analiz konularında yeterli bilgi derinliğine sahiptir.

**Alternatiflere Bakış:**

| Karar | Tercih | Reddedilen Alternatif | Gerekçe |
|-------|--------|----------------------|---------|
| State Management | Provider | BLoC, Riverpod | Proje ölçeğine orantılı basitlik |
| Backend | FastAPI | Django, Node.js | Python ML kütüphane ekosistemi |
| LLM | Groq/Llama | OpenAI GPT-4 | Maliyet + düşük gecikme |
| DB (dev) | SQLite | PostgreSQL | Hızlı kurulum; prod'da geçiş planlandı |
| Piyasa Verisi | yfinance | Alpha Vantage, Binance API | Ücretsiz, geniş sembol desteği |

---

## 4. Detaylı Tasarım

### 4.1 Modül Tasarımı

---

#### **Modül 1: AuthProvider**
**Dosya:** `lib/providers/auth_provider.dart`  
**Açıklama:** Kullanıcı kimlik doğrulama durumunu yönetir.

**Arayüz Özellikleri:**
- `String? get token` — JWT erişim tokenı
- `User? get currentUser` — Oturum açmış kullanıcı
- `bool get isLoading` — Yükleme durumu
- `bool get isLoggedIn` — Oturum durumu

**Temel İşlemler:**

| Metot | Parametre | Dönüş | Açıklama |
|-------|-----------|-------|----------|
| `login(email, password)` | String, String | `Future<void>` | Kimlik doğrulama |
| `register(email, password, fullName)` | String × 3 | `Future<void>` | Yeni kayıt |
| `logout()` | — | `void` | Oturumu kapat, token sil |
| `fetchMe()` | — | `Future<void>` | Token'dan kullanıcı bilgisi yenile |
| `_persistSession()` | — | `Future<void>` | SharedPreferences'a kaydet |
| `_restoreSession()` | — | `Future<void>` | Uygulama açılışında oturumu geri yükle |

**Dahili Algoritma:**
```
login():
  1. ApiService.login(email, password) → {token, user}
  2. _token = token, _currentUser = user
  3. SharedPreferences'a kaydet (rememberMe ise)
  4. notifyListeners()
```

---

#### **Modül 2: PortfolioProvider**
**Dosya:** `lib/providers/portfolio_provider.dart`  
**Açıklama:** Portföy, bakiye, piyasa verileri ve AI tavsiyelerini yönetir.

**Arayüz Özellikleri:**
- `double get balance` — Nakit bakiye (sanal TRY)
- `List<StockModel> get marketData` — İzleme listesi hisse verileri
- `List<dynamic> get myHoldings` — Kullanıcı pozisyonları
- `double get totalPnl` — Toplam kar/zarar
- `double get totalAssetValue` — Toplam varlık (nakit + hisse)

**Temel İşlemler:**

| Metot | Açıklama |
|-------|----------|
| `loadInitialData(userId, token)` | Portföy + piyasa verilerini çek |
| `executeBuyOrder(userId, symbol, qty, token)` | Hisse alımı gerçekleştir |
| `executeSellOrder(userId, symbol, qty, token)` | Hisse satışı gerçekleştir |
| `addToWatchlist(symbol)` | İzleme listesine sembol ekle |
| `removeFromWatchlist(symbol)` | İzleme listesinden kaldır |
| `refreshMarketData()` | Fiyatları yenile |
| `loadCoachAdvice(userId, token)` | AI tavsiyesi yükle |

---

#### **Modül 3: ChatProvider**
**Dosya:** `lib/providers/chat_provider.dart`  
**Açıklama:** AI sohbet oturumunu ve SSE stream yönetimini gerçekleştirir.

**Temel İşlemler:**

| Metot | Açıklama |
|-------|----------|
| `loadHistory(userId, token)` | Önceki sohbet mesajlarını yükle |
| `sendMessage(userId, token, message)` | Mesaj gönder, SSE stream aç |
| `cancelStream()` | Devam eden stream'i iptal et |
| `clearHistory(userId, token)` | Sohbet geçmişini sil |

**SSE Stream Algoritması:**
```
sendMessage():
  1. _messages.add(UserMessage)
  2. _isStreaming = true
  3. ApiService.streamChatMessage(userId, token, message) → SSEStream
  4. Her 'token' event'i için:
      a. Son mesaj AssistantMessage ise içeriğe ekle
      b. Her 60ms'de bir notifyListeners()
  5. 'done' event'inde: _isStreaming = false, notifyListeners()
```

---

#### **Modül 4: ApiService**
**Dosya:** `lib/services/api_service.dart`  
**Açıklama:** Tüm backend HTTP ve SSE iletişimini merkezi olarak yönetir.

**Platform Bazlı URL Konfigürasyonu:**
```dart
- Android Emulator : http://10.0.2.2:8000/api/v1
- iOS Simulator    : http://192.168.1.19:8000/api/v1
- Web              : http://127.0.0.1:8000/api/v1
```

**Temel Metodlar:**

| Metot | HTTP | Endpoint |
|-------|------|----------|
| `login(email, pass)` | POST | `/auth/login` |
| `register(email, pass, name)` | POST | `/auth/register` |
| `fetchMe(token)` | GET | `/auth/me` |
| `fetchPopularStocks(symbols)` | GET (parallel) | `/market/price/{symbol}` |
| `fetchStockHistory(symbol, period)` | GET | `/market/history/{symbol}` |
| `searchStocks(query)` | GET | `/market/search?q=` |
| `buyStock(userId, symbol, qty, token)` | POST | `/trading/order` |
| `sellStock(userId, symbol, qty, token)` | POST | `/trading/order` |
| `fetchUserPortfolio(userId)` | GET | `/portfolio/{userId}` |
| `fetchSectorBreakdown(userId)` | GET | `/portfolio/{userId}/sectors` |
| `fetchNews(force)` | GET | `/news/latest` |
| `fetchBehaviorProfile(userId, token)` | GET | `/behavior/profile/{userId}` |
| `fetchStressScenarios(token)` | GET | `/stress/scenarios` |
| `runStressTest(userId, scenario, token)` | GET | `/stress/run/{userId}` |
| `streamChatMessage(userId, token, msg)` | GET/SSE | `/chat/send` |
| `loadChatHistory(userId, token)` | GET | `/chat/history/{userId}` |
| `clearChatHistory(userId, token)` | DELETE | `/chat/history/{userId}` |

---

#### **Modül 5: behavioral_finance_service (Backend)**
**Dosya:** `backend/app/services/behavioral_finance_service.py`  
**Açıklama:** Kullanıcının işlem geçmişinden davranışsal finans önyargılarını hesaplar.

**Temel Algoritmalar:**

**Disposition Effect (Shefrin & Statman, 1985):**
```
PGR = Gerçekleşen_Kazanç_Sayısı / (Gerçekleşen + Gerçekleşmemiş Kazançlar)
PLR = Gerçekleşen_Kayıp_Sayısı  / (Gerçekleşen + Gerçekleşmemiş Kayıplar)
Skor = PGR - PLR        → Aralık: [-1.0, +1.0]
Pozitif skor: kazanç hisselerini erken satma eğilimi
```

**Loss Aversion (Kahneman & Tversky, 1979):**
```
Ort_Kazanç_Gün = Ortalama tutuş günü (kazançlı kapatılan işlemler)
Ort_Kayıp_Gün  = Ortalama tutuş günü (zararlı kapatılan işlemler)
Skor = Ort_Kayıp_Gün / (Ort_Kazanç_Gün + Ort_Kayıp_Gün)  → [0.0, 1.0]
Yüksek skor: kayıpları uzun süre tutma eğilimi
```

**Overconfidence (Barber & Odean, 2001):**
```
Günlük_İşlem = Toplam_İşlem_Sayısı / Aktif_Gün_Sayısı
Skor = min(Günlük_İşlem / THRESHOLD, 1.0)         → [0.0, 1.0]
Yüksek skor: aşırı işlem sıklığı
```

---

#### **Modül 6: stress_test_service (Backend)**
**Dosya:** `backend/app/services/stress_test_service.py`  
**Açıklama:** Geometric Brownian Motion ile Monte Carlo simülasyonu gerçekleştirir.

**Algoritma:**
```
1. Portföydeki her hisse için yfinance'ten μ (ortalama getiri) ve σ (oynaklık) hesapla
2. Seçilen senaryoya göre μ ve σ değerlerini ayarla (kriz senaryoları σ artırır)
3. 10.000 simülasyon yolu oluştur:
   S(t+1) = S(t) × exp((μ - σ²/2)Δt + σ√Δt × Z)   [Z ~ N(0,1)]
4. Son dönem portföy değerlerini sırala
5. Hesapla: P5 (kötü senaryo), Mean (orta senaryo), P95 (iyi senaryo)
6. VaR@95 = Başlangıç_Değeri - P5
```

---

### 4.2 Sınıf Diyagramları ve İlişkileri

```
┌─────────────────────────────────┐
│          ChangeNotifier          │
└──────────────┬──────────────────┘
               │ extends (kalıtım)
   ┌───────────┼────────────┐
   ▼           ▼            ▼
AuthProvider  PortfolioProvider  ChatProvider
│              │
│ kullanır     │ kullanır
▼              ▼
         ApiService (singleton)
               │
               │ HTTP/SSE
               ▼
         FastAPI Backend
         ┌────────────────┐
         │   Router Layer  │
         │ auth / market / │
         │ trading / chat  │
         └────────┬────────┘
                  │ çağırır
         ┌────────▼────────┐
         │  Service Layer  │
         │ auth_service    │
         │ market_service  │
         │ chat_service    │
         │ behavior_service│
         │ stress_service  │
         └────────┬────────┘
                  │ ORM sorgular
         ┌────────▼────────┐
         │   Model Layer   │
         │ User, Portfolio │
         │ Transaction,Chat│
         └────────┬────────┘
                  │
              SQLite DB
```

**Temel İlişkiler:**

| İlişki | Tür | Detay |
|--------|-----|-------|
| `AuthProvider → ApiService` | Bağımlılık | login/register/fetchMe çağrıları |
| `PortfolioProvider → ApiService` | Bağımlılık | market/portfolio/trading çağrıları |
| `ChatProvider → ApiService` | Bağımlılık | SSE stream ve geçmiş çağrıları |
| `Screen → Provider` | Tüketim | `context.watch<Provider>()` |
| `User 1 → N Portfolio` | İlişkilendirme | Bir kullanıcının birden fazla pozisyonu |
| `User 1 → N Transaction` | İlişkilendirme | Tüm işlem geçmişi |
| `User 1 → N Chat` | İlişkilendirme | Sohbet mesajları |

---

### 4.3 Durum ve Sıra Diyagramları

#### Kimlik Doğrulama Durum Diyagramı

```
[Başlangıç] → (SharedPreferences kontrol)
      │
      ├─ Token var → [Oturum Yenileniyor] → fetchMe()
      │                   ├─ Başarılı → [Giriş Yapıldı] → HomeScreen
      │                   └─ Başarısız → [Çıkış] → LoginScreen
      │
      └─ Token yok → [Çıkış] → LoginScreen
                         │
                  (kullanıcı giriş yapar)
                         │
                   [Kimlik Doğrulanıyor]
                         ├─ Başarılı → [Giriş Yapıldı] → HomeScreen
                         └─ Başarısız → [Hata Mesajı] → LoginScreen
```

#### Hisse Alımı Sıra Diyagramı

```
Kullanıcı    StockDetailScreen    PortfolioProvider    ApiService    Backend
    │               │                    │                │             │
    │──miktar gir──▶│                    │                │             │
    │──"AL" tuşu───▶│                    │                │             │
    │               │──executeBuyOrder()─▶│                │             │
    │               │                    │──buyStock()────▶│             │
    │               │                    │                │──POST /order▶│
    │               │                    │                │             │──bakiye kontrol
    │               │                    │                │             │──DB kaydet
    │               │                    │                │◀──{success}─│
    │               │                    │◀──{success}────│             │
    │               │                    │──balance güncelle             │
    │               │                    │──holdings güncelle            │
    │               │                    │──notifyListeners()            │
    │               │◀─ UI rebuild ───────│                │             │
    │◀──Snackbar "Başarılı"──────────────│                │             │
```

#### AI Sohbet SSE Akış Diyagramı

```
Kullanıcı    ChatScreen    ChatProvider    ApiService    Backend (SSE)
    │             │               │             │              │
    │─mesaj gir──▶│               │             │              │
    │             │──sendMessage()─▶│             │              │
    │             │               │─streamChat()─▶│              │
    │             │               │             │──GET /chat/send▶│
    │             │               │             │              │──Groq API
    │             │               │             │◀─event:token─│
    │             │               │◀─token akışı─│              │
    │             │◀─UI rebuild────│             │              │
    │◀─kelime kelime görüntüleme──│             │              │
    │             │               │             │◀─event:done──│
    │             │               │──_isStreaming=false          │
    │             │◀─ Final UI────│             │              │
```

---

## 5. Veri Tasarımı

### 5.1 Veri Modeli

**Varlık-İlişki Diyagramı:**

```
┌─────────────────┐     1:N     ┌──────────────────┐
│      USERS      │────────────▶│   PORTFOLIOS     │
├─────────────────┤             ├──────────────────┤
│ id (PK)         │             │ id (PK)          │
│ email (UNIQUE)  │             │ user_id (FK)     │
│ password_hash   │             │ symbol           │
│ full_name       │             │ quantity         │
│ balance (Float) │             │ average_cost     │
│ created_at      │             │ current_price    │
│ updated_at      │             │ updated_at       │
└─────────────────┘             └──────────────────┘
         │ 1:N
         ▼
┌──────────────────┐     ┌──────────────────┐
│   TRANSACTIONS   │     │      CHATS       │
├──────────────────┤     ├──────────────────┤
│ id (PK)          │     │ id (PK)          │
│ user_id (FK)     │     │ user_id (FK)     │
│ symbol           │     │ role             │
│ type (BUY/SELL)  │     │ content (TEXT)   │
│ quantity         │     │ timestamp        │
│ price            │     └──────────────────┘
│ total_value      │
│ executed_at      │
└──────────────────┘
```

**İlişkisel Şema:**
```sql
Users(id, email, password_hash, full_name, balance, created_at, updated_at)
  PK: id

Portfolios(id, user_id, symbol, quantity, average_cost, current_price, updated_at)
  PK: id
  FK: user_id → Users(id)

Transactions(id, user_id, symbol, transaction_type, quantity, price, total_value, executed_at)
  PK: id
  FK: user_id → Users(id)
  ENUM transaction_type: {'BUY', 'SELL'}

Chats(id, user_id, role, content, timestamp)
  PK: id
  FK: user_id → Users(id)
  ENUM role: {'user', 'assistant'}
```

### 5.2 Veri Yapıları

#### StockModel (Flutter)
```dart
class StockModel {
  final String symbol;         // Hisse sembolü: "AAPL", "THYAO.IS"
  final double currentPrice;   // Güncel fiyat
  final double changePercent;  // Günlük değişim (%)
  final String companyName;    // Şirket adı
  final String marketType;     // "BIST", "NASDAQ", "CRYPTO", "ETF"
}
```

#### ChatMessage (Flutter)
```dart
class ChatMessage {
  final String role;        // "user" | "assistant"
  String content;           // Mesaj içeriği (mutable - stream için)
  final DateTime timestamp;
  bool isStreaming;          // Token akışı devam ediyor mu
}
```

#### Portfolio Holding (Backend Pydantic)
```python
class HoldingSchema(BaseModel):
    symbol: str
    quantity: float
    average_cost: float
    current_price: float
    total_value: float
    pnl: float
    pnl_percent: float
```

#### Behavioral Profile (Backend)
```python
class BehaviorProfile(BaseModel):
    has_enough_data: bool
    persona: PersonaSchema          # title, description, color
    disposition_effect: BiasScore   # score [-1,1], ger. kazanç/kayıp
    loss_aversion: BiasScore        # score [0,1], ort. tutuş günü
    overconfidence: BiasScore       # score [0,1], işlem sıklığı
```

#### StressSimulation (Backend)
```python
class StressSimulation(BaseModel):
    initial_value: float
    p5_worst_case: float     # %5 en kötü senaryo (10.000 sim.)
    mean: float              # Ortalama beklenti
    p95_best_case: float     # %95 en iyi senaryo
    var_95: float            # Value at Risk @%95
    academic_reference: str
```

### 5.3 Veri Akışı

**Piyasa Verisi Akışı:**
```
Yahoo Finance (yfinance)
        │
        ▼
market_data_service.get_stock_price(symbol)
        │ {current_price, change_percent, company_name}
        ▼
GET /api/v1/market/price/{symbol}
        │ JSON response
        ▼
ApiService.fetchPopularStocks() — paralel çağrılar
        │ List<StockModel>
        ▼
PortfolioProvider._marketData
        │ notifyListeners()
        ▼
HomeScreen → StockCard widget'ları güncellenir
```

**AI Sohbet Veri Akışı:**
```
ChatScreen (kullanıcı mesajı)
        │
        ▼
ChatProvider.sendMessage()
        │
        ▼
ApiService.streamChatMessage() — GET /chat/send
        │ SSE bağlantısı
        ▼
chat_service (backend)
  1. Chat DB'ye user mesajı kaydet
  2. Kullanıcı portföyü + davranış profili bağlamını hazırla
  3. Groq API'ye prompt gönder (streaming)
  4. Token token → SSE event: token
  5. Bitti → SSE event: done + DB'ye assistant mesajı kaydet
        │
        ▼
ChatProvider: buffer → ChatMessage.content güncelle
        │
        ▼
ChatScreen: AnimatedList yeniden çizilir
```

---

## 6. Arayüz Tasarımı

### 6.1 Kullanıcı Arayüzü (UI)

Portly, **Material Design 3** ile dark tema kullanmaktadır. Ana renk: Teal (#00BCD4). Yazı tipi: Google Fonts (Poppins/Roboto).

**Navigasyon Yapısı:**
```
AuthGate
 ├── Giriş Yapılmadı → LoginScreen → RegisterScreen
 └── Giriş Yapıldı  → MainScreen (BottomNavigationBar)
          ├── [Ana Sayfa]    HomeScreen
          ├── [Haberler]     NewsScreen
          └── [Portföy]      PortfolioScreen
```

**Ana Ekranlar:**

| Ekran | Bileşenler | Navigasyon Hedefi |
|-------|-----------|------------------|
| `HomeScreen` | Varlık kartı, AI koç / Davranış / Stres test kartları, izleme listesi | ChatScreen, BehaviorScreen, StressTestScreen, StockDetailScreen |
| `PortfolioScreen` | Bakiye, pozisyon listesi, sektör görünümü | SectorBreakdownScreen, StockDetailScreen, ChatScreen |
| `NewsScreen` | NLP duygu etiketli haber kartları | Harici URL (url_launcher) |
| `StockDetailScreen` | LineChart (fl_chart), zaman seçici, alım/satım butonu | — |
| `ChatScreen` | Mesaj listesi, SSE stream gösterge, öneri kartları | — |
| `BehaviorScreen` | Persona kartı, 3 bias ExpansionTile | ChatScreen |
| `StressTestScreen` | Senaryo butonları, Gauge Chart (CustomPaint), P5/Mean/P95 | — |
| `SectorBreakdownScreen` | PieChart (fl_chart), legend tablosu, konsantrasyon uyarısı | — |

**Kritik UI Akışları:**

*Alım-Satım Akışı:*
```
StockDetailScreen
  → Grafik + güncel fiyat göster
  → Lot miktarı TextField
  → "AL" / "SAT" butonları
  → ConfirmationDialog (isteğe bağlı)
  → Snackbar (başarı / hata)
  → Portföy güncelleme (Provider)
```

*AI Sohbet Akışı:*
```
ChatScreen
  → Mesaj alanı + gönder butonu
  → Kullanıcı mesajı baloncuk
  → "Yazıyor..." animasyonu (3 nokta)
  → SSE token-by-token yanıt görünümü
  → Otomatik scroll-to-bottom
```

### 6.2 Harici Arayüzler

**Yazılım Arayüzleri:**

| Sistem | Protokol | Endpoint / Kütüphane | Veri Formatı |
|--------|----------|---------------------|-------------|
| FastAPI Backend | HTTP/REST | `http://[host]:8000/api/v1/` | JSON |
| AI Chat (Groq) | HTTP SSE | `/chat/send` | `text/event-stream` |
| Yahoo Finance | Python | `yfinance` kütüphanesi | DataFrame |
| Groq LLM | HTTPS | `groq.Client().chat.completions.create()` | JSON/Stream |
| VADER Sentiment | Python | `SentimentIntensityAnalyzer()` | Dict |
| SharedPreferences | Yerel | `shared_preferences` Flutter package | Key-Value |

**İletişim Arayüzleri:**

| Protokol | Kullanım Yeri | Detay |
|----------|--------------|-------|
| **HTTP/1.1** | Tüm REST API çağrıları | `Content-Type: application/json` |
| **SSE (Server-Sent Events)** | AI sohbet token akışı | `Content-Type: text/event-stream` |
| **JWT Bearer Token** | Kimlik doğrulama | `Authorization: Bearer <token>` |
| **HTTPS** | Üretim ortamı | TLS 1.2+ |

**Donanım Arayüzleri:**
- Kullanıcının ağ bağlantısı (WiFi / Mobil veri) — API çağrıları için zorunlu
- Cihaz depolama — SharedPreferences için minimum alan (< 1KB)

---

## 7. Gereksinim İzlenebilirliği

### 7.1 Gereksinim Eşlemesi

| SRS Gereksinim ID | Gereksinim | Tasarım Bileşeni |
|-------------------|-----------|-----------------|
| FR-01 | Kullanıcı kaydı ve girişi | `AuthProvider`, `auth_service`, `LoginScreen`, `RegisterScreen` |
| FR-02 | Gerçek zamanlı hisse fiyatı gösterimi | `PortfolioProvider`, `market_data_service`, `HomeScreen`, `StockCard` |
| FR-03 | Hisse alım-satım işlemi | `order_service`, `StockDetailScreen`, `PortfolioProvider.executeBuyOrder/SellOrder` |
| FR-04 | Portföy yönetimi | `portfolio_service`, `PortfolioScreen`, `PortfolioProvider` |
| FR-05 | Fiyat grafiği (tarihsel veri) | `market_data_service`, `StockDetailScreen`, `fl_chart` |
| FR-06 | Haber akışı ile duygu analizi | `nlp_sentiment_service`, `NewsScreen`, `news.py router` |
| FR-07 | AI koçluk tavsiyesi | `ai_coach_service`, `HomeScreen AICoachCard`, `ChatScreen` |
| FR-08 | SSE tabanlı AI sohbet | `chat_service`, `ChatProvider`, `ChatScreen`, `ApiService.streamChatMessage` |
| FR-09 | Davranışsal finans profili | `behavioral_finance_service`, `BehaviorScreen` |
| FR-10 | Monte Carlo stres testi | `stress_test_service`, `StressTestScreen` |
| FR-11 | Sektör dağılımı analizi | `portfolio_service.get_sector_breakdown`, `SectorBreakdownScreen` |
| FR-12 | İzleme listesi yönetimi | `PortfolioProvider`, `HomeScreen` (Dismissible, arama dialog) |
| NFR-01 | JWT tabanlı güvenlik | `auth_service`, `python_jose`, SharedPreferences |
| NFR-02 | Rate limiting | `slowapi`, `core/limiter.py` |
| NFR-03 | Cross-platform destek | Flutter framework (iOS + Android) |
| NFR-04 | Düşük gecikme AI yanıtı | SSE streaming, Groq API (düşük latency) |
| NFR-05 | Veri doğrulama | Pydantic schemas (tüm endpoint'lerde) |

### 7.2 Doğrulama Stratejisi

| Gereksinim | Doğrulama Yöntemi |
|-----------|------------------|
| FR-01 (Kimlik Doğrulama) | Unit test: `auth_service.authenticate()` — geçerli/geçersiz kimlik bilgileri |
| FR-03 (Alım-Satım) | Entegrasyon testi: POST `/trading/order` — yetersiz bakiye, başarılı alım |
| FR-08 (SSE Chat) | El ile test: Token-by-token akış gözlemlenir, `event: done` alınır |
| FR-09 (Behavioral) | Birim test: 5+ işlem senaryosu, disposition/loss/overconfidence skorları doğrulanır |
| FR-10 (Stres Testi) | Birim test: 10.000 simülasyon, P5 < Mean < P95 mantık kontrolü |
| NFR-01 (Güvenlik) | Geçersiz token ile korumalı endpoint'lere erişim → 401 dönmeli |
| NFR-02 (Rate Limit) | Hızlı ardışık istekler → 429 Too Many Requests dönmeli |

---

## 8. Destekleyici Bilgiler

### 8.1 Sözlük

| Terim | Tanım |
|-------|-------|
| **SDD** | Software Design Document — Yazılım Tasarım Belgesi |
| **SRS** | Software Requirements Specification — Yazılım Gereksinimleri Spesifikasyonu |
| **JWT** | JSON Web Token — Kimlik doğrulama için imzalı token |
| **SSE** | Server-Sent Events — Sunucudan istemciye tek yönlü event akışı |
| **Provider** | Flutter'da reaktif state yönetim deseni |
| **ORM** | Object-Relational Mapper — Python nesnelerini DB tablolarına eşleyen araç (SQLAlchemy) |
| **LLM** | Large Language Model — Büyük dil modeli (Llama 3.3 70B via Groq) |
| **VADER** | Valence Aware Dictionary and sEntiment Reasoner — kural tabanlı duygu analizi |
| **GBM** | Geometric Brownian Motion — Hisse fiyat simülasyonunda kullanılan stokastik süreç |
| **VaR** | Value at Risk — Belirli bir güven aralığında olası maksimum kayıp |
| **Disposition Effect** | Yatırımcının kazançlı hisseleri erken satıp zararlıları uzun tutma eğilimi |
| **Loss Aversion** | Kayıpların kazançlardan yaklaşık 2× daha güçlü hissedilmesi (Kahneman-Tversky) |
| **Overconfidence** | Yatırımcının bilgi ve becerilerine aşırı güvenmesi nedeniyle fazla işlem yapması |
| **Monte Carlo** | Rassal örnekleme ile olasılıksal simülasyon yöntemi |
| **P5 / P95** | 5. ve 95. yüzdelik dilim — sırasıyla en kötü ve en iyi %5'lik senaryo |
| **PnL** | Profit and Loss — Kar ve Zarar |
| **BIST** | Borsa İstanbul — Türkiye ulusal hisse senedi borsası |
| **yfinance** | Yahoo Finance Python kütüphanesi; gerçek zamanlı ve tarihsel piyasa verisi sağlar |
| **Groq** | Düşük gecikmeli LLM çıkarım API sağlayıcısı |
| **bcrypt** | Kriptografik parola hashleme algoritması |
| **Pydantic** | Python veri doğrulama ve parsing kütüphanesi |

### 8.2 Ekler

#### Ek A: Proje Teknoloji Yığını

| Katman | Teknoloji | Versiyon |
|--------|-----------|---------|
| Mobil İstemci | Flutter (Dart) | 3.x |
| Grafik | fl_chart | 0.71.0 |
| State Yönetimi | Provider | 6.1.5 |
| HTTP İstemci | http (Dart) | 1.6.0 |
| SSE İstemci | flutter_client_sse | 2.0.3 |
| Yerel Depolama | shared_preferences | 2.3.2 |
| Backend Framework | FastAPI (Python) | 0.136.1 |
| ORM | SQLAlchemy | 2.0.49 |
| Veritabanı | SQLite (dev) | — |
| LLM API | Groq (Llama 3.3 70B) | 1.2.0 |
| Piyasa Verisi | yfinance | 1.3.0 |
| Duygu Analizi | vaderSentiment | 3.3.2 |
| Parola Güvenliği | bcrypt | 4.2.1 |
| Token | python_jose | 3.5.0 |
| Rate Limiting | slowapi | 0.1.9 |
| Logging | loguru | 0.7.3 |

#### Ek B: API Endpoint Özeti

```
POST  /api/v1/auth/login
POST  /api/v1/auth/register
GET   /api/v1/auth/me

GET   /api/v1/market/price/{symbol}
GET   /api/v1/market/history/{symbol}?period=
GET   /api/v1/market/search?q=

GET   /api/v1/portfolio/{userId}
GET   /api/v1/portfolio/{userId}/sectors

POST  /api/v1/trading/order
POST  /api/v1/trading/demo/{userId}

GET   /api/v1/news/latest?force=

GET   /api/v1/coach/advice/{userId}

GET   /api/v1/behavior/profile/{userId}

GET   /api/v1/stress/scenarios
GET   /api/v1/stress/run/{userId}?scenario=

GET   /api/v1/chat/send?user_id=&message=  (SSE)
GET   /api/v1/chat/history/{userId}
DELETE /api/v1/chat/history/{userId}
```

#### Ek C: Sürüm Kontrolü

| Sürüm | Tarih | Değişiklik |
|-------|-------|-----------|
| 1.0 | 3 Mayıs 2026 | İlk SDD sürümü oluşturuldu |

---

*Bu belge IEEE 1016-2009 standardına uygun olarak Portly projesinin Yazılım Tasarım Dokümanı olarak hazırlanmıştır.*
