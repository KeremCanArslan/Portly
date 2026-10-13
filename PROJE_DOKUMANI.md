# PORTLY — Yapay Zeka Destekli Sanal Borsa Simülatörü
## Proje Dokümanı

**Hazırlayan:** Kerem Can Arslan & Umut Altan  

---

## 1. PROJENİN TANIMI VE AMACI

Portly, kullanıcıların gerçek para riske atmadan hisse senedi alım satımını öğrenmesini ve pratik yapmasını sağlayan **yapay zeka destekli bir sanal borsa simülatörüdür**.

Projenin temel hedefleri:
- Kullanıcılara gerçek piyasa verileriyle sanal ticaret deneyimi sunmak
- Yapay zeka tabanlı bir "yatırım koçu" ile kişiselleştirilmiş tavsiyeler vermek
- Davranışsal finans psikolojisini (Disposition Effect, Aşırı Güven, Kayıp Korkusu) ölçerek kullanıcıyı bilinçlendirmek
- Monte Carlo simülasyonlarıyla portföy risk analizini görselleştirmek

---

## 2. TEKNOLOJİK ALTYAPI (TECH STACK)

### 2.1 Mobil Uygulama (Frontend)
| Teknoloji | Kullanım Amacı |
|-----------|---------------|
| **Flutter / Dart** | Çapraz platform mobil uygulama (iOS + Android) |
| **Provider** | Uygulama geneli durum yönetimi (State Management) |
| **fl_chart** | Hisse senedi grafikleri ve portföy grafikleri |
| **Google Fonts** | Tipografi |
| **flutter_client_sse** | Yapay zeka cevaplarının anlık (streaming) gösterimi |
| **shared_preferences** | Kullanıcı oturumunun cihazda saklanması |
| **http** | Backend API ile iletişim |

### 2.2 Sunucu Tarafı (Backend)
| Teknoloji | Kullanım Amacı |
|-----------|---------------|
| **FastAPI (Python)** | REST API sunucusu |
| **SQLite / SQLAlchemy** | Veri tabanı ve ORM |
| **Groq API (Llama 3.3 70B)** | Büyük dil modeli — yapay zeka koç |
| **yfinance** | Yahoo Finance'den gerçek zamanlı hisse fiyatları |
| **VADER Sentiment** | Haber başlıklarının duygu analizi (NLP) |
| **bcrypt** | Şifre hashleme |
| **python-jose** | JWT token üretimi ve doğrulama |
| **slowapi** | API rate limiting (saniyede istek limiti) |
| **sse_starlette** | Server-Sent Events — anlık AI yanıtı akışı |

---

## 3. MİMARİ YAPI

Portly **3 katmanlı (3-tier) istemci-sunucu mimarisi** üzerine inşa edilmiştir:

```
┌─────────────────────────────────────────┐
│       FLUTTER MOBİL UYGULAMA           │  ← Kullanıcı Arayüzü
│  (Screens → Providers → API Service)   │
└────────────────┬────────────────────────┘
                 │ HTTP / SSE
                 ▼
┌─────────────────────────────────────────┐
│         FastAPI REST API               │  ← İş Mantığı
│  (Auth / Market / Trading / AI / Risk) │
└────────────────┬────────────────────────┘
                 │ SQLAlchemy ORM
                 ▼
┌─────────────────────────────────────────┐
│         SQLite Veritabanı              │  ← Veri Katmanı
│  (users, portfolios, transactions,     │
│   chat_messages tabloları)             │
└─────────────────────────────────────────┘
```

---

## 4. VERİTABANI ŞEMASI

Proje 4 ana tablo içermektedir:

### `users` — Kullanıcılar
| Alan | Tür | Açıklama |
|------|-----|---------|
| id | INT (PK) | Birincil anahtar |
| email | VARCHAR | Benzersiz e-posta |
| hashed_password | VARCHAR | bcrypt ile hashlenmiş şifre |
| full_name | VARCHAR | Ad soyad |
| balance | FLOAT | Sanal bakiye (başlangıç: 100.000 TL) |

### `portfolios` — Portföy/Hisseler
| Alan | Tür | Açıklama |
|------|-----|---------|
| id | INT (PK) | Birincil anahtar |
| user_id | INT (FK) | Kullanıcı referansı |
| symbol | VARCHAR | Hisse kodu (ör. THYAO.IS, AAPL) |
| quantity | FLOAT | Adet |
| average_cost | FLOAT | Ortalama maliyet |

