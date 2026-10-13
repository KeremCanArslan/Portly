import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:portly/models/stock_model.dart';

/// AI Koç SSE akışı için iptal edilebilir tutamaç. [cancel] çağrısı altta yatan
/// HTTP bağlantısını gerçekten kapatır (provider iptal/dispose'da kullanır).
class ChatStreamHandle {
  final http.Client _client;
  bool _cancelled = false;
  ChatStreamHandle(this._client);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _client.close();
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Oturum içi 401 kurtarması: token'lı bir istek 401 alırsa access token BİR KEZ
/// yenilenir ve istek tekrarlanır.
///
/// Neden gerekliydi: access token 60 dakikalık; token yenilemesi YALNIZ açılışta
/// (`AuthProvider._bootstrap`/`_revalidateSession`) yapılıyordu. Uygulama bundan
/// uzun süre açık kalınca portföy · sohbet · izleme · haber uçlarının hepsi 401'e
/// düşüyor ve ancak uygulama yeniden başlatılınca düzeliyordu (webde sayfa
/// yenileme kurtarıyordu, telefonda PWA arka plandan dönünce kurtarmıyordu).
///
/// Sınır: yalnız gövdesi tekrar gönderilebilen istekler (`http.Request`)
/// tekrarlanır. Dosya yükleme (`MultipartRequest`) tekrarlanamaz — orada token
/// yine de yenilenir (oturum kurtulur), yükleme 401 döner ve kullanıcı tekrar
/// dener.
class _AuthRetryClient extends http.BaseClient {
  final http.Client _inner;
  _AuthRetryClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (response.statusCode != 401) return response;
    // Token'sız istek (giriş/şifre sıfırlama) → yenilenecek bir oturum yok.
    final stale =
        request.headers['Authorization'] ?? request.headers['authorization'];
    if (stale == null) return response;
    final fresh =
        await ApiService.refreshSessionOnce(stale.replaceFirst('Bearer ', ''));
    if (fresh == null) return response; // yenileme tutmadı → oturum kapandı
    if (request is! http.Request) return response; // multipart tekrarlanamaz
    await response.stream.drain<void>(); // ilk yanıtın gövdesi serbest kalsın
    return _inner.send(ApiService.retryRequest(request, fresh));
  }

  @override
  void close() => _inner.close();
}

class ApiService {
  static String? authToken;

  /// 401 alındığında access token'ı yenileyen kanca — `AuthProvider` doldurur.
  /// Parametre: 401 alan isteğin kullandığı (bayat) token. Dönüş: yeni access
  /// token; null ise oturum kapatılmıştır (kullanıcı giriş ekranına düşer).
  static Future<String?> Function(String? staleToken)? onUnauthorized;

  /// Aynı anda 401 alan N istek tek bir yenileme turu paylaşır. Yoksa her istek
  /// ayrı `/auth/refresh` çağırır; refresh token tek kullanımlık olduğu için
  /// (sunucu tarafında atomik iptal) ikinci tur kendi kendini geçersiz kılardı.
  static Future<String?>? _refreshFlight;

  static Future<String?> refreshSessionOnce(String? staleToken) {
    final handler = onUnauthorized;
    if (handler == null) return Future.value(null);
    final inFlight = _refreshFlight;
    if (inFlight != null) return inFlight;
    final started =
        handler(staleToken).whenComplete(() => _refreshFlight = null);
    _refreshFlight = started;
    return started;
  }

  /// 401 alan isteğin yeni token'la birebir kopyası (tek tekrar; kopya doğrudan
  /// iç istemciye gider, yeniden 401 gelirse döngü olmaz).
  static http.Request retryRequest(http.Request original, String token) {
    final copy = http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..bodyBytes = original.bodyBytes
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    copy.headers['Authorization'] = 'Bearer $token';
    return copy;
  }

  static final http.Client _client = _AuthRetryClient();

  /// Testler 401→yenile→tekrarla davranışını sahte bir iç istemciyle sürsün diye.
  @visibleForTesting
  static http.Client retryClientForTest(http.Client inner) =>
      _AuthRetryClient(inner);

  // Release build'lerde KESİN prod URL — .env asset parse'ı APK'da
  // sessizce fail edebiliyor (telefonda "127.0.0.1" fallback'e düşüp
  // bağlanamıyordu). Compile-time sabit, dotenv.env bypass.
  static const String _kProdBaseUrl =
      'https://portly-app-api.onrender.com/api/v1';

  static Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  static String get baseUrl {
    // Release/profile build → compile-time prod URL (her platformda).
    // Debug + .env'de USE_PROD_API=true → yine prod URL.
    if (kReleaseMode || dotenv.env['USE_PROD_API'] == 'true') {
      return _kProdBaseUrl;
    }

    if (kIsWeb) {
      return dotenv.env['API_BASE_URL_LOCAL'] ?? "http://127.0.0.1:8000/api/v1";
    }
    if (Platform.isAndroid) {
      return dotenv.env['API_BASE_URL_ANDROID'] ??
          "http://10.0.2.2:8000/api/v1";
    }
    if (Platform.isIOS) {
      return dotenv.env['API_BASE_URL_NETWORK'] ??
          "http://127.0.0.1:8000/api/v1";
    }
    return dotenv.env['API_BASE_URL_LOCAL'] ?? "http://127.0.0.1:8000/api/v1";
  }

  // Cold start (Render free tier ~30-60sn) için tolerant timeout.
  // Warm istekler tipik 200-500ms; bu sınır yalnız soğuk açılışta önemli.
  static const Duration _timeout = Duration(seconds: 30);

