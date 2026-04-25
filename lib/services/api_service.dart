import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ApiService {
  static String get baseUrl {
    if (kIsWeb) return "http://127.0.0.1:8000/api/v1";
    if (Platform.isAndroid) return "http://10.0.2.2:8000/api/v1";
    if (Platform.isIOS) return "http://127.0.0.1:8000/api/v1";
    return "http://127.0.0.1:8000/api/v1";
  }

  static const Duration _timeout = Duration(seconds: 10);

  // ============== AUTH ==============
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'access_token': data['access_token'],
          'user': data['user'],
        };
      } else {
        final body = jsonDecode(response.body);
        return {'success': false, 'error': body['detail'] ?? 'Giriş başarısız'};
      }
    } on SocketException {
      return {'success': false, 'error': 'İnternet bağlantısı yok'};
    } catch (e) {
      return {'success': false, 'error': 'Sunucu hatası: $e'};
    }
  }

  Future<Map<String, dynamic>> register(
      String email, String password, String fullName) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': password,
              'full_name': fullName,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'access_token': data['access_token'],
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
    } catch (e) {
      return {'success': false, 'error': 'Sunucu hatası: $e'};
    }
  }

  Future<Map<String, dynamic>> generateDemoTrades(int userId) async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/trading/demo/$userId'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {
        'success': false,
        'error': 'Sunucu hatası: ${response.statusCode}'
      };
    } catch (e) {
      return {'success': false, 'error': 'Bağlantı hatası: $e'};
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

  // ============== STOCKS ==============
  Future<List<Map<String, dynamic>>> fetchPopularStocks(
      List<String> symbols) async {
    if (symbols.isEmpty) return [];
    final results = await Future.wait(symbols.map((s) => _fetchSingleStock(s)));
    return results.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>?> _fetchSingleStock(String symbol) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/market/price/$symbol'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final changePct = (data['change_percent'] as num?)?.toDouble() ?? 0.0;
        final bool isTurkish = symbol.endsWith('.IS') || symbol.endsWith('.TR');
        final String currency = isTurkish ? '₺' : '\$';
        return {
          "symbol": symbol,
          "name": data['company_name'] ?? symbol,
          "price":
              (data['current_price'] as num?)?.toStringAsFixed(2) ?? "0.00",
          "change":
              "${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%",
          "isUp": changePct >= 0,
          "rawPrice": (data['current_price'] as num?)?.toDouble() ?? 0.0,
          "currency": currency,
          "isTurkish": isTurkish,
        };
      }
    } catch (e) {
      debugPrint('fetchSingleStock($symbol) hata: $e');
    }
    return null;
  }

  // ============== USER DATA ==============
  Future<List<dynamic>> fetchUserPortfolio(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/portfolio/$userId'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint('fetchUserPortfolio hata: $e');
      return [];
    }
  }

  Future<List<dynamic>> fetchNews({bool force = false}) async {
    try {
      final url =
          force ? '$baseUrl/news/latest?force=true' : '$baseUrl/news/latest';
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint('fetchNews hata: $e');
      return [];
    }
  }

  // ============== TRADING ==============
  Future<TradeResult> buyStock(int userId, String symbol, int quantity) async {
    return _placeOrder(userId, symbol, quantity, 'BUY');
  }

  Future<TradeResult> sellStock(int userId, String symbol, int quantity) async {
    return _placeOrder(userId, symbol, quantity, 'SELL');
  }

  Future<TradeResult> _placeOrder(
      int userId, String symbol, int quantity, String type) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/trading/order'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'symbol': symbol,
              'quantity': quantity.toDouble(),
              'transaction_type': type,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return TradeResult(success: true, message: '$type emri başarılı');
      } else {
        final body = jsonDecode(response.body);
        return TradeResult(
            success: false, message: body['detail'] ?? 'Sunucu hatası');
      }
    } on SocketException {
      return TradeResult(success: false, message: 'İnternet bağlantısı yok');
    } catch (e) {
      return TradeResult(success: false, message: 'Emir iletilemedi: $e');
    }
  }

  // ============== COACH ==============
  Future<Map<String, dynamic>> fetchCoachAdvice(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/coach/advice/$userId'))
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
      final response = await http
          .get(Uri.parse('$baseUrl/behavior/profile/$userId'))
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
      final response = await http
          .get(Uri.parse('$baseUrl/stress/scenarios'))
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
      final response = await http
          .get(Uri.parse('$baseUrl/stress/run/$userId?scenario=$scenario'))
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
  Future<Map<String, dynamic>> fetchStockHistory(
      String symbol, String period) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/market/history/$symbol?period=$period'))
          .timeout(const Duration(seconds: 15));
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
      final response = await http
          .get(Uri.parse('$baseUrl/market/search?q=$encoded&limit=10'))
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
  /// Server-Sent Events ile streaming chat response.
  /// Her token geldiğinde [onToken] çağrılır.
  /// Bittiğinde [onDone] çağrılır.
  /// Hata olursa [onError] çağrılır.
  /// İade edilen [http.Client] cancel için kullanılabilir.
  http.Client? streamChatMessage({
    required int userId,
    required String message,
    required void Function(String token) onToken,
    required void Function() onDone,
    required void Function(String error) onError,
  }) {
    final client = http.Client();
    final request = http.Request('POST', Uri.parse('$baseUrl/chat/send'));
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'text/event-stream';
    request.body = jsonEncode({
      'user_id': userId,
      'message': message,
    });

    client.send(request).then((response) {
      if (response.statusCode != 200) {
        onError('Sunucu hatası: ${response.statusCode}');
        client.close();
        return;
      }

      // SSE format: "event: <name>\ndata: <content>\n\n"
      // Her event çift newline ile ayrılır.
      String buffer = '';
      String? currentEvent;

      response.stream.transform(utf8.decoder).listen(
        (chunk) {
          buffer += chunk;
          // Event'ler \n\n ile ayrılır
          while (buffer.contains('\n\n')) {
            final idx = buffer.indexOf('\n\n');
            final rawEvent = buffer.substring(0, idx);
            buffer = buffer.substring(idx + 2);

            // Bu event'in satırlarını parse et
            String? eventName;
            final dataLines = <String>[];
            for (final line in rawEvent.split('\n')) {
              if (line.startsWith('event:')) {
                eventName = line.substring(6).trim();
              } else if (line.startsWith('data:')) {
                // 'data: ' sonrası her şey - ilk boşluğu da koru
                final content = line.length > 5 ? line.substring(5) : '';
                // SSE spec'te 'data: ' (data: + space) standart, space'i kaldır
                dataLines.add(
                    content.startsWith(' ') ? content.substring(1) : content);
              }
            }

            currentEvent = eventName ?? currentEvent;
            final data = dataLines.join('\n');

            if (currentEvent == 'token' && data.isNotEmpty) {
              onToken(data);
            } else if (currentEvent == 'done') {
              onDone();
              client.close();
              return;
            } else if (currentEvent == 'error') {
              onError(data);
              client.close();
              return;
            }
          }
        },
        onError: (e) {
          onError('Bağlantı hatası: $e');
          client.close();
        },
        onDone: () {
          onDone();
          client.close();
        },
        cancelOnError: true,
      );
    }).catchError((e) {
      onError('İstek hatası: $e');
      client.close();
    });

    return client;
  }

  /// Chat geçmişini al
  Future<List<dynamic>> fetchChatHistory(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/chat/history/$userId'))
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
      final response = await http
          .delete(Uri.parse('$baseUrl/chat/history/$userId'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('clearChatHistory hata: $e');
      return false;
    }
  }
}

class TradeResult {
  final bool success;
  final String message;
  TradeResult({required this.success, required this.message});
}
