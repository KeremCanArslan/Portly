import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

/// Oturum açıkken şifre değiştirme (Profil → Ayarlar).
///
/// `ForgotPasswordScreen` e-posta kodu ister ve mail gönderimi hâlâ Brevo
/// anahtarını bekliyor; giriş yapmış kullanıcının şifresini değiştirmesi
/// için o yolu beklemeye gerek yok — mevcut şifre kimlik kanıtı olarak
/// yeterli.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _repeatController = TextEditingController();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;

    if (current.isEmpty) {
      _showError('Mevcut şifreni gir');
      return;
    }
    if (next.length < 8) {
      _showError('Yeni şifre en az 8 karakter olmalı');
      return;
    }
    if (next != _repeatController.text) {
      _showError('Yeni şifreler eşleşmiyor');
      return;
    }
    if (next == current) {
      _showError('Yeni şifre eskisiyle aynı olamaz');
      return;
    }

    setState(() => _loading = true);
    final error =
        await context.read<AuthProvider>().changePassword(current, next);
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      _showError(error);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Şifren güncellendi. Diğer cihazlardaki oturumlar '
            'kapatıldı.'),
      ),
    );
    Navigator.of(context).pop();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFB7185),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'Şifreni\ndeğiştir.',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 40,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1.5,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Mevcut şifreni ve yeni şifreni gir.\n'
                    'Değişiklikten sonra diğer cihazlardaki oturumlar kapanır.',
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 15,
                      letterSpacing: -0.1,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 40),
                  IOSGroupedCard(
                    children: [
                      IOSField(
                        controller: _currentController,
                        label: 'Mevcut şifre',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscure,
                        enabled: !_loading,
                        suffix: IconButton(
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          splashRadius: 18,
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: c.textSubtle,
                            size: 19,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  IOSGroupedCard(
                    children: [
                      IOSField(
                        controller: _newController,
                        label: 'Yeni şifre',
                        icon: Icons.lock_reset_rounded,
                        obscureText: _obscure,
                        enabled: !_loading,
                      ),
                      IOSField(
                        controller: _repeatController,
                        label: 'Yeni şifre (tekrar)',
                        icon: Icons.lock_reset_rounded,
                        obscureText: _obscure,
                        onSubmitted: _submit,
                        enabled: !_loading,
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  IOSPillButton(
                    label: 'Şifreyi Değiştir',
                    width: double.infinity,
                    isLoading: _loading,
                    onPressed: _loading ? null : _submit,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
