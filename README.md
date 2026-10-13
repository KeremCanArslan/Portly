# Portly

Portföy takip + finans haberi + kural tabanlı **AL / TUT / SAT sinyal asistanı**.
Flutter (web + mobil) + FastAPI + PostgreSQL.

> **Not:** Portly başlangıçta "AI destekli sanal borsa simülatörü" idi. **5 Temmuz 2026'da
> pivot edildi** — sanal bakiye ve emir motoru kaldırıldı. Uygulama artık gerçek portföyü
> **takip eder**, sanal alım-satım yaptırmaz. İşlem geçmişi bir **kayıt defteridir**:
> kullanıcı kendi gerçek alış/satışını girer, maliyet ve temettü mutabakatı buna dayanır.

Üretilen sinyaller **yatırım tavsiyesi değildir**.

---

## Ne yapar

**Çekirdek**
- **Portföy takibi** — manuel pozisyon girişi, küsüratlı adet, maliyet takibi, Bugün/Toplam kâr-zarar
- **Sinyaller** — teknik göstergeler (SMA50/200, golden/death cross, RSI, MACD, Bollinger %B, Stochastic, hacim onayı) + temel oranlar (F/K, PEG, ROE, marj, büyüme, borç/özkaynak, temettü, analist konsensüsü, 52h konum) → **0-100 skor** (teknik %55 + temel %45) → AL ≥65 / SAT ≤35 / arası TUT, Türkçe gerekçeli. **LLM kullanmaz** (tarama başına AI kotası yakmamak için).
- **Haberler** — RSS tabanlı, bölge yönlendirmeli (BIST → Türk basını, ABD/kripto/döviz/emtia → İngilizce orijinal), hibrit duygu analizi (VADER + Türkçe finansal sözlük), "Etkilenen Varlıklar" eşlemesi
- **İzleme listesi** ve **fiyat alarmları**

**Yardımcı modüller**
- Temettü takibi · sektör kırılımı · karşılaştırma (BIST100/S&P/dolar/altın/mevduat/enflasyon)
- AI Koç sohbeti (portföy bağlamıyla, SSE streaming) · AI portföy önerisi
- What-If senaryoları · stres testi · davranışsal finans analizi · risk profili testi
- Yatırımcı günlüğü (not alma) · akademi · mum tahmin pratiği
- Ekran görüntüsünden portföy içe aktarma (OCR) · CSV dışa aktarma
- ABD hisseleri için **pre/post-market** (uzatılmış seans) fiyatı — yalnız hisse detay ekranında

---

## Teknoloji

**Frontend:** Flutter 3.6+ / Dart · Provider · fl_chart · özel `CustomPainter` grafik (Çizgi/Mum/Heikin Ashi + MA20/50/200 + crosshair) · flutter_dotenv · share_plus

**Backend:** Python 3.10+ · FastAPI · SQLAlchemy + PostgreSQL (Alembic) · Redis (rate limiter, in-memory fallback) · JWT (python-jose, refresh + rotation + blacklist) · bcrypt

**Dış servisler:**

| Servis | Ne için | Not |
|---|---|---|
| Google Gemini 2.5 Flash / Flash-Lite | Birincil LLM | Kota dolunca iki model arası otomatik geçiş |
| Groq (Llama 3.3 70B) | LLM yedeği | Gemini'nin iki modeli de tükenirse |
| yfinance | Fiyat, grafik, geçmiş veri | **Yalnız kişisel kullanım** — ticari kullanım Yahoo şartlarına aykırı |
| Finnhub | Temel oranlar, profil, analist | Ücretsiz katman **yalnız ABD borsaları** — BIST hâlâ `data_limited` |
| Google News RSS | Haber akışı | Bölge parametreli (hl/gl/ceid) |
| Brevo (HTTP API) | Şifre sıfırlama e-postası | SMTP değil — Render SMTP portlarını bloklar |

**Barındırma:** Render (backend web service + frontend static site, ikisi de Frankfurt) · Neon PostgreSQL. `git push` → ~3 dk sonra otomatik canlı (Auto-Deploy "On Commit" açık). Backend soğuk başlangıçta `alembic upgrade head` koşar.

---

## Kurulum