### `transactions` — İşlem Geçmişi
| Alan | Tür | Açıklama |
|------|-----|---------|
| id | INT (PK) | Birincil anahtar |
| user_id | INT (FK) | Kullanıcı referansı |
| symbol | VARCHAR | Hisse kodu |
| transaction_type | ENUM | BUY veya SELL |
| quantity | FLOAT | Adet |
| price | FLOAT | İşlem fiyatı |
| timestamp | DATETIME | İşlem zamanı |

### `chat_messages` — Yapay Zeka Sohbet Geçmişi
| Alan | Tür | Açıklama |
|------|-----|---------|
| id | INT (PK) | Birincil anahtar |
| user_id | INT (FK) | Kullanıcı referansı |
| role | VARCHAR | "user" veya "assistant" |
| content | TEXT | Mesaj içeriği |
| timestamp | DATETIME | Zaman damgası |

---

## 5. TAMAMLANAN ÖZELLİKLER

### 5.1 Kullanıcı Yönetimi ve Güvenlik
- ✅ Kayıt (e-posta + şifre) ve giriş sistemi
- ✅ JWT tabanlı kimlik doğrulama (7 günlük token)
- ✅ bcrypt ile güvenli şifre hashleme
- ✅ Cihazda oturum saklama (SharedPreferences)
- ✅ API uç noktalarında rate limiting (giriş: 10/dk, kayıt: 5/dk)
- ✅ CORS yapılandırması

### 5.2 Piyasa Verileri
- ✅ Yahoo Finance'den gerçek zamanlı hisse fiyatları (1 dakika önbellekleme)
- ✅ Hisse fiyat geçmişi (1 gün, 5 gün, 1 ay, 3 ay, 6 ay, 1 yıl, 2 yıl, 5 yıl)
- ✅ Hisse arama (BIST, NYSE, NASDAQ, Kripto)
- ✅ Fiyat değişim yüzdesi hesaplama
- ✅ Varsayılan izleme listesi: Altın, USD/TRY, EUR/TRY, BTC, THYAO, ASELS, AAPL, NVDA

### 5.3 Sanal Ticaret
- ✅ Simüle hisse alım/satım (BUY/SELL emirleri)
- ✅ Bakiye takibi ve güncelleme
- ✅ Portföy kar/zarar hesaplama (gerçekleşmiş + gerçekleşmemiş)
- ✅ Yeni kullanıcılar için otomatik demo işlemler oluşturma
- ✅ Sektöre göre portföy dağılımı görselleştirmesi
- ✅ Başlangıç bakiyesi: 100.000 TL

### 5.4 Yapay Zeka Yatırım Koçu
- ✅ Groq API üzerinden Llama 3.3 70B dil modeli entegrasyonu
- ✅ Server-Sent Events (SSE) ile gerçek zamanlı yanıt akışı (streaming)
- ✅ RAG (Retrieval-Augmented Generation) ile kişiselleştirilmiş bağlam:
  - Kullanıcının mevcut portföyü ve kar/zarar durumu
  - Son işlem geçmişi
  - Davranışsal finans profili
  - Güncel haber duygu analizi
- ✅ Sohbet geçmişi veritabanında saklanma (son 50 mesaj)
- ✅ Portföye özel otomatik tavsiye üretimi

### 5.5 Davranışsal Finans Analizi
Akademik finansal psikoloji metriklerinin hesaplanması:

- ✅ **Disposition Effect** — PGR (Kazanç Gerçekleştirme Oranı) - PLR (Kayıp Gerçekleştirme Oranı): Kazançlı hisseleri erken satıp zararlı hisseleri tutma eğilimi  
  *Kaynak: Shefrin & Statman (1985)*

- ✅ **Aşırı Güven Önyargısı (Overconfidence)** — Günlük işlem sıklığı oranı: Aşırı işlem yapma eğilimi  
  *Kaynak: Barber & Odean (2001)*

- ✅ **Kayıptan Kaçınma (Loss Aversion)** — Kazanç vs kayıp tepkilerindeki asimetri  
  *Kaynak: Kahneman & Tversky (1979)*

