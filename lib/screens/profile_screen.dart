import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/providers/theme_provider.dart';
import 'package:portly/screens/change_password_screen.dart';
import 'package:portly/utils/snackbar.dart';
import 'package:portly/screens/risk_profile_test_screen.dart';
import 'package:portly/screens/missions_screen.dart';
import 'package:portly/screens/education_screen.dart';
import 'package:portly/screens/transaction_history_screen.dart';
import 'package:portly/screens/gold_rates_screen.dart';
import 'package:portly/screens/alerts_screen.dart';
import 'package:portly/screens/investor_journal_screen.dart';
import 'package:portly/screens/login_screen.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final portfolio = context.watch<PortfolioProvider>();
    final c = AppColorsExt.of(context);
    final email = auth.email ?? '';
    final name = auth.fullName ?? email;
    final totalAsset = portfolio.totalAssetValue;
    final profile = auth.riskProfile;

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
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                // Avatar + ad — editorial sade
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          name.isNotEmpty
                              ? name.substring(0, 1).toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textMuted,
                                fontSize: 13,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Stat grouped card
                IOSGroupedCard(
                  children: [
                    _statRow(
                      context,
                      label: 'Toplam Varlık',
                      value: '₺${_fmt(totalAsset)}',
                    ),
                    _statRow(
                      context,
                      label: 'Risk Profili',
                      value: profile ?? 'Test edilmedi',
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                const IOSSectionHeader(label: 'Yatırımcı'),
                IOSGroupedCard(
                  children: [
                    IOSListRow(
                      icon: Icons.psychology_outlined,
                      title: 'Risk Profili Testi',
                      subtitle: profile == null
                          ? 'Yatırımcı kişiliğini öğren'
                          : 'Profilini güncelle',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RiskProfileTestScreen()),
                      ),
                    ),
                    IOSListRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'İşlem Geçmişi',
                      subtitle: 'AL/SAT kayıtları',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TransactionHistoryScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const IOSSectionHeader(label: 'Eğitim & Pratik'),
                IOSGroupedCard(
                  children: [
                    IOSListRow(
                      icon: Icons.school_outlined,
                      title: 'Akademi',
                      subtitle: '$academyLessonCount ders, $academyCategoryCount kategori',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EducationScreen()),
                      ),
                    ),
                    IOSListRow(
                      icon: Icons.emoji_events_outlined,
                      title: 'Görevler & Rozetler',
                      subtitle: 'XP ve başarımların',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MissionsScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const IOSSectionHeader(label: 'Araçlar'),
                IOSGroupedCard(
                  children: [
                    const _AlertsRow(),
                    IOSListRow(
                      icon: Icons.menu_book_outlined,
                      title: 'Yatırımcı Günlüğü',
                      subtitle: 'Not ve gözlemlerin',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const InvestorJournalScreen()),
                      ),
                    ),
                    IOSListRow(
                      icon: Icons.savings_outlined,
                      title: 'Banka Altın Karşılaştırma',
                      subtitle: 'Hangi banka en uygun?',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const GoldRatesScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const IOSSectionHeader(label: 'Ayarlar'),
                Builder(builder: (ctx) {
                  final tp = ctx.watch<ThemeProvider>();
                  return IOSGroupedCard(
                    children: [
                      IOSListRow(
                        icon: tp.isDark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        title: 'Tema',
                        subtitle: tp.isDark ? 'Koyu mod' : 'Açık mod',
                        trailing: Switch(
                          value: tp.isDark,
                          onChanged: (_) => tp.toggle(),
                          activeColor: c.textPrimary,
                          activeTrackColor:
                              c.textPrimary.withValues(alpha: 0.3),
                          inactiveTrackColor: c.surfaceAlt,
                        ),
                      ),
                      IOSListRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'Şifre Değiştir',
                        subtitle: 'Hesap şifreni güncelle',
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                              builder: (_) => const ChangePasswordScreen()),
                        ),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 24),

                // Çıkış — secondary pill (gri, vurgu az)
                IOSPillButton(
                  label: 'Çıkış Yap',
                  icon: Icons.logout_rounded,
                  secondary: true,
                  width: double.infinity,
                  onPressed: () => _confirmLogout(context),
                ),
                const SizedBox(height: 10),
                // Hesap silme: geri dönüşü yok → çıkışla aynı görsel ağırlıkta
                // OLMAMALI, ama saklanmamalı da (KVKK silme hakkı bulunabilir
                // olmalı). Sönük metin bağlantısı bu dengeyi kuruyor.
                Center(
                  child: IOSTextLink(
                    label: 'Hesabımı Sil',
                    fontSize: 13,
                    onTap: () => _confirmDeleteAccount(context),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Portly',
                    style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 11,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statRow(BuildContext context,
      {required String label, required String value}) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.textMuted,
              fontSize: 14,
              letterSpacing: -0.1,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showIOSBottomSheet(
      context: context,
      title: 'Çıkış Yap',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (ctx) {
              final c = AppColorsExt.of(ctx);
              return Text(
                'Hesabından çıkmak istediğine emin misin?',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 14,
                  letterSpacing: -0.1,
                  height: 1.5,
                ),
              );
            }),
            const SizedBox(height: 20),
            IOSPillButton(
              label: 'Çıkış Yap',
              width: double.infinity,
              onPressed: () async {
                Navigator.pop(context);
                await context.read<AuthProvider>().logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            IOSPillButton(
              label: 'Vazgeç',
              secondary: true,
              width: double.infinity,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Hesap silme onayı — şifre ister, sonucu geri döndürülemez.
  ///
  /// İki kapı var: (1) şifre alanı (token çalınmışsa silinemesin),
  /// (2) neyin gideceğini açıkça yazan uyarı. "Emin misin?" tek başına
  /// yetersizdi: kullanıcı portföyünün de silineceğini bilmeli.
  void _confirmDeleteAccount(BuildContext context) {
    final passwordController = TextEditingController();
    bool busy = false;

    showIOSBottomSheet(
      context: context,
      title: 'Hesabımı Sil',
      child: StatefulBuilder(builder: (sheetContext, setSheetState) {
        final c = AppColorsExt.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hesabın, portföyün, işlem geçmişin, izleme listen, notların '
                've alarmların kalıcı olarak silinir. Bu işlem geri alınamaz.',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 14,
                  letterSpacing: -0.1,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              IOSGroupedCard(
                children: [
                  IOSField(
                    controller: passwordController,
                    label: 'Şifren',
                    icon: Icons.lock_outline_rounded,
                    obscureText: true,
                    enabled: !busy,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              IOSPillButton(
                label: 'Hesabımı Kalıcı Olarak Sil',
                width: double.infinity,
                isLoading: busy,
                onPressed: busy
                    ? null
                    : () async {
                        final password = passwordController.text;
                        if (password.isEmpty) {
                          showAppSnackBar(sheetContext, 'Şifreni gir',
                              isError: true);
                          return;
                        }
                        setSheetState(() => busy = true);
                        final error = await context
                            .read<AuthProvider>()
                            .deleteAccount(password);
                        if (!sheetContext.mounted) return;
                        if (error != null) {
                          setSheetState(() => busy = false);
                          showAppSnackBar(sheetContext, error, isError: true);
                          return;
                        }
                        Navigator.pop(sheetContext);
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()),
                            (_) => false,
                          );
                        }
                      },
              ),
              const SizedBox(height: 10),
              IOSPillButton(
                label: 'Vazgeç',
                secondary: true,
                width: double.infinity,
                onPressed: busy ? null : () => Navigator.pop(sheetContext),
              ),
            ],
          ),
        );
      }),
    );
  }

  static String _fmt(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final dec = parts.length > 1 ? parts[1] : '00';
    final buf = StringBuffer();
    final isNeg = intPart.startsWith('-');
    final digits = isNeg ? intPart.substring(1) : intPart;
    final n = digits.length;
    for (int i = 0; i < n; i++) {
      buf.write(digits[i]);
      final remaining = n - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write('.');
    }
    return '${isNeg ? '−' : ''}${buf.toString()},$dec';
  }
}

/// Profil "Fiyat Alarmları" satırı — tetiklenmiş ama görülmemiş alarm varsa
/// monokrom sayaç rozeti gösterir (e-posta teslimatından bağımsız uygulama-içi
/// sinyal). Ekran açılınca [AlertsScreen] alarmları "görüldü" işaretler →
/// geri dönünce sayaç yeniden çekilir, rozet temizlenir.
class _AlertsRow extends StatefulWidget {
  const _AlertsRow();

  @override
  State<_AlertsRow> createState() => _AlertsRowState();
}

class _AlertsRowState extends State<_AlertsRow> {
  final ApiService _api = ApiService();
  int _unseen = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await _api.fetchUnseenAlertCount();
    if (mounted) setState(() => _unseen = n);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return IOSListRow(
      icon: Icons.notifications_active_outlined,
      title: 'Fiyat Alarmları',
      subtitle: _unseen > 0
          ? '$_unseen alarm tetiklendi'
          : 'Seviye uyarıları',
      trailing: _unseen == 0
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.textPrimary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$_unseen',
                    style: TextStyle(
                      color: c.bg,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: c.textSubtle, size: 22),
              ],
            ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AlertsScreen()),
        );
        _refresh();
      },
    );
  }
}