### Ön gereksinimler
- **Flutter SDK** 3.6+ ([kurulum](https://docs.flutter.dev/get-started/install))
- **Python** 3.10+
- **PostgreSQL** 14+ (macOS: `brew install postgresql@16 && brew services start postgresql@16`)
- **Redis** — rate limiter için, opsiyonel (yoksa in-memory'ye düşer)
- (iOS için) Xcode · (Android için) Android Studio + emülatör veya gerçek cihaz

### Hızlı başlangıç

```bash
git clone https://github.com/umutaltan/Portly.git
cd Portly

# Backend
cd backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
createdb portly
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000   # ayrı terminalde bırak

# Frontend (kök dizinde)
cd .. && flutter pub get && flutter run -d chrome
```

API: `http://localhost:8000/api/v1` · Dokümantasyon: `http://localhost:8000/docs`

### Ortam değişkenleri

`backend/.env` repoda hazır geliyor (private repo). Kendi anahtarlarını kullanacaksan
`backend/.env.example`'a bak:

| Değişken | Zorunlu | Nereden |
|---|---|---|
| `DATABASE_URL` | evet | PostgreSQL bağlantı dizesi |
| `SECRET_KEY` | evet | `python -c "import secrets;print(secrets.token_urlsafe(64))"` |
| `GEMINI_API_KEY` | evet | https://aistudio.google.com |
| `GROQ_API_KEY` | hayır | https://console.groq.com (LLM yedeği) |
| `FINNHUB_API_KEY` | hayır | https://finnhub.io (temel oranlar; yoksa degrade mod) |
| `NEWS_API_KEY` | hayır | https://newsapi.org |
| `BREVO_API_KEY` / `BREVO_SENDER_EMAIL` | hayır | Şifre sıfırlama maili için |
| `REDIS_URL` | hayır | Yoksa in-memory rate limiter |
| `ALLOWED_ORIGINS` | hayır | CORS kilidi |

Kökteki `.env` Flutter'ın backend adreslerini tutar — **kendi yerel IP'ne göre güncelle**:

```env
API_BASE_URL_ANDROID=http://10.0.2.2:8000/api/v1      # Android emülatör (host'a erişim)
API_BASE_URL_LOCAL=http://127.0.0.1:8000/api/v1       # iOS simülatör / masaüstü
API_BASE_URL_NETWORK=http://192.168.X.X:8000/api/v1   # Gerçek cihaz: makinenin LAN IP'si
```

Yerel IP: macOS/Linux `ifconfig` veya `ip a`, Windows `ipconfig`.

---

## Test

```bash
# Backend — venv shebang bozuk, "python -m" ŞART
cd backend && venv/bin/python -m pytest

# Frontend — proje KÖKÜNDEN koş (yanlış dizinde sessizce koşmaz)
flutter test
flutter analyze
```

---

## Proje yapısı

```
backend/          FastAPI servisi
  app/
    main.py       Giriş noktası
    api/v1/       Route handler'lar (auth, portfolio, signals, news, chat, ...)
    core/         Config, JWT, cache, SafeJSONResponse (NaN→null güvenlik ağı)
    models/       SQLAlchemy ORM
    schemas/      Pydantic şemaları
    services/     İş mantığı (sinyal, piyasa verisi, sentiment, LLM, ...)
  alembic/        Migration'lar
  tests/          pytest
  requirements.txt

lib/              Flutter app
  main.dart       AuthGate + alt menü (Ana Sayfa · Haberler · Sinyaller · Portföy)
  screens/        Sayfalar
  providers/      State (Provider pattern)
  services/       API client (api_service.dart) + SSE
  models/         Veri modelleri
  widgets/        Ortak UI bileşenleri
  theme/          Tema ve iOS tarzı bileşenler

render.yaml       Render deploy tanımı
portly.db         Bayat SQLite fallback — prod ve lokal Postgres kullanır
```

---

## Doküman haritası

| Dosya | İçerik |
|---|---|
| **README.md** | Bu dosya — kurulum ve genel bakış |
| **SESSION_HANDOFF.md** | Tek ileri-plan kaynağı: güncel durum, açık işler, kalıcı kurallar |
| **CIHAZ_DOGRULAMA.md** | Telefonda elle doğrulanacak işlerin listesi |
| **GELISTIRME_ONERILERI.md** | Detaylı backlog |
| **CHANGELOG.md** | Tarihsel geçmiş (tur tur) |
| **Portly_SDD.md** / **PROJE_DOKUMANI.md** | Donmuş akademik teslim (Mayıs 2026) — güncel kodu **yansıtmaz** |

---

## Geliştirici notları

- **API çağrıları:** `lib/services/api_service.dart`. `baseUrl` getter'ı platforma göre `.env`'den seçer.
- **State:** Provider pattern; her ekran ilgili provider'ı `Consumer`/`context.watch` ile dinler.
- **SSE (streaming AI yanıtları):** sahibi-biz `http.Client` streamed GET + elle SSE parse. `flutter_client_sse` paketi **kaldırıldı** — global singleton'ı mesaj duplikasyonuna yol açıyordu.
- **DB değişikliği:** `backend/app/models/` altında ORM güncelle → **elle** Alembic migration yaz (`venv/bin/python -m alembic revision -m "..."`; autogenerate'e güvenme) → `alembic upgrade head`. Deploy'da otomatik koşar.
- **Yeni endpoint:** `api/v1/` altına route + `schemas/` altına Pydantic + gerekirse `services/` altına iş mantığı → `main.py`'da router'ı include et.
- **NaN kuralı:** Tüm yanıtlar `SafeJSONResponse` üzerinden geçer (NaN/inf → null). Bu son savunmadır; veri doğruluğunu kaynakta düzelt.

---

## Sık karşılaşılan sorunlar

| Belirti | Sebep / çözüm |
|---|---|
| Değişiklik telefonda görünmüyor | **PWA cache.** PWA'yı sil + site verilerini temizle + `?cb=1` ile aç. Çalışan kod bozuk görünmesinin en sık sebebi. |
| İlk istek 30-50 sn sürüyor | Render free tier soğuk başlangıç. Normal. |
| Flutter "connection refused" | `.env` içindeki IP yanlış. Telefon ve bilgisayar aynı Wi-Fi'da olmalı, firewall 8000'i açmalı. |
| Android emülatör bağlanmıyor | `localhost` değil `10.0.2.2` kullan. |
| BIST hissesinde oranlar "—" | Beklenen. Finnhub ücretsiz katmanı yalnız ABD borsalarını kapsar. |
| `flutter test` "Test directory not found" | Proje kökünden koş, `backend/` içinden değil. |
| `pytest: command not found` | venv shebang bozuk → `venv/bin/python -m pytest` kullan. |
| Şifre sıfırlama maili gelmiyor | Render'da `BREVO_API_KEY` + `BREVO_SENDER_EMAIL` tanımlı değil. |
