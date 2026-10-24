import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/models/holding.dart';
import 'package:portly/data/portfolio_repository.dart';
import 'package:portly/data/market_repository.dart';
import 'package:portly/utils/symbol_display.dart';

// portföy, piyasa verisi, haberler ve AI koçunu bir arada yöneten büyük provider
// belki ilerleyen versiyonda bunları ayırabiliriz ama şimdilik burada
class PortfolioProvider extends ChangeNotifier {
  List<StockModel> _marketData = []; // watchlist hisse verileri
  bool _isLoading = true;

  List<dynamic> _myHoldings = []; // kullanıcının açık pozisyonları
  bool _isPortfolioLoading = true;

  List<dynamic> _newsData = [];
  bool _isNewsLoading = true;

  String? _coachAdvice;
  bool _isCoachLoading = false;
  String? _coachError;

  String? _lastError;
  // Bölüm bazlı hata durumu. Tek `_lastError` yetmiyordu: ekran "veri
  // YOK" ile "veri ALINAMADI"yı ayırt edemiyor, ağ hatasında 38
  // pozisyonu olan kullanıcıya "portföyün boş" diyordu.
  String? _portfolioError;
  String? _marketError;
  String? _newsError;

  List<String> _watchlistSymbols = []; // kullanıcının takip listesi

  int? _userId;
  String? _token;

  // varsayılan watchlist - kullanıcı henüz hiçbir şey eklemediyse bunlar gösterilir
  static const List<String> _defaultWatchlist = [
    "GC=F", // altın
    "USDTRY=X", // dolar/TL
    "EURTRY=X", // euro/TL
    "BTC-USD", // bitcoin
    "THYAO.IS", // türk hava yolları
    "ASELS.IS", // aselsan
    "AAPL",
    "NVDA",
  ];

  final ApiService _apiService;

  // F-core veri erişim katmanı (uçuş-içi dedup; ekranlar etkilenmez).
  late final PortfolioRepository _portfolioRepo =
      PortfolioRepository(_apiService);
  late final MarketRepository _marketRepo = MarketRepository(_apiService);

  // Portföy ₺ toplamları tek yerde hesaplanır (qty*avg uydurması yok).
  PortfolioSnapshot _snapshot = PortfolioSnapshot.empty();

  // getter'lar
  int? get userId => _userId;
  List<StockModel> get marketData => _marketData;
  bool get isLoading => _isLoading;
  List<dynamic> get myHoldings => _myHoldings;
  // Tipli pozisyonlar (İşlem ekranı hızlı-erişimi gibi yerler için).
  List<Holding> get holdings => _snapshot.holdings;
  bool get isPortfolioLoading => _isPortfolioLoading;
  List<dynamic> get newsData => _newsData;
  bool get isNewsLoading => _isNewsLoading;
  String? get lastError => _lastError;

  /// Portföy çekimi başarısız oldu ve gösterilecek pozisyon yok.
  String? get portfolioError => _portfolioError;

  /// İzleme listesi fiyatları alınamadı (cache de yok).
  String? get marketError => _marketError;

  /// Haber çekimi başarısız oldu.
  String? get newsError => _newsError;
  List<String> get watchlistSymbols => _watchlistSymbols;

  String? get coachAdvice => _coachAdvice;
  bool get isCoachLoading => _isCoachLoading;
  String? get coachError => _coachError;

  // toplam hisse değeri — ₺. Snapshot, her pozisyonda total_value_try
  // (yoksa native total_value) toplar → eski getter ile BİREBİR aynı
  // sayı; tek fark hesabın tek yerde, tipli olması.
  double get totalHoldingsValue => _snapshot.totalHoldingsValueTry;

  // Toplam varlık = pozisyonların değeri. (Sanal nakit bakiye pivotla
  // kaldırıldı: uygulama artık gerçek portföyü İZLER, alım-satım simüle etmez.)
  double get totalAssetValue => totalHoldingsValue;

  // Görüntüleme para birimi (₺ ↔ $) — opsiyonel, kullanıcı seçer, kalıcı.
  bool _showUsd = false;
  bool get showUsd => _showUsd;

  // USDTRY=X canlı kuru. Önce izleme listesinden; orada yoksa watchlist'ten
  // bağımsız çekilen yedek kuru kullan (kullanıcı USDTRY=X'i silse de USD
  // modu çalışsın diye).
  double? _fxUsdTry;
  double? get usdTryRate {
    for (final m in _marketData) {
      if (m.symbol.toUpperCase() == 'USDTRY=X' && m.rawPrice > 0) {
        return m.rawPrice;
      }
    }
    return _fxUsdTry;
  }

