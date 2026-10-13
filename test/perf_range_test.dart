import 'package:flutter_test/flutter_test.dart';
import 'package:portly/models/holding.dart';

/// Ana ekran hero'su artık dört pencere sunuyor. Sözleşme: hafta/ay verisi
/// gelmediğinde SIFIR değil NULL olmalı — "+0,00%" basmak "hiç değişmemiş"
/// diye okunur, oysa veri yoktur.
void main() {
  test('PerfRange dört pencereyi kapsar', () {
    expect(PerfRange.values, hasLength(4));
    expect(PerfRange.values, containsAll(<PerfRange>[
      PerfRange.total,
      PerfRange.daily,
      PerfRange.week,
      PerfRange.month,
    ]));
  });

  test('PortfolioSnapshot.fromHoldings toplamları ₺ bazında kurar', () {
    final snap = PortfolioSnapshot.fromHoldings([
      Holding.fromJson(const {
        'symbol': 'AAPL',
        'quantity': 2,
        'average_cost': 100.0,
        'current_price': 110.0,
        'total_value': 220.0,
        'total_value_try': 8800.0,
        'total_cost_try': 8000.0,
        'pnl_try': 800.0,
        'currency': 'USD',
        'change_percent': 1.5,
      }),
    ]);
    expect(snap.totalHoldingsValueTry, closeTo(8800.0, 0.01));
    expect(snap.totalPnlTry, closeTo(800.0, 0.01));
    expect(snap.totalPnlPercent, closeTo(10.0, 0.01));
  });

  test('Holding günlük değişimi taşır (satırda "Bugün" için)', () {
    final h = Holding.fromJson(const {
      'symbol': 'LMT',
      'quantity': 3,
      'average_cost': 533.23,
      'current_price': 544.50,
      'total_value': 1633.5,
      'total_value_try': 78000.0,
      'total_cost_try': 76000.0,
      'pnl_try': 2000.0,
      'currency': 'USD',
      'change_percent': 2.11,
    });
    expect(h.dailyChangePct, closeTo(2.11, 0.001));
  });
}
