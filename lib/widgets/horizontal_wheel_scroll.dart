import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Yatay kaydırılabilir bir alanı (grafik araç çubuğu, zaman dilimi satırı)
/// MASAÜSTÜNDE dikey fare tekerleğiyle kaydırılabilir kılar.
///
/// Sorun (tester, masaüstü): Flutter web'de yatay ScrollView'lar dikey fare
/// tekerleğine yanıt vermez → olay sayfaya kabarır, SAYFA kayar ve sağdaki
/// butonlara (Pro, palet, göstergeler…) ulaşılamaz.
///
/// Çözüm: tekerlek olayını `pointerSignalResolver`'a kaydedip TÜKETİYORUZ
/// (grafiğin kendi zoom'unda kullanılan aynı desen) → sayfa kaymaz; dikey
/// delta'yı (trackpad'de yatay delta varsa onu) yatay offset'e çeviriyoruz.
class HorizontalWheelScroll extends StatefulWidget {
  /// Verilen controller'ı yatay bir scrollable'a (SingleChildScrollView/
  /// ListView, `scrollDirection: Axis.horizontal`) bağlamalısın.
  final Widget Function(ScrollController controller) builder;

  const HorizontalWheelScroll({super.key, required this.builder});

  @override
  State<HorizontalWheelScroll> createState() => _HorizontalWheelScrollState();
}

class _HorizontalWheelScrollState extends State<HorizontalWheelScroll> {
  final ScrollController _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (signal) {
        if (signal is! PointerScrollEvent || !_ctrl.hasClients) return;
        final maxExtent = _ctrl.position.maxScrollExtent;
        // Taşma yoksa olayı TÜKETME → sayfa normal kayabilsin (yalnız sağda
        // gizli öğe varken tekerleği yatay kaydırmaya çeviriyoruz).
        if (maxExtent <= 0) return;
        GestureBinding.instance.pointerSignalResolver.register(signal, (e) {
          final ev = e as PointerScrollEvent;
          // Trackpad yatay jesti (dx) varsa onu, yoksa dikey tekerleği (dy).
          final delta =
              ev.scrollDelta.dx != 0 ? ev.scrollDelta.dx : ev.scrollDelta.dy;
          _ctrl.jumpTo((_ctrl.offset + delta).clamp(0.0, maxExtent));
        });
      },
      child: widget.builder(_ctrl),
    );
  }
}