  // İzleme listesinde USDTRY=X yoksa kuru ayrıca çek (USD modu için şart).
  Future<void> _ensureFxRate() async {
    for (final m in _marketData) {
      if (m.symbol.toUpperCase() == 'USDTRY=X' && m.rawPrice > 0) {
        _fxUsdTry = m.rawPrice; // izleme listesindekiyle taze tut
        return;
      }
    }
    try {
      final r = await _marketRepo.fetchMany(['USDTRY=X']);
      if (r.isNotEmpty && r.first.rawPrice > 0) {
        _fxUsdTry = r.first.rawPrice;
        notifyListeners();
      }
    } catch (_) {/* yedek kur alınamadı; usdTryRate null kalır */}
  }

  static String _curPrefKey(int? uid) =>
      uid != null ? 'show_usd_$uid' : 'show_usd';

  Future<void> _loadCurrencyPref() async {
    final prefs = await SharedPreferences.getInstance();
    _showUsd = prefs.getBool(_curPrefKey(_userId)) ?? false;
    notifyListeners();
  }

  Future<void> _persistCurrencyPref() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_curPrefKey(_userId), _showUsd);
  }

  void toggleDisplayCurrency() => setShowUsd(!_showUsd);

  /// Para birimini açıkça ayarla (Piyasalar'daki ₺/$ seçici). Kur yoksa
  /// USD'ye geçmez (yanlış rakam göstermemek için).
  void setShowUsd(bool usd) {
    if (usd && usdTryRate == null) return;
    if (_showUsd == usd) return;
    _showUsd = usd;
    notifyListeners();
    _persistCurrencyPref();
  }

  // toplam kâr/zarar — ₺ (pnl_try, yoksa native pnl). Eski getter ile aynı.
  double get totalPnl => _snapshot.totalPnlTry;

  /// Toplam ₺ K/Z'nin KUR kaynaklı kısmı. USD pozisyonların ₺ maliyeti alış
  /// günündeki kurla tutulduğu için kur kazancı artık K/Z'ye giriyor; bu
  /// getter onu ayırır ki ekran "bunun ne kadarı kurdan geldi" diyebilsin.
  /// ₺ varlıkta ve alış kuru bilinmeyen eski kayıtta katkı 0.
  double get totalFxGain => _snapshot.totalFxGainTry;

  // toplam K/Z yüzdesi — maliyet ₺ bazında (total_cost_try). Backend bu
  // alanı HER ZAMAN gönderir (Module A/C, C1 sözleşme testi + cihaz
  // doğrulaması) → eski kodun qty*avg UYDURMA kolu kaldırıldı: pratikte
  // aynı sayı, ama USD avg'ı ₺ pnl'e bölen gizli çift-hata riski yok.
  double get totalPnlPercent => _snapshot.totalPnlPercent;

  // ── Ana sayfa performans aralığı ──────────────────────────────────────
  // Eskiden yalnız Toplam (alış maliyetine göre) ve Bugün vardı: biri yıllar
  // öncesine, diğeri tek güne bakıyordu — aradaki en faydalı pencere yoktu.
  // Hafta/Ay sunucudan gelir (kapanış serisi zaten cache'te, ek istek yok).
  PerfRange _perfRange = PerfRange.total;
  PerfRange get perfRange => _perfRange;

  /// Geriye uyum: eski `perfDaily` API'si (widget testleri + eski çağrılar).
  bool get perfDaily => _perfRange == PerfRange.daily;
  void setPerfDaily(bool daily) =>
      setPerfRange(daily ? PerfRange.daily : PerfRange.total);

  void setPerfRange(PerfRange range) {
    if (_perfRange == range) return;
    _perfRange = range;
    notifyListeners();
    // Hafta/Ay ilk kez seçildiğinde veri yoksa çek.
    if (range == PerfRange.week || range == PerfRange.month) {
      if (_periodPerf == null) loadPerformance();
    }
  }

  /// {"1w": {pnl_try, pnl_percent}, "1m": {...}} — null = henüz gelmedi.
  Map<String, dynamic>? _periodPerf;

  /// Seçili aralığın ₺ K/Z'si. Veri yoksa null (UI "—" gösterir; sıfır
  /// göstermek "hiç değişmemiş" gibi okunurdu).
  double? get rangePnl => switch (_perfRange) {
        PerfRange.total => totalPnl,
        PerfRange.daily => dailyPnl,
        PerfRange.week => _periodValue('1w', 'pnl_try'),
        PerfRange.month => _periodValue('1m', 'pnl_try'),
      };

  double? get rangePnlPercent => switch (_perfRange) {
        PerfRange.total => totalPnlPercent,
        PerfRange.daily => dailyPnlPercent,
        PerfRange.week => _periodValue('1w', 'pnl_percent'),
        PerfRange.month => _periodValue('1m', 'pnl_percent'),
      };

  double? _periodValue(String key, String field) {
    final p = (_periodPerf?[key] as Map?)?.cast<String, dynamic>();
    return (p?[field] as num?)?.toDouble();
  }

  bool _perfLoading = false;
  bool get perfLoading => _perfLoading;

  Future<void> loadPerformance() async {
    final uid = _userId;
    if (uid == null || _perfLoading) return;
    _perfLoading = true;
    notifyListeners();
    final data = await _apiService.fetchPortfolioPerformance(uid);
    if (_userId != uid) return; // istek uçarken çıkış yapıldı → yazma
    final periods = (data?['periods'] as Map?)?.cast<String, dynamic>();
    // Boş/başarısız yanıtta ESKİYİ KORU — geçici bir hata yüzünden hero
    // "veri yok"a düşmesin.
    if (periods != null && periods.isNotEmpty) _periodPerf = periods;
    _perfLoading = false;
    notifyListeners();
  }

  /// Güncel fiyatı ALINAMAYAN pozisyon sayısı. Backend fiyat gelmeyince
  /// maliyeti fiyat yerine koyar (toplamlar bozulmasın) ve satırı
  /// `price_available: false` ile işaretler. Ekran bu sayıyı gösterir ki
  /// kullanıcı toplamın eksik olduğunu bilsin (uydurma sıfır yok).
  int get unpricedCount {
    var n = 0;
    for (final h in _myHoldings) {
      if (h is Map && h['price_available'] == false) n++;
    }
    return n;
  }

  /// Bugünkü ₺ K/Z — her pozisyonun günlük % değişiminden (dün kapanış → şimdi).
  /// Günlük değişimi BİLİNMEYEN pozisyon (backend `change_available: false`)
  /// hesaba HİÇ girmez: 0 katkı vermek "bugün hiç oynamadı" demek olurdu ve
  /// yüzdeyi de sıfıra doğru seyreltirdi.
  double get dailyPnl {
    double pnl = 0;
    for (final h in holdings) {
      final prev = _prevDayValueTry(h);
      if (prev == null) continue;
      pnl += h.valueTry - prev;
    }
    return pnl;
  }

  /// Pozisyonun DÜNKÜ ₺ değeri: bugünkü değer ÷ (1 + günlük %).
  ///
  /// `d <= 0` ise geri çıkarılamaz ve pozisyon hesap dışı kalır:
  /// - `d == 0` → tam -%100, bugünkü fiyat 0. Dünkü değer bu iki sayıdan
  ///   ÇIKARILAMAZ (eski kod `prev = valueTry` diyordu → K/Z 0, yani gerçek
  ///   zarar gizleniyordu).
  /// - `d < 0` → -%100'den kötü; kaynak verisi bozuk. Bölme NEGATİF bir
  ///   "dünkü değer" üretir, toplam yüzdeyi ters çevirir.
  ///
  /// Maliyeti dünkü değer yerine koymak ÇÖZÜM DEĞİL: o zaman "bugünkü K/Z"
  /// sessizce TOPLAM K/Z'ye dönerdi. Bilinmiyorsa hesaba katılmaz — günlük
  /// değişimi bilinmeyen (`changeAvailable == false`) pozisyonlarla aynı kural.
  double? _prevDayValueTry(Holding h) {
    if (!h.changeAvailable) return null;
    final d = 1 + h.dailyChangePct / 100;
    if (d <= 0) return null;
    return h.valueTry / d;
  }

  /// Bugünkü ağırlıklı % getiri (dün kapanışına göre).
  double get dailyPnlPercent {
    double prevTotal = 0, pnl = 0;
    for (final h in holdings) {
      final prev = _prevDayValueTry(h);
      if (prev == null) continue;
      prevTotal += prev;
      pnl += h.valueTry - prev;
    }
    return prevTotal > 0 ? pnl / prevTotal * 100 : 0.0;
  }

  /// [api] yalnız testler için: sahte `ApiService` ile hata/başarı yollarını
  /// ağ olmadan sürmeye yarar. Üretimde varsayılan örnek kullanılır.
  PortfolioProvider({ApiService? api}) : _apiService = api ?? ApiService() {
    _init();
  }

  Future<void> _init() async {
    await _initWatchlist();
    _loadCurrencyPref();
    loadMarketData();
    // Haber AÇILIŞTA ÇEKİLMEZ: `newsData` yalnız Haber sekmesinde kullanılıyor
    // (grep ile doğrulandı) → sekme ilk açıldığında `ensureNewsLoaded()` ile
    // çekilir. Açılışta bir istek + bir "yükleniyor" döngüsü eksilir.
  }

  // watchlist'i yükle — giriş yapılmışsa BACKEND kaynak-doğrudur (cihazlar arası
  // senkron), ulaşılamazsa yerel SharedPreferences cache'ine düşülür. Giriş yoksa
  // yerel cache/defaults. Backend ilk kez boşsa mevcut yerel liste hesaba TAŞINIR.
  // kullanıcıya göre farklı prefs key kullanılır ki hesaplar arası karışmasın.
  // Uçuş-içi kurulum: açılışta `_init()` prefs'i beklerken auth geliyor ve
  // `updateUserAuth` İKİNCİ bir kurulum başlatıyordu → `/watchlist` iki kez
  // gidiyordu (canlıda ölçüldü).
  Future<bool>? _watchlistInit;
  int? _watchlistInitUser;

  /// İzleme listesini kurar; listenin DEĞİŞİP değişmediğini döndürür.
  /// (Açılışta iki kez fiyat çekmemek için: giriş öncesi yerel listeyle bir
  /// kez çekiliyor, sonra token gelince liste aynıysa ikinci çekim gereksiz.)
  /// Aynı kullanıcı için eşzamanlı ikinci çağrı AYNI Future'ı alır; kullanıcı
  /// kimliği anahtar olduğu için giriş öncesi yerel kurulum, giriş sonrası
  /// sunucu kurulumunu ENGELLEMEZ.
  Future<bool> _initWatchlist() {
    final uid = _userId;
    final inflight = _watchlistInit;
    if (inflight != null && _watchlistInitUser == uid) return inflight;
    final fut = _runInitWatchlist(uid);
    _watchlistInit = fut;
    _watchlistInitUser = uid;
    fut.whenComplete(() {
      if (identical(_watchlistInit, fut)) {
        _watchlistInit = null;
        _watchlistInitUser = null;
      }
    }).ignore();
    return fut;
  }

  /// `uid` çağrı ANINDAKİ kullanıcıdır (await'ler sırasında `_userId`
  /// değişebilir; aynı çalıştırma baştan sona tek kimlikle davranmalı).
  Future<bool> _runInitWatchlist(int? uid) async {
    final before = List<String>.from(_watchlistSymbols);
    bool changed() => !_sameList(before, _watchlistSymbols);
    final prefs = await SharedPreferences.getInstance();
    // Açılışın ilk anlarında auth henüz gelmemiş oluyor (`uid == null`) ama
    // diskte "beni hatırla" oturumu duruyor olabilir. O hâlde genel
    // `watchlist` anahtarı (→ varsayılan 8 sembol) yerine kullanıcının kendi
    // listesini okuruz; böylece giriş öncesi ve sonrası fiyat çekimi AYNI
    // listeye düşer ve ikinci `/market/prices` isteği hiç gitmez.
    // Oturum yoksa/çıkış yapılmışsa `rememberedUserId` null döner → eski
    // davranış (genel anahtar + varsayılanlar) aynen korunur.
    final keyUid = uid ?? AuthProvider.rememberedUserId(prefs);
    final key = keyUid != null ? 'watchlist_$keyUid' : 'watchlist';
    final saved = prefs.getStringList(key);
    final local = saved ?? List<String>.from(_defaultWatchlist);

    if (uid == null) {
      _watchlistSymbols = local; // giriş yok → yerel cache/defaults
      return changed();
    }

    final remote = await _apiService.getWatchlist();
    if (remote == null) {
      _watchlistSymbols = local; // offline/cold-start → yerel cache
      return changed();
    }
    if (remote.isNotEmpty) {
      _watchlistSymbols = remote; // backend kaynak-doğru
      await _persistWatchlistLocal(); // cache'i tazele
    } else {
      // backend boş → mevcut yerel listeyi (cache ya da defaults) hesaba taşı
      _watchlistSymbols = local;
      final synced = await _apiService.saveWatchlist(local);
      if (synced != null && synced.isNotEmpty) _watchlistSymbols = synced;
      await _persistWatchlistLocal();
    }
    return changed();
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toUpperCase() != b[i].toUpperCase()) return false;
    }
    return true;
  }

  // izleme listesini yerel cache'e yaz (kullanıcıya özel key)
  Future<void> _persistWatchlistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _userId != null ? 'watchlist_$_userId' : 'watchlist';
    await prefs.setStringList(key, _watchlistSymbols);
  }

  // yerel cache + (giriş varsa) backend'e en-iyi-çaba yansıt. Bütün-liste PUT:
  // ekle/sil/sırala hepsini tek tip kapsar; backend hatası sessiz (UI bloklanmaz,
  // cache zaten yazıldı → offline toleransı).
  Future<void> _persistWatchlist() async {
    await _persistWatchlistLocal();
    if (_userId != null) {
      unawaited(
          _apiService.saveWatchlist(List<String>.from(_watchlistSymbols)));
    }
  }

  // auth değiştiğinde çağrılır (giriş/çıkış)
  // yeni userId ile veri yükle ya da temizle
  void updateUserAuth(int? newUserId, String? token) {
    if (_userId == newUserId && _token == token) return;
    _userId = newUserId;
    _token = token;
    if (newUserId != null) {
      _loadCurrencyPref();
      // Liste değişmediyse (yerel cache = sunucu listesi, olağan hâl) açılışta
      // ZATEN çekilmiş fiyatları ikinci kez çekme.
      _initWatchlist().then((changed) {
        if (changed || _marketData.isEmpty) loadMarketData();
      });
      // Dönem getirisini portföyden SONRA çek: ilk boyama portföyü beklemesin,
      // ayrıca sunucu kapanış serisini o arada ısıtmış olur.
      loadMyPortfolio().then((_) => loadPerformance());
    } else {
      // çıkış yapıldı, her şeyi sıfırla
      _myHoldings = [];
      _portfolioFromCache = false;
      _periodPerf = null;
      _snapshot = PortfolioSnapshot.empty();
      _coachAdvice = null;
      _coachError = null;
      // Uçuştaki istekler oturum değiştiğini görüp erken dönüyor → bayrakları
      // BURADA indir. Kalırsa: portföy spinner'ı asılı kalır ve `_perfLoading`
      // true takıldığı için tekrar girişte dönem getirisi HİÇ yüklenmez.
      _isPortfolioLoading = false;
      _perfLoading = false;
      _initWatchlist().then((_) => loadMarketData());
      _newsLoadStarted = false;
      notifyListeners();
    }
  }

  // hisseyi watchlist'e ekle
  Future<bool> addToWatchlist(String symbol) async {
    symbol = symbol.toUpperCase().trim();
    if (symbol.isEmpty) return false;
    if (_watchlistSymbols.contains(symbol)) return false; // zaten var

    _watchlistSymbols.add(symbol);
    await _persistWatchlist();
    await loadMarketData();
    return true;
  }

  // sola kaydırarak silme bu fonksiyonu çağırıyor.
  // Silinen sembolün SIRASINI döner (yoksa -1): "Geri Al" onu listenin
  // sonuna değil, kullanıcının koyduğu yere geri koysun.
  Future<int> removeFromWatchlist(String symbol) async {
    final index = _watchlistSymbols.indexOf(symbol);
    if (index < 0) return -1;
    _watchlistSymbols.removeAt(index);
    await _persistWatchlist();
    await loadMarketData();
    return index;
  }

  /// "Geri Al" — sembolü ESKİ sırasına döndürür. [index] < 0 ise sona eklenir.
  Future<void> restoreToWatchlist(String symbol, int index) async {
    symbol = symbol.toUpperCase().trim();
    if (symbol.isEmpty || _watchlistSymbols.contains(symbol)) return;
    final at = index < 0
        ? _watchlistSymbols.length
        : index.clamp(0, _watchlistSymbols.length);
    _watchlistSymbols.insert(at, symbol);
    await _persistWatchlist();
    await loadMarketData();
  }

  /// İzleme listesini yeniden sırala — drag-to-reorder için.
  /// newIndex Flutter'ın ReorderableListView formatına uyar (eski indexten büyükse
  /// kaldırma sonrası 1 azaltılır).
  Future<void> reorderWatchlist(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _watchlistSymbols.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _watchlistSymbols.removeAt(oldIndex);
    _watchlistSymbols.insert(newIndex, item);
    // marketData'yı da aynı sırayla yeniden düzenle ki UI anlık güncellesin
    final reordered = <StockModel>[];
    for (final s in _watchlistSymbols) {
      final found = _marketData.where((m) => m.symbol == s);
      if (found.isNotEmpty) reordered.add(found.first);
    }
    _marketData = reordered;
    await _persistWatchlist();
    notifyListeners();
  }

  // tüm verileri paralel yenile - Future.wait eş zamanlı bekler
  Future<void> refreshAll() async {
    await Future.wait([
      loadMarketData(),
      loadNewsData(),
      if (_userId != null) loadMyPortfolio(),
      if (_userId != null) loadPerformance(),
    ]);
  }

  // Fiyat cache'i sembol bazında GLOBAL (fiyatlar kullanıcıdan bağımsız) →
  // hesaplar arası paylaşılır, en iyi cache-hit. watchlist per-user kalır.
  static const String _marketCacheKey = 'market_cache_v1';

  // Son başarılı fiyatları sembol→json olarak diske yaz (mevcut cache'le
  // birleştir ki watchlist'ten çıkıp tekrar eklenen sembolün fiyatı kalsın).
  Future<void> _persistMarketCache(List<StockModel> data) async {
    if (data.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_marketCacheKey);
      final Map<String, dynamic> map =
          raw != null ? (jsonDecode(raw) as Map<String, dynamic>) : {};
      for (final m in data) {
        map[m.symbol] = m.toCacheJson();
      }
      await prefs.setString(_marketCacheKey, jsonEncode(map));
    } catch (_) {/* cache yazımı kritik değil — sessiz geç */}
  }

  // Diskteki cache'ten mevcut watchlist sırasına göre liste kur (eksik
  // sembol atlanır; ağ dönünce tamamlanır). Cache yoksa boş döner.
  Future<List<StockModel>> _loadMarketCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_marketCacheKey);
      if (raw == null) return [];
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <StockModel>[];
      for (final s in _watchlistSymbols) {
        final entry = map[s];
        if (entry is Map<String, dynamic>) {
          out.add(StockModel.fromCacheJson(entry));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> loadMarketData() async {
    // CACHE-FIRST (stale-while-revalidate): elde veri yoksa diskteki son
    // fiyatları ANINDA göster — skeleton/cold-start beklemesi yerine. Ağ
    // verisi arkadan akıp tazeler.
    if (_marketData.isEmpty) {
      final cached = await _loadMarketCache();
      if (cached.isNotEmpty) {
        _marketData = cached;
        _isLoading = false;
        notifyListeners();
      }
    }
    // Gösterecek hiçbir şey yoksa (cache de yok) skeleton göster.
    if (_marketData.isEmpty) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final fresh = await _marketRepo.fetchMany(_watchlistSymbols);
      if (fresh.isNotEmpty) {
        _marketData = fresh;
        _persistMarketCache(fresh);
        _marketError = null;
      } else if (_watchlistSymbols.isNotEmpty) {
        // İstenen sembol var ama HİÇ fiyat dönmedi → bu "liste boş" değil,
        // "veri alınamadı". Ekran ikisini ayırt edebilsin.
        _marketError = 'Fiyatlar alınamadı';
      } else {
        _marketError = null;
      }
    } catch (e) {
      _marketError = 'Piyasa verisi alınamadı';
      _setError('Piyasa verisi hatası: $e');
    }
    _isLoading = false;
    notifyListeners();
    _ensureFxRate();
    _scheduleNameRefresh();
  }

  // ── Şirket adı geç geliyor (ilk giriş) ───────────────────────────────
  // Batch fiyat ucu ad çözmek için AĞA ÇIKMAZ (açılış hızı): bilmediği adı
  // sembol olarak döner, adı arka planda çözer. Sonuç: ilk girişte
  // "MU / MU", "GOOG / GOOG" görünüyor, ancak sayfa YENİLENİNCE gerçek ad
  // geliyordu. Çözüm: adlar çözülene kadar SESSİZCE (spinner yok, hata
  // gösterimi yok) en fazla iki kez tazele. Ekranda zaten gösterilebilir
  // bir ad varsa (Altın, Bitcoin… → SymbolDisplay haritası) tazeleme YOK.
  static const int _maxNameRetries = 2;
  int _nameRetries = 0;
  Timer? _nameRetryTimer;
  bool _disposed = false;

  bool get _hasUnnamedSymbols => _marketData.any((m) =>
      SymbolDisplay.pickTitle(m.symbol, m.name).toUpperCase() ==
      m.symbol.toUpperCase());

  void _scheduleNameRefresh() {
    if (_nameRetries >= _maxNameRetries) return;
    if (!_hasUnnamedSymbols) return;
    _nameRetries++;
    _nameRetryTimer?.cancel();
    // Arka plan ad çözümü sunucuda sembol-sembol ilerliyor → ilk deneme 5 sn,
    // ikinci 10 sn sonra.
    _nameRetryTimer = Timer(Duration(seconds: 5 * _nameRetries), () async {
      try {
        final fresh = await _marketRepo.fetchMany(_watchlistSymbols);
        // İstek uçarken provider kapanmış olabilir (çıkış/hot restart) →
        // dispose sonrası notifyListeners Flutter'da hata fırlatır.
        if (_disposed || fresh.isEmpty) return;
        _marketData = fresh;
        _persistMarketCache(fresh);
        notifyListeners();
      } catch (_) {
        return; // sessiz: kullanıcı zaten fiyatları görüyor
      }
      _scheduleNameRefresh(); // hâlâ eksikse son bir deneme
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _nameRetryTimer?.cancel();
    super.dispose();
  }

  // Haber sekmesi ilk açıldığında tetiklenir (açılışta değil).
  bool _newsLoadStarted = false;

  /// Haber sekmesi görününce çağrılır: veri yoksa bir kez çeker.
  void ensureNewsLoaded() {
    if (_newsLoadStarted || _newsData.isNotEmpty) return;
    _newsLoadStarted = true;
    loadNewsData();
  }

  Future<void> loadNewsData({bool force = false}) async {
    _isNewsLoading = true;
    notifyListeners();
    try {
      _newsData = await _apiService.fetchNews(force: force);
      _newsError = null;
    } catch (e) {
      _newsError = 'Haberler yüklenemedi';
      // Sekmeye bir sonraki gelişte yeniden denensin; kalırsa uyuyan
      // sunucuya denk gelen ilk deneme sekmeyi oturum boyunca boş bırakır.
      _newsLoadStarted = false;
      _setError('Haberler yüklenemedi: $e');
    }
    _isNewsLoading = false;
    notifyListeners();
  }

  // ── Portföy yerel cache'i ────────────────────────────────────────────
  // Render ücretsiz katmanı boşta uyuyor; ilk istek 50sn+ sürebiliyor
  // (Render'ın kendi uyarısı). İzleme listesi zaten cache'liydi ama portföy
  // DEĞİLDİ → uygulama açılışında boş iskelet bekleniyordu. Son başarılı
  // portföy diske yazılır ve açılışta ANINDA gösterilir; canlı veri gelince
  // sessizce üstüne yazılır.
  static String _portfolioCacheKey(int userId) => 'portfolio_cache_v1_$userId';

  /// Gösterilen portföy diskten mi geldi (henüz tazelenmedi)?
  bool _portfolioFromCache = false;
  bool get portfolioFromCache => _portfolioFromCache;

  Future<void> _persistPortfolioCache(List<dynamic> raw) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_portfolioCacheKey(uid), jsonEncode(raw));
    } catch (_) {
      // Cache yazılamazsa akış bozulmaz — sadece açılış yine yavaş olur.
    }
  }

  Future<List<dynamic>?> _loadPortfolioCache() async {
    final uid = _userId;
    if (uid == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_portfolioCacheKey(uid));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Ham listeyi state'e uygular (canlı ve cache yolu AYNI dönüşümü kullansın
  /// diye tek yerde — iki kopya olsaydı biri tipli toplamları unuturdu).
  void _applyPortfolioRaw(List<dynamic> raw) {
    _myHoldings = raw;
    _snapshot = PortfolioSnapshot.fromHoldings([
      for (final item in raw)
        if (item is Map) Holding.fromJson(Map<String, dynamic>.from(item)),
    ]);
  }

  Future<void> loadMyPortfolio() async {
    // Kullanıcı kimliği BAŞTA yerel değişkene alınır ve her `await` sonrası
    // hâlâ aynı mı diye bakılır. Sebep (canlıda görüldü, 4 Eyl): oturum
    // düşünce (refresh de 401) `updateUserAuth(null)` `_userId`'yi
    // null'lıyor; disk cache'i beklerken bu olursa sonraki `_userId!`
    // patlıyordu → kullanıcıya "Portföy yüklenemedi: Null check operator
    // used on a null value". Ayrıca çıkıştan SONRA gelen yanıtın state'e
    // yazılması eski kullanıcının portföyünü ekranda bırakırdı.
    final uid = _userId;
    if (uid == null) return;
    // Elde bir şey yoksa önce diskteki son portföyü göster — kullanıcı soğuk
    // backend'i boş ekranla beklemesin.
    if (_myHoldings.isEmpty) {
      final cached = await _loadPortfolioCache();
      if (_userId != uid) return;
      if (cached != null && cached.isNotEmpty && _myHoldings.isEmpty) {
        _applyPortfolioRaw(cached);
        _portfolioFromCache = true;
        notifyListeners();
      }
    }
    _isPortfolioLoading = true;
    notifyListeners();
    try {
      final res = await _portfolioRepo.load(uid);
      if (_userId != uid) return;
      _myHoldings = res.raw; // ham liste — ekran geri uyumu (ZERO regresyon)
      _snapshot = res.snapshot; // tipli ₺ toplamlar
      _portfolioFromCache = false;
      _lastError = null;
      _portfolioError = null;
      unawaited(_persistPortfolioCache(res.raw));
    } catch (_) {
      // Soğuk fiyat cache'i ilk çağrıda yavaş olabilir → bir kez daha dene
      // (ikinci çağrı ısınmış cache'e düşer, anında döner). Yine olmazsa
      // MEVCUT pozisyonları KORU: geçici bir timeout'u "boş portföy" gibi
      // gösterme (kök sebep buydu — boş state ile timeout karışıyordu).
      try {
        final res = await _portfolioRepo.load(uid);
        if (_userId != uid) return;
        _myHoldings = res.raw;
        _snapshot = res.snapshot;
        _portfolioFromCache = false;
        _lastError = null;
        _portfolioError = null;
        unawaited(_persistPortfolioCache(res.raw));
      } catch (e) {
        // Oturum kapandıysa hata GÖSTERME: kullanıcı giriş ekranına gidiyor,
        // "portföy yüklenemedi" onun için gürültü.
        if (_userId != uid) return;
        // Cache'ten gelen pozisyonlar duruyorsa onları KORU: eski veri
        // göstermek boş ekrandan iyidir (rozet zaten "cache" diyor).
        if (_myHoldings.isEmpty) {
          _portfolioError = 'Portföy yüklenemedi';
          _setError('Portföy yüklenemedi: $e');
        }
      }
    }
    _isPortfolioLoading = false;
    notifyListeners();
  }

  // AI koçundan tavsiye al - biraz yavaş olabilir, loading state var
  Future<void> loadCoachAdvice() async {
    if (_userId == null) return;
    _isCoachLoading = true;
    _coachAdvice = null;
    _coachError = null;
    notifyListeners();

    final result = await _apiService.fetchCoachAdvice(_userId!);
    if (result.containsKey('advice')) {
      _coachAdvice = result['advice'] as String;
    } else {
      _coachError = result['error']?.toString() ?? 'AI yanıt vermedi';
    }

    _isCoachLoading = false;
    notifyListeners();
  }

  // Satış kaydı — kullanıcının GERÇEKTE yaptığı satışı deftere işler:
  // pozisyon azalır, SELL kaydı düşülür (sanal nakit yok).
  Future<TradeResult> recordSell(String symbol, num quantity) async {
    if (_userId == null) {
      return TradeResult(success: false, message: 'Giriş yapmalısın');
    }
    if (quantity <= 0) {
      return TradeResult(success: false, message: 'Lot adedi pozitif olmalı');
    }

    final result = await _apiService.sellStock(_userId!, symbol, quantity);
    if (result.success) await loadMyPortfolio();
    return result;
  }

  // Pozisyonu tamamen kaldır — YANLIŞ GİRİŞ düzeltmesi (satış değil).
  // Satışta lot düşer ve SELL kaydı geçmişte kalır; burada sembol hiç
  // eklenmemiş hâline döner (işlem kayıtları da silinir).
  Future<TradeResult> deletePosition(String symbol) async {
    if (_userId == null) {
      return TradeResult(success: false, message: 'Giriş yapmalısın');
    }
    final result = await _apiService.deletePosition(_userId!, symbol);
    if (result.success) await loadMyPortfolio();
    return result;
  }

  // pozisyon ekle (maliyet + lot) — gerçek portföyü deftere işler
  Future<TradeResult> executeImportPosition(
    String symbol,
    num quantity,
    double avgCost, {
    DateTime? acquiredAt,
  }) async {
    if (_userId == null) {
      return TradeResult(success: false, message: 'Giriş yapmalısın');
    }
    if (quantity <= 0 || avgCost <= 0) {
      return TradeResult(
          success: false, message: 'Lot ve maliyet pozitif olmalı');
    }

    final result = await _apiService.importPosition(
      userId: _userId!,
      symbol: symbol,
      quantity: quantity,
      avgCost: avgCost,
      acquiredAt: acquiredAt,
    );
    if (result.success) await loadMyPortfolio();
    return result;
  }

  /// Toplu manuel pozisyon girişi (portföyü tek seferde içe aktar). Her satırı
  /// sırayla yollar. Janklık olmasın diye portföyü her satırda
  /// değil, sonda TEK kez tazeler. Döner: (ok: başarı sayısı, failed: hatalar).
  Future<({int ok, List<(String, String)> failed})> executeImportPositions(
    List<({String symbol, num quantity, double avgCost, DateTime? acquiredAt})>
        items,
  ) async {
    if (_userId == null) {
      return (
        ok: 0,
        failed: items.map((e) => (e.symbol, 'Giriş yapmalısın')).toList()
      );
    }
    var ok = 0;
    final failed = <(String, String)>[];
    for (final it in items) {
      if (it.quantity <= 0 || it.avgCost <= 0) {
        failed.add((it.symbol, 'Lot ve maliyet pozitif olmalı'));
        continue;
      }
      final r = await _apiService.importPosition(
        userId: _userId!,
        symbol: it.symbol,
        quantity: it.quantity,
        avgCost: it.avgCost,
        acquiredAt: it.acquiredAt,
      );
      if (r.success) {
        ok++;
      } else {
        failed.add((it.symbol, r.message));
      }
    }
    if (ok > 0) await loadMyPortfolio();
    return (ok: ok, failed: failed);
  }

  // bu sembolden kaç lot elinde var?
  double heldQuantity(String symbol) {
    for (var h in _myHoldings) {
      if (h['symbol'] == symbol) {
        return (h['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return 0.0;
  }

  void _setError(String msg) {
    _lastError = msg;
    debugPrint(msg);
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }
}
