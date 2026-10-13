/// Sembolleri kullanıcı dostu etiketlere dönüştürür.
///
/// Yahoo Finance sembolleri (GC=F, USDTRY=X gibi) teknik kullanıcıya anlamlı,
/// son kullanıcıya değil. Bu yardımcı sınıf, bilinen sembolleri Türkçe isimlerle
/// gösterir; bilinmeyenler için sembolün kendisini döner.
class SymbolDisplay {
  static const Map<String, String> _labels = {
    'GC=F': 'Altın',
    'SI=F': 'Gümüş',
    'CL=F': 'Ham Petrol',
    'USDTRY=X': 'USD/TRY',
    'EURTRY=X': 'EUR/TRY',
    'GBPTRY=X': 'GBP/TRY',
    'BTC-USD': 'Bitcoin',
    'ETH-USD': 'Ethereum',
    'SOL-USD': 'Solana',
    'BNB-USD': 'BNB',
    'DOGE-USD': 'Dogecoin',
    'XRP-USD': 'XRP',
    '^GSPC': 'S&P 500',
    '^IXIC': 'Nasdaq',
    '^DJI': 'Dow Jones',
    'XU100.IS': 'BIST 100',
    'THYAO.IS': 'Türk Hava Yolları',
    'ASELS.IS': 'Aselsan',
    'GARAN.IS': 'Garanti BBVA',
    'AKBNK.IS': 'Akbank',
    'ISCTR.IS': 'İş Bankası',
    'YKBNK.IS': 'Yapı Kredi',
    'KCHOL.IS': 'Koç Holding',
    'SAHOL.IS': 'Sabancı Holding',
    'BIMAS.IS': 'BİM',
    'MGROS.IS': 'Migros',
    'EREGL.IS': 'Ereğli Demir Çelik',
    'TCELL.IS': 'Türkcell',
    'PGSUS.IS': 'Pegasus',
    'TUPRS.IS': 'Tüpraş',
    'FROTO.IS': 'Ford Otosan',
    'TOASO.IS': 'Tofaş',
    // Fiziki altın/gümüş — backend saklama sembolleri (".ALTIN"/".GUMUS"),
    // kullanıcıya ürün adıyla gösterilir.
    'GRAM.ALTIN': 'Gram Altın',
    'HAS.ALTIN': 'Gram Has Altın',
    'CEYREK.ALTIN': 'Çeyrek Altın',
    'YARIM.ALTIN': 'Yarım Altın',
    'TAM.ALTIN': 'Tam Altın',
    'CUMHURIYET.ALTIN': 'Cumhuriyet Altını',
    'ATA.ALTIN': 'Ata Altın',
    'BILEZIK22.ALTIN': '22 Ayar Bilezik',
    'AYAR18.ALTIN': '18 Ayar Altın',
    'AYAR14.ALTIN': '14 Ayar Altın',
    'GRAM.GUMUS': 'Gram Gümüş',
  };

  /// Fiziki altın/gümüş mü (kuyumcudaki somut varlık)?
  static bool isPhysical(String symbol) {
    final s = symbol.toUpperCase();
    return s.endsWith('.ALTIN') || s.endsWith('.GUMUS');
  }

  /// Fiziki varlığın miktar birimi: çeyrek/tam/cumhuriyet ADET ile,
  /// gram/has/bilezik/ayar ürünleri GRAM ile alınır satılır (serbest piyasa
  /// fiyatları da öyle kote edilir). Yanlış birim maliyeti 5-6 katı yanlış
  /// gösterirdi.
  static String physicalUnit(String symbol) {
    const perPiece = {
      'CEYREK.ALTIN', 'YARIM.ALTIN', 'TAM.ALTIN',
      'CUMHURIYET.ALTIN', 'ATA.ALTIN',
    };
    return perPiece.contains(symbol.toUpperCase()) ? 'adet' : 'gram';
  }

  /// Verilen sembol için gösterim adını döner. Bilinmeyen sembollerde
  /// sembolün kendisini geri verir.
  static String label(String symbol) {
    final s = symbol.toUpperCase();
    final mapped = _labels[s];
    if (mapped != null) return mapped;
    // Haritasız kripto: Yahoo "HYPE32196-USD" gibi sembole sayısal CMC
    // id'si ekliyor → "-USD" + sondaki rakamları at ("HYPE"). Normal
    // hisse "-USD" ile bitmez, dokunulmaz.
    if (s.endsWith('-USD')) {
      final base =
          s.substring(0, s.length - 4).replaceAll(RegExp(r'\d+$'), '');
      if (base.isNotEmpty) return base;
    }
    // TEFAS fonu: ".FON" backend'in saklama soneği, kullanıcıya anlamsız →
    // portföy satırı ve sinyal kartı başlığı "TLY.FON" yazıyordu. compact()
    // zaten kırpıyordu, label() kırpmıyordu. ".IS"/".TR" bilinçli olarak
    // DOKUNULMAZ (eski davranış, BIST kullanıcısı kodu böyle tanıyor).
    if (s.endsWith('.FON')) {
      final base = s.substring(0, s.length - 4);
      if (base.isNotEmpty) return base;
    }
    return symbol;
  }

