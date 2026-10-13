import 'package:portly/utils/symbol_display.dart';
import 'package:portly/utils/money.dart';

class StockModel {
  final String symbol;
  final String name;
  final String price;
  final String change;
  final bool isUp;
  final double rawPrice;
  final String currency;
  final bool isTurkish;
  // Pre/post-market (yalnız ABD hisseleri, tek-sembol /price yolunda dolar):
  // marketState 'PRE'|'REGULAR'|'POST'|'CLOSED'|null; extended* yalnız PRE/POST'ta.
  // Geçici veri → cache'e yazılmaz (bayat pre-market göstermeyelim), canlı fetch doldurur.
  final String? marketState;
  final double? extendedPrice;
  final double? extendedChangePct;
  /// Günlük değişim GERÇEK mi? false ise rozet "—" ve nötr renk olmalı
  /// (backend fiyatı bilip değişimi bilmediğinde: altın/gümüş spot kaynağı).
  final bool changeAvailable;

  StockModel({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.isUp,
    required this.rawPrice,
    required this.currency,
    required this.isTurkish,
    this.marketState,
    this.extendedPrice,
    this.extendedChangePct,
    this.changeAvailable = true,
  });

  factory StockModel.fromJson(Map<String, dynamic> json,
      {String? defaultSymbol}) {
    final symbol = json['symbol'] as String? ?? defaultSymbol ?? 'UNKNOWN';
    final changePct = (json['change_percent'] as num?)?.toDouble() ?? 0.0;
    final changeLive = json['change_available'] as bool? ?? true;
    // TEFAS fonu ve fiziki altın da ₺ ile kote edilir.
    final isTurkish = symbol.endsWith('.IS') ||
        symbol.endsWith('.TR') ||
        SymbolDisplay.isFund(symbol) ||
        SymbolDisplay.isPhysical(symbol);
    // Döviz pariteleri (USDTRY=X, EURTRY=X) ₺ ile kote → currencyOf'a bırak.
    final currency = SymbolDisplay.currencyOf(symbol);

    return StockModel(
      symbol: symbol,
      name: json['company_name'] as String? ?? symbol,
      price: (json['current_price'] as num?)
              ?.toStringAsFixed(SymbolDisplay.priceDecimals(
                  symbol, (json['current_price'] as num).toDouble())) ??
          "0.00",
      change: changeLive ? "${formatPctSigned(changePct, decimals: 2)}%" : "—",
      isUp: changePct >= 0,
      rawPrice: (json['current_price'] as num?)?.toDouble() ?? 0.0,
      currency: currency,
      isTurkish: isTurkish,
      marketState: json['market_state'] as String?,
      extendedPrice: (json['extended_price'] as num?)?.toDouble(),
      extendedChangePct: (json['extended_change_percent'] as num?)?.toDouble(),
      changeAvailable: changeLive,
    );
  }

  /// SharedPreferences cache'i için sade serileştirme (cache-first açılış).
  /// fromJson backend şemasını bekler; bunlar zaten işlenmiş alanları saklar.
  Map<String, dynamic> toCacheJson() => {
        'symbol': symbol,
        'name': name,
        'price': price,
        'change': change,
        'isUp': isUp,
        'rawPrice': rawPrice,
        'currency': currency,
        'isTurkish': isTurkish,
        'changeAvailable': changeAvailable,
      };

  factory StockModel.fromCacheJson(Map<String, dynamic> json) => StockModel(
        symbol: json['symbol'] as String? ?? 'UNKNOWN',
        name: json['name'] as String? ?? (json['symbol'] as String? ?? '—'),
        price: json['price'] as String? ?? '0.00',
        change: json['change'] as String? ?? '0.00%',
        isUp: json['isUp'] as bool? ?? true,
        rawPrice: (json['rawPrice'] as num?)?.toDouble() ?? 0.0,
        currency: json['currency'] as String? ?? '₺',
        isTurkish: json['isTurkish'] as bool? ?? false,
        changeAvailable: json['changeAvailable'] as bool? ?? true,
      );
}
