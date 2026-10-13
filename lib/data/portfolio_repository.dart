import 'package:portly/models/holding.dart';
import 'package:portly/services/api_service.dart';

/// Portföy veri erişim katmanı (Module F-core).
///
/// - TEK parse noktası: JSON → tipli `Holding`/`PortfolioSnapshot`.
///   Ekranlar hâlâ ham listeyi alır (kademeli geçiş → ZERO regresyon).
/// - Uçuş-içi (in-flight) dedup: aynı userId için EŞZAMANLI iki istek
///   tek HTTP'ye iner. IndexedStack ile 4 sekme açılışta aynı portföyü
///   isteyince israfı keser. TTL/staleness YOK → açık yenileme her zaman
///   tazeyi alır (TTL bilinçli olarak ileri UI batch'ine ertelendi;
///   tazelik göstergeleri o batch'te tasarlanacak).
class PortfolioLoadResult {
  final List<dynamic> raw; // ekran geri uyumu (h['...'])
  final PortfolioSnapshot snapshot; // tipli toplamlar
  const PortfolioLoadResult(this.raw, this.snapshot);
}

class PortfolioRepository {
  final ApiService _api;
  PortfolioRepository(this._api);

  final Map<int, Future<PortfolioLoadResult>> _inFlight = {};

  Future<PortfolioLoadResult> load(int userId) {
    final existing = _inFlight[userId];
    if (existing != null) return existing; // eşzamanlı çağrıyı birleştir
    final fut = _fetch(userId);
    _inFlight[userId] = fut;
    // `.ignore()` şart: whenComplete TÜREV bir future döndürür ve çağrı
    // başarısız olursa o türevin hatasını kimse yakalamaz → istek her
    // patladığında konsola "Unhandled exception" düşerdi (hata zaten
    // `fut`'u bekleyen tarafta ele alınıyor).
    fut.whenComplete(() => _inFlight.remove(userId)).ignore();
    return fut;
  }

  Future<PortfolioLoadResult> _fetch(int userId) async {
    final raw = await _api.fetchUserPortfolio(userId);
    final holdings = <Holding>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        holdings.add(Holding.fromJson(item));
      } else if (item is Map) {
        holdings.add(Holding.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return PortfolioLoadResult(raw, PortfolioSnapshot.fromHoldings(holdings));
  }
}