- ✅ Kullanıcı kişilik tipi sınıflandırması: Muhafazakâr / Orta / Agresif

### 5.6 Risk Analizi (Monte Carlo Simülasyonu)
- ✅ Geometrik Brownian Motion (GBM) modeli ile 10.000 simülasyon yolu
- ✅ 5 senaryo:
  1. **2008 Mortgage Krizi** — 6 ayda -%38 düşüş
  2. **2020 COVID Çöküşü** — 30 günde -%34 düşüş
  3. **2018 BIST/TL Krizi** — BIST'te -%20
  4. **Kara Kuğu Olayı** — Öngörülemeyen aşırı olay
  5. **Normal Piyasa Koşulları**
- ✅ 20., 50., 80. yüzdelik dilimlerle fan grafik görselleştirmesi
- ✅ VaR (Value at Risk — Risk Değeri) hesaplama

### 5.7 Haber ve Duygu Analizi
- ✅ Finansal haber toplama (newsapi.org)
- ✅ VADER ile haber başlıklarında NLP duygu analizi (pozitif/negatif/nötr)
- ✅ 5 dakikalık önbellekleme mekanizması

---

## 6. API UÇ NOKTALARI ÖZETİ

| Grup | Uç Nokta | Açıklama |
|------|---------|---------|
| **Auth** | `POST /api/v1/auth/register` | Kayıt ol |
| | `POST /api/v1/auth/login` | Giriş yap, JWT al |
| | `GET /api/v1/auth/me` | Mevcut kullanıcı bilgisi |
| **Piyasa** | `GET /api/v1/market/price/{symbol}` | Anlık fiyat |
| | `GET /api/v1/market/history/{symbol}` | Fiyat geçmişi |
| | `GET /api/v1/market/search?q=...` | Hisse arama |
| **Ticaret** | `POST /api/v1/trading/order` | Alım/satım emri |
| **Portföy** | `GET /api/v1/portfolio/{user_id}` | Portföy listesi |
| | `GET /api/v1/portfolio/{user_id}/sectors` | Sektör dağılımı |
| **AI Koç** | `POST /api/v1/chat/send` | SSE streaming sohbet |
| | `GET /api/v1/coach/advice/{user_id}` | Portföy tavsiyesi |
| **Davranış** | `GET /api/v1/behavior/profile/{user_id}` | Önyargı metrikleri |
| **Risk** | `GET /api/v1/stress/run/{user_id}` | Monte Carlo analizi |
| **Haber** | `GET /api/v1/news/latest` | Haberler + duygu skoru |

---

## 7. EKRANLAR (UYGULAMA AKIŞI)

```
Giriş/Kayıt Ekranı
       │
       ▼
Ana Ekran (Dashboard)
  ├── Portföy özeti + bakiye
  ├── AI Koç kartı (kısa tavsiye)
  ├── İzleme listesi fiyatları
  └── Hızlı erişim navigasyonu
       │
       ├── Hisse Detay Ekranı → Grafik + Alım/Satım
       ├── Portföy Ekranı → Tüm hisseler + PnL
       ├── AI Sohbet Ekranı → Anlık streaming koç
       ├── Haberler Ekranı → Duygu analizi ile haberler
       ├── Davranış Ekranı → Önyargı profili
       └── Stres Testi Ekranı → Monte Carlo grafikleri
```

---

## 8. BUNDAN SONRA YAPILACAKLAR

### 8.1 Kritik Eksikler (Üretime Geçiş İçin Zorunlu)

| Öncelik | Konu | Açıklama |
|---------|------|---------|
| 🔴 Yüksek | JWT Refresh Token | Şu an 7 günlük token iptal edilemiyor; logout endpoint yok |
| 🔴 Yüksek | PostgreSQL Geçişi + Alembic | SQLite tek yazıcıya izin veriyor; şema değişikliklerinde veri kaybı riski |
| 🔴 Yüksek | HTTPS + Nginx | Şu an düz HTTP; JWT token ve şifreler açıkta |
| 🔴 Yüksek | yfinance Arka Plan Görevi | BIST sorguları 10+ saniye sürüyor; async task queue gerekiyor |
| 🟡 Orta | Redis Rate Limiter | Şu anki in-memory limiter birden fazla worker'da çalışmıyor |
| 🟡 Orta | Şifre Sıfırlama | E-posta ile şifre sıfırlama akışı yok |

