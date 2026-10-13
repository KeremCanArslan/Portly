import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/services/api_service.dart';

// kullanıcı giriş/çıkış durumunu yönetir
// token SharedPreferences'ta saklanıyor, uygulama kapansa bile oturumu koruyor
class AuthProvider extends ChangeNotifier {
  // SharedPreferences key'leri - bunları değiştirme, kaydedilmiş veriler bozulur
  static const _tokenKey = 'auth_token';
  static const _refreshKey = 'auth_refresh';
  static const _userKey = 'auth_user';
  static const _rememberKey = 'auth_remember';

  final ApiService _apiService = ApiService();

  String? _token;
  String? _refreshToken;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true; // başlangıçta true, token kontrol edilene kadar
  String? _error;
  bool _rememberMe = true; // varsayılan olarak beni hatırla açık

  // getter'lar
  String? get token => _token;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null && _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int? get userId => _currentUser?['id'] as int?;
  String? get fullName => _currentUser?['full_name'] as String?;
  String? get email => _currentUser?['email'] as String?;
  String? get riskProfile => _currentUser?['risk_profile'] as String?;
  bool get rememberMe => _rememberMe;

  AuthProvider() {
    // Oturum İÇİNDE 401 alan her istek buraya düşer (bkz.
    // ApiService.onUnauthorized) — token'ı yenileyip isteği tekrarlatır.
    ApiService.onUnauthorized = handleUnauthorized;
    // constructor'da hemen token kontrolü başlat
    _bootstrap();
  }

  /// Bir API isteği 401 aldığında çağrılır. Yeni access token döner; oturum
  /// kurtarılamıyorsa null döner ve oturum kapatılır (kullanıcı giriş ekranına).
  ///
  /// [staleToken] isteğin kullandığı token. Elde bundan FARKLI bir token varsa
  /// aradaki bir başka istek zaten yenilemiş demektir: ikinci bir
  /// `/auth/refresh` turu (refresh token tek kullanımlık) gereksizdir.
  Future<String?> handleUnauthorized(String? staleToken) async {
    final current = _token;
    if (current == null) return null; // çıkış yapılmış — dirilme yok
    if (staleToken != null && staleToken != current) return current;

    final prefs = await SharedPreferences.getInstance();
    if (_token == null) return null; // ağ turu sürerken çıkış yapıldı
    if (await _tryRefresh(prefs)) return _token;
    if (_token == null) return null;
    await _clearSession(prefs);
    notifyListeners();
    return null;
  }

  // uygulama açılırken kayıtlı token'ı oku ve kullanıcıyı otomatik giriş yap
  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // "beni hatırla" kapalıysa direkt login ekranına git
      _rememberMe = prefs.getBool(_rememberKey) ?? true;
      if (!_rememberMe) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final savedToken = prefs.getString(_tokenKey);
      final savedRefresh = prefs.getString(_refreshKey);
      final savedUser = prefs.getString(_userKey);