  // ============== AUTH ==============
  /// Render ücretsiz katmanda sunucu boşta uyur ve ilk istek ~30-50 sn sürer.
  /// Giriş/kayıt bu yüzden ilk denemede timeout'a düşüp "Sunucu hatası:
  /// TimeoutException" gösteriyordu; kullanıcı butona ikinci kez basınca
  /// çalışıyordu (Kerem, 4 Eyl: "giriş yaparken önce sunucu hatası verdi,
  /// tekrar basınca giriş yapabildim"). Burada o ikinci basış OTOMATİK:
  /// zaman aşımında istek bir kez daha denenir — bu sırada sunucu uyanmış olur.
  static const Duration _wakeTimeout = Duration(seconds: 45);

  Future<http.Response> _postAwake(String path, Map<String, dynamic> body) =>
      _postAwakeWith(http.Client(), path, body);

  /// Testler uyanma tekrarını sahte istemciyle sürsün diye ayrık.
  @visibleForTesting
  static Future<http.Response> postAwakeForTest(
          http.Client client, String path, Map<String, dynamic> body) =>
      ApiService()._postAwakeWith(client, path, body);

  Future<http.Response> _postAwakeWith(
      http.Client client, String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final payload = jsonEncode(body);
    const headers = {'Content-Type': 'application/json'};
    try {
      return await client
          .post(uri, headers: headers, body: payload)
          .timeout(_wakeTimeout);
    } on TimeoutException {
      // Tek tekrar: ilk istek sunucuyu zaten uyandırdı.
      return await client
          .post(uri, headers: headers, body: payload)
          .timeout(_wakeTimeout);
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _postAwake(
          '/auth/login', {'email': email, 'password': password});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'access_token': data['access_token'],
          'refresh_token': data['refresh_token'],
          'user': data['user'],
        };
      } else {
        final body = jsonDecode(response.body);
        return {'success': false, 'error': body['detail'] ?? 'Giriş başarısız'};
      }
    } on SocketException {
      return {'success': false, 'error': 'İnternet bağlantısı yok'};
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Sunucu yanıt vermedi. Uyku modundan uyanıyor olabilir — '
            'birkaç saniye sonra tekrar dene.'
      };
    } catch (e) {
      debugPrint('login hata: $e');
      return {
        'success': false,
        'error': 'Giriş yapılamadı. Tekrar dener misin?'
      };
    }
  }

  Future<Map<String, dynamic>> register(
      String email, String password, String fullName) async {
    try {
      final response = await _postAwake('/auth/register', {
        'email': email,
        'password': password,
        'full_name': fullName,
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'access_token': data['access_token'],
          'refresh_token': data['refresh_token'],
          'user': data['user'],
        };
      } else {
        final body = jsonDecode(response.body);
        return {
          'success': false,
          'error': body['detail'] ?? 'Kayıt başarısız',
        };
      }
    } on SocketException {
      return {'success': false, 'error': 'İnternet bağlantısı yok'};
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Sunucu yanıt vermedi. Uyku modundan uyanıyor olabilir — '
            'birkaç saniye sonra tekrar dene.'
      };
    } catch (e) {
      debugPrint('register hata: $e');
      return {
        'success': false,
        'error': 'Kayıt yapılamadı. Tekrar dener misin?'
      };
    }
  }

  /// Refresh token'ı kullanarak yeni access + refresh token alır.
  /// Başarısız olursa null döner — çağıran logout yapmalı.
  Future<Map<String, String>?> refreshAccessToken(String refreshToken) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refreshToken}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'access_token': data['access_token'] as String,
          'refresh_token': data['refresh_token'] as String,
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchMe(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw ApiException('Token geçersiz', statusCode: response.statusCode);
  }

  Future<Map<String, dynamic>?> updateRiskProfile(String riskProfile) async {
    try {
      final response = await _client
          .patch(
            Uri.parse('$baseUrl/auth/risk-profile'),
            headers: _headers,
            body: jsonEncode({'risk_profile': riskProfile}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('updateRiskProfile hata: $e');
    }
    return null;
  }

  /// Oturum açıkken şifre değiştirir.
  ///
  /// Sunucu diğer cihazların refresh token'larını iptal ettiği için yanıtta
  /// BU cihaz için taze bir refresh token gelir — çağıran onu saklamazsa
  /// kullanıcı access token'ın ömrü (60 dk) dolunca dışarı düşer.
  Future<Map<String, dynamic>> changePassword(
      String currentPassword, String newPassword) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/auth/change-password'),
            headers: _headers,
            body: jsonEncode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(_timeout);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return {'success': true, 'refresh_token': body['refresh_token']};
      }
      return {
        'success': false,
        'error': body['detail'] is String
            ? body['detail'] as String
            : 'Şifre değiştirilemedi',
      };
    } on SocketException {
      return {'success': false, 'error': 'İnternet bağlantısı yok'};
    } on TimeoutException {
      return {
        'success': false,
        'error': 'Sunucu yanıt vermedi. Birkaç saniye sonra tekrar dene.'
      };
    } catch (e) {
      debugPrint('changePassword hata: $e');
      return {'success': false, 'error': 'Şifre değiştirilemedi'};
    }
  }

  /// Hesabı ve tüm verileri kalıcı olarak siler (KVKK silme hakkı).
  ///
  /// Şifre sunucuda tekrar doğrulanır — token tek başına yetmez, çünkü
  /// işlemin geri dönüşü yok.
  Future<Map<String, dynamic>> deleteAccount(String password) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/auth/delete-account'),
            headers: _headers,
            body: jsonEncode({'password': password}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return {'success': true};
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'error': body['detail'] is String
            ? body['detail'] as String
            : 'Hesap silinemedi',
      };
    } on SocketException {
      return {'success': false, 'error': 'İnternet bağlantısı yok'};
    } on TimeoutException {
      return {'success': false, 'error': 'Sunucu yanıt vermedi'};
    } catch (e) {
      debugPrint('deleteAccount hata: $e');
      return {'success': false, 'error': 'Hesap silinemedi'};
    }
  }

  /// Sunucuya çıkış bildirir (access token kara listeye alınır).
  ///
  /// [token] verilirse statik `authToken` yerine o kullanılır: `AuthProvider`
  /// çıkışta bellek içi oturumu ÖNCE düşürüyor (arka planda dönen oturum
  /// doğrulaması geri yazmasın diye), o yüzden bu isteğin başlığını taşıyacak
  /// token'ı elle geçirir. Token'sız gidilirse uç 401 döner ve kara liste
  /// kaydı hiç oluşmazdı.
  Future<void> logoutFromServer({String? token}) async {
    try {
      final headers = token == null
          ? _headers
          : {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            };
      await http
          .post(Uri.parse('$baseUrl/auth/logout'), headers: headers)
          .timeout(_timeout);
    } catch (_) {
      // Sunucuya ulaşılamazsa sessizce devam et — yerel temizlik yine yapılır.
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/forgot-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final body = jsonDecode(response.body);
      return {'success': false, 'error': body['detail'] ?? 'İstek başarısız'};
    } on SocketException {
      return {'success': false, 'error': 'İnternet bağlantısı yok'};
    } catch (e) {
      return {'success': false, 'error': 'Sunucu hatası: $e'};
    }
  }

  Future<Map<String, dynamic>> resetPassword(
      String email, String code, String newPassword) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/reset-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'code': code,
              'new_password': newPassword,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return {'success': true};
      }
      final body = jsonDecode(response.body);
      return {'success': false, 'error': body['detail'] ?? 'İstek başarısız'};
    } on SocketException {
      return {'success': false, 'error': 'İnternet bağlantısı yok'};
    } catch (e) {
      return {'success': false, 'error': 'Sunucu hatası: $e'};
    }
  }

  // ============== STOCKS ==============
  Future<List<StockModel>> fetchPopularStocks(List<String> symbols) async {
    if (symbols.isEmpty) return [];
    final results = await Future.wait(symbols.map((s) => fetchSingleStock(s)));
    return results.whereType<StockModel>().toList();
  }

  /// TEK istekte çok sembol fiyatı (`/market/prices?symbols=A,B,C`).
  ///
  /// Açılışın en pahalı parçası buydu: izleme listesi sembol başına ayrı
  /// `/market/price/{sym}` çağırıyordu (8 sembol = 8 HTTP; her biri sunucuda
  /// ad çözümü için ek Yahoo isteği). Sunucu artık batch + yedek kaynak
  /// zinciriyle tek yanıt veriyor. Uç yoksa/hata verirse `null` döner →
  /// çağıran eski sembol-sembol yola düşer (geriye dönük güvenli).
  Future<List<StockModel>?> fetchStockPrices(List<String> symbols) async {
    if (symbols.isEmpty) return [];
    try {
      final q = symbols.map(Uri.encodeComponent).join(',');
      final response = await _client
          .get(Uri.parse('$baseUrl/market/prices?symbols=$q'),
              headers: _headers)
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final quotes = (data['quotes'] as List?) ?? const [];
      return [
        for (final q in quotes) StockModel.fromJson(q as Map<String, dynamic>)
      ];
    } catch (e) {
      debugPrint('fetchStockPrices hata: $e');
      return null;
    }
  }

  Future<StockModel?> fetchSingleStock(String symbol) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/market/price/$symbol'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return StockModel.fromJson(data, defaultSymbol: symbol);
      }
    } catch (e) {
      debugPrint('fetchSingleStock($symbol) hata: $e');
    }
    return null;
  }

  // ============== USER DATA ==============
  Future<List<dynamic>> fetchUserPortfolio(int userId) async {
    // Ağır agregat: N pozisyon için canlı fiyat çekimi → soğuk cache'te
    // 10s yetmiyor (~10-12s sürebiliyor). 30s ver. Hata/timeout'u YUTMA,
    // FIRLAT: çağıran (provider) geçici bir timeout'u "boş portföy" sanıp
    // "İlk yatırımını bekliyor" göstermesin. Gerçek boş portföy yalnız
    // 200 + [] ile temsil edilir.
    final response = await _client
        .get(Uri.parse('$baseUrl/portfolio/$userId'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('portfolio HTTP ${response.statusCode}');
  }

  Future<Map<String, dynamic>> fetchSectorBreakdown(int userId) async {
    // Hata/timeout'u YUTMA, FIRLAT: çağıran geçici bir hatayı "sektör yok"
    // sanıp boş-state göstermesin. Gerçek boş yalnız 200 + sectors:[] .
    final response = await _client
        .get(Uri.parse('$baseUrl/portfolio/$userId/sectors'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('sectors HTTP ${response.statusCode}');
  }

  /// Dönem getirisi (hafta/ay) — ana ekran hero'su. Kapanış serisi sunucuda
  /// zaten cache'te olduğu için ucuz; hata YUTULUR (hero "—" gösterir).
  Future<Map<String, dynamic>?> fetchPortfolioPerformance(int userId) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/portfolio/$userId/performance'),
              headers: _headers)
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchPortfolioPerformance hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchPortfolioHealth(int userId) async {
    // Hata/timeout'u FIRLAT (çağıran retry gösterir). Gerçek "veri yok"
    // 200 + has_data:false ile gelir → o ayrı, sessizce gizlenir.
    final response = await _client
        .get(Uri.parse('$baseUrl/portfolio/$userId/health'), headers: _headers)
        .timeout(_timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('health HTTP ${response.statusCode}');
  }

  Future<Map<String, dynamic>?> fetchFinancials(String symbol) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/coach/financials/$symbol'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchFinancials hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchDividends(int userId) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/portfolio/$userId/dividends'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchDividends hata: $e');
    }
    return null;
  }

  /// Kuru çalıştırma: collect ÇALIŞTIRMADAN şu an tahsil edilebilir kesin
  /// tutar/olaylar. Şekil collectDividends ile aynı (credited/events/
  /// new_balance) ama hiçbir mutasyon yapmaz.
  Future<Map<String, dynamic>?> fetchDividendsPreview(int userId) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/portfolio/$userId/dividends/preview'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchDividendsPreview hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> collectDividends(int userId) async {
    try {
      final response = await _client
          .post(Uri.parse('$baseUrl/portfolio/$userId/dividends/collect'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('collectDividends hata: $e');
    }
    return null;
  }

  Future<List<dynamic>> fetchNews({bool force = false, String? query}) async {
    try {
      final params = <String>[];
      if (force) params.add('force=true');
      if (query != null && query.trim().isNotEmpty) {
        params.add('query=${Uri.encodeComponent(query.trim())}');
      }
      final url = params.isEmpty
          ? '$baseUrl/news/latest'
          : '$baseUrl/news/latest?${params.join('&')}';
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint('fetchNews hata: $e');
      return [];
    }
  }

  /// Portföyüm/İzleme: çok-sembollü haber TEK istekte (`?q=...&q=...`).
  /// Sunucu sorguları paralel çekip tek batch enrich yapar — eski sembol-başına
  /// N çağrı (N LLM) gecikmesi biter.
  Future<List<dynamic>> fetchNewsForSymbols(List<String> queries,
      {bool force = false}) async {
    if (queries.isEmpty) return const [];
    try {
      final params = [
        for (final q in queries)
          if (q.trim().isNotEmpty) 'q=${Uri.encodeComponent(q.trim())}',
        if (force) 'force=true',
      ];
      final url = '$baseUrl/news/for-symbols?${params.join('&')}';
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          // Uç, sembol başına Google News RSS çekiyor (soğuk cache'te ~10 sn) —
          // üstüne Render ücretsiz katmanın uyanması binince 30 sn sınırı
          // İSTEMCİDE doluyordu: haber gelmiş olsa bile ekran BOŞ kalıyordu.
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint('fetchNewsForSymbols hata: $e');
      return [];
    }
  }

  // ============== PORTFÖY KAYITLARI ==============
  // Satış kaydı — kullanıcının gerçekte yaptığı satışı deftere işler
  // (pozisyon azalır, SELL kaydı düşülür; sanal emir motoru yok).
  Future<TradeResult> sellStock(int userId, String symbol, num quantity) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/trading/order'),
            headers: _headers,
            body: jsonEncode({
              'user_id': userId,
              'symbol': symbol,
              'quantity': quantity.toDouble(),
              'transaction_type': 'SELL',
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return TradeResult(success: true, message: 'Satış kaydedildi');
      } else {
        final body = jsonDecode(response.body);
        return TradeResult(
            success: false, message: body['detail'] ?? 'Sunucu hatası');
      }
    } on SocketException {
      return TradeResult(success: false, message: 'İnternet bağlantısı yok');
    } catch (e) {
      return TradeResult(success: false, message: 'Kayıt iletilemedi: $e');
    }
  }

  /// Pozisyonu portföyden TAMAMEN kaldırır (yanlış girilmiş kayıt için).
  /// Satış değildir: sembolün işlem kayıtları da silinir, geriye iz kalmaz.
  Future<TradeResult> deletePosition(int userId, String symbol) async {
    try {
      final response = await _client
          .delete(
            Uri.parse(
                '$baseUrl/portfolio/$userId/positions/${Uri.encodeComponent(symbol)}'),
            headers: _headers,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return TradeResult(success: true, message: 'Pozisyon silindi');
      }
      final body = jsonDecode(response.body);
      return TradeResult(
          success: false, message: body['detail'] ?? 'Sunucu hatası');
    } on SocketException {
      return TradeResult(success: false, message: 'İnternet bağlantısı yok');
    } catch (e) {
      return TradeResult(success: false, message: 'Silinemedi: $e');
    }
  }

  // Pozisyon ekleme — maliyet + lot ile portföye tanımlar (kayıt defteri).
  Future<TradeResult> importPosition({
    required int userId,
    required String symbol,
    required num quantity,
    required double avgCost,
    DateTime? acquiredAt,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/trading/manual-position'),
            headers: _headers,
            body: jsonEncode({
              'user_id': userId,
              'symbol': symbol,
              'quantity': quantity.toDouble(),
              'avg_cost': avgCost,
              if (acquiredAt != null)
                'acquired_at': acquiredAt.toUtc().toIso8601String(),
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return TradeResult(success: true, message: 'Pozisyon eklendi');
      }
      final body = jsonDecode(response.body);
      return TradeResult(
          success: false, message: body['detail'] ?? 'Sunucu hatası');
    } on SocketException {
      return TradeResult(success: false, message: 'İnternet bağlantısı yok');
    } catch (e) {
      return TradeResult(success: false, message: 'Pozisyon eklenemedi: $e');
    }
  }

  /// Portföy ekran görüntüsünü backend'e yollar; AI (Gemini vision) okuyup
  /// pozisyon adaylarına çevirir. Dönen liste toplu editöre dökülür.
  /// Hata fırlatır (timeout/non-200) — çağıran yakalayıp "okunamadı" gösterir.
  Future<List<Map<String, dynamic>>> parsePortfolioScreenshot(
    Uint8List bytes,
    String filename,
    String mime,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/trading/parse-screenshot'),
    );
    if (authToken != null) {
      request.headers['Authorization'] = 'Bearer $authToken';
    }
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType.parse(mime),
    ));

    // Vision OCR + sembol eşleme uzun sürebilir → uzun timeout.
    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      String detail = 'Görsel işlenemedi (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] != null) detail = '${body['detail']}';
      } catch (_) {}
      throw ApiException(detail, statusCode: response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final positions = (data['positions'] as List?) ?? const [];
    // Backend pozisyon yoksa boş liste + `error` döner (AI kotası/down ile
    // "görselde pozisyon yok"u ayırmak için). error varsa AI tarafı patladı →
    // istisna fırlat ki çağıran "okunamadı"yı "bulunamadı"dan ayırsın.
    if (positions.isEmpty && data['error'] != null) {
      throw ApiException('${data['error']}', statusCode: 200);
    }
    return positions.cast<Map<String, dynamic>>();
  }

  /// Aracı kurum ekstresi (Midas PDF) → işlem satırları + portföy özeti.
  /// HİÇBİR ŞEY KAYDETMEZ; kullanıcı önizlemede onaylayınca
  /// [commitStatementImport] çağrılır.
  ///
  /// Çoklu dosya: Midas ekstreyi yalnız aylık verdiği için bir yıllık geçmiş
  /// 12 dosya demek. Hepsi tek istekte gider, backend birleştirir.
  Future<Map<String, dynamic>> parseBrokerStatements(
    List<({Uint8List bytes, String filename})> files,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/trading/import-statement'),
    );
    if (authToken != null) {
      request.headers['Authorization'] = 'Bearer $authToken';
    }
    for (final f in files) {
      request.files.add(http.MultipartFile.fromBytes(
        'files',
        f.bytes,
        filename: f.filename,
        contentType: MediaType.parse('application/pdf'),
      ));
    }

    // Çok sayıda PDF + tablo çıkarımı uzun sürebilir.
    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      String detail = 'Ekstre okunamadı (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] != null) detail = '${body['detail']}';
      } catch (_) {}
      throw ApiException(detail, statusCode: response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Önizlemede onaylananları portföye işler.
  ///
  /// [mode] `positions` → ekstrenin PORTFÖY ÖZETİ'ni yazar (aracı kurumun
  /// adet + ortalama maliyet kaydı; tek dosyayla portföy doğru kurulur).
  /// [mode] `trades` → işlemleri kronolojik oynatır (yalnız TÜM ekstreler
  /// yüklendiyse doğru).
  Future<Map<String, dynamic>> commitStatementImport({
    required int userId,
    required String mode,
    List<Map<String, dynamic>> rows = const [],
    List<Map<String, dynamic>> positions = const [],
    String? positionsAsOf,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/trading/import-statement/commit'),
          headers: _headers,
          body: jsonEncode({
            'user_id': userId,
            'mode': mode,
            'rows': rows,
            'positions': positions,
            if (positionsAsOf != null) 'positions_as_of': positionsAsOf,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      String detail = 'Aktarım başarısız (${response.statusCode})';
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body is Map && body['detail'] != null) detail = '${body['detail']}';
      } catch (_) {}
      throw ApiException(detail, statusCode: response.statusCode);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> fetchQuizQuestion(
      [String horizon = 'medium']) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/market/quiz?horizon=$horizon'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchQuizQuestion hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchFundamental(String symbol,
      {bool force = false}) async {
    try {
      final url = force
          ? '$baseUrl/coach/fundamental/$symbol?force=true'
          : '$baseUrl/coach/fundamental/$symbol';
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchFundamental hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchPrediction(String symbol,
      {bool force = false}) async {
    try {
      final url = force
          ? '$baseUrl/coach/predict/$symbol?force=true'
          : '$baseUrl/coach/predict/$symbol';
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchPrediction hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> buildAiPortfolio({
    required String riskProfile,
    required String horizon,
    required double amount,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/coach/build-portfolio'),
            headers: _headers,
            body: jsonEncode({
              'risk_profile': riskProfile,
              'horizon': horizon,
              'amount': amount,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('buildAiPortfolio hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchBenchmark(int userId,
      {String period = '3m'}) async {
    // Hata/timeout'u FIRLAT: çağıran retry gösterir, kartı sessizce
    // gizlemez. Veri her zaman 200 + shape ile döner (has_holdings flag'i
    // boş portföyü temsil eder) → gerçek "boş" ayrı.
    final response = await _client
        .get(Uri.parse('$baseUrl/portfolio/$userId/benchmark?period=$period'),
            headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('benchmark HTTP ${response.statusCode}');
  }

  Future<Map<String, dynamic>?> analyzeNews(
      String title, String description) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/news/analyze'),
            headers: _headers,
            body: jsonEncode({'title': title, 'description': description}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('analyzeNews hata: $e');
    }
    return null;
  }

  // ============== PRICE ALERTS ==============
  Future<List<dynamic>?> fetchPriceAlerts() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/alerts'), headers: _headers)
          .timeout(_timeout);
      if (r.statusCode == 200) return jsonDecode(r.body) as List<dynamic>;
    } catch (e) {
      debugPrint('fetchPriceAlerts hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> createPriceAlert({
    required String symbol,
    required double thresholdPrice,
    required String direction, // ABOVE / BELOW
    bool notifyEmail = true,
    String? note,
  }) async {
    try {
      final r = await _client
          .post(
            Uri.parse('$baseUrl/alerts'),
            headers: _headers,
            body: jsonEncode({
              'symbol': symbol,
              'threshold_price': thresholdPrice,
              'direction': direction,
              'notify_email': notifyEmail,
              if (note != null) 'note': note,
            }),
          )
          .timeout(_timeout);
      if (r.statusCode == 200 || r.statusCode == 201) {
        return jsonDecode(r.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('createPriceAlert hata: $e');
    }
    return null;
  }

  Future<bool> deletePriceAlert(int id) async {
    try {
      final r = await _client
          .delete(Uri.parse('$baseUrl/alerts/$id'), headers: _headers)
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Tetiklenmiş ama uygulama içinde henüz görülmemiş alarm sayısı (rozet).
  Future<int> fetchUnseenAlertCount() async {
    try {
      final r = await _client
          .get(Uri.parse('$baseUrl/alerts/unseen-count'), headers: _headers)
          .timeout(_timeout);
      if (r.statusCode == 200) {
        return (jsonDecode(r.body)['count'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint('fetchUnseenAlertCount hata: $e');
    }
    return 0;
  }

  /// Tetiklenmiş alarmları 'görüldü' işaretle (alarm ekranı açılınca).
  Future<void> markAlertsSeen() async {
    try {
      await _client
          .post(Uri.parse('$baseUrl/alerts/mark-seen'), headers: _headers)
          .timeout(_timeout);
    } catch (e) {
      debugPrint('markAlertsSeen hata: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchGoldRates() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/market/gold-rates'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchGoldRates hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchWhatIf({
    required String symbol,
    required double amount,
    required double yearsBack,
    String? startDate,
    String? endDate,
  }) async {
    try {
      var url = '$baseUrl/market/what-if?symbol=$symbol'
          '&amount=$amount&years_back=$yearsBack';
      if (startDate != null && startDate.isNotEmpty) {
        url += '&start_date=$startDate';
      }
      if (endDate != null && endDate.isNotEmpty) {
        url += '&end_date=$endDate';
      }
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchWhatIf hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchDca({
    required String symbol,
    required double monthlyAmount,
    required double yearsBack,
    String? startDate,
    String? endDate,
  }) async {
    try {
      var url = '$baseUrl/market/dca?symbol=$symbol'
          '&monthly_amount=$monthlyAmount&years_back=$yearsBack';
      if (startDate != null && startDate.isNotEmpty) {
        url += '&start_date=$startDate';
      }
      if (endDate != null && endDate.isNotEmpty) {
        url += '&end_date=$endDate';
      }
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchDca hata: $e');
    }
    return null;
  }

  Future<List<dynamic>?> fetchMacroCalendar({bool force = false}) async {
    try {
      final url = force
          ? '$baseUrl/market/macro-calendar?force=true'
          : '$baseUrl/market/macro-calendar';
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (e) {
      debugPrint('fetchMacroCalendar hata: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchFearGreed({bool force = false}) async {
    try {
      final url = force
          ? '$baseUrl/market/fear-greed?force=true'
          : '$baseUrl/market/fear-greed';
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('fetchFearGreed hata: $e');
    }
    return null;
  }

  Future<List<int>?> fetchCsvBytes(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('fetchCsvBytes hata: $e');
    }
    return null;
  }

  Future<List<dynamic>> fetchTransactions(int userId, {int limit = 50}) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/trading/transactions/$userId?limit=$limit'),
              headers: _headers)
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('fetchTransactions hata: $e');
    }
    return [];
  }

  // ============== COACH ==============
  Future<Map<String, dynamic>> fetchCoachAdvice(int userId) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/coach/advice/$userId'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'error': 'Sunucu hatası: ${response.statusCode}'};
    } catch (e) {
      return {'error': 'Bağlantı hatası: $e'};
    }
  }

  Future<Map<String, dynamic>> fetchBehaviorProfile(int userId) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/behavior/profile/$userId'),
              headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'error': 'Sunucu hatası: ${response.statusCode}'};
    } catch (e) {
      return {'error': 'Bağlantı hatası: $e'};
    }
  }

  Future<List<dynamic>> fetchStressScenarios() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/stress/scenarios'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint('fetchStressScenarios hata: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> runStressTest(
      int userId, String scenario) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/stress/run/$userId?scenario=$scenario'),
              headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'error': 'Sunucu hatası: ${response.statusCode}'};
    } catch (e) {
      return {'error': 'Bağlantı hatası: $e'};
    }
  }

  // ============== HISTORY ==============
  Future<Map<String, dynamic>> fetchStockHistory(String symbol, String period,
      {String? interval}) async {
    try {
      final q = interval == null
          ? 'period=$period'
          : 'period=$period&interval=$interval';
      final response = await _client
          .get(Uri.parse('$baseUrl/market/history/$symbol?$q'),
              headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'error': 'Geçmiş veri alınamadı: ${response.statusCode}'};
    } catch (e) {
      return {'error': 'Bağlantı hatası: $e'};
    }
  }

  Future<List<Map<String, dynamic>>> searchStocks(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final encoded = Uri.encodeQueryComponent(query.trim());
      final response = await _client
          .get(Uri.parse('$baseUrl/market/search?q=$encoded&limit=10'),
              headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('searchStocks hata: $e');
      return [];
    }
  }

  // ============== AI CHAT (SSE Streaming) ==============

  // ============== AI CHAT (SSE Streaming) ==============
  /// AI Koç sohbeti — SSE streaming.
  ///
  /// `flutter_client_sse` paketi KULLANILMIYOR. O paketin global singleton
  /// `_client`'ı vardı ve `unsubscribeFromSSE()` çağrısı in-flight stream'de
  /// hata fırlatıp paketin `_retryConnection`'ını tetikliyordu → 5 sn sonra
  /// AYNI URL (aynı mesaj) ile yeniden bağlanıyor, backend `stream_chat_response`'u
  /// tekrar çalıştırıp mesaj + cevabı DB'ye duplike kaydediyor ve UI'da 2-3 kez
  /// gösteriyordu. Ayrıca eski metot `null` döndürdüğünden provider gerçekten
  /// iptal/dispose edemiyordu.
  ///
  /// Yeni yaklaşım: sahibi biz olan tek bir [http.Client] ile streamed GET açıp
  /// SSE'yi elle parse ediyoruz. Otomatik reconnect yok, listener birikmesi yok.
  /// Geri dönen [ChatStreamHandle.cancel] çağrısı bağlantıyı gerçekten kapatır.
  ChatStreamHandle streamChatMessage({
    required int userId,
    required String message,
    required void Function(String token) onToken,
    required void Function() onDone,
    required void Function(String error) onError,
  }) {
    final encodedMsg = Uri.encodeQueryComponent(message);
    final url = '$baseUrl/chat/send?user_id=$userId&message=$encodedMsg';
    final handle = ChatStreamHandle(http.Client());

    // onDone/onError tam bir kez çağrılsın; sonrasında client kapatılsın.
    var finished = false;
    void finishOnce(void Function() action) {
      if (finished) return;
      finished = true;
      action();
      handle._client.close();
    }

    () async {
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers.addAll(_headers);
        request.headers['Accept'] = 'text/event-stream';
        request.headers['Cache-Control'] = 'no-cache';

        var response = await handle._client.send(request);
        // Oturum içi 401 — akış kendi istemcisini kullandığı için (iptal
        // edilebilirlik) `_AuthRetryClient`'ın kapsamı dışında: token'ı bir kez
        // yenileyip akışı yeniden aç. Aksi hâlde 60 dk'dan uzun açık kalan
        // uygulamada AI Koç "Sunucu hatası (401)" veriyordu.
        if (response.statusCode == 401) {
          final fresh = await refreshSessionOnce(authToken);
          if (fresh != null && !handle._cancelled) {
            await response.stream.drain<void>();
            response = await handle._client.send(retryRequest(request, fresh));
          }
        }
        if (response.statusCode != 200) {
          finishOnce(() => onError('Sunucu hatası (${response.statusCode})'));
          return;
        }

        var currentEvent = '';
        final dataBuffer = StringBuffer();

        void dispatch() {
          if (currentEvent.isEmpty && dataBuffer.isEmpty) return;
          final event = currentEvent;
          final data = dataBuffer.toString();
          currentEvent = '';
          dataBuffer.clear();

          if (event == 'thinking') {
            return;
          } else if (event == 'token') {
            if (data.isNotEmpty) {
              try {
                // Token JSON encode edilmiş ({"t": "..."}) — SSE'nin leading
                // whitespace trimleme davranışından korunmak için.
                final decoded = jsonDecode(data) as Map<String, dynamic>;
                final t = decoded['t'] as String? ?? '';
                if (t.isNotEmpty) onToken(t);
              } catch (_) {
                onToken(data); // geriye uyumluluk: düz string
              }
            }
          } else if (event == 'done') {
            finishOnce(onDone);
          } else if (event == 'error') {
            var msg = data.isEmpty ? 'Bilinmeyen hata' : data;
            try {
              final decoded = jsonDecode(data) as Map<String, dynamic>;
              msg = decoded['msg'] as String? ?? msg;
            } catch (_) {}
            finishOnce(() => onError(msg));
          }
        }

        await for (final line in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (finished) break;
          if (line.isEmpty) {
            dispatch(); // boş satır = event seti tamamlandı
            continue;
          }
          if (line.startsWith(':')) continue; // SSE yorum/ping satırı
          final idx = line.indexOf(':');
          final field = idx == -1 ? line : line.substring(0, idx);
          var value = idx == -1 ? '' : line.substring(idx + 1);
          if (value.startsWith(' ')) value = value.substring(1);
          if (field == 'event') {
            currentEvent = value;
          } else if (field == 'data') {
            dataBuffer.write(value);
          }
          // id/retry alanları yok sayılır.
        }

        // Sunucu stream'i kapattı; 'done' gelmediyse normal tamamla.
        finishOnce(onDone);
      } catch (e) {
        // Provider cancel() çağırdıysa bu beklenen bir kapanmadır: hata gösterme,
        // o ana dek gelen kısmi cevabı koruyup akışı düzgünce sonlandır (onDone).
        if (handle._cancelled) {
          finishOnce(onDone);
        } else {
          // Ham istisnayı kullanıcıya GÖSTERME: canlıda balonda
          // "ClientException: Failed to fetch, uri=...user_id=1&message=..."
          // yazıyordu (hem anlaşılmaz hem uç/kimlik sızdırıyor). Gerçek hata
          // konsola gider, kullanıcı ne yapacağını bilsin.
          debugPrint('chat stream hata: $e');
          finishOnce(() => onError(
              'Bağlantı koptu — cevap tamamlanamadı. Tekrar dener misin?'));
        }
      }
    }();

    return handle;
  }

  /// Chat geçmişini al
  Future<List<dynamic>> fetchChatHistory(int userId) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/chat/history/$userId'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint('fetchChatHistory hata: $e');
      return [];
    }
  }

  /// Chat geçmişini sil
  Future<bool> clearChatHistory(int userId) async {
    try {
      final response = await _client
          .delete(Uri.parse('$baseUrl/chat/history/$userId'), headers: _headers)
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('clearChatHistory hata: $e');
      return false;
    }
  }

  // ============== CHART DRAWINGS (çizim kalıcılığı) ==============
  // Kullanıcının sembol başına kaydettiği grafik çizimleri (timestamp-bazlı
  // JSON payload; auth gerekir). En-iyi-çaba: hata sessiz — başarısızsa
  // çizimler bellekte kalır, UI bozulmaz (cold-start/ağ toleransı).

  /// Sembolün kayıtlı çizim payload'unu döner (yoksa boş {}). Hata → null.
  Future<Map<String, dynamic>?> getChartDrawings(String symbol) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/chart/drawings/${Uri.encodeComponent(symbol)}'),
            headers: _headers,
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final payload = data is Map ? data['payload'] : null;
        return payload is Map
            ? Map<String, dynamic>.from(payload)
            : <String, dynamic>{};
      }
    } catch (e) {
      debugPrint('getChartDrawings hata: $e');
    }
    return null;
  }

  /// Çizim setini kaydeder (upsert). Başarı → true.
  Future<bool> saveChartDrawings(
      String symbol, Map<String, dynamic> payload) async {
    try {
      final response = await _client
          .put(
            Uri.parse('$baseUrl/chart/drawings/${Uri.encodeComponent(symbol)}'),
            headers: _headers,
            body: jsonEncode({'payload': payload}),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('saveChartDrawings hata: $e');
      return false;
    }
  }

  /// Sembolün tüm çizimlerini siler. Başarı → true.
  Future<bool> deleteChartDrawings(String symbol) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('$baseUrl/chart/drawings/${Uri.encodeComponent(symbol)}'),
            headers: _headers,
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('deleteChartDrawings hata: $e');
      return false;
    }
  }

  // ============== WATCHLIST (izleme listesi kalıcılığı) ==============
  // İzleme listesi (sıralı sembol listesi) hesaba bağlı saklanır → cihaz/tarayıcı
  // değişince veya PWA cache temizlenince kaybolmaz (auth gerekir). En-iyi-çaba:
  // hata sessiz → backend ulaşılamazsa yerel SharedPreferences cache'i kullanılır,
  // UI bozulmaz (chart drawings ile aynı cold-start/offline toleransı).

  /// Kullanıcının kayıtlı izleme listesini döner (sıralı). Hata → null.
  Future<List<String>?> getWatchlist() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/watchlist'), headers: _headers)
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final syms = data is Map ? data['symbols'] : null;
        return syms is List
            ? syms.map((e) => e.toString()).toList()
            : <String>[];
      }
    } catch (e) {
      debugPrint('getWatchlist hata: $e');
    }
    return null;
  }

  /// İzleme listesini tümüyle kaydeder (reorder + ilk taşıma). Sunucunun
  /// döndürdüğü normalize listeyi verir; hata → null.
  Future<List<String>?> saveWatchlist(List<String> symbols) async {
    try {
      final response = await _client
          .put(
            Uri.parse('$baseUrl/watchlist'),
            headers: _headers,
            body: jsonEncode({'symbols': symbols}),
          )
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final syms = data is Map ? data['symbols'] : null;
        return syms is List
            ? syms.map((e) => e.toString()).toList()
            : <String>[];
      }
    } catch (e) {
      debugPrint('saveWatchlist hata: $e');
    }
    return null;
  }

  /// Sembolü izleme listesine ekler (idempotent). Başarı → true.
  Future<bool> addWatchlistSymbol(String symbol) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/watchlist/${Uri.encodeComponent(symbol)}'),
            headers: _headers,
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('addWatchlistSymbol hata: $e');
      return false;
    }
  }

  /// Sembolü izleme listesinden çıkarır. Başarı → true.
  Future<bool> removeWatchlistSymbol(String symbol) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('$baseUrl/watchlist/${Uri.encodeComponent(symbol)}'),
            headers: _headers,
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('removeWatchlistSymbol hata: $e');
      return false;
    }
  }

  // ============== NOTES (yatırımcı günlüğü) ==============
  // Kullanıcıya özel notlar; hisseye bağlı (symbol) ya da genel (symbol yok).
  // watchlist ile aynı en-iyi-çaba deseni: hata sessiz → null/false, UI bozulmaz.
  // Auth header'ı `_headers` (statik authToken) sağlar; backend sahipliği
  // user_id ile filtreler (başkasının notu → 404).

  /// Notları döner (symbol verilirse o hisseye ait, yoksa hepsi). Backend
  /// en-yeni-önce sıralar. Ham liste döner (provider Note'a çevirir); hata → null.
  Future<List<dynamic>?> getNotes({String? symbol}) async {
    try {
      final uri = (symbol == null || symbol.isEmpty)
          ? Uri.parse('$baseUrl/notes')
          : Uri.parse('$baseUrl/notes?symbol=${Uri.encodeComponent(symbol)}');
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is List ? data : <dynamic>[];
      }
    } catch (e) {
      debugPrint('getNotes hata: $e');
    }
    return null;
  }

  /// Not oluşturur (symbol null/boş = genel günlük). Başarı → oluşan ham not,
  /// hata/doğrulama (422 boş·tavan / 400 yalnız-boşluk) → null.
  Future<Map<String, dynamic>?> createNote(String content,
      {String? symbol}) async {
    try {
      final body = <String, dynamic>{'content': content};
      if (symbol != null && symbol.isNotEmpty) body['symbol'] = symbol;
      final response = await _client
          .post(Uri.parse('$baseUrl/notes'),
              headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : null;
      }
    } catch (e) {
      debugPrint('createNote hata: $e');
    }
    return null;
  }

  /// Notun içeriğini günceller. Başarı → güncel ham not; 404/400 → null.
  Future<Map<String, dynamic>?> updateNote(int id, String content) async {
    try {
      final response = await _client
          .put(Uri.parse('$baseUrl/notes/$id'),
              headers: _headers, body: jsonEncode({'content': content}))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : null;
      }
    } catch (e) {
      debugPrint('updateNote hata: $e');
    }
    return null;
  }

  /// Notu siler. Başarı → true; 404/hata → false.
  Future<bool> deleteNote(int id) async {
    try {
      final response = await _client
          .delete(Uri.parse('$baseUrl/notes/$id'), headers: _headers)
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('deleteNote hata: $e');
      return false;
    }
  }

  // ============== SİNYALLER (AL/TUT/SAT taraması) ==============
  // Kural tabanlı sinyal motoru: portföy + izleme sembollerinin teknik+temel
  // taraması. Backend 15 dk cache'ler; force=true cache'i atlar (pull-refresh).

  /// Kullanıcının tüm sembol sinyalleri:
  /// {signals: [...], failed: [...], disclaimer, generated_at}. Hata → null.
  Future<Map<String, dynamic>?> getSignals({bool force = false}) async {
    try {
      final uri = Uri.parse('$baseUrl/signals${force ? '?force=true' : ''}');
      final response = await _client
          .get(uri, headers: _headers)
          // Soğuk tarama sembol başına yfinance çeker → normal timeout yetmez.
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : null;
      }
    } catch (e) {
      debugPrint('getSignals hata: $e');
    }
    return null;
  }

  /// Tek sembolün sinyali (hisse detay ekranı için). Hata → null.
  Future<Map<String, dynamic>?> getSymbolSignal(String symbol) async {
    try {
      final uri = Uri.parse('$baseUrl/signals/${Uri.encodeComponent(symbol)}');
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map<String, dynamic> ? data : null;
      }
    } catch (e) {
      debugPrint('getSymbolSignal hata: $e');
    }
    return null;
  }
}

class TradeResult {
  final bool success;
  final String message;
  TradeResult({required this.success, required this.message});
}
