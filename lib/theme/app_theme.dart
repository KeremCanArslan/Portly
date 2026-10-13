import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';

/// Portly premium tema sistemi.
/// Renk paleti: Zümrüt (#10B981) + Platin (#D6DAE0) + Lacivert (#0B1220).
/// Hem koyu hem açık modda VIP yatırımcı hissi veren tonlar.
class AppTheme {
  // Marka renkleri — tüm temalarda sabit
  static const emerald = Color(0xFF10B981);
  static const emeraldDark = Color(0xFF059669);
  static const platinum = Color(0xFFD6DAE0);
  static const gold = Color(0xFFE0B96D);
  static const danger = Color(0xFFEF5350);
  static const success = Color(0xFF26A69A);

  // Data-ink monokrom: bg pure black, surface'lar sadece ton farkıyla ayrılır.
  // Emerald'ı `accent` slot'undan çıkardık — beyaz/antrasit dominasyonu.
  // Yeşil/kırmızı YALNIZCA c.positive / c.negative üzerinden veri için.
  static ThemeData dark() {
    const bg = Colors.black;
    const surface = Color(0xFF0E0E0E); // grouped card için çok hafif lift
    const surfaceAlt = Color(0xFF1A1A1A); // input/chip için biraz daha
    const onSurface = Colors.white;
    const onSurfaceMuted = Color(0xFFB3B3B3); // grey.shade400 civarı
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      primaryColor: Colors.white,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Color(0xFFB3B3B3),
        surface: surface,
        onSurface: onSurface,
        error: danger,
      ),
      cardColor: surface,
      dividerColor: const Color(0xFF1F1F1F),
      fontFamily: 'Inter',
      textTheme: _textTheme(onSurface, onSurfaceMuted),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
            color: onSurface, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      extensions: const [
        AppColorsExt(
          bg: bg,
          surface: surface,
          surfaceAlt: surfaceAlt,
          textPrimary: onSurface,
          textMuted: onSurfaceMuted,
          textSubtle: Color(0xFF6E6E6E), // grey.shade600
          border: Color(0x00000000), // KULLANILMAZ — data-ink kuralı
          divider: Color(0xFF1F1F1F), // hairline, sadece gerekli yerde
          accent: Colors.white, // ana aksiyon = beyaz
          accentSoft: Color(0x14FFFFFF), // %8 beyaz
          warmAccent: Color(0xFFC9A572), // antique gold — brand & primary link
          warmAccentSoft: Color(0x1FC9A572), // %12 gold — segmented pill
          chipBg: Color(0xFF1A1A1A),
          positive: Color(0xFF34D399), // SADECE finansal veri için
          negative: Color(0xFFFB7185), // SADECE finansal veri için
        ),
      ],
    );
  }

  // Light tema da aynı data-ink disiplini: pure white bg, subtle surface tone,
  // siyah aksiyon. Yeşil/kırmızı yalnızca veri için.
  static ThemeData light() {
    const bg = Colors.white;
    const surface = Color(0xFFFAFAFA); // çok hafif off-white
    const surfaceAlt = Color(0xFFF2F2F7); // iOS systemGrey6
    const onSurface = Colors.black;
    const onSurfaceMuted = Color(0xFF6E6E73); // iOS systemGrey
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      primaryColor: Colors.black,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        secondary: Color(0xFF6E6E73),
        surface: surface,
        onSurface: onSurface,
        error: danger,
      ),
      cardColor: surface,
      dividerColor: const Color(0xFFE5E5EA),
      fontFamily: 'Inter',
      textTheme: _textTheme(onSurface, onSurfaceMuted),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
            color: onSurface, fontSize: 18, fontWeight: FontWeight.w600),
      ),
      extensions: const [
        AppColorsExt(
          bg: bg,
          surface: surface,
          surfaceAlt: surfaceAlt,
          textPrimary: onSurface,
          textMuted: onSurfaceMuted,
          textSubtle: Color(0xFFAEAEB2),
          border: Color(0x00000000), // KULLANILMAZ
          divider: Color(0xFFE5E5EA),
          accent: Colors.black, // ana aksiyon = siyah
          accentSoft: Color(0x14000000), // %8 siyah
          warmAccent:
              Color(0xFFA88044), // koyu antique gold — light mod kontrast
          warmAccentSoft: Color(0x1FA88044), // %12 gold
          chipBg: Color(0xFFF2F2F7),
          positive: Color(0xFF059669), // SADECE finansal veri için
          negative: Color(0xFFDC2626), // SADECE finansal veri için
        ),
      ],
    );
  }

  static TextTheme _textTheme(Color primary, Color muted) {
    return TextTheme(
      displayLarge: TextStyle(
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: TextStyle(
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(color: primary, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: primary, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: primary),
      bodyMedium: TextStyle(color: primary),
      bodySmall: TextStyle(color: muted),
      labelLarge: TextStyle(color: primary, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(color: muted, fontSize: 11),
      labelSmall: TextStyle(color: muted, fontSize: 10),
    );
  }
}

/// Tema'ya bağlı uygulama renkleri — `AppColorsExt.of(context)` ile erişin.
class AppColorsExt extends ThemeExtension<AppColorsExt> {
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textMuted;
  final Color textSubtle;
  final Color border;
  final Color divider;
  final Color accent;
  final Color accentSoft;
  final Color warmAccent;
  final Color warmAccentSoft;
  final Color chipBg;
  final Color positive;
  final Color negative;

  const AppColorsExt({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textMuted,
    required this.textSubtle,
    required this.border,
    required this.divider,
    required this.accent,
    required this.accentSoft,
    required this.warmAccent,
    required this.warmAccentSoft,
    required this.chipBg,
    required this.positive,
    required this.negative,
  });

  static AppColorsExt of(BuildContext context) {
    return Theme.of(context).extension<AppColorsExt>()!;
  }

  @override
  ThemeExtension<AppColorsExt> copyWith() => this;

  @override
  ThemeExtension<AppColorsExt> lerp(
      covariant ThemeExtension<AppColorsExt>? other, double t) {
    if (other is! AppColorsExt) return this;
    return AppColorsExt(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      warmAccent: Color.lerp(warmAccent, other.warmAccent, t)!,
      warmAccentSoft: Color.lerp(warmAccentSoft, other.warmAccentSoft, t)!,
      chipBg: Color.lerp(chipBg, other.chipBg, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
    );
  }
}

/// Premium görünüm için reusable widget'lar.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final List<Color>? gradient;
  final Color? borderColor;

  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? c.surface : null,
        gradient: gradient != null
            ? LinearGradient(
                colors: gradient!,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? c.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return base;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: base,
      ),
    );
  }
}

