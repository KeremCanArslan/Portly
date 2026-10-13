# Yahoo çıkış-IP çözümü (ücretsiz) — Cloudflare Worker

**Sorun:** Yahoo Finance, Render ücretsiz katmanının **paylaşılan çıkış IP'sini**
rate-limit'liyor (`HTTP 429 Too Many Requests`). Aynı IP'yi kullanan başka Render
müşterileri de aynı kotayı yakıyor → Portly'nin kendi istek sayısını düşürmesi
sorunu **çözmüyor**. Etkisi: BIST ve kripto fiyatları gelmiyor, Sinyaller sekmesi
6 aylık mum bulamadığı için boş kalıyor.

**Çözüm (ücretsiz):** Yahoo'ya Render'ın IP'sinden değil, **Cloudflare'in çıkış
havuzundan** gitmek. Cloudflare Workers ücretsiz plan **100.000 istek/gün** verir;
Portly günde ~900 istek atıyor.

Alternatifler ve neden bu seçildi:

| Seçenek | Ücret | Not |
|---|---|---|
| **Cloudflare Worker vekil** | **0 ₺** | Bu belge. Kod değişikliği zaten yapıldı, tek iş Worker'ı yayına almak. |
| Render ücretli sabit çıkış IP'si | aylık ücretli | Temiz ama ücretli; ayrıca yeni IP'nin de temiz kalacağı garanti değil. |
| Ücretli veri sağlayıcı (Finnhub/Twelve Data ücretli) | aylık ücretli | En sağlamı; BIST kapsaması ayrıca kontrol edilmeli. |

---

## Kurulum (~5 dakika, kart istemez)

1. **Hesap:** https://dash.cloudflare.com → ücretsiz kayıt.
2. **Workers & Pages → Create → Worker**. Ad: `portly-yahoo`. **Deploy** de.
3. **Edit code** → açılan editördeki her şeyi sil, bu klasördeki
   [`yahoo-proxy.js`](./yahoo-proxy.js) içeriğini yapıştır → **Deploy**.
4. Worker adresini not al: `https://portly-yahoo.<hesap-adın>.workers.dev`
5. **Doğrula** (tarayıcıdan aç, JSON dönmeli):
   `https://portly-yahoo.<hesap>.workers.dev/v8/finance/chart/THYAO.IS?range=5d&interval=1d`
6. **Render → portly-backend → Environment** → yeni değişken:
   - `YAHOO_PROXY_BASE` = `https://portly-yahoo.<hesap>.workers.dev`
   - Save → servis yeniden başlar (~1 dk).
7. **Canlı doğrula:**
   ```bash
   curl -s https://portly-backend-5jii.onrender.com/api/v1/market/price/THYAO.IS
   curl -s https://portly-backend-5jii.onrender.com/api/v1/market/price/BTC-USD
   ```
   429 yerine fiyat dönmeli. Sinyaller için:
   ```bash
   curl -s -H "Authorization: Bearer <token>" \
     https://portly-backend-5jii.onrender.com/api/v1/signals | head -c 300
   ```
   `failed` listesi kısalmalı.

### İsteğe bağlı: Worker'ı kendine kilitle

Worker herkese açık bir URL. Yalnız Portly kullansın istersen:

1. Worker → **Settings → Variables → Add variable**: `PORTLY_TOKEN` = uzun rastgele
   bir dize (Encrypt işaretle).
2. Backend tarafında istek başlığına `x-portly-token` eklemek gerekir —
   `yahoo_chart_service._collect` içindeki `headers` sözlüğüne eklenir.
   (Bugün gerekmiyor: Worker yalnız Yahoo'nun **açık** uçlarını vekilliyor,
   kötüye kullanımın maliyeti sadece kota.)

---

## TEFAS (yatırım fonu) — yalnız GEREKİRSE

Fon birim pay değeri (TLY.FON, LTL.FON …) Yahoo'da **hiç yok**; kaynağı
TEFAS'ın kendi açık ucu (`www.tefas.gov.tr/api/funds/fonFiyatBilgiGetir`).
Backend oraya **doğrudan** gidiyor ve bu yeterli olmalı — TEFAS'ın Render
çıkış IP'sini kısıtlayıp kısıtlamadığı ölçülmedi.

Kısıtlarsa (fon fiyatları 429/boş dönerse) **kod değişikliği gerekmez**:

1. Worker'ı bu klasördeki güncel [`yahoo-proxy.js`](./yahoo-proxy.js) ile
   yeniden yayına al (TEFAS yolunu `POST` olarak vekilliyor).
2. Render → portly-backend → Environment:
   `TEFAS_PROXY_BASE` = `https://portly-yahoo.<hesap>.workers.dev`
3. Doğrula:
   ```bash
   curl -s https://portly-backend-5jii.onrender.com/api/v1/market/price/TLY.FON
   ```

TEFAS ~4 hızlı istekten sonra 429 veriyor (~45 sn). Backend zaten fon başına
tek istekle 3 yıllık seriyi çekiyor, sonucu saatlerce cache'liyor ve 429'da
5 dk susuyor (`fund_source_service`).

---

## Kod tarafı (yapıldı)

- `backend/app/core/config.py` → `YAHOO_PROXY_BASE` ayarı (boşsa doğrudan Yahoo).
- `backend/app/services/yahoo_chart_service.py` → yfinance'siz, yalnız açık
  `chart` ucunu kullanan istemci. **429 görürse 15 dk kendini kapatır**
  (devre kesici — cezayı uzatmamak için).
- `backend/app/services/market_data_service.py` → fiyat / kapanış serisi /
  OHLCV yollarının **son yedek halkası** olarak bağlı.

`YAHOO_PROXY_BASE` tanımlı değilken davranış eskisiyle aynıdır (yalnız
yfinance başarısız olursa açık chart ucu bir kez denenir).

## Toplu fiyat ucu (`/v7/finance/quote`) — 4 Eylül 2026

Backend artık N sembolü **tek istekte** çekiyor (`market_data_service.
_fetch_quotes_batch`); eski yol (`yf.download`) sembol BAŞINA bir
`/v8/finance/chart/` isteği atıyordu — 51 sembollük tarama = 51 Yahoo isteği,
Render'ın paylaşılan IP'sinde 429'un asıl kaynağı buydu.

Worker'da bunun için iki şey değişti; **Worker'ı yeniden deploy etmeden yeni uç
vekilden geçmez** (403 alır ve backend doğrudan Yahoo'ya düşer — çalışır ama
IP koruması olmaz):

1. `ALLOWED_PREFIXES`'e `/v7/finance/quote` eklendi (ayrıca spark'ın gerçek
   yolu `/v8/finance/spark` — eskiden yalnız `/v7/...` yazılıydı, hiç
   eşleşmiyordu).
2. İstemciden gelen **`Cookie` başlığı Yahoo'ya iletiliyor**: `/v7/finance/quote`
   çerez + crumb ister, çerez düşerse 401/429 döner. Bu Yahoo'nun anonim
   consent çerezidir (oturum/kimlik değil) ve yalnız Yahoo'ya gider.
