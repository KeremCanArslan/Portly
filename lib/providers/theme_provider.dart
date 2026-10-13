import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Açık/koyu tema yönetimi.
///
/// Şu anda çoğu ekran hardcoded koyu renkler kullanıyor; bu provider tema
/// modunu saklar ve yeni geliştirilen widget'lar `theme.brightness`'a göre
/// renk seçimi yapabilir. Tam geçiş için tüm hardcoded `Color(0xFF...)`
/// değerlerinin `Theme.of(context)` ile değiştirilmesi gerekir.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.dark;

  ThemeProvider() {
    _load();
  }

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == 'light') _mode = ThemeMode.light;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }
}

/// Tema-aware renk paleti. Tüm widget'lar bunu kullanmalı.
class AppColors {
  final bool isDark;
  const AppColors._(this.isDark);

  factory AppColors.of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return AppColors._(brightness == Brightness.dark);
  }

  Color get bg => isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get card => isDark ? const Color(0xFF1E1E1E) : Colors.white;
  Color get cardAlt =>
      isDark ? const Color(0xFF161616) : const Color(0xFFF0F2F5);
  Color get text => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textMuted => isDark ? Colors.grey[400]! : Colors.grey[700]!;
  Color get textSubtle => isDark ? Colors.grey[600]! : Colors.grey[500]!;
  Color get border => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.08);
  // Marka aksanı her temada teal — değişmez
  Color get accent => const Color(0xFF14B8A6);
}
