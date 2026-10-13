// Oturum İÇİNDE 401 kurtarması (3 Eylül, 5. tur).
//
// Access token 60 dakikalık, token yenilemesi ise YALNIZ açılışta yapılıyordu:
// uygulama bundan uzun açık kalınca portföy · sohbet · izleme · haber uçlarının
// hepsi 401'e düşüyor, ancak uygulama yeniden başlatılınca düzeliyordu (telefonda
// PWA arka plandan dönünce düzelmiyordu). Aşağıdaki durumlar `_AuthRetryClient`
// sözleşmesini sabitliyor.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portly/services/api_service.dart';

void main() {
  setUp(() {
    ApiService.onUnauthorized = null;
    ApiService.authToken = null;
  });

  tearDown(() => ApiService.onUnauthorized = null);

  test('401 → token yenilenir, istek YENİ token ile bir kez tekrarlanır',
      () async {
    final sentTokens = <String?>[];
    var refreshCount = 0;
    ApiService.onUnauthorized = (stale) async {
      refreshCount++;
      return 'taze-token';
    };

    final client = ApiService.retryClientForTest(MockClient((request) async {
      sentTokens.add(request.headers['Authorization']);
      return request.headers['Authorization'] == 'Bearer taze-token'
          ? http.Response('{"ok":true}', 200)
          : http.Response('{"detail":"Not authenticated"}', 401);
    }));

    final response = await client.get(
      Uri.parse('https://ornek/api/v1/portfolio/1'),
      headers: {'Authorization': 'Bearer bayat-token'},
    );

    expect(response.statusCode, 200);
    expect(refreshCount, 1);
    expect(sentTokens, ['Bearer bayat-token', 'Bearer taze-token']);
  });

  test('yenileme kancasına 401 alan İSTEĞİN token\'ı verilir', () async {
    String? seen;
    ApiService.onUnauthorized = (stale) async {
      seen = stale;
      return null;
    };
    final client = ApiService.retryClientForTest(
        MockClient((_) async => http.Response('', 401)));

    await client.get(Uri.parse('https://ornek/x'),
        headers: {'Authorization': 'Bearer bayat-token'});

    // "Bearer " öneki soyulmuş ham token — AuthProvider elindekiyle
    // karşılaştırıp gereksiz ikinci yenilemeyi eleyebilsin diye.
    expect(seen, 'bayat-token');
  });

  test('yenileme tutmazsa 401 çağırana döner, istek tekrarlanmaz', () async {
    var calls = 0;
    ApiService.onUnauthorized = (_) async => null; // oturum kapandı
    final client = ApiService.retryClientForTest(MockClient((_) async {
      calls++;
      return http.Response('{"detail":"Not authenticated"}', 401);
    }));

    final response = await client.get(Uri.parse('https://ornek/x'),
        headers: {'Authorization': 'Bearer bayat'});

    expect(response.statusCode, 401);
    expect(calls, 1);
  });

  test('tekrarlanan istek yine 401 alırsa DÖNGÜYE girmez', () async {
    var calls = 0;
    var refreshCount = 0;
    ApiService.onUnauthorized = (_) async {
      refreshCount++;
      return 'yeni';
    };
    final client = ApiService.retryClientForTest(MockClient((_) async {
      calls++;
      return http.Response('', 401);
    }));

    final response = await client.get(Uri.parse('https://ornek/x'),
        headers: {'Authorization': 'Bearer bayat'});

    expect(response.statusCode, 401);
    expect(calls, 2); // ilk istek + TEK tekrar
    expect(refreshCount, 1);
  });

  test('aynı anda 401 alan istekler TEK yenileme turu paylaşır', () async {
    var refreshCount = 0;
    final gate = Completer<void>();
    ApiService.onUnauthorized = (_) async {
      refreshCount++;
      await gate.future; // ilk tur bitmeden ikinci istek de 401 alsın
      return 'taze';
    };
    final client = ApiService.retryClientForTest(MockClient((request) async {
      return request.headers['Authorization'] == 'Bearer taze'
          ? http.Response('{}', 200)
          : http.Response('', 401);
    }));

    final first = client.get(Uri.parse('https://ornek/a'),
        headers: {'Authorization': 'Bearer bayat'});
    final second = client.get(Uri.parse('https://ornek/b'),
        headers: {'Authorization': 'Bearer bayat'});
    await Future<void>.delayed(Duration.zero);
    gate.complete();

    expect((await first).statusCode, 200);
    expect((await second).statusCode, 200);
    // Refresh token tek kullanımlık (sunucu tarafında atomik iptal): ikinci bir
    // tur ilkinin token'ını geçersiz kılardı.
    expect(refreshCount, 1);
  });

  test('token\'sız istek 401 alırsa yenileme denenmez (giriş/şifre sıfırlama)',
      () async {
    var refreshCount = 0;
    ApiService.onUnauthorized = (_) async {
      refreshCount++;
      return 'taze';
    };
    final client = ApiService.retryClientForTest(
        MockClient((_) async => http.Response('{"detail":"bad password"}', 401)));

    final response = await client.post(Uri.parse('https://ornek/auth/login'));

    expect(response.statusCode, 401);
    expect(refreshCount, 0);
  });

  test('dosya yükleme (multipart) tekrarlanamaz ama oturum yine kurtarılır',
      () async {
    var calls = 0;
    var refreshCount = 0;
    ApiService.onUnauthorized = (_) async {
      refreshCount++;
      return 'taze';
    };
    final client = ApiService.retryClientForTest(MockClient((_) async {
      calls++;
      return http.Response('', 401);
    }));

    final request = http.MultipartRequest(
        'POST', Uri.parse('https://ornek/trading/parse-screenshot'))
      ..headers['Authorization'] = 'Bearer bayat'
      ..files.add(http.MultipartFile.fromBytes('file', [1, 2, 3],
          filename: 'ss.png'));
    final streamed = await client.send(request);

    expect(streamed.statusCode, 401); // kullanıcı tekrar dener
    expect(calls, 1); // gövde replay EDİLMEZ
    expect(refreshCount, 1); // ama sonraki istekler için oturum tazelendi
  });

  test('200 dönen istekte yenileme kancasına hiç dokunulmaz', () async {
    var refreshCount = 0;
    ApiService.onUnauthorized = (_) async {
      refreshCount++;
      return 'taze';
    };
    final client = ApiService.retryClientForTest(
        MockClient((_) async => http.Response('{"ok":1}', 200)));

    final response = await client.get(Uri.parse('https://ornek/x'),
        headers: {'Authorization': 'Bearer gecerli'});

    expect(response.statusCode, 200);
    expect(refreshCount, 0);
  });

  test('kanca tanımlı değilse (test/başlangıç anı) 401 aynen döner', () async {
    ApiService.onUnauthorized = null;
    final client = ApiService.retryClientForTest(
        MockClient((_) async => http.Response('', 401)));

    final response = await client.get(Uri.parse('https://ornek/x'),
        headers: {'Authorization': 'Bearer bayat'});

    expect(response.statusCode, 401);
  });
}