      if (savedToken != null && savedToken.isNotEmpty) {
        _token = savedToken;
        _refreshToken = savedRefresh;
        ApiService.authToken = savedToken;

        // ⚡ AÇILIŞ HIZI: elde kayıtlı kullanıcı varsa uygulamayı HEMEN aç,
        // token doğrulamasını ARKADAN yap. Eskiden `fetchMe` beklenirken tüm
        // uygulama boş bir spinner'daydı → Render ücretsiz katman uykudan
        // kalkıyorsa kullanıcı 50 sn boş ekrana bakıyordu. Doğrulama
        // başarısız olursa (401 + refresh de tutmazsa) oturum kapatılır ve
        // giriş ekranına düşülür. Aynı "önce cache, arkadan taze" deseni
        // portföy ve fiyatlarda zaten kullanılıyor.
        if (savedUser != null) {
          try {
            _currentUser = jsonDecode(savedUser) as Map<String, dynamic>;
          } catch (_) {
            _currentUser = null;
          }
          if (_currentUser != null) {
            _isLoading = false;
            notifyListeners();
            unawaited(_revalidateSession(prefs, savedRefresh));
            return;
          }
        }

        try {
          // token geçerli mi diye backend'e sor, kullanıcı verilerini tazele
          final freshUser = await _apiService.fetchMe(savedToken);
          _currentUser = freshUser;
          await prefs.setString(_userKey, jsonEncode(freshUser));
        } on ApiException catch (e) {
          // 401 — access token süresi dolmuş olabilir, refresh dene
          if (e.statusCode == 401 && savedRefresh != null) {
            final refreshed = await _tryRefresh(prefs);
            if (refreshed) {
              try {
                final freshUser = await _apiService.fetchMe(_token!);
                _currentUser = freshUser;
                await prefs.setString(_userKey, jsonEncode(freshUser));
              } catch (_) {
                await _clearSession(prefs);
              }
            } else {
              await _clearSession(prefs);
            }
          } else if (savedUser != null) {
            _currentUser = jsonDecode(savedUser) as Map<String, dynamic>;
          } else {
            await _clearSession(prefs);
          }
        } catch (_) {
          // Network hatası — önbellekteki kullanıcı verisiyle devam et
          if (savedUser != null) {
            _currentUser = jsonDecode(savedUser) as Map<String, dynamic>;
          } else {
            await _clearSession(prefs);
          }
        }
      }
    } catch (e) {
      debugPrint('Auth bootstrap hata: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Açılışta cache'teki kullanıcıyla ekranı açtıktan SONRA token'ı doğrular.
  /// Geçerliyse kullanıcı verisi sessizce tazelenir; 401 ise refresh denenir;
  /// o da tutmazsa oturum kapatılır (kullanıcı giriş ekranına düşer).
  /// Ağ hatası oturumu KAPATMAZ — çevrimdışıyken kullanıcı atılmamalı.
  ///
  /// ⚠️ Bu iş ARKA PLANDA koşar (`unawaited`) ve Render ücretsiz katman
  /// uykudan kalkıyorsa `fetchMe` 50 sn sürebilir. Kullanıcı o sırada ÇIKIŞ
  /// yapabilir: her `await` dönüşünde oturumun hâlâ açık olduğu (`_token`)
  /// doğrulanmazsa kapanmış oturumun üstüne yazılır — kullanıcı verisi geri
  /// gelir, `_tryRefresh` diske yeni token yazar ve kullanıcı çıkış yaptığı
  /// halde girişli görünür. Bu yüzden her dönüşte erken çıkış var.
  Future<void> _revalidateSession(
      SharedPreferences prefs, String? savedRefresh) async {
    final token = _token;
    if (token == null) return;
    try {
      final freshUser = await _apiService.fetchMe(token);
      if (_token == null) return; // arada çıkış yapıldı
      _currentUser = freshUser;
      await prefs.setString(_userKey, jsonEncode(freshUser));
      notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode != 401) return; // sunucu hatası → oturuma dokunma
      if (_token == null) return;
      if (savedRefresh != null && await _tryRefresh(prefs)) {
        final rotated = _token;
        if (rotated == null) return;
        try {
          final freshUser = await _apiService.fetchMe(rotated);
          if (_token == null) return;
          _currentUser = freshUser;
          await prefs.setString(_userKey, jsonEncode(freshUser));
          notifyListeners();
          return;
        } catch (_) {/* aşağıda oturum kapatılır */}
      }
      if (_token == null) return;
      await _clearSession(prefs);
      notifyListeners();
    } catch (_) {
      // Ağ/timeout — çevrimdışı olabilir; cache'teki oturumla devam.
    }
  }

  Future<bool> _tryRefresh(SharedPreferences prefs) async {
    if (_refreshToken == null || _refreshToken!.isEmpty) return false;
    final result = await _apiService.refreshAccessToken(_refreshToken!);
    if (result == null) return false;
    // Ağ turu sürerken kullanıcı çıkış yapmış olabilir; yenilenen token'ı
    // yazmak kapanmış oturumu DİRİLTİRDİ (diske de yazılıyor).
    if (_refreshToken == null) return false;
    _token = result['access_token'];
    _refreshToken = result['refresh_token'];
    ApiService.authToken = _token;
    if (_rememberMe) {
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_refreshKey, _refreshToken!);
    }
    return true;
  }

  Future<void> _clearSession(SharedPreferences prefs) async {
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    // Kullanıcı cache'i de silinir: açılış artık cache'teki kullanıcıyla
    // ekranı hemen açıyor (bkz. _bootstrap) → bayat kayıt kalırsa geçersiz
    // oturum bir sonraki açılışta yeniden "girişli" gibi görünürdü.
    await prefs.remove(_userKey);
    _token = null;
    _refreshToken = null;
    _currentUser = null;
    ApiService.authToken = null;
  }

  /// Açılışta "beni hatırla" ile saklanmış oturumun kullanıcı kimliği (yoksa
  /// null). `_bootstrap` bu kaydı okuyup girişi geri yüklemeden ÖNCE de
  /// çağrılabilir: PortfolioProvider bunu izleme listesini doğru prefs
  /// anahtarından (`watchlist_<id>`) okumak için kullanıyor — aksi hâlde
  /// açılışta önce varsayılan 8 sembolle, sonra gerçek listeyle iki ayrı
  /// fiyat isteği gidiyordu. Oturum kapanınca (`logout`/`_clearSession`)
  /// `_userKey` silindiği için burası null döner, yani çıkıştan sonra eski
  /// kullanıcının listesi okunmaz.
  static int? rememberedUserId(SharedPreferences prefs) {
    if (!(prefs.getBool(_rememberKey) ?? true)) return null;
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final user = jsonDecode(raw);
      if (user is Map && user['id'] is int) return user['id'] as int;
    } catch (_) {/* bozuk kayıt — kimlik bilinmiyor */}
    return null;
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
      _refreshToken = result['refresh_token'] as String?;
      ApiService.authToken = _token;
      _currentUser = result['user'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberKey, _rememberMe);

      // "beni hatırla" açıksa disk'e yaz, değilse sadece bellekte tut
      if (_rememberMe) {
        await prefs.setString(_tokenKey, _token!);
        if (_refreshToken != null) {
          await prefs.setString(_refreshKey, _refreshToken!);
        }
        await prefs.setString(_userKey, jsonEncode(_currentUser));
      } else {
        await prefs.remove(_tokenKey);
        await prefs.remove(_refreshKey);
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
      _refreshToken = result['refresh_token'] as String?;
      ApiService.authToken = _token;
      _currentUser = result['user'] as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberKey, _rememberMe);
      if (_rememberMe) {
        await prefs.setString(_tokenKey, _token!);
        if (_refreshToken != null) {
          await prefs.setString(_refreshKey, _refreshToken!);
        }
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

  /// Şifreyi değiştirir. Hata mesajını döner (null = başarı).
  ///
  /// Sunucu diğer cihazların oturumunu düşürüyor; bu cihazın yeni refresh
  /// token'ı yanıttan alınıp yerine yazılır, yoksa 60 dk sonra bu cihaz da
  /// dışarı düşerdi.
  Future<String?> changePassword(
      String currentPassword, String newPassword) async {
    final result =
        await _apiService.changePassword(currentPassword, newPassword);
    if (result['success'] != true) {
      return result['error'] as String? ?? 'Şifre değiştirilemedi';
    }
    final fresh = result['refresh_token'] as String?;
    if (fresh != null && fresh.isNotEmpty) {
      _refreshToken = fresh;
      if (_rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_refreshKey, fresh);
      }
    }
    return null;
  }

  /// Hesabı siler. Hata mesajını döner (null = başarı).
  /// Başarıda yerel oturum da temizlenir — sunucuda karşılığı kalmadı.
  Future<String?> deleteAccount(String password) async {
    final result = await _apiService.deleteAccount(password);
    if (result['success'] != true) {
      return result['error'] as String? ?? 'Hesap silinemedi';
    }
    final prefs = await SharedPreferences.getInstance();
    await _clearSession(prefs);
    notifyListeners();
    return null;
  }

  Future<bool> setRiskProfile(String profile) async {
    final updated = await _apiService.updateRiskProfile(profile);
    if (updated == null) return false;
    _currentUser = updated;
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_userKey, jsonEncode(_currentUser));
    }
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    // Bellek içi oturum ÖNCE düşer, ağ/disk işleri sonra. Sırası önemli:
    // sunucuya çıkış isteği atarken arka planda dönen `_revalidateSession`
    // hâlâ dolu bir `_token` görürse yanıtı geldiğinde oturumu geri yazardı.
    // Sunucu ucu Bearer başlığı beklediği için token yerel değişkende taşınır.
    final revoking = _token;
    _token = null;
    _refreshToken = null;
    _currentUser = null;
    ApiService.authToken = null;
    notifyListeners();

    await _apiService.logoutFromServer(token: revoking);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_userKey);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
