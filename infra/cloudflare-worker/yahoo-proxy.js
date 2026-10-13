/**
 * Portly — Yahoo Finance ters vekil (reverse proxy) · Cloudflare Worker
 *
 * NEDEN: Yahoo, Render ücretsiz katmanının PAYLAŞILAN çıkış IP'sini
 * rate-limit'liyor (HTTP 429). Aynı IP'den yfinance kullanan başka Render
 * kullanıcıları da aynı kotayı yakıyor → kod tarafında ne yapılırsa yapılsın
 * BIST ve kripto fiyatı gelmiyordu. Bu Worker, isteği Cloudflare'in kendi
 * çıkış havuzundan yapar → Render'ın cezalı IP'si devreden çıkar.
 *
 * ÜCRET: Cloudflare Workers ücretsiz plan = 100.000 istek/gün. Portly'nin
 * arka plan yenileyicisi 5 dk'da 3 batch → günde ~900 istek. Fazlasıyla yeter.
 *
 * TEFAS: yatırım fonu birim pay değeri (TLY.FON gibi) Yahoo'da HİÇ yok,
 * kaynağı TEFAS'ın kendi açık ucu. TEFAS'ın Render IP'sini kısıtlayıp
 * kısıtlamadığı ölçülmedi; kısıtlarsa backend'e `TEFAS_PROXY_BASE` env'i
 * eklemek yeterli — Worker o yolu da (POST) burada vekilliyor.
 *
 * GÜVENLİK: Yalnız Yahoo'nun ve TEFAS'ın AÇIK (kimlik doğrulamasız) uçlarına
 * izin verilir; açık vekil (open proxy) değildir. İstersen PORTLY_TOKEN
 * ortam değişkenini tanımlayıp yalnız kendi backend'inin kullanmasını sağla.
 */

const ALLOWED_HOSTS = [
  "query1.finance.yahoo.com",
  "query2.finance.yahoo.com",
];

// Yalnız bu yol önekleri geçer (açık vekil olmasın).
const ALLOWED_PREFIXES = [
  "/v8/finance/chart/",
  // Toplu fiyat: TEK istekte 50 sembole kadar (backend _fetch_quotes_batch).
  "/v7/finance/quote",
  // Spark (toplu kapanış serisi) gerçek yolu /v8'dir; /v7 yazılıydı ve hiç
  // eşleşmiyordu.
  "/v8/finance/spark",
  "/v7/finance/spark",
  "/v1/finance/search",
];

// TEFAS fon uçları: JSON gövdeli POST — ayrı hedef ve ayrı izin listesi.
const TEFAS_HOST = "www.tefas.gov.tr";
const TEFAS_PREFIXES = ["/api/funds/"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // İsteğe bağlı paylaşılan sır: env.PORTLY_TOKEN tanımlıysa zorunlu.
    if (env.PORTLY_TOKEN) {
      const sent = request.headers.get("x-portly-token");
      if (sent !== env.PORTLY_TOKEN) {
        return new Response("Yetkisiz", { status: 401 });
      }
    }

    // TEFAS (fon birim pay değeri): POST + JSON gövde.
    if (TEFAS_PREFIXES.some((p) => url.pathname.startsWith(p))) {
      if (request.method !== "POST") {
        return new Response("TEFAS uçları POST bekler", { status: 405 });
      }
      const target = new URL(url.pathname + url.search, `https://${TEFAS_HOST}`);
      const upstream = await fetch(target.toString(), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "User-Agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/125.0 Safari/537.36",
          Referer: `https://${TEFAS_HOST}/`,
        },
        body: await request.text(),
      });
      const h = new Headers(upstream.headers);
      h.set("access-control-allow-origin", "*");
      h.set("x-portly-proxy", "cf-worker-tefas");
      return new Response(upstream.body, { status: upstream.status, headers: h });
    }

    if (request.method !== "GET") {
      return new Response("Yalnız GET", { status: 405 });
    }

    if (!ALLOWED_PREFIXES.some((p) => url.pathname.startsWith(p))) {
      return new Response("Bu yol vekillenmiyor", { status: 403 });
    }

    const host = env.YAHOO_HOST || ALLOWED_HOSTS[0];
    if (!ALLOWED_HOSTS.includes(host)) {
      return new Response("Geçersiz hedef", { status: 400 });
    }

    const target = new URL(url.pathname + url.search, `https://${host}`);

    const upstream = await fetch(target.toString(), {
      method: "GET",
      headers: {
        // Yahoo tarayıcı benzeri bir istemci bekliyor.
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
          "(KHTML, like Gecko) Chrome/125.0 Safari/537.36",
        Accept: "application/json,text/plain,*/*",
        "Accept-Language": "en-US,en;q=0.9",
        // /v7/finance/quote çerez + crumb ister; çerez İLETİLMEZSE Yahoo 401
        // ya da 429 döner ve vekil bu uçta işe yaramaz. Yahoo'nun anonim
        // consent çerezidir (oturum/kimlik değil) ve yalnız Yahoo'ya gider.
        ...(request.headers.get("cookie")
          ? { Cookie: request.headers.get("cookie") }
          : {}),
      },
      // Cloudflare kenar önbelleği: aynı sembol arka arkaya istenirse
      // Yahoo'ya hiç gitmez (hem hız hem kota). Çerezli istek kişiye özel
      // değil (anonim consent) → paylaşımlı cache sorun değil.
      cf: { cacheTtl: 60, cacheEverything: true },
    });

    const headers = new Headers(upstream.headers);
    headers.set("access-control-allow-origin", "*");
    headers.set("x-portly-proxy", "cf-worker");

    return new Response(upstream.body, {
      status: upstream.status,
      headers,
    });
  },
};
