import 'dart:ui' show ImageFilter;
import 'package:portly/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portly/theme/app_theme.dart';

/// iOS Settings tarzı gruplandırılmış kart — DATA-INK disiplini:
/// - HİÇ Border.all yok
/// - HİÇ glow BoxShadow yok
/// - Sadece surface tone'u + ince hairline divider'lar
class IOSGroupedCard extends StatelessWidget {
  final List<Widget> children;
  final double radius;
  final double dividerInset;

  const IOSGroupedCard({
    super.key,
    required this.children,
    this.radius = 14,
    this.dividerInset = 48,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);

    final spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i < children.length - 1) {
        spaced.add(Container(
          margin: EdgeInsets.only(left: dividerInset),
          height: 0.5,
          color: c.divider,
        ));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(children: spaced),
      ),
    );
  }
}

/// iOS tarzı düz (border'sız) text field — IOSGroupedCard içinde kullanılır.
class IOSField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? suffix;
  final VoidCallback? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final double? letterSpacing;

  const IOSField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffix,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.letterSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final textColor = enabled ? c.textPrimary : c.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, color: c.textSubtle, size: 18),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              obscureText: obscureText,
              keyboardType: keyboardType,
              autocorrect: false,
              autofocus: autofocus,
              maxLength: maxLength,
              inputFormatters: inputFormatters,
              textCapitalization: textCapitalization,
              onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                letterSpacing: letterSpacing ?? -0.1,
              ),
              cursorColor: c.textPrimary,
              decoration: InputDecoration(
                hintText: label,
                hintStyle: TextStyle(
                  color: c.textSubtle,
                  fontSize: 15,
                  letterSpacing: -0.1,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
              ),
            ),
          ),
          if (suffix != null) suffix!,
        ],
      ),
    );
  }
}

/// Apple-Midas tarzı pill button — DATA-INK:
/// - Primary: beyaz zemin + siyah yazı (dark mode'da), tersi light mode'da
/// - Secondary: antrasit (grey.shade900) zemin + beyaz yazı
/// - HİÇ glow BoxShadow yok, sadece mikro tap-scale
class IOSPillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final bool secondary;

  const IOSPillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.secondary = false,
  });

  @override
  State<IOSPillButton> createState() => _IOSPillButtonState();
}

class _IOSPillButtonState extends State<IOSPillButton> {
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onPressed != null && !widget.isLoading;

    // Primary = ters kontrast (dark: beyaz, light: siyah)
    // Secondary = antrasit (dark: grey.shade900, light: surfaceAlt)
    final Color bg;
    final Color fg;
    if (widget.secondary) {
      bg = isDark ? const Color(0xFF1A1A1A) : c.surfaceAlt;
      fg = c.textPrimary;
    } else {
      bg = isDark ? Colors.white : Colors.black;
      fg = isDark ? Colors.black : Colors.white;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) => setState(() => _pressing = false),
        onTapCancel: () => setState(() => _pressing = false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressing ? 0.985 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: widget.width,
              height: 52,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: widget.isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: fg,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, color: fg, size: 17),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            widget.label,
                            style: TextStyle(
                              color: fg,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Portly" yazımarka — Midas tarzı temiz, w600 + tight tracking.
class IOSWordmark extends StatelessWidget {
  final double fontSize;
  final Color? color;

  const IOSWordmark({super.key, this.fontSize = 34, this.color});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Text(
      'Portly',
      style: TextStyle(
        color: color ?? c.textPrimary,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.2,
        height: 1.05,
      ),
    );
  }
}

/// Logo emblem — monokrom zemin + warm gold "P".
/// Marka kimliği için tek aksent noktası.
class IOSLogoMark extends StatelessWidget {
  final double size;

