// Haber sekmesi uyuyan sunucuda boş kalıyordu (24 Ekim 2026).
//
// Kerem: "giriş yaparken çok geç açılıyor, haberler kısmı çalışmıyor."
// `fetchNews` hata/zaman aşımında BOŞ LİSTE dönüyordu → provider bunu "haber
// yok" sayıyor, "yüklenemedi — tekrar dene" kartı hiç çıkmıyordu; üstüne
// `ensureNewsLoaded` bir daha denemediği için sekme oturum boyunca boş
// kalıyordu. Artık hata yukarı çıkar, sekmeye dönünce yeniden denenir.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  bool newsThrows = true;
  int newsCalls = 0;

  @override
  Future<List<String>?> getWatchlist() async => null;

  @override
  Future<List<StockModel>?> fetchStockPrices(List<String> symbols) async =>
      const [];

  @override
  Future<List<dynamic>> fetchNews({bool force = false, String? query}) async {
    newsCalls++;
    if (newsThrows) throw Exception('zaman aşımı');
    return [
      {'title': 'Haber', 'url': 'https://ornek.com/1'}
    ];
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'USE_PROD_API=true'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ApiService haber uçları hatayı YUTMAZ', () {
    test('fetchNews: HTTP 500 → istisna', () async {
      ApiService.clientForTest = MockClient((_) async => http.Response('', 500));
      await expectLater(ApiService().fetchNews(), throwsA(isA<Exception>()));
    });

    test('fetchNewsForSymbols: ağ hatası → istisna', () async {
      ApiService.clientForTest =
          MockClient((_) async => throw http.ClientException('uyuyor'));
      await expectLater(ApiService().fetchNewsForSymbols(['en|AAPL']),
          throwsA(isA<Exception>()));
    });

    test('fetchNews: 200 → liste', () async {
      ApiService.clientForTest = MockClient((_) async => http.Response(
          jsonEncode([
            {'title': 'Haber'}
          ]),
          200));
      expect(await ApiService().fetchNews(), hasLength(1));
    });
  });

  test('haber çekimi patlarsa newsError DOLAR (boş liste değil)', () async {
    final api = _FakeApi();
    final p = PortfolioProvider(api: api);
    p.ensureNewsLoaded();
    await _settle();

    expect(p.newsData, isEmpty);
    expect(p.newsError, isNotNull,
        reason: 'ekran "haber bulunamadı" değil "yüklenemedi" demeli');
    expect(p.isNewsLoading, isFalse);
  });

  test('başarısız ilk çekimden sonra sekmeye dönünce TEKRAR denenir',
      () async {
    final api = _FakeApi();
    final p = PortfolioProvider(api: api);
    p.ensureNewsLoaded();
    await _settle();

    api.newsThrows = false; // sunucu uyandı
    p.ensureNewsLoaded();
    await _settle();

    expect(api.newsCalls, 2);
    expect(p.newsData, hasLength(1));
    expect(p.newsError, isNull);
  });

  test('başarılı çekimden sonra sekmeye dönmek yeniden İSTEK ATMAZ', () async {
    final api = _FakeApi()..newsThrows = false;
    final p = PortfolioProvider(api: api);
    p.ensureNewsLoaded();
    await _settle();
    p.ensureNewsLoaded();
    await _settle();

    expect(api.newsCalls, 1);
  });
}
