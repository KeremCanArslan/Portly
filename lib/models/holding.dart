/// Tipli portföy pozisyonu + portföy özeti.
///
/// Module F / H1: client tarafında `total_cost_try` UYDURMASINI (qty*avg)
/// bitirir. Backend Module A/C sonrası `total_value_try`, `total_cost_try`,
/// `pnl_try` alanlarını HER ZAMAN gönderir (C1 sözleşme testi + cihaz
/// doğrulaması). Eksik maliyet artık qty*avg ile uydurulMAZ; eksikse o
/// pozisyon maliyete 0 katkı verir ve snapshot `costComplete=false`
/// işaretlenir (pratikte erişilemez — backend garantisi).
///
/// ZERO regresyon: sayısal sonuç eski provider getter'larıyla birebir
/// aynıdır (backend tüm *_try alanlarını gönderdiği için); yalnızca
/// tehlikeli uydurma kol kaldırıldı.
class Holding {
  final String symbol;
  final double quantity;
  final double averageCost;
  final double currentPrice;
  final double totalValue; // kendi para birimi (yalnız satır gösterimi)
  final double pnl; // kendi para birimi
  final double pnlPercent;
  final String currency;
  final double? totalValueTry;
  final double? totalCostTry;
  final double? pnlTry;

  /// ₺ K/Z'nin KUR kaynaklı kısmı (`native maliyet × [canlı kur − alış kuru]`).
  /// Maliyet artık alış günündeki kurla değerlendiği için kur kazancı K/Z'ye
  /// giriyor; bu alan onu ayırır ki ekran "bunun ne kadarı kurdan geldi"
  /// sorusunu cevaplayabilsin. ₺ varlıkta ve alış kuru bilinmeyen eski
  /// kayıtta 0.
  final double fxGainTry;
  final double dailyChangePct; // hissenin bugünkü % değişimi (günlük performans)
  /// Günlük değişim GERÇEK mi? Backend fiyatı bilip değişimi bilmediğinde
  /// (altın/gümüş spot kaynağı) `change_available: false` gönderir → 0'ı
  /// "hiç oynamamış" diye göstermeyelim, günlük toplamlara da katmayalım.
  final bool changeAvailable;

  /// Ekranların ham `h['...']` erişimi için (kademeli geçiş, geri uyum).
  final Map<String, dynamic> raw;

  const Holding({
    required this.symbol,
    required this.quantity,
    required this.averageCost,
    required this.currentPrice,
    required this.totalValue,
    required this.pnl,
    required this.pnlPercent,
    required this.currency,
    required this.totalValueTry,
    required this.totalCostTry,
    required this.pnlTry,
    required this.raw,
    this.fxGainTry = 0,
    this.dailyChangePct = 0,
    this.changeAvailable = true,
  });

  /// Tek-birim (₺) değer — eski getter'la aynı: total_value_try yoksa
  /// native total_value'ya düş.
  double get valueTry => totalValueTry ?? totalValue;

  /// Tek-birim (₺) K/Z — eski getter'la aynı: pnl_try yoksa native pnl.
  double get pnlValueTry => pnlTry ?? pnl;

  bool get hasCostTry => totalCostTry != null;

  factory Holding.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
    double? dn(dynamic v) => v == null ? null : (v as num?)?.toDouble();
    return Holding(
      symbol: j['symbol'] as String? ?? '',
      quantity: d(j['quantity']),
      averageCost: d(j['average_cost']),
      currentPrice: d(j['current_price']),
      totalValue: d(j['total_value']),
      pnl: d(j['pnl']),
      pnlPercent: d(j['pnl_percent']),
      currency: j['currency'] as String? ?? 'USD',
      totalValueTry: dn(j['total_value_try']),
      totalCostTry: dn(j['total_cost_try']),
      pnlTry: dn(j['pnl_try']),
      fxGainTry: d(j['fx_gain_try']),
      dailyChangePct: d(j['change_percent']),
      changeAvailable: j['change_available'] as bool? ?? true,
      raw: j,
    );
  }
}

/// Portföyün ₺ bazlı toplamları — tek hesap noktası.
class PortfolioSnapshot {
  final List<Holding> holdings;
  final double totalHoldingsValueTry;
  final double totalPnlTry;
  final double totalCostTry;
  final double totalPnlPercent;

  /// Toplam ₺ K/Z'nin kur kaynaklı kısmı (pozisyonların `fxGainTry` toplamı).
  final double totalFxGainTry;

  /// Tüm pozisyonlarda backend total_cost_try geldiyse true. false ise
  /// yüzde, eksik maliyetli pozisyonları HARİÇ tutar (uydurma yerine
  /// dürüst eksik) — pratikte hep true (backend garantisi, C1 testi).
  final bool costComplete;

  const PortfolioSnapshot({
    required this.holdings,
    required this.totalHoldingsValueTry,
    required this.totalPnlTry,
    required this.totalCostTry,
    required this.totalPnlPercent,
    required this.costComplete,
    this.totalFxGainTry = 0,
  });

  factory PortfolioSnapshot.empty() => const PortfolioSnapshot(
        holdings: [],
        totalHoldingsValueTry: 0,
        totalPnlTry: 0,
        totalCostTry: 0,
        totalPnlPercent: 0,
        costComplete: true,
      );

  factory PortfolioSnapshot.fromHoldings(List<Holding> hs) {
    double v = 0, p = 0, c = 0, fx = 0;
    bool complete = true;
    for (final h in hs) {
      v += h.valueTry;
      p += h.pnlValueTry;
      fx += h.fxGainTry;
      if (h.hasCostTry) {
        c += h.totalCostTry!;
      } else {
        complete = false; // qty*avg UYDURMA YOK (eski hatalı koldu)
      }
    }
    final pct = c == 0 ? 0.0 : (p / c) * 100;
    return PortfolioSnapshot(
      holdings: hs,
      totalHoldingsValueTry: v,
      totalPnlTry: p,
      totalCostTry: c,
      totalPnlPercent: pct,
      costComplete: complete,
      totalFxGainTry: fx,
    );
  }
}

/// Ana ekran hero'sundaki performans penceresi.
///
/// `total` alış maliyetine göre (yıllar öncesine bakabilir), `daily` tek güne.
/// Aradaki `week`/`month` sunucudan gelir — kapanış serisi zaten cache'te
/// olduğu için ek piyasa isteği doğurmaz.
enum PerfRange { total, daily, week, month }
