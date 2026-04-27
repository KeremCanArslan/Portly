import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/services/api_service.dart';

class PortfolioProvider extends ChangeNotifier {

  double _balance = 0.0;

  List<Map<String, dynamic>> _marketData = [];
  bool _isLoading = true;

  List<dynamic> _myHoldings = [];
  bool _isPortfolioLoading = true;

  List<dynamic> _newsData = [];
  bool _isNewsLoading = true;

  String? _coachAdvice;
  bool _isCoachLoading = false;
  String? _coachError;

  String? _lastError;

  List<String> _watchlistSymbols = [];

  int? _userId;
  String? _token;

  static const List<String> _defaultWatchlist = [
    "GC=F", 
    "USDTRY=X", 
    "EURTRY=X", 
    "BTC-USD", 
    "THYAO.IS",
    "ASELS.IS",
    "AAPL",
    "NVDA",
  ];

  final ApiService _apiService = ApiService();


  int? get userId => _userId;
  double get balance => _balance;
  List<Map<String, dynamic>> get marketData => _marketData;
  bool get isLoading => _isLoading;
  List<dynamic> get myHoldings => _myHoldings;
  bool get isPortfolioLoading => _isPortfolioLoading;
  List<dynamic> get newsData => _newsData;
  bool get isNewsLoading => _isNewsLoading;
  String? get lastError => _lastError;
  List<String> get watchlistSymbols => _watchlistSymbols;

  String? get coachAdvice => _coachAdvice;
  bool get isCoachLoading => _isCoachLoading;
  String? get coachError => _coachError;

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


  PortfolioProvider() {
    _init();
  }

  Future<void> _init() async {
    await _initWatchlist();
    loadMarketData();
    loadNewsData();
  }

  Future<void> _initWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('watchlist');
    _watchlistSymbols = saved ?? List.from(_defaultWatchlist);
  }

  void updateUserAuth(int? newUserId, String? token) {
    if (_userId == newUserId && _token == token) return;
    _userId = newUserId;
    _token = token;
    if (newUserId != null) {
      loadUserBalance(token);
      loadMyPortfolio();
    } else {
      _balance = 0.0;
      _myHoldings = [];
      _coachAdvice = null;
      _coachError = null;
      notifyListeners();
    }
  }


  Future<bool> addToWatchlist(String symbol) async {
    symbol = symbol.toUpperCase().trim();
    if (symbol.isEmpty) return false;
    if (_watchlistSymbols.contains(symbol)) return false;

    _watchlistSymbols.add(symbol);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('watchlist', _watchlistSymbols);
    await loadMarketData();
    return true;
  }

  Future<void> removeFromWatchlist(String symbol) async {
    _watchlistSymbols.remove(symbol);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('watchlist', _watchlistSymbols);
    await loadMarketData();
  }


  Future<void> refreshAll() async {
    await Future.wait([
      loadMarketData(),
      loadNewsData(),
      if (_userId != null) loadUserBalance(_token),
      if (_userId != null) loadMyPortfolio(),
    ]);
  }

  Future<void> loadUserBalance(String? token) async {
    if (_userId == null || token == null) return;
    try {
      final me = await _apiService.fetchMe(token);
      _balance = (me['balance'] as num?)?.toDouble() ?? 0.0;
      notifyListeners();
    } catch (e) {
      _setError('Bakiye yüklenemedi: $e');
    }
  }

  Future<void> loadMarketData() async {
    _isLoading = true;
    notifyListeners();
    try {
      _marketData = await _apiService.fetchPopularStocks(_watchlistSymbols);
    } catch (e) {
      _setError('Piyasa verisi hatası: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadNewsData({bool force = false}) async {
    _isNewsLoading = true;
    notifyListeners();
    try {
      _newsData = await _apiService.fetchNews(force: force);
    } catch (e) {
      _setError('Haberler yüklenemedi: $e');
    }
    _isNewsLoading = false;
    notifyListeners();
  }

  Future<void> loadMyPortfolio() async {
    if (_userId == null) return;
    _isPortfolioLoading = true;
    notifyListeners();
    try {
      _myHoldings = await _apiService.fetchUserPortfolio(_userId!);
    } catch (e) {
      _setError('Portföy yüklenemedi: $e');
    }
    _isPortfolioLoading = false;
    notifyListeners();
  }

  Future<void> loadCoachAdvice() async {
    if (_userId == null) return;
    _isCoachLoading = true;
    _coachAdvice = null;
    _coachError = null;
    notifyListeners();

    final result = await _apiService.fetchCoachAdvice(_userId!);
    if (result.containsKey('advice')) {
      _coachAdvice = result['advice'] as String;
    } else {
      _coachError = result['error']?.toString() ?? 'AI yanıt vermedi';
    }

    _isCoachLoading = false;
    notifyListeners();
  }

  Future<bool> generateDemoTrades() async {
    if (_userId == null) return false;
    final result = await _apiService.generateDemoTrades(_userId!);
    if (result['success'] == true) {
      await Future.wait([loadUserBalance(_token), loadMyPortfolio()]);
      return true;
    }
    return false;
  }

  Future<TradeResult> executeBuyOrder(
      String symbol, int quantity, double currentPrice) async {
    if (_userId == null) {
      return TradeResult(success: false, message: 'Giriş yapmalısın');
    }
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

    final result = await _apiService.buyStock(_userId!, symbol, quantity);
    if (result.success) {
      await Future.wait([loadUserBalance(_token), loadMyPortfolio()]);
    }
    return result;
  }

  Future<TradeResult> executeSellOrder(String symbol, int quantity) async {
    if (_userId == null) {
      return TradeResult(success: false, message: 'Giriş yapmalısın');
    }
    if (quantity <= 0) {
      return TradeResult(success: false, message: 'Lot adedi pozitif olmalı');
    }

    final result = await _apiService.sellStock(_userId!, symbol, quantity);
    if (result.success) {
      await Future.wait([loadUserBalance(_token), loadMyPortfolio()]);
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
