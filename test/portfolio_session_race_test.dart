// Oturum düşerken portföy yükleme yarışı (4 Eylül 2026, 6. tur).
//
// Canlıda görüldü (Safari konsolu): /auth/refresh de 401 dönüp oturum
// kapandığında ekranda "Portföy yüklenemedi: Null check operator used on a
// null value" çıkıyordu. Kök sebep: `loadMyPortfolio` disk cache'ini
// beklerken `updateUserAuth(null)` `_userId`'yi null'lıyor, sonraki
// `_userId!` patlıyordu. İkinci risk: çıkıştan SONRA dönen yanıtın state'e
// yazılması (eski kullanıcının portföyü ekranda kalırdı).

import 'package:flutter_test/flutter_test.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('yükleme sırasında çıkış yapılırsa çökmez ve hata göstermez', () async {
    final p = PortfolioProvider();
    p.updateUserAuth(1, 'token');       // yükleme başlar (ağ testte başarısız)
    p.updateUserAuth(null, null);       // tam o sırada oturum düşer
    // Yükleme akışının bitmesini bekle: eskiden burada TypeError atıyordu.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(p.lastError, isNull);
    expect(p.myHoldings, isEmpty);
  });

  test('çıkışta loading bayrakları iner (tekrar giriş kilitlenmesin)', () async {
    final p = PortfolioProvider();
    p.updateUserAuth(1, 'token');
    p.updateUserAuth(null, null);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // `_perfLoading` asılı kalsaydı tekrar girişte dönem getirisi HİÇ
    // yüklenmezdi; `_isPortfolioLoading` asılı kalsaydı spinner dönerdi.
    expect(p.isPortfolioLoading, isFalse);
    expect(p.perfLoading, isFalse);
  });
}
