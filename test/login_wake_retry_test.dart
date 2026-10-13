// Uyku modundaki sunucuda giriş (4 Eylül 2026, 6. tur).
//
// Kerem: "giriş yaparken önce sunucu hatası verdi, tekrar basınca giriş
// yapabildim." Render ücretsiz katmanda instance boşta uyur ve ilk istek
// ~30-50 sn sürer; login timeout'u 30 sn'ydi → ilk deneme TimeoutException'a
// düşüp ekrana ham istisna basıyordu ("Sunucu hatası: TimeoutException...").
// Kullanıcının yaptığı ikinci basış artık OTOMATİK.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portly/services/api_service.dart';

void main() {
  // baseUrl .env okuyor; testte dosya yok → boş yapılandırmayla başlat
  // (prod URL sabiti devreye girer, istek zaten sahte istemciye gidiyor).
  setUpAll(() => dotenv.loadFromString(envString: 'USE_PROD_API=true'));

  test('zaman aşımında istek bir kez otomatik tekrarlanır', () async {
    var deneme = 0;
    final client = MockClient((req) async {
      deneme++;
      if (deneme == 1) throw TimeoutException('uyuyor');
      return http.Response(
          jsonEncode({
            'access_token': 'a',
            'refresh_token': 'r',
            'user': {'id': 1, 'email': 'x@y.z'}
          }),
          200);
    });

    final res = await ApiService.postAwakeForTest(
        client, '/auth/login', {'email': 'x@y.z', 'password': 'p'});

    expect(deneme, 2, reason: 'ilk istek sunucuyu uyandırır, ikincisi cevap alır');
    expect(res.statusCode, 200);
  });

  test('ikinci deneme de düşerse hata yükselir (sonsuz tekrar yok)', () async {
    var deneme = 0;
    final client = MockClient((req) async {
      deneme++;
      throw TimeoutException('hâlâ uyuyor');
    });

    await expectLater(
      ApiService.postAwakeForTest(
          client, '/auth/login', {'email': 'x@y.z', 'password': 'p'}),
      throwsA(isA<TimeoutException>()),
    );
    expect(deneme, 2);
  });
}
