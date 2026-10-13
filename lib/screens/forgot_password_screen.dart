import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();

  final _api = ApiService();

  bool _codeSent = false;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Geçerli bir e-posta gir');
      return;
    }
    setState(() => _loading = true);
    final result = await _api.forgotPassword(email);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      setState(() => _codeSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Kod e-postana gönderildi (gelmediyse spam klasörünü kontrol et)'),
        ),
      );
    } else {
      _showError(result['error'] as String? ?? 'İstek başarısız');
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;

    if (code.length != 6) {
      _showError('Kod 6 haneli olmalı');
      return;
    }
    if (newPassword.length < 8) {
      _showError('Şifre en az 8 karakter olmalı');
      return;
    }

    setState(() => _loading = true);
    final result = await _api.resetPassword(email, code, newPassword);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Şifre güncellendi, yeni şifrenle giriş yapabilirsin'),
        ),
      );
      Navigator.of(context).pop();
    } else {
      _showError(result['error'] as String? ?? 'İstek başarısız');
    }
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
        backgroundColor: AppColorsExt.of(context)
            .bg, // opak: şeffaf AppBar açık temada ghost bırakıyor
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
                  // State-aware başlık
                  Text(
                    _codeSent ? 'Kodu\ngir.' : 'Şifreni mi\nunuttun?',
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
                    _codeSent
                        ? 'E-postana 6 haneli bir kod gönderdik.\nKodu ve yeni şifreni gir.'
                        : 'E-posta adresini yaz.\nSıfırlama kodunu sana göndereceğiz.',
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
                        controller: _emailController,
                        label: 'E-posta',
                        icon: Icons.alternate_email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_codeSent && !_loading,
                      ),
                    ],
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 14),
                    IOSGroupedCard(
                      children: [
                        IOSField(
                          controller: _codeController,
                          label: '6 haneli kod',
                          icon: Icons.pin_outlined,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          letterSpacing: 6,
                          enabled: !_loading,
                        ),
                        IOSField(
                          controller: _newPasswordController,
                          label: 'Yeni şifre',
                          icon: Icons.lock_outline_rounded,
                          obscureText: _obscurePassword,
                          onSubmitted: _resetPassword,
                          enabled: !_loading,
                          suffix: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            splashRadius: 18,
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: c.textSubtle,
                              size: 19,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 26),
                  IOSPillButton(
                    label: _codeSent ? 'Şifreyi Sıfırla' : 'Kodu Gönder',
                    width: double.infinity,
                    isLoading: _loading,
                    onPressed: _loading
                        ? null
                        : (_codeSent ? _resetPassword : _sendCode),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: IOSTextLink(
                        label: 'Farklı bir e-posta gir',
                        fontSize: 13,
                        onTap: _loading
                            ? () {}
                            : () {
                                setState(() {
                                  _codeSent = false;
                                  _codeController.clear();
                                  _newPasswordController.clear();
                                });
                              },
                      ),
                    ),
                  ],
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
