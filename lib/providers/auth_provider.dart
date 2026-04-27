import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';
  static const _rememberKey = 'auth_remember'; 

  final ApiService _apiService = ApiService();

  String? _token;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  String? _error;
  bool _rememberMe = true; 

  String? get token => _token;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null && _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int? get userId => _currentUser?['id'] as int?;
  String? get fullName => _currentUser?['full_name'] as String?;
  String? get email => _currentUser?['email'] as String?;
  bool get rememberMe => _rememberMe; 

  AuthProvider() {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
  
      _rememberMe = prefs.getBool(_rememberKey) ?? true;
      if (!_rememberMe) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final savedToken = prefs.getString(_tokenKey);
      final savedUser = prefs.getString(_userKey);

      if (savedToken != null && savedToken.isNotEmpty) {
        _token = savedToken;
        try {
          final freshUser = await _apiService.fetchMe(savedToken);
          _currentUser = freshUser;
          await prefs.setString(_userKey, jsonEncode(freshUser));
        } catch (_) {
          if (savedUser != null) {
            _currentUser = jsonDecode(savedUser) as Map<String, dynamic>;
          } else {
            await prefs.remove(_tokenKey);
            _token = null;
          }
        }
      }
    } catch (e) {
      debugPrint('Auth bootstrap hata: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  void setRememberMe(bool value) {
    _rememberMe = value;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _error = null;
    notifyListeners();

    final result = await _apiService.login(email, password);
    if (result['success'] == true) {
      _token = result['access_token'] as String;
      _currentUser = result['user'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberKey, _rememberMe);

      if (_rememberMe) {
        await prefs.setString(_tokenKey, _token!);
        await prefs.setString(_userKey, jsonEncode(_currentUser));
      } else {
        await prefs.remove(_tokenKey);
        await prefs.remove(_userKey);
      }
      notifyListeners();
      return true;
    } else {
      _error = result['error'] as String? ?? 'Giriş başarısız';
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String email, String password, String fullName) async {
    _error = null;
    notifyListeners();

    final result = await _apiService.register(email, password, fullName);
    if (result['success'] == true) {
      _token = result['access_token'] as String;
      _currentUser = result['user'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberKey, _rememberMe);
      if (_rememberMe) {
        await prefs.setString(_tokenKey, _token!);
        await prefs.setString(_userKey, jsonEncode(_currentUser));
      }
      notifyListeners();
      return true;
    } else {
      _error = result['error'] as String? ?? 'Kayıt başarısız';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    _token = null;
    _currentUser = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
