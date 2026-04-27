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
    if (Platform.isIOS) return "http://192.168.1.19:8000/api/v1";
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
Future<Map<String, dynamic>> fetchSectorBreakdown(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/portfolio/$userId/sectors'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'sectors': [], 'total_value': 0.0};
    } catch (e) {
      debugPrint('fetchSectorBreakdown hata: $e');
      return {'sectors': [], 'total_value': 0.0};
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

  // ============== AI CHAT (SSE Streaming) ==============
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
    request.headers['Cache-Control'] = 'no-cache';
    request.body = jsonEncode({
      'user_id': userId,
      'message': message,
    });

    bool isClosed = false;

    void closeOnce() {
      if (isClosed) return;
      isClosed = true;
      try {
        client.close();
      } catch (_) {}
    }

    client.send(request).then((response) {
      if (response.statusCode != 200) {
        onError('Sunucu hatası: ${response.statusCode}');
        closeOnce();
        return;
      }

      // Buffer-based SSE parser
      // SSE spec: events are separated by \n\n
      // Each event has lines like "event: <name>" and "data: <content>"
      String buffer = '';

      response.stream.transform(utf8.decoder).listen(
        (chunk) {
          if (isClosed) return;
          buffer += chunk;

          // Parse complete events (separated by \n\n)
          while (true) {
            final separatorIdx = buffer.indexOf('\n\n');
            if (separatorIdx == -1) break;

            final rawEvent = buffer.substring(0, separatorIdx);
            buffer = buffer.substring(separatorIdx + 2);

            String? eventName;
            final dataLines = <String>[];

            for (final line in rawEvent.split('\n')) {
              if (line.isEmpty) continue;
              if (line.startsWith('event:')) {
                eventName = line.substring(6).trim();
              } else if (line.startsWith('data:')) {
                // SSE spec: 'data: foo' -> 'foo' (one space removed)
                // 'data:foo' -> 'foo'
                String content;
                if (line.length > 5 && line[5] == ' ') {
                  content = line.substring(6);
                } else {
                  content = line.substring(5);
                }
                dataLines.add(content);
              }
            }

            if (dataLines.isEmpty && eventName == null) continue;

            // Multi-line data joined with newline (per SSE spec)
            final data = dataLines.join('\n');

            if (eventName == 'thinking') {
              // Backend hazır, ilk token bekleniyor — sadece bağlantı doğrulandı
              continue;
            } else if (eventName == 'token') {
              if (data.isNotEmpty) onToken(data);
            } else if (eventName == 'done') {
              onDone();
              closeOnce();
              return;
            } else if (eventName == 'error') {
              onError(data.isEmpty ? 'Bilinmeyen hata' : data);
              closeOnce();
              return;
            }
          }
        },
        onError: (e) {
          if (isClosed) return;
          onError('Bağlantı hatası: $e');
          closeOnce();
        },
        onDone: () {
          if (isClosed) return;
          // Stream kapanırken buffer'da event kalmış olabilir
          if (buffer.trim().isNotEmpty) {
            // Son event'i parse et
            final lines = buffer.split('\n');
            String? eventName;
            final dataLines = <String>[];
            for (final line in lines) {
              if (line.startsWith('event:')) {
                eventName = line.substring(6).trim();
              } else if (line.startsWith('data:')) {
                final content = line.length > 5 && line[5] == ' '
                    ? line.substring(6)
                    : line.substring(5);
                dataLines.add(content);
              }
            }
            if (eventName == 'token' && dataLines.isNotEmpty) {
              onToken(dataLines.join('\n'));
            }
          }
          onDone();
          closeOnce();
        },
        cancelOnError: true,
      );
    }).catchError((e) {
      onError('İstek hatası: $e');
      closeOnce();
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
