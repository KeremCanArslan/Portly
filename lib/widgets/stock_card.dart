import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/screens/stock_detail_screen.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/utils/haptics.dart';
import 'package:portly/utils/snackbar.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';

/// Apple Stocks tarzı izleme listesi kartı.
/// Data-ink monokrom: border yok, glow yok, ikon dairesi yok.
/// Yeşil/kırmızı SADECE değişim yüzdesi rozetinde.
class StockCard extends StatefulWidget {
  final StockModel data;

  const StockCard({super.key, required this.data});

  @override
  State<StockCard> createState() => _StockCardState();
}

class _StockCardState extends State<StockCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final isUp = widget.data.isUp;
    final currency = widget.data.currency;
    // Değişim bilinmiyorsa yeşil/kırmızı BASMA (veri rengi yalnız gerçek veri
    // için) → sönük nötr rozet + "—".
    final dataColor = !widget.data.changeAvailable
        ? c.textMuted
        : (isUp ? c.positive : c.negative);

    return Dismissible(
      key: Key(widget.data.symbol),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: c.negative.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 24),
      ),
      onDismissed: (_) {
        // İzleme listesi silmesi ONAY SORMAZ (portföyün aksine): kalıcı veri
        // gitmiyor, sembol tek dokunuşla geri gelir. Onay yerine "Geri Al".
        // context yalnız bu senkron blokta kullanılıyor — satır bir sonraki
        // frame'de ağaçtan kalkıyor, await sonrası context'e dokunmak yanlış
        // olurdu; silme future'ı yakalanıp yalnız "Geri Al" basılırsa
        // bekleniyor (silinen SIRA oradan geliyor).
        final provider = context.read<PortfolioProvider>();
        final symbol = widget.data.symbol;
        Haptics.light();
        final removal = provider.removeFromWatchlist(symbol);
        showAppSnackBar(
          context,
          '${SymbolDisplay.compact(symbol)} izlemeden çıkarıldı',
          actionLabel: 'Geri Al',
          onAction: () async {
            Haptics.selection();
            await provider.restoreToWatchlist(symbol, await removal);
          },
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StockDetailScreen(stockData: widget.data),
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _hovering ? c.surfaceAlt : c.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        SymbolDisplay.pickTitle(
                            widget.data.symbol, widget.data.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        SymbolDisplay.secondaryLabel(widget.data.symbol),
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
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      widget.data.rawPrice,
                      currency: currency,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: c.textPrimary,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: dataColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        widget.data.change,
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
      ),
    );
  }
}
