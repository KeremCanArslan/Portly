import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/models/stock_model.dart';

// Cache-first açılış (stale-while-revalidate) sembol fiyatlarını
// SharedPreferences'a JSON olarak yazıp okur. Bu tur, yazıp-okuma
// sırasında HİÇBİR alanın bozulmadığını (kuruş, işaret, para birimi)
// jsonEncode/Decode köprüsünden geçirerek kilitler.
void main() {
  StockModel sample({
    String symbol = 'AAPL',
    String price = '193.42',
    String change = '+1.27%',
    bool isUp = true,
    double rawPrice = 193.42,
    String currency = r'$',
    bool isTurkish = false,
  }) =>
      StockModel(
        symbol: symbol,
        name: 'Apple Inc.',
        price: price,
        change: change,
        isUp: isUp,
        rawPrice: rawPrice,
        currency: currency,
        isTurkish: isTurkish,
      );

  void expectSame(StockModel a, StockModel b) {
    expect(b.symbol, a.symbol);
    expect(b.name, a.name);
    expect(b.price, a.price);
    expect(b.change, a.change);
    expect(b.isUp, a.isUp);
    expect(b.rawPrice, a.rawPrice);
    expect(b.currency, a.currency);
    expect(b.isTurkish, a.isTurkish);
  }

  test('toCacheJson → fromCacheJson tam round-trip (alan kaybı yok)', () {
    final original = sample();
    final restored = StockModel.fromCacheJson(original.toCacheJson());
    expectSame(original, restored);
  });

  test('jsonEncode/Decode köprüsü (gerçek disk yolu) bozmuyor', () {
    final original = sample(
      symbol: 'THYAO.IS',
      price: '312,50'.replaceAll(',', '.'),
      change: '-2.04%',
      isUp: false,
      rawPrice: 312.5,
      currency: '₺',
      isTurkish: true,
    );
    final encoded = jsonEncode(original.toCacheJson());
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    expectSame(original, StockModel.fromCacheJson(decoded));
  });

  test('eksik/bozuk alanlar güvenli varsayılana düşer (crash yok)', () {
    final partial = StockModel.fromCacheJson({'symbol': 'XU100.IS'});
    expect(partial.symbol, 'XU100.IS');
    expect(partial.name, 'XU100.IS'); // ad yoksa sembole düşer
    expect(partial.price, '0.00');
    expect(partial.rawPrice, 0.0);
    expect(partial.isUp, true);

    final empty = StockModel.fromCacheJson({});
    expect(empty.symbol, 'UNKNOWN');
    expect(empty.rawPrice, 0.0);
  });
}
