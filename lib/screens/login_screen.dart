import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/screens/register_screen.dart';
import 'package:portly/screens/forgot_password_screen.dart';
import 'package:portly/providers/theme_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-posta ve şifre boş bırakılamaz')),
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
    final success = await auth.login(email, password);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Giriş başarısız'),
          backgroundColor: const Color(0xFFFB7185),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final tp = context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            // Sağ üstte sade tema toggle
            Positioned(
              top: 4,
              right: 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => tp.toggle(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      tp.isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: c.textMuted,
                      size: 19,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Tepede brand mark — logo + wordmark, ezici olmasın
                      const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 56),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image(
                                image: AssetImage('assets/images/logo.png'),
                                height: 76,
                                width: 76,
                              ),
                              SizedBox(height: 16),
                              IOSWordmark(fontSize: 24),
                            ],
                          ),
                        ),
                      ),

                      // Hem yeni hem geri dönen kullanıcıya uyan karşılama
                      Text(
                        'Hoş geldin.',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.5,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Hesabına giriş yap.',
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 16,
                          letterSpacing: -0.1,
                        ),
                      ),

                      const SizedBox(height: 44),

                      // Form kartı
                      IOSGroupedCard(
                        children: [
                          IOSField(
                            controller: _emailController,
                            label: 'E-posta',
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          IOSField(
                            controller: _passwordController,
                            label: 'Şifre',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            onSubmitted: _submit,
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
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: context.watch<AuthProvider>().rememberMe,
                                onChanged: (val) => context
                                    .read<AuthProvider>()
                                    .setRememberMe(val ?? true),
                                activeColor: c.textPrimary,
                                checkColor: c.bg,
                                side:
                                    BorderSide(color: c.textSubtle, width: 1.2),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () {
                                final auth = context.read<AuthProvider>();
                                auth.setRememberMe(!auth.rememberMe);
                              },
                              child: Text(
                                'Beni hatırla',
                                style: TextStyle(
                                  color: c.textMuted,
                                  fontSize: 13,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IOSTextLink(
                              label: 'Şifremi unuttum',
                              fontSize: 13,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      IOSPillButton(
                        label: 'Giriş Yap',
                        width: double.infinity,
                        isLoading: _isSubmitting,
                        onPressed: _isSubmitting ? null : _submit,
                      ),
                      const SizedBox(height: 28),
                      // Yeni kullanıcı için ikinci yol — link değil tam genişlik
                      // tipografik CTA. Login'e yanlışlıkla gelen kayıtsız
                      // kullanıcının "nereye gideceğim" anını çözer.
                      Center(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen()),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Hesabın yok mu?',
                                    style: TextStyle(
                                      color: c.textMuted,
                                      fontSize: 14,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Hesap Oluştur',
                                    style: TextStyle(
                                      color: c.warmAccent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_rounded,
                                      size: 15, color: c.warmAccent),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