/// Premium animasyonlu buton — hover'da hafifçe parlar, scale animasyonu.
class PremiumButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final List<Color>? gradient;
  final bool isLoading;
  final double? width;
  final EdgeInsetsGeometry padding;
  final TextStyle? labelStyle;

  const PremiumButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.gradient,
    this.isLoading = false,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    this.labelStyle,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> {
  bool _hovering = false;
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final enabled = widget.onPressed != null && !widget.isLoading;
    final colors = widget.gradient ?? [c.accent, AppTheme.emeraldDark];
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) => setState(() => _pressing = false),
        onTapCancel: () => setState(() => _pressing = false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressing ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: widget.width,
            padding: widget.padding,
            decoration: BoxDecoration(
              gradient: enabled
                  ? LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(colors: [c.surface, c.surface]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: colors.first
                            .withValues(alpha: _hovering ? 0.45 : 0.30),
                        blurRadius: _hovering ? 18 : 12,
                        offset: Offset(0, _hovering ? 6 : 4),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else ...[
                  if (widget.icon != null) ...[
                    Icon(widget.icon,
                        color: enabled ? Colors.white : c.textMuted, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: widget.labelStyle ??
                        TextStyle(
                          color: enabled ? Colors.white : c.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Premium boş durum görseli — ikon + başlık + alt yazı + opsiyonel CTA.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? iconColor;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (iconColor ?? c.accent).withValues(alpha: 0.18),
                  (iconColor ?? c.accent).withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(
                  color: (iconColor ?? c.accent).withValues(alpha: 0.25),
                  width: 1),
            ),
            child: Icon(icon, color: iconColor ?? c.accent, size: 38),
          ),
          const SizedBox(height: 18),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: c.textMuted, fontSize: 13, height: 1.4)),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Tabular nums + monospace gibi yapı için para birimi formatlayıcı.
/// Uygulama genelinde TEK para etiketi. Türkçe gruplu biçim (formatMoney);
/// istenirse küsürat soluk (Midas tarzı). Eski çağrılarla geriye uyumlu.
class MoneyText extends StatelessWidget {
  final double value;
  final String currency;
  final double? fontSize;
  final Color? color;
  final FontWeight fontWeight;
  final int decimals;
  final bool dimDecimals;
  final double? letterSpacing;
  final String prefix; // '+' / '−'

  const MoneyText(
    this.value, {
    super.key,
    this.currency = '₺',
    this.fontSize,
    this.color,
    this.fontWeight = FontWeight.w600,
    this.decimals = 2,
    this.dimDecimals = false,
    this.letterSpacing,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final base = color ?? c.textPrimary;
    final f = formatMoney(value, decimals: decimals);
    final ci = f.lastIndexOf(',');

    // ⚠️ Flutter web `--web-renderer html` TextSpan sınırlarında font
    // metriğini (özellikle fontFeatures/letterSpacing farklı span'larda)
    // bozuyor → '.'/',' küçük & düşük çiziliyordu. tnum'ın bu fontta
    // bozuk noktalama glyph'i de ekleniyor. Çözüm: TEK tip stil, tnum
    // YOK, span bölme YOK. dimDecimals gerekiyorsa SADECE renk farklı
    // ikinci span (renk farkı metriği bozmaz).
    final intPart = ci >= 0 ? f.substring(0, ci) : f;
    final decPart = ci >= 0 ? f.substring(ci) : '';
    final rootStyle = TextStyle(
      color: base,
      fontSize: fontSize ?? 14,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: 1.0,
    );

    if (!dimDecimals || decPart.isEmpty) {
      return Text('$prefix$currency$f', style: rootStyle);
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$prefix$currency$intPart'),
        TextSpan(
          text: decPart,
          style: TextStyle(color: base.withValues(alpha: 0.32)),
        ),
      ]),
      style: rootStyle,
    );
  }
}
