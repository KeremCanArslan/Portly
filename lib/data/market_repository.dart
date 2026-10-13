import 'package:portly/models/stock_model.dart';
import 'package:portly/services/api_service.dart';

/// Piyasa verisi erişim katmanı (Module F-core).
///
/// Uçuş-içi (in-flight) dedup: aynı sembol EŞZAMANLI istenirse tek
/// HTTP'ye iner. IndexedStack ile birden çok sekme açılışta aynı sembolü
/// isteyince (örn. izleme listesi + ana ekran) yinelenen ağ isteğini
/// keser. TTL/staleness YOK → her açık yenileme tazeyi alır (ZERO
/// regresyon; eski fetchPopularStocks davranışı sıra dahil birebir).
class MarketRepository {
  final ApiService _api;
  MarketRepository(this._api);

  final Map<String, Future<StockModel?>> _inFlight = {};

  Future<StockModel?> fetchOne(String symbol) {
    final key = symbol.toUpperCase();
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final fut = _api.fetchSingleStock(symbol);
    _inFlight[key] = fut;
    fut
        .whenComplete(() => _inFlight.remove(key))
        .ignore(); // bkz. portfolio_repository
    return fut;
  }

  /// Çok sembol fiyatı — TEK HTTP isteği (`/market/prices`).
  ///
  /// Eskiden sembol başına ayrı istek atıyordu: 8 sembollü izleme listesi
  /// açılışta 8 HTTP demekti ve her biri sunucuda ad çözümü tetikliyordu.
  /// Yeni toplu uç yanıt vermezse (eski sunucu / geçici hata) otomatik
  /// olarak eski sembol-sembol yola düşülür → davranış aynı, hız farklı.
  /// Sıra korunur, null'lar elenir.
  Future<List<StockModel>> fetchMany(List<String> symbols) {
    if (symbols.isEmpty) return Future.value(const []);
    // Uçuş-içi dedup fetchOne'da vardı, BURADA YOKTU → iki tüketici aynı anda
    // çağırınca 16 sembollük batch açılışta İKİ kez ağa çıkıyordu (canlıda
    // ölçüldü: 6 açılış isteğinin 2'si fazlalık). Anahtar = istenen sembol
    // listesi (sıra dahil: dönen liste sırası isteğe bağlı).
    final key = symbols.map((s) => s.toUpperCase()).join(',');
    final existing = _inFlightMany[key];
    if (existing != null) return existing;
    final fut = _fetchManyUncached(symbols);
    _inFlightMany[key] = fut;
    fut.whenComplete(() => _inFlightMany.remove(key)).ignore();
    return fut;
  }

  final Map<String, Future<List<StockModel>>> _inFlightMany = {};

  Future<List<StockModel>> _fetchManyUncached(List<String> symbols) async {
    final batch = await _api.fetchStockPrices(symbols);
    if (batch != null && batch.isNotEmpty) {
      // İstenen sırayı koru (sunucu sırayı zaten koruyor; savunmacı davran).
      final bySymbol = {for (final m in batch) m.symbol.toUpperCase(): m};
      final ordered = <StockModel>[];
      for (final s in symbols) {
        final m = bySymbol[s.toUpperCase()];
        if (m != null) ordered.add(m);
      }
      return ordered;
    }
    final results = await Future.wait(symbols.map(fetchOne));
    return results.whereType<StockModel>().toList();
  }
}