### 8.2 UX / Arayüz İyileştirmeleri

- [ ] Skeleton loader ekranları (yükleme animasyonları)
- [ ] Hata durumunda "Tekrar Dene" butonları
- [ ] Boş portföy için yönlendirici UX
- [ ] E-posta format doğrulama (frontend'de)
- [ ] "Şu hisse olsaydı ne olurdu?" hesaplayıcı
- [ ] Pull-to-refresh tüm ekranlara yaygınlaştırma

### 8.3 Yeni Özellikler

- [ ] **İzleme Listesi Yönetimi** — Kullanıcı kendi listesini özelleştirsin
- [ ] **Kıyaslama (Benchmark)** — Portföy performansını BIST100 / S&P500 ile karşılaştır
- [ ] **Sharpe Oranı** — Risk-ağırlıklı getiri metriği
- [ ] **Eğitim Akademisi** — Finans kavramları öğretici içerikler
- [ ] **Başarımlar ve Rozetler** — Gamification (oyunlaştırma)
- [ ] **Günlük Görevler** — Kullanıcıyı motive etmek için
- [ ] **CSV Dışa Aktarım** — İşlem geçmişini indirme
- [ ] **Push Bildirimleri** — Önemli fiyat hareketleri için
- [ ] **Dark/Light Mod** — Tema seçeneği
- [ ] **Çoklu Dil (i18n)** — Türkçe / İngilizce

### 8.4 Teknik Altyapı

- [ ] **Test Yazımı** — Backend için unit + integration testleri
- [ ] **Docker + docker-compose** — Tek komutla çalıştırılabilir ortam
- [ ] **CI/CD** — GitHub Actions ile otomatik test ve deploy
- [ ] **İki Faktörlü Doğrulama (2FA)** — Altyapı hazır, aktif edilmesi gerekiyor
- [ ] **Sentry** — Üretim ortamı hata takibi

---

## 9. PROJE DOSYA YAPISI

```
Portly-main/
├── lib/                          # Flutter uygulaması
│   ├── main.dart                 # Giriş noktası, navigasyon
│   ├── screens/                  # Uygulama ekranları (10 ekran)
│   ├── providers/                # State yönetimi (auth, portfolio, chat)
│   ├── services/api_service.dart # Tüm API çağrıları
│   ├── models/                   # Veri modelleri
│   └── widgets/                  # Yeniden kullanılabilir UI bileşenleri
│
├── backend/
│   ├── app/
│   │   ├── main.py               # FastAPI başlatma
│   │   ├── api/v1/               # 9 API router modülü
│   │   ├── services/             # İş mantığı katmanı (9 servis)
│   │   ├── models/               # SQLAlchemy ORM modelleri
│   │   ├── schemas/              # Pydantic istek/yanıt şemaları
│   │   └── core/                 # Yapılandırma, DB bağlantısı, limiter
│   ├── portly.db                 # SQLite veritabanı (geliştirme)
│   └── requirements.txt
│
├── Portly_SDD.md                 # IEEE 1016-2009 Yazılım Tasarım Dokümanı
└── GELISTIRME_ONERILERI.md       # Teknik geliştirme önerileri
```

---

## 10. PROJE DEĞERLENDİRMESİ

### Güçlü Yönler
- Temiz 3 katmanlı mimari ile servis katmanı ayrımı
- Akademik kaynaklara dayalı davranışsal finans modelleri (Shefrin & Statman 1985, Kahneman & Tversky 1979, Barber & Odean 2001)
- Gerçek zamanlı AI yanıtı için SSE streaming
- Provider pattern ile düzgün state yönetimi
- Hassas API uç noktalarında rate limiting
- Kapsamlı yazılım tasarım dokümanı (SDD)
- Gerçek piyasa verileriyle çalışan (Yahoo Finance) tam işlevli simülatör

### Geliştirme Alanları
- Üretim ortamı güvenlik eksiklikleri (refresh token, HTTPS)
- Test kapsamı sıfır
- 2FA altyapısı hazır ama aktif değil
- Stres testi bellek kullanımı optimize edilmeli
- BIST sorgu gecikmesi kullanıcı deneyimini olumsuz etkiliyor