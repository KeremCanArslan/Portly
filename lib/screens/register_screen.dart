import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tüm alanları doldur')),
      );
      return;
    }
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifre en az 8 karakter olmalı')),
      );
      return;
    }
    final emailOk = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(email);
    if (!emailOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Geçerli bir e-posta gir (örn. ad@site.com)'),
          backgroundColor: Color(0xFFFB7185),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.register(email, password, name);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Kayıt başarısız'),
          backgroundColor: const Color(0xFFFB7185),
        ),
      );
    }
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
                  // Marketing copy — burada haklı kullanım: yeni kullanıcıyı ikna et
                  Text(
                    'Sade. Akıllı.\nYatırım.',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 44,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1.8,
                      height: 1.04,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Risksiz simülatörde gerçek piyasayı dene.\nGerçek para yok, gerçek dersler var.',
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
                        controller: _nameController,
                        label: 'Ad Soyad',
                        icon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                      ),
                      IOSField(
                        controller: _emailController,
                        label: 'E-posta',
                        icon: Icons.alternate_email_rounded,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      IOSField(
                        controller: _passwordController,
                        label: 'Şifre (en az 8 karakter)',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        onSubmitted: _submit,
                        suffix: IconButton(
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
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
                  const SizedBox(height: 26),
                  IOSPillButton(
                    label: 'Hesap Oluştur',
                    width: double.infinity,
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Kayıt olarak Portly\'nin eğitim amaçlı kullanım\nkoşullarını kabul etmiş sayılırsın.',
                    style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 12,
                      height: 1.55,
                      letterSpacing: -0.1,
                    ),
                    textAlign: TextAlign.center,
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
