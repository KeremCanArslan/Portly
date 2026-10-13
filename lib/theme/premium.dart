// ============================================================================
// Elite tasarım sistemi temeli (Module F-core — ADDITIVE, henüz BAĞLI DEĞİL).
//
// Bu dosya gated UI batch'lerinin ortak görsel sözlüğüdür. Hiçbir ekrana
// bağlanmadığı için ZERO görsel regresyon getirir. Mevcut app_theme.dart
// içindeki Premium* widget'larına DOKUNULMAZ (ekranlar onlara bağımlı);
// burada ayrı `Elite*` isim alanı kullanılır.
//
// Data-ink disiplini (sıkı):
//   • Saf siyah zemin, yüzeyler yalnız ton farkıyla ayrılır.
//   • GLOW YOK (boxShadow yok). Border.all YOK (yüzey kenarsız; ayrım
//     gerekirse 0.5px hairline tek-çizgi — kutu kenarı değil).
//   • Monokrom; yeşil/kırmızı YALNIZCA finansal veri (c.positive/negative).
//   • fontFeatures/tnum YOK, CustomPainter metni YOK (html-renderer kuralı).
//   • Cömert boşluk, net tipografik hiyerarşi, yumuşak geçişler.
// ============================================================================
import 'package:flutter/material.dart';
import 'package:portly/theme/app_theme.dart';

/// 4'lük tabana oturan boşluk ölçeği — tutarlı ritim için.
class EliteSpace {
  EliteSpace._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Yumuşak köşe yarıçapları.
class EliteRadii {
  EliteRadii._();
  static const Radius rSm = Radius.circular(10);
  static const Radius rMd = Radius.circular(16);
  static const Radius rLg = Radius.circular(22);
  static const BorderRadius sm = BorderRadius.all(rSm);
  static const BorderRadius md = BorderRadius.all(rMd);
  static const BorderRadius lg = BorderRadius.all(rLg);
}

/// Mikro-etkileşim zamanlamaları — her yerde aynı his.
class EliteMotion {
  EliteMotion._();
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
  static const Curve curve = Curves.easeOutCubic;
}

/// Kenarsız, gölgesiz yüzey kartı (data-ink). Yalnız ton + yarıçap.
class EliteSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool elevatedTone; // surfaceAlt kullan (hafif daha yüksek ton)

  const EliteSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(EliteSpace.md),
    this.onTap,
    this.elevatedTone = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final body = AnimatedContainer(
      duration: EliteMotion.fast,
      curve: EliteMotion.curve,
      padding: padding,
      decoration: BoxDecoration(
        color: elevatedTone ? c.surfaceAlt : c.surface,
        borderRadius: EliteRadii.md,
        // GLOW/BORDER YOK — data-ink.
      ),
      child: child,
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: EliteRadii.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashFactory: InkRipple.splashFactory,
        child: body,
      ),
    );
  }
}

/// Bölüm başlığı — küçük, harf aralıklı, soluk (elit hiyerarşi).
class EliteSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const EliteSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(
          left: EliteSpace.xxs, bottom: EliteSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: c.textSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 0.5px hairline ayraç — kutu kenarı değil, tek çizgi.
class EliteHairline extends StatelessWidget {
  final double indent;
  const EliteHairline({super.key, this.indent = 0});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Container(
      height: 0.5,
      margin: EdgeInsets.only(left: indent),
      color: c.divider,
    );
  }
}

/// Zarif yükleme bloku — shimmer/gradient YOK; ince opaklık nabzı.
class EliteSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius radius;
  const EliteSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = EliteRadii.sm,
  });

  @override
  State<EliteSkeleton> createState() => _EliteSkeletonState();
}

class _EliteSkeletonState extends State<EliteSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 0.7).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: widget.radius,
        ),
      ),
    );
  }
}

/// İçerik geçişlerinde yumuşak fade + hafif yükseliş.
class EliteFade extends StatelessWidget {
  final Widget child;
  const EliteFade({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: EliteMotion.base,
      switchInCurve: EliteMotion.curve,
      switchOutCurve: EliteMotion.curve,
      transitionBuilder: (w, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(anim),
          child: w,
        ),
      ),
      child: child,
    );
  }
}
