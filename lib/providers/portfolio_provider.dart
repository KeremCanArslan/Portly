import 'package:flutter/material.dart';
import 'package:portly/services/api_service.dart';

class PortfolioProvider extends ChangeNotifier {
  // ==========================================
  // STATE
  // ==========================================
  double _balance = 0.0;

  List<Map<String, dynamic>> _marketData = [];
  bool _isLoading = true;

  List<dynamic> _myHoldings = [];
  bool _isPortfolioLoading = true;

  List<dynamic> _newsData = [];
  bool _isNewsLoading = true;

  // AI Koç state
  String? _coachAdvice;
  bool _isCoachLoading = false;
  String? _coachError;

  // Global hata mesajı
  String? _lastError;

  // Şimdilik sabit user ID. JWT devreye girince buradan okunacak.
  static const int _userId = 1;

  // ==========================================
  // SERVICES
  // ==========================================
  final ApiService _apiService = ApiService();

  // ==========================================
  // GETTERS
  // ==========================================
  double get balance => _balance;
  List<Map<String, dynamic>> get marketData => _marketData;
  bool get isLoading => _isLoading;
  List<dynamic> get myHoldings => _myHoldings;
  bool get isPortfolioLoading => _isPortfolioLoading;
  List<dynamic> get newsData => _newsData;
  bool get isNewsLoading => _isNewsLoading;
  String? get lastError => _lastError;

  // AI Koç getter'ları
  String? get coachAdvice => _coachAdvice;
  bool get isCoachLoading => _isCoachLoading;
  String? get coachError => _coachError;

  // Türevlenmiş getter'lar
  double get totalHoldingsValue {
    double total = 0.0;
    for (var h in _myHoldings) {
      total += (h['total_value'] as num?)?.toDouble() ?? 0.0;
    }
    return total;
  }

  double get totalAssetValue => _balance + totalHoldingsValue;

  double get totalPnl {
    double total = 0.0;
    for (var h in _myHoldings) {
      total += (h['pnl'] as num?)?.toDouble() ?? 0.0;
    }
    return total;
  }

  double get totalPnlPercent {
    double totalCost = 0.0;
    for (var h in _myHoldings) {
      final qty = (h['quantity'] as num?)?.toDouble() ?? 0.0;
      final avg = (h['average_cost'] as num?)?.toDouble() ?? 0.0;
      totalCost += qty * avg;
    }
    if (totalCost == 0) return 0;
    return (totalPnl / totalCost) * 100;
  }

  // ==========================================
  // CONSTRUCTOR
  // ==========================================
  PortfolioProvider() {
    refreshAll();
  }

  // ==========================================
  // LOADERS
  // ==========================================
  Future<void> refreshAll() async {
    await Future.wait([
      loadUserBalance(),
      loadMarketData(),
      loadNewsData(),
      loadMyPortfolio(),
    ]);
  }

  Future<void> loadUserBalance() async {
    try {
      _balance = await _apiService.fetchUserBalance(_userId);
      notifyListeners();
    } catch (e) {
      _setError('Bakiye yüklenemedi: $e');
    }
  }

  Future<void> loadMarketData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _marketData = await _apiService.fetchPopularStocks();
    } catch (e) {
      _setError('Piyasa verisi hatası: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadNewsData() async {
    _isNewsLoading = true;
    notifyListeners();
    try {
      _newsData = await _apiService.fetchNews();
    } catch (e) {
      _setError('Haberler yüklenemedi: $e');
    }
    _isNewsLoading = false;
    notifyListeners();
  }

  Future<void> loadMyPortfolio() async {
    _isPortfolioLoading = true;
    notifyListeners();
    try {
      _myHoldings = await _apiService.fetchUserPortfolio(_userId);
    } catch (e) {
      _setError('Portföy yüklenemedi: $e');
    }
    _isPortfolioLoading = false;
    notifyListeners();
  }

  // AI Koç tavsiyesini yükle
  Future<void> loadCoachAdvice() async {
    _isCoachLoading = true;
    _coachAdvice = null;
    _coachError = null;
    notifyListeners();

    final result = await _apiService.fetchCoachAdvice(_userId);
    if (result.containsKey('advice')) {
      _coachAdvice = result['advice'] as String;
    } else {
      _coachError = result['error']?.toString() ?? 'AI yanıt vermedi';
    }

    _isCoachLoading = false;
    notifyListeners();
  }

  // ==========================================
  // TRADING
  // ==========================================
  Future<TradeResult> executeBuyOrder(
      String symbol, int quantity, double currentPrice) async {
    if (quantity <= 0) {
      return TradeResult(success: false, message: 'Lot adedi pozitif olmalı');
    }

    final totalCost = quantity * currentPrice;
    if (_balance < totalCost) {
      return TradeResult(
        success: false,
        message: 'Yetersiz bakiye. Gerekli: ₺${totalCost.toStringAsFixed(2)}',
      );
    }

    final result = await _apiService.buyStock(_userId, symbol, quantity);
    if (result.success) {
      await Future.wait([loadUserBalance(), loadMyPortfolio()]);
    }
    return result;
  }

  Future<TradeResult> executeSellOrder(String symbol, int quantity) async {
    if (quantity <= 0) {
      return TradeResult(success: false, message: 'Lot adedi pozitif olmalı');
    }

    final result = await _apiService.sellStock(_userId, symbol, quantity);
    if (result.success) {
      await Future.wait([loadUserBalance(), loadMyPortfolio()]);
    }
    return result;
  }

  double heldQuantity(String symbol) {
    for (var h in _myHoldings) {
      if (h['symbol'] == symbol) {
        return (h['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return 0.0;
  }

  // ==========================================
  // HELPERS
  // ==========================================
  void _setError(String msg) {
    _lastError = msg;
    debugPrint(msg);
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }
}
