// "Veri YOK" ile "veri ALINAMADI" ayrımı (4 Eylül 2026, 8. tur).
//
// Tarama bulgusu: `ApiService` hata durumunda null/boş liste döndürüyor,
// ekranlar bunu boş-durumla aynı sayıyordu. Sonuç: ağ hatasında 38 pozisyonu
// olan kullanıcıya "BAŞLANGIÇ — ilk hisseni ekle", dolu izleme listesine
// "Listen boş", alarmları olan kullanıcıya "henüz alarm yok" deniyordu.
// Sağlıklı yolun bayrağı KAPALI tutması da bu testin konusu: aksi hâlde
// gerçekten boş portföyde hata kartı çıkardı.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/widgets/load_error_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  _FakeApi({this.portfolioThrows = false, this.pricesThrow = false});

  bool portfolioThrows;
  bool pricesThrow;
  List<dynamic> portfolio = const [];
  int portfolioCalls = 0;

  @override
  Future<List<String>?> getWatchlist() async => null; // ağ yok

  @override
  Future<List<String>?> saveWatchlist(List<String> symbols) async => symbols;

  @override
  Future<List<StockModel>?> fetchStockPrices(List<String> symbols) async {
    if (pricesThrow) throw Exception('ağ yok');
    return [
      for (final s in symbols)
        StockModel.fromJson(
            {'symbol': s, 'current_price': 1.0, 'change_percent': 0.0})
    ];
  }

  @override
  Future<List<dynamic>> fetchUserPortfolio(int userId) async {
    portfolioCalls++;
    if (portfolioThrows) throw Exception('zaman aşımı');
    return portfolio;
  }

  @override
  Future<Map<String, dynamic>?> fetchPortfolioPerformance(int userId) async =>
      null;
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('portföy çekimi patlarsa portfolioError DOLAR (boş portföy değil)',
      () async {
    final api = _FakeApi(portfolioThrows: true);
    final p = PortfolioProvider(api: api);
    p.updateUserAuth(1, 'token');
    await _settle();

    expect(p.myHoldings, isEmpty);
    expect(p.portfolioError, isNotNull,
        reason: 'ekran "portföyün boş" değil "yüklenemedi" demeli');
  });

  test('portföy GERÇEKTEN boşsa portfolioError BOŞ kalır', () async {
    final api = _FakeApi();
    final p = PortfolioProvider(api: api);
    p.updateUserAuth(1, 'token');
    await _settle();

    expect(p.myHoldings, isEmpty);
    expect(p.portfolioError, isNull,
        reason: 'yeni kullanıcıya hata kartı değil BAŞLANGIÇ rehberi çıkmalı');
  });

  test('hatadan sonra başarılı yükleme bayrağı temizler', () async {
    final api = _FakeApi(portfolioThrows: true);
    final p = PortfolioProvider(api: api);
    p.updateUserAuth(1, 'token');
    await _settle();
    expect(p.portfolioError, isNotNull);

    api.portfolioThrows = false;
    api.portfolio = [
      {'symbol': 'AAPL', 'quantity': 1, 'average_price': 100.0}
    ];
    await p.loadMyPortfolio();

    expect(p.portfolioError, isNull);
    expect(p.myHoldings, hasLength(1));
  });

  test('fiyat çekimi patlarsa marketError DOLAR', () async {
    final api = _FakeApi(pricesThrow: true);
    final p = PortfolioProvider(api: api);
    await _settle();
    await p.loadMarketData();

    expect(p.marketData, isEmpty);
    expect(p.marketError, isNotNull,
        reason: 'dolu izleme listesine "Listen boş" denmemeli');
  });

  test('fiyatlar gelirse marketError BOŞ kalır', () async {
    final api = _FakeApi();
    final p = PortfolioProvider(api: api);
    await _settle();
    await p.loadMarketData();

    expect(p.marketData, isNotEmpty);
    expect(p.marketError, isNull);
  });

  testWidgets('LoadErrorCard başlığı + Tekrar Dene basar ve geri çağırır',
      (t) async {
    var tiklandi = 0;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: LoadErrorCard(
          title: 'Portföy yüklenemedi',
          onRetry: () => tiklandi++,
        ),
      ),
    ));
    await t.pump();

    expect(find.text('Portföy yüklenemedi'), findsOneWidget);
    await t.tap(find.text('Tekrar Dene'));
    expect(tiklandi, 1);
  });

  testWidgets('onRetry verilmezse buton çıkmaz', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: LoadErrorCard(title: 'Bir şey olmadı')),
    ));
    await t.pump();

    expect(find.text('Tekrar Dene'), findsNothing);
  });
}