  const IOSLogoMark({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? const Color(0xFF1A1A1A) : c.surfaceAlt,
      ),
      child: Center(
        child: Text(
          'P',
          style: TextStyle(
            color: c.warmAccent,
            fontSize: size * 0.48,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.8,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// iOS "Inset Grouped" section başlığı — uppercase, ince, gri.
class IOSSectionHeader extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry padding;

  const IOSSectionHeader({
    super.key,
    required this.label,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: padding,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// iOS tarzı text link — Data-ink: dekoratif renk yok, sadece gri tonları.
/// İkincil aksiyon (forgot password vs.) için.
class IOSTextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double fontSize;
  final Color? color;
  final FontWeight fontWeight;

  const IOSTextLink({
    super.key,
    required this.label,
    required this.onTap,
    this.fontSize = 14,
    this.color,
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: color ?? c.textMuted,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

/// Apple Settings tarzı navigasyon satırı — IOSGroupedCard içinde kullanılır.
/// İkon + başlık + opsiyonel alt yazı + chevron.
class IOSListRow extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;

  const IOSListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
  });

  @override
  State<IOSListRow> createState() => _IOSListRowState();
}

class _IOSListRowState extends State<IOSListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _hover && widget.onTap != null
              ? c.accentSoft
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(widget.icon,
                  color: widget.iconColor ?? c.textMuted, size: 19),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null)
                widget.trailing!
              else if (widget.onTap != null)
                Icon(Icons.chevron_right_rounded,
                    color: c.textSubtle, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Apple Stocks tarzı izleme listesi satırı — IOSGroupedCard içinde.
/// Symbol + isim solda, fiyat + değişim rozetı sağda. Yeşil/kırmızı SADECE
/// data değişim göstergesinde (badge), başka yerde renk yok.
class IOSStockRow extends StatefulWidget {
  final String symbol;
  final String name;
  final String price;
  final String currency;
  final double changePct;
  final VoidCallback? onTap;

  const IOSStockRow({
    super.key,
    required this.symbol,
    required this.name,
    required this.price,
    required this.currency,
    required this.changePct,
    this.onTap,
  });

  @override
  State<IOSStockRow> createState() => _IOSStockRowState();
}

class _IOSStockRowState extends State<IOSStockRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final isUp = widget.changePct >= 0;
    final dataColor = isUp ? c.positive : c.negative;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: _hover && widget.onTap != null
              ? c.accentSoft
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.symbol,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 12,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${widget.currency}${widget.price}',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: dataColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${formatPctSigned(widget.changePct, decimals: 2)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS tarzı segmented control — Apple Stocks/Wallet'in tabini.
/// Beyaz pill, gri zemin. Renk dekoratif değil.
class IOSSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChange;

  const IOSSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: options.map((opt) {
          final selected = opt.$1 == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChange(opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? c.warmAccentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    opt.$2,
                    style: TextStyle(
                      color: selected ? c.warmAccent : c.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Büyük, çarpıcı verdict banner — AL/SAT/TUT, YÜKSELİŞ/DÜŞÜŞ gibi.
/// Dolgulu renk zemin, iri tipografi, opsiyonel alt detay satırı.
class IOSVerdictBanner extends StatelessWidget {
  final String verdict;
  final String? sub;
  final Color color;
  final IconData? icon;
  final List<(String, String)> stats;

  const IOSVerdictBanner({
    super.key,
    required this.verdict,
    required this.color,
    this.sub,
    this.icon,
    this.stats = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verdict,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (sub != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          sub!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: stats.map((s) {
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.$1,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.$2,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// 0-100 skor barı — etiket + sayı + görsel ilerleme. Düz "70" yerine.
class IOSScoreBar extends StatelessWidget {
  final String label;
  final double score; // 0-100
  final String? verdict;

  const IOSScoreBar({
    super.key,
    required this.label,
    required this.score,
    this.verdict,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final pct = (score.clamp(0, 100)) / 100.0;
    // Skor = veri → renk izinli
    final dataColor =
        score >= 70 ? c.positive : (score >= 40 ? c.warmAccent : c.negative);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            Text(
              score.toStringAsFixed(0),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            if (verdict != null) ...[
              const SizedBox(width: 6),
              Text(
                verdict!,
                style: TextStyle(
                  color: c.textSubtle,
                  fontSize: 11,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(height: 6, color: c.surfaceAlt),
              FractionallySizedBox(
                widthFactor: pct == 0 ? 0.02 : pct,
                child: Container(height: 6, color: dataColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Açıklama sheet'lerinin ortak hero bloğu — iri değer + birim + durum
/// rozeti + opsiyonel 0-100 ilerleme barı + hedef notu. Skor "veri" olduğu
/// için band rengi izinli; başka dekoratif renk yok.
class IOSSheetHero extends StatelessWidget {
  final String value; // "60" veya "1.06"
  final String? unit; // "/ 100" (Sharpe'ta null)
  final Color color; // band rengi (positive/warmAccent/negative)
  final String verdict; // "Orta" / "İyi risk-getiri"
  final double? progress; // 0..1 → bar çizer; null → bar yok
  final String? footnote; // "Hedef: %20 altı"

  const IOSSheetHero({
    super.key,
    required this.value,
    required this.color,
    required this.verdict,
    this.unit,
    this.progress,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final p = progress?.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -2,
                    height: 1.0)),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text(unit!,
                    style: TextStyle(
                        color: c.textSubtle,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
              ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(verdict,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1)),
            ),
          ],
        ),
        if (p != null) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(children: [
              Container(height: 7, color: c.surfaceAlt),
              FractionallySizedBox(
                widthFactor: p == 0 ? 0.02 : p,
                child: Container(height: 7, color: color),
              ),
            ]),
          ),
        ],
        if (footnote != null) ...[
          const SizedBox(height: 11),
          Row(children: [
            Icon(Icons.gps_fixed, size: 13, color: c.textSubtle),
            const SizedBox(width: 6),
            Text(footnote!,
                style: TextStyle(
                    color: c.textSubtle,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1)),
          ]),
        ],
      ],
    );
  }
}

/// Açıklama sheet'i bölümü — ikonlu majüskül etiket + opsiyonel formül kutusu
/// + gövde. [emphasize] → warmAccentSoft zeminli "çağrı" kutusu (yapılması
/// gereken aksiyon için): metin textPrimary, etiket+ikon warmAccent.
class IOSInfoBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String body;
  final String? formula;
  final bool emphasize;

  const IOSInfoBlock({
    super.key,
    required this.icon,
    required this.label,
    required this.body,
    this.formula,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final accent = emphasize ? c.warmAccent : c.textSubtle;
    final col = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
        ]),
        if (formula != null) ...[
          const SizedBox(height: 11),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(formula!,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    height: 1.35)),
          ),
        ],
        const SizedBox(height: 9),
        Text(body,
            style: TextStyle(
                color: emphasize ? c.textPrimary : c.textMuted,
                fontSize: 14,
                height: 1.5,
                letterSpacing: -0.1)),
      ],
    );
    if (!emphasize) return col;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: c.warmAccentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: col,
    );
  }
}

/// Büyük stat tile — grid içinde kullanılır. İri rakam + etiket.
class IOSStatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap; // verilirse kart dokunulabilir + "?" ipucu çıkar

  const IOSStatTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 12,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.help_outline, size: 13, color: c.textSubtle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? c.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: tile,
    );
  }
}

/// Rakamlar için zorunlu tabular figures formatlayıcı.
/// Tüm para/yüzde/sayı metinleri bunu kullanmalı (Apple Stocks tarzı hizalama).
class TabularText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final double letterSpacing;

  const TabularText(
    this.text, {
    super.key,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w500,
    this.color,
    this.letterSpacing = -0.1,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Text(
      text,
      style: TextStyle(
        color: color ?? c.textPrimary,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
      ),
    );
  }
}

/// Premium bottom sheet — BackdropFilter blur + handle + grouped içerik.
/// Eğitim/analiz detayları sayfa içinde değil bunun üstünden gösterilmeli.
///
/// Kullanım:
/// ```
/// showIOSBottomSheet(
///   context: context,
///   title: 'Analiz Detayı',
///   child: ...,
/// );
/// ```
Future<T?> showIOSBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  String? title,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _IOSBottomSheetShell(title: title, child: child),
  );
}

class _IOSBottomSheetShell extends StatelessWidget {
  final String? title;
  final Widget child;

  const _IOSBottomSheetShell({required this.child, this.title});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.textSubtle.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (title != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Text(
                      title!,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
