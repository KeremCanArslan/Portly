import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/widgets/allocation_donut.dart';

/// Hisse bazında ağırlık dağılımı — ortak [AllocationDonut] + tek-hisse
/// konsantrasyon notu. Donut tasarımı (hover, merkez detay, lider çizgiler,
/// ayırt edilebilir palet) AllocationDonut'tan gelir; Sektör ve Borsa
/// görünümleri de aynı widget'ı kullanır → tek tasarım kaynağı.
class HoldingsAllocationCard extends StatelessWidget {
  const HoldingsAllocationCard({super.key});

  static String name(String symbol) => SymbolDisplay.compact(symbol);

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final provider = context.watch<PortfolioProvider>();

    final rows = <({String label, double value})>[];
    String? topSymbol;
    double topVal = 0;
    double total = 0;
    for (final h in provider.myHoldings) {
      final m = h as Map<String, dynamic>;
      final v = (m['total_value_try'] as num?)?.toDouble() ??
          (m['total_value'] as num?)?.toDouble() ??
          0.0;
      if (v <= 0) continue;
      final sym = (m['symbol'] as String?) ?? '—';
      rows.add((label: name(sym), value: v));
      total += v;
      if (v > topVal) {
        topVal = v;
        topSymbol = sym;
      }
    }

    if (rows.isEmpty || total <= 0) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.donut_large_rounded, size: 38, color: c.textSubtle),
            const SizedBox(height: 14),
            Text(
              'Hisse dağılımı için en az bir pozisyon gerekli.',
              style: TextStyle(
                  color: c.textMuted, fontSize: 14, letterSpacing: -0.1),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final topPct = topVal / total * 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AllocationDonut(items: rows, centerUnit: 'varlık'),
        const SizedBox(height: 12),
        _concentrationNote(c, name(topSymbol ?? '—'), topPct),
      ],
    );
  }

  Widget _concentrationNote(AppColorsExt c, String topName, double topPct) {
    final ok = topPct < 40;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: ok ? c.positive : c.warmAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok
                  ? 'Tek bir hisseye aşırı yüklenme yok; pozisyonlar dengeli.'
                  : 'Portföyünün %${topPct.toStringAsFixed(0)}\'i tek varlıkta '
                      '($topName). Tek hisse riskini azaltmak için ağırlığı '
                      'düşürmeyi düşün.',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 13,
                height: 1.5,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
