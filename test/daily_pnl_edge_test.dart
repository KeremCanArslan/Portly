// Günlük K/Z: dünkü değer geri çıkarılamadığında ne yapılır (4 Eyl 2026, 8. tur).
//
// `prev = valueTry / (1 + günlükYüzde/100)`. Bu bölüm iki durumda anlamını
// yitiriyor:
//   d == 0  → tam -%100. Eski kod `prev = valueTry` diyordu. ÖLÇÜLDÜ: fiyat 0
//             olduğu için değer de 0 → ₺ K/Z iki kodda da 0, yani "zarar
//             gizleniyor" İDDİASI DOĞRU DEĞİL. Fark YÜZDE paydasında: tutarsız
//             veri (değer > 0 ama değişim -%100) gelirse eski kod o değeri
//             paydaya katıp günlük yüzdeyi seyreltiyordu.
//   d < 0   → -%100'den kötü, yani kaynak verisi bozuk. ASIL BOZUK DURUM: bölme
//             NEGATİF bir "dünkü değer" üretiyor, sahte KAZANÇ yazıyordu
//             (aşağıdaki testte +10 ₺ yerine +93 ₺).
//
// Doğru davranış: dünkü değer bilinmiyorsa pozisyon hesaba HİÇ katılmaz —
// `change_available: false` ile aynı kural. Maliyeti dünkü değer yerine
// koymak (bir modelin önerisiydi) günlük K/Z'yi sessizce TOPLAM K/Z'ye
// çevirirdi.

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiService {
  _Api(this.portfolio);
  final List<dynamic> portfolio;

  @override
  Future<List<String>?> getWatchlist() async => null;

  @override
  Future<List<String>?> saveWatchlist(List<String> symbols) async => symbols;

  @override
  Future<List<dynamic>> fetchUserPortfolio(int userId) async => portfolio;

  @override
  Future<Map<String, dynamic>?> fetchPortfolioPerformance(int userId) async =>
      null;
}

Map<String, dynamic> _pos(
  String symbol, {
  required double valueTry,
  required double changePct,
  bool changeAvailable = true,
  double costTry = 1000,
}) =>
    {
      'symbol': symbol,
      'quantity': 1,
      'average_cost': costTry,
      'current_price': valueTry,
      'total_value': valueTry,
      'total_value_try': valueTry,
      'total_cost_try': costTry,
      'currency': 'TRY',
      'change_percent': changePct,
      'change_available': changeAvailable,
    };

Future<PortfolioProvider> _yukle(List<dynamic> pozisyonlar) async {
  final p = PortfolioProvider(api: _Api(pozisyonlar));
  p.updateUserAuth(1, 'token');
  await Future<void>.delayed(const Duration(milliseconds: 60));
  return p;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('normal pozisyon: dünkü değer geri çıkarılır', () async {
    // 110 ₺, bugün +%10 → dün 100 ₺ → günlük K/Z +10 ₺.
    final p = await _yukle([_pos('AAA', valueTry: 110, changePct: 10)]);

    expect(p.holdings, hasLength(1));
    expect(p.dailyPnl, closeTo(10, 0.001));
    expect(p.dailyPnlPercent, closeTo(10, 0.001));
  });

  test('-%100 pozisyon maliyetiyle "zarar" uydurmaz', () async {
    final p = await _yukle([
      _pos('IYI', valueTry: 110, changePct: 10),
      _pos('SIFIR', valueTry: 0, changePct: -100, costTry: 5000),
    ]);

    // Not: bu senaryoda ESKİ kod da 10 ₺ veriyordu (değer 0 → katkı 0).
    // Testin koruduğu şey, önerilen ama YANLIŞ düzeltme: maliyeti dünkü
    // değer sayıp -5000 ₺ "günlük zarar" yazmak.
    expect(p.dailyPnl, closeTo(10, 0.001));
    expect(p.dailyPnlPercent, closeTo(10, 0.001));
  });

  test('tutarsız veri (-%100 ama değer > 0) günlük yüzdeyi seyreltmez',
      () async {
    final p = await _yukle([
      _pos('IYI', valueTry: 110, changePct: 10),
      _pos('TUTARSIZ', valueTry: 110, changePct: -100),
    ]);

    // Eski kod paydaya 110 ₺ ekliyordu → %10 yerine %4,76 görünüyordu.
    expect(p.dailyPnl, closeTo(10, 0.001));
    expect(p.dailyPnlPercent, closeTo(10, 0.001));
  });

  test('-%100\'den kötü (bozuk veri) SAHTE KAZANÇ yazmaz', () async {
    final p = await _yukle([
      _pos('IYI', valueTry: 110, changePct: 10),
      _pos('BOZUK', valueTry: 50, changePct: -250),
    ]);

    // d = -1,5 → prev = -33,3 ₺ → katkı 50-(-33,3) = +83,3 ₺.
    // Eski kod bu yüzden 10 ₺ yerine 93,33 ₺ "günlük kazanç" gösteriyordu.
    expect(p.dailyPnl, closeTo(10, 0.001));
    expect(p.dailyPnlPercent, greaterThan(0));
  });

  test('günlük değişimi bilinmeyen pozisyon eskisi gibi hesap dışı', () async {
    final p = await _yukle([
      _pos('IYI', valueTry: 110, changePct: 10),
      _pos('ALTIN', valueTry: 900, changePct: 0, changeAvailable: false),
    ]);

    expect(p.dailyPnl, closeTo(10, 0.001));
  });

  test('hiçbir pozisyonun günlük değişimi bilinmiyorsa yüzde 0 döner',
      () async {
    final p = await _yukle([
      _pos('SIFIR', valueTry: 0, changePct: -100),
    ]);

    expect(p.dailyPnl, 0);
    expect(p.dailyPnlPercent, 0);
  });
}
