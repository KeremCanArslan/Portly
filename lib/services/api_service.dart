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
  // Platform-aware baseUrl: emülatör, simulator ve gerçek cihaz ayrımı
  static String get baseUrl {
    if (kIsWeb) return "http://127.0.0.1:8000/api/v1";
    if (Platform.isAndroid)
      return "http://10.0.2.2:8000/api/v1"; // Android emulator
    if (Platform.isIOS) return "http://127.0.0.1:8000/api/v1"; // iOS simulator
    return "http://127.0.0.1:8000/api/v1";
  }

  static const Duration _timeout = Duration(seconds: 10);

  // 1. POPÜLER HİSSELER
  Future<List<Map<String, dynamic>>> fetchPopularStocks() async {
    const symbols = ["THYAO.IS", "ASELS.IS", "AAPL", "TSLA"];
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
        return {
          "symbol": symbol,
          "name": data['company_name'] ?? symbol,
          "price":
              (data['current_price'] as num?)?.toStringAsFixed(2) ?? "0.00",
          "change":
              "${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(2)}%",
          "isUp": changePct >= 0,
          "rawPrice": (data['current_price'] as num?)?.toDouble() ?? 0.0,
        };
      }
    } catch (e) {
      debugPrint('fetchSingleStock($symbol) hata: $e');
    }
    return null;
  }

  // 2. BAKİYE
  Future<double> fetchUserBalance(int userId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/auth/$userId')).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['balance'] as num?)?.toDouble() ?? 0.0;
      }
      throw ApiException('Bakiye alınamadı', statusCode: response.statusCode);
    } on SocketException {
      throw ApiException('İnternet bağlantısı yok');
    } catch (e) {
      throw ApiException('Bakiye hatası: $e');
    }
  }

  // 3. PORTFÖY
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

  // 4. HABERLER
  Future<List<dynamic>> fetchNews() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/news/latest'))
          .timeout(const Duration(seconds: 15)); // NLP biraz uzun sürebilir
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint('fetchNews hata: $e');
      return [];
    }
  }

  // 5. ALIM
  Future<TradeResult> buyStock(int userId, String symbol, int quantity) async {
    return _placeOrder(userId, symbol, quantity, 'BUY');
  }

  // 6. SATIM (YENİ)
  Future<TradeResult> sellStock(int userId, String symbol, int quantity) async {
    return _placeOrder(userId, symbol, quantity, 'SELL');
  }

  Future<Map<String, dynamic>> fetchCoachAdvice(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/coach/advice/$userId'))
          .timeout(const Duration(seconds: 30)); // LLM biraz sürer
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'error': 'Sunucu hatası: ${response.statusCode}'};
    } catch (e) {
      return {'error': 'Bağlantı hatası: $e'};
    }
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
}

class TradeResult {
  final bool success;
  final String message;
  TradeResult({required this.success, required this.message});
}
