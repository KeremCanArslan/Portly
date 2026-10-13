import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/widgets/allocation_donut.dart';

/// Borsa/piyasa bazında dağılım — pozisyonları BIST / ABD / Kripto / Fon /
/// Emtia / Döviz / Endeks olarak gruplar (coğrafi-piyasa çeşitlendirmesi). Ortak
/// [AllocationDonut] tasarımını kullanır; gruplama tamamen istemci tarafında
/// `SymbolDisplay.exchangeOf` ile yapılır (backend değişikliği yok).
class ExchangeAllocationCard extends StatelessWidget {
  const ExchangeAllocationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final provider = context.watch<PortfolioProvider>();

    // Borsa → toplam ₺ değer.
    final totals = <String, double>{};
    for (final h in provider.myHoldings) {
      final m = h as Map<String, dynamic>;
      final v = (m['total_value_try'] as num?)?.toDouble() ??
          (m['total_value'] as num?)?.toDouble() ??
          0.0;
      if (v <= 0) continue;
      final ex = SymbolDisplay.exchangeOf((m['symbol'] as String?) ?? '');
      totals[ex] = (totals[ex] ?? 0) + v;
    }

    final total = totals.values.fold<double>(0, (s, v) => s + v);

    if (totals.isEmpty || total <= 0) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.public_rounded, size: 38, color: c.textSubtle),
            const SizedBox(height: 14),
            Text(
              'Borsa dağılımı için en az bir pozisyon gerekli.',
              style: TextStyle(
                  color: c.textMuted, fontSize: 14, letterSpacing: -0.1),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final rows = [
      for (final e in totals.entries) (label: e.key, value: e.value)
    ]..sort((a, b) => b.value.compareTo(a.value));
    final topName = rows.first.label;
    final topPct = rows.first.value / total * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AllocationDonut(items: rows, centerUnit: 'borsa'),
        const SizedBox(height: 12),
        _note(c, topName, topPct, rows.length),
      ],
    );
  }

  Widget _note(AppColorsExt c, String topName, double topPct, int n) {
    // Tek piyasaya yığılma = kur/ülke riski; birden çok piyasa daha dengeli.
    final ok = topPct < 70 && n > 1;
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
                  ? 'Birden çok piyasaya yayılmışsın; tek ülke/kur riskine '
                      'karşı dengeli duruyorsun.'
                  : 'Portföyünün %${topPct.toStringAsFixed(0)}\'i tek piyasada '
                      '($topName). Farklı borsalara (ör. BIST + ABD) yayılmak '
                      'tek ülke ve kur riskini azaltır.',
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
