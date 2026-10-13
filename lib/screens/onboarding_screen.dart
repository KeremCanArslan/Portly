import 'package:flutter/material.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

/// İlk-açılış tanıtım turu — uygulama ilk kez açıldığında bir kez gösterilir
/// (AuthGate, `onboarding_seen` flag'i ile tetikler). Kaydırmalı kartlar +
/// atlanabilir. Data-ink: monokrom, Border.all yok, glow yok; vurgu yalnız
/// warmAccent (marka) ve nokta göstergesinde.
class OnboardingScreen extends StatefulWidget {
  /// Tur bitince ya da atlanınca çağrılır (flag'i set eder, ana akışa geçer).
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String body;
  const _OnboardingPage(this.icon, this.title, this.body);
}

const List<_OnboardingPage> _pages = [
  _OnboardingPage(
    Icons.auto_awesome,
    'Portly\'ye Hoş Geldin',
    'Gerçek portföyünü ekle; haberlerini, analizlerini ve sinyallerini '
        'tek yerden takip et. Birkaç adımda uygulamayı tanıyalım.',
  ),
  _OnboardingPage(
    Icons.account_balance_wallet_outlined,
    'Portföyünü Ekle',
    'Hisse, altın, döviz ve kripto pozisyonlarını lot + maliyetle ya da '
        'ekran görüntüsünden içe aktar; değerini ve kâr/zararını canlı izle.',
  ),
  _OnboardingPage(
    Icons.insights_outlined,
    'Alım-Satım Sinyalleri',
    'Portföyün ve izleme listen için teknik + temel analize dayalı '
        'AL/TUT/SAT sinyalleri al; gerekçeleriyle birlikte, tavsiye değil.',
  ),
  _OnboardingPage(
    Icons.menu_book_outlined,
    'Haberler, AI Koç & Akademi',
    'Sembollerinin gerçek zamanlı haberlerini takip et; AI Koç\'a portföyünü '
        'sor, stres testi ve akademiyle öğrenmeye devam et.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      widget.onDone();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final isLast = _index == _pages.length - 1;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Atla — sağ üstte; son sayfada gizlenir (zaten "Başla" var).
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: isLast ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: isLast ? null : widget.onDone,
                  child: Text(
                    'Atla',
                    style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // İlk sayfa: marka logosu; sonrakiler: konu ikonu.
                        if (i == 0)
                          const Image(
                            image: AssetImage('assets/images/logo.png'),
                            height: 96,
                            width: 96,
                          )
                        else
                          Icon(p.icon, size: 72, color: c.warmAccent),
                        const SizedBox(height: 36),
                        Text(
                          p.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: 15,
                            height: 1.55,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Nokta göstergesi
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active ? c.warmAccent : c.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: IOSPillButton(
                label: isLast ? 'Başla' : 'İleri',
                icon: isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                width: double.infinity,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
