import 'package:flutter/material.dart';
import 'package:portly/theme/app_theme.dart';

/// Piyasa açık/kapalı göstergesi — nokta + kısa etiket.
///
/// Veri backend'den (`market_state`) gelir ve her varlık sınıfı için doludur:
/// BIST İstanbul seansına, ABD hissesi New York seansına (pre/post dahil),
/// kripto 7/24 açığa göre. TEFAS fonunun seansı yoktur (günde tek fiyat) →
/// `state` null gelir ve BURADA HİÇBİR ŞEY ÇİZİLMEZ; "Kapalı" demek yanlış
/// olurdu.
///
/// Açıkken nokta yavaşça nabız atar (canlı veri işareti). Kapalıyken sabit
/// gri — data-ink: hareket yalnız "şu an değişiyor" demek için.
class MarketStateDot extends StatefulWidget {
  final String? state;
  const MarketStateDot({super.key, required this.state});

  @override
  State<MarketStateDot> createState() => _MarketStateDotState();
}

class _MarketStateDotState extends State<MarketStateDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant MarketStateDot old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncPulse();
  }

  void _syncPulse() {
    if (widget.state == 'REGULAR') {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state == null) return const SizedBox.shrink();
    final c = AppColorsExt.of(context);

    final (String label, Color color) = switch (state) {
      'REGULAR' => ('Açık', c.positive),
      'PRE' => ('Ön seans', c.textMuted),
      'POST' => ('Kapanış sonrası', c.textMuted),
      _ => ('Kapalı', c.textMuted),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.35).animate(_pulse),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: c.textMuted,
            fontSize: 12,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}
