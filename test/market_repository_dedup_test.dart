// Açılışta yinelenen `/market/prices` isteği (uçuş-içi dedup).
//
// Bağlam: canlı ölçümde 6 açılış isteğinin 2'si fazlalıktı — 16 sembollük
// batch İKİ kez gidiyordu. `fetchOne`'da uçuş-içi dedup vardı, `fetchMany`'de
// yoktu; iki tüketici (izleme listesi kurulumu + auth sonrası tazeleme) aynı
// anda çağırınca ikisi de ağa çıkıyordu.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/data/market_repository.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/services/api_service.dart';

class _CountingApi extends ApiService {
  int calls = 0;
  final List<Completer<List<StockModel>?>> pending = [];

  @override
  Future<List<StockModel>?> fetchStockPrices(List<String> symbols) {
    calls++;
    final c = Completer<List<StockModel>?>();
    pending.add(c);
    return c.future;
  }

  void completeAll(List<String> symbols) {
    for (final c in pending) {
      c.complete([
        for (final s in symbols)
          StockModel.fromJson(
              {'symbol': s, 'current_price': 1.0, 'change_percent': 0.0})
      ]);
    }
    pending.clear();
  }
}

void main() {
  test('eşzamanlı aynı liste → TEK istek, iki çağrı da sonucu alır', () async {
    final api = _CountingApi();
    final repo = MarketRepository(api);

    final f1 = repo.fetchMany(['AAPL', 'GC=F']);
    final f2 = repo.fetchMany(['aapl', 'gc=f']); // büyük/küçük harf fark etmez

    expect(api.calls, 1, reason: 'ikinci çağrı da ağa çıktı');
    api.completeAll(['AAPL', 'GC=F']);
    final r1 = await f1;
    final r2 = await f2;
    expect(r1.map((m) => m.symbol).toList(), ['AAPL', 'GC=F']);
    expect(r2.map((m) => m.symbol).toList(), ['AAPL', 'GC=F']);
  });

  test('farklı liste ayrı istektir (dedup fazla eşleşmiyor)', () async {
    final api = _CountingApi();
    final repo = MarketRepository(api);

    final f1 = repo.fetchMany(['AAPL']);
    final f2 = repo.fetchMany(['AAPL', 'MSFT']);

    expect(api.calls, 2);
    api.completeAll(['AAPL']);
    await Future.wait([f1, f2]);
  });

  test('istek bittikten sonraki çağrı tazeyi çeker (cache DEĞİL)', () async {
    final api = _CountingApi();
    final repo = MarketRepository(api);

    final f1 = repo.fetchMany(['AAPL']);
    api.completeAll(['AAPL']);
    await f1;

    final f2 = repo.fetchMany(['AAPL']);
    expect(api.calls, 2, reason: 'dedup tamamlanan isteği tutmamalı');
    api.completeAll(['AAPL']);
    await f2;
  });

  test('boş liste ağa çıkmaz', () async {
    final api = _CountingApi();
    expect(await MarketRepository(api).fetchMany([]), isEmpty);
    expect(api.calls, 0);
  });
}