  /// Dar bağlam (donut etiketi, çip) için KISA gösterim adı:
  /// - Bilinen şifreli sembol → Türkçe ad ("GC=F"→"Altın", "USDTRY=X"→
  ///   "USD/TRY"). Kullanıcı "GC=F değil Altın görmek istiyorum" dedi.
  /// - Kripto "HYPE32196-USD" → "HYPE" (Yahoo'nun eklediği sayısal
  ///   CMC id'si + "-USD" atılır; "yanında kodu ile geldi" şikâyeti).
  /// - Normal hisse → temiz ticker (THYAO.IS→THYAO; ad çok uzun
  ///   olabileceği için donut'ta ticker tercih edilir).
  static String compact(String symbol) {
    final s = symbol.toUpperCase();
    final mapped = _labels[s];
    if (mapped != null) return mapped;
    if (s.endsWith('-USD')) {
      final base =
          s.substring(0, s.length - 4).replaceAll(RegExp(r'\d+$'), '');
      return base.isEmpty ? s : base;
    }
    for (final suf in ['.IS', '.TR', '.FON', '.ALTIN', '.GUMUS']) {
      if (s.endsWith(suf)) return s.substring(0, s.length - suf.length);
    }
    if (s.endsWith('=X') || s.endsWith('=F')) {
      return s.substring(0, s.length - 2);
    }
    return s;
  }

  /// "Anlamlı" başlık seçer:
  /// - Bilinen sembol varsa Türkçe adı (örn. "Altın")
  /// - Yoksa yfinance'ten gelen name (örn. "Apple Inc.")
  /// - O da boşsa sembol
  static String pickTitle(String symbol, String fallbackName) {
    final mapped = _labels[symbol.toUpperCase()];
    if (mapped != null) return mapped;
    if (fallbackName.isNotEmpty && fallbackName != symbol) return fallbackName;
    return symbol;
  }

  /// Haber sorgusu anahtar kelimesi (Google News RSS).
  /// BIST hisseleri: ticker + Türkçe isim (OR) → Google News TR Türkçe finansal
  /// haber döndürür (İngilizce marka adı "turkish airlines" global+yabancı dilde
  /// alakasız haber çekiyordu). ABD/kripto/emtia İngilizce kalır (EN finans haberi).
  static const Map<String, String> _newsQueries = {
    'GC=F': 'gold price',
    'SI=F': 'silver price',
    'CL=F': 'crude oil',
    'USDTRY=X': 'turkish lira',
    'EURTRY=X': 'turkish lira euro',
    'BTC-USD': 'bitcoin',
    'ETH-USD': 'ethereum',
    'SOL-USD': 'solana',
    'BNB-USD': 'binance',
    'DOGE-USD': 'dogecoin',
    'XRP-USD': 'ripple',
    '^GSPC': 'S&P 500',
    '^IXIC': 'nasdaq',
    '^DJI': 'dow jones',
    'XU100.IS': 'BIST 100 OR "Borsa İstanbul"',
    'THYAO.IS': 'THYAO OR "Türk Hava Yolları"',
    'ASELS.IS': 'ASELS OR Aselsan',
    'GARAN.IS': 'GARAN OR "Garanti BBVA"',
    'AKBNK.IS': 'AKBNK OR Akbank',
    'ISCTR.IS': 'ISCTR OR "İş Bankası"',
    'KCHOL.IS': 'KCHOL OR "Koç Holding"',
    'SAHOL.IS': 'SAHOL OR "Sabancı Holding"',
    'PGSUS.IS': 'PGSUS OR Pegasus',
    'AAPL': 'apple',
    'MSFT': 'microsoft',
    'GOOGL': 'google alphabet',
    'AMZN': 'amazon',
    'META': 'meta facebook',
    'TSLA': 'tesla',
    'NVDA': 'nvidia',
    'AMD': 'AMD chip',
    'INTC': 'intel',
    'NFLX': 'netflix',
  };

