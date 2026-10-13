// ₺ K/Z'nin kur payı — backend `fx_gain_try` alanının istemci tarafındaki yolu.
//
// USD pozisyonların ₺ maliyeti artık ALIŞ günündeki kurla tutuluyor, yani
// kurdan gelen kâr toplam K/Z'nin içinde. Ekran "bunun ne kadarı kurdan geldi"
// diyebilsin diye alan pozisyondan snapshot'a taşınıyor. Burada kilitlenen:
// alan okunuyor, toplanıyor ve eksikse (eski yanıt) 0'a düşüyor — regresyon yok.

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/models/holding.dart';

Map<String, dynamic> _json({double? fxGain}) => {
      'symbol': 'AAPL',
      'quantity': 10,
      'average_cost': 100,
      'current_price': 100,
      'total_value': 1000,
      'pnl': 0,
      'pnl_percent': 0,
      'currency': 'USD',
      'total_value_try': 48000,
      'total_cost_try': 39000,
      'pnl_try': 9000,
      if (fxGain != null) 'fx_gain_try': fxGain,
    };

void main() {
  test('fx_gain_try okunur', () {
    expect(Holding.fromJson(_json(fxGain: 9000)).fxGainTry, 9000);
  });

  test('alan yoksa 0 — eski yanıt biçimi kırılmaz', () {
    expect(Holding.fromJson(_json()).fxGainTry, 0);
  });

  test('snapshot kur payını toplar', () {
    final snap = PortfolioSnapshot.fromHoldings([
      Holding.fromJson(_json(fxGain: 9000)),
      Holding.fromJson(_json(fxGain: 1500)),
      Holding.fromJson(_json()), // ₺ varlık / kuru bilinmeyen kayıt
    ]);
    expect(snap.totalFxGainTry, 10500);
    // Kur payı toplam K/Z'nin İÇİNDE — ayrı bir kalem olarak eklenmez.
    expect(snap.totalPnlTry, 27000);
  });
}
