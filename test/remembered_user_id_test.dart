// Açılıştaki fazla `/market/prices` isteğinin kökü: giriş bilgisi gelmeden
// önce izleme listesi GENEL `watchlist` anahtarından (→ varsayılan 8 sembol)
// okunuyor, token gelince gerçek liste (16 sembol) ile ikinci kez fiyat
// çekiliyordu. Çözüm: açılışta "beni hatırla" oturumunun kullanıcı kimliğini
// diskten okuyup `watchlist_<id>` anahtarını kullanmak.
//
// Buradaki asıl risk ÇIKIŞ hâli: çıkıştan sonra eski kullanıcının listesi
// okunmamalı. Aşağıdaki durumların hepsi o sınırı sabitliyor.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/providers/auth_provider.dart';

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

const _user = {'id': 7, 'email': 'umut@mail.com'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kayıtlı oturum → kullanıcı kimliği döner', () async {
    final prefs = await _prefs({
      'auth_remember': true,
      'auth_token': 'jwt',
      'auth_user': jsonEncode(_user),
    });
    expect(AuthProvider.rememberedUserId(prefs), 7);
  });

  test('çıkış yapılmış (kullanıcı kaydı silinmiş) → null', () async {
    // logout()/_clearSession() token + kullanıcı kaydını siler.
    final prefs = await _prefs({'auth_remember': true});
    expect(AuthProvider.rememberedUserId(prefs), isNull);
  });

  test('"beni hatırla" kapalı → null', () async {
    final prefs = await _prefs({
      'auth_remember': false,
      'auth_token': 'jwt',
      'auth_user': jsonEncode(_user),
    });
    expect(AuthProvider.rememberedUserId(prefs), isNull);
  });

  test('token yok / boş → null', () async {
    final prefs = await _prefs({
      'auth_remember': true,
      'auth_token': '',
      'auth_user': jsonEncode(_user),
    });
    expect(AuthProvider.rememberedUserId(prefs), isNull);
  });

  test('bozuk kullanıcı kaydı → null (patlamaz)', () async {
    final prefs = await _prefs({
      'auth_remember': true,
      'auth_token': 'jwt',
      'auth_user': '{bozuk',
    });
    expect(AuthProvider.rememberedUserId(prefs), isNull);
  });

  test('kimlik alanı yok/yanlış tip → null', () async {
    final prefs = await _prefs({
      'auth_remember': true,
      'auth_token': 'jwt',
      'auth_user': jsonEncode({'email': 'umut@mail.com', 'id': '7'}),
    });
    expect(AuthProvider.rememberedUserId(prefs), isNull);
  });

  test('anahtar hiç yokken varsayılan "beni hatırla" açık sayılır', () async {
    // `auth_remember` yazılmamışsa AuthProvider._bootstrap true varsayar;
    // burası da aynı varsayımı kullanmalı ki davranış ayrışmasın.
    final prefs = await _prefs({
      'auth_token': 'jwt',
      'auth_user': jsonEncode(_user),
    });
    expect(AuthProvider.rememberedUserId(prefs), 7);
  });
}