  /// Verilen sembol için haber sorgusu. Bilinmeyen BIST (.IS) hisselerinde
  /// ticker'ı Türkçe bağlamla aratır (`TICKER hisse`) → Google News TR Türkçe
  /// finansal haber döndürür. Diğerlerinde sembolün adına düşer.
  static String newsQuery(String symbol) {
    final upper = symbol.toUpperCase();
    // Bölge öneki: BIST → Türk basını (tr), ABD/kripto/döviz/emtia → İngilizce
    // orijinal (en). Backend bu önekle Google News baskısını (hl/gl) seçer →
    // ABD/kripto haberi makine-çevirisi agregatör yerine Reuters/Bloomberg vb.
    // gerçek İngilizce kaynaktan gelir (VADER skorlayabilir, daha az "Nötr").
    final region = (upper.endsWith('.IS') ||
            upper.endsWith('.TR') ||
            upper.endsWith('.FON') ||
            isPhysical(upper))
        ? 'tr'
        : 'en';
    final mapped = _newsQueries[upper];
    if (mapped != null) return '$region|$mapped';
    if (upper.endsWith('.IS')) {
      final ticker = upper.replaceAll('.IS', '');
      final name = label(upper);
      return '$region|${name != upper ? '$ticker OR "$name"' : '$ticker hisse'}';
    }
    if (upper.endsWith('.FON')) {
      // Fon kodu tek başına ("TLY") haber aramasında gürültü getiriyor →
      // "yatırım fonu" bağlamıyla ara.
      return '$region|${compact(upper)} yatırım fonu';
    }
    if (isPhysical(upper)) {
      // "Çeyrek Altın" diye haber aranmaz; fiyatı belirleyen gram altındır.
      return upper.endsWith('.GUMUS')
          ? '$region|gümüş fiyatı'
          : '$region|altın fiyatı gram altın';
    }
    return '$region|${label(upper)}';
  }

  /// Sembolün doğal para birimini döner.
  /// - .IS, .FON (TEFAS yatırım fonu), .ALTIN/.GUMUS (fiziki), TRY=X → ₺
  /// - Gerisi → $
  static String currencyOf(String symbol) {
    final s = symbol.toUpperCase();
    if (s.endsWith('.IS') ||
        s.endsWith('.TR') ||
        s.endsWith('.FON') ||
        isPhysical(s)) {
      return '₺';
    }
    if (s.contains('TRY=X')) return '₺';
    return '\$';
  }

  /// TEFAS yatırım fonu mu? (Backend sembolü "TLY.FON" biçiminde saklar —
  /// fonun Yahoo karşılığı yoktur, fiyatı TEFAS'tan gelir.)
  static bool isFund(String symbol) => symbol.toUpperCase().endsWith('.FON');

  /// Birim fiyat kaç ondalıkla gösterilsin?
  ///
  /// Fon birim pay değeri 1,096196 gibi olabiliyor → 2 basamağa yuvarlamak
  /// binde 3'lük hata demek (maliyetle yan yana yazınca kâr/zarar yüzdesiyle
  /// çelişik görünüyor). Hisse/kripto 2 basamakta kalır.
  static int priceDecimals(String symbol, double value) {
    if (!isFund(symbol)) return 2;
    final v = value.abs();
    if (v >= 100) return 2;
    if (v >= 1) return 4;
    return 6;
  }

  /// Borsa sınıfı — portföy görünümünde gruplama için.
  static String exchangeOf(String symbol) {
    final s = symbol.toUpperCase();
    if (s.endsWith('.IS') || s.endsWith('.TR')) return 'BIST';
    if (s.endsWith('.FON')) return 'Fon';
    if (s.endsWith('-USD')) return 'Kripto';
    if (s.contains('TRY=X')) return 'Döviz';
    if (s.endsWith('=F')) return 'Emtia';
    if (s.startsWith('^')) return 'Endeks';
    return 'ABD';
  }

  /// Başlık altındaki ikincil satır. Yahoo'nun şifreli sembolleri
  /// (GC=F, USDTRY=X, ^GSPC) son kullanıcıya anlamsız → varlık sınıfını
  /// göster ("Emtia", "Döviz"). Normal hisse kodları (AAPL, THYAO.IS)
  /// anlaşılır → sembolün kendisini koru.
  static String secondaryLabel(String symbol) {
    final s = symbol.toUpperCase();
    if (s.contains('=') || s.startsWith('^')) return exchangeOf(symbol);
    // "TLY.FON" soneki kullanıcıya anlamsız → "TLY · Fon".
    if (s.endsWith('.FON')) return '${compact(s)} · Fon';
    return symbol;
  }
}
