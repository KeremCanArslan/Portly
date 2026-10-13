import 'package:flutter/material.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';

/// Arama sonucu satırı — sol: borsa rozeti + sembol + şirket adı; sağ: CANLI
/// fiyat + günlük değişim rozeti (lazy `fetchSingleStock`, satır oluşunca bir
/// kez). İşlem ekranı ve sembol-arama sheet'i ORTAK kullanır → her iki aramada
/// aynı profesyonel sonuç görünümü (tutarlılık).
///
/// Fiyat ayrı çekilir ki arama listesi anında görünsün (sembol+ad) ve fiyatlar
/// arkadan "aksın"; arama isteği fiyat beklemez.
class SearchResultRow extends StatefulWidget {
  final String symbol;
  final String name;
  final String market;
  final VoidCallback onTap;

  const SearchResultRow({
    super.key,
    required this.symbol,
    required this.name,
    required this.market,
    required this.onTap,
  });

  @override
  State<SearchResultRow> createState() => _SearchResultRowState();
}

class _SearchResultRowState extends State<SearchResultRow> {
  late final Future<StockModel?> _price;

  @override
  void initState() {
    super.initState();
    // initState'te bir kez → rebuild'lerde tekrar istek atılmaz. Liste
    // değişince ValueKey(symbol) yeni state yaratır → yeni sembol, yeni istek.
    _price = ApiService().fetchSingleStock(widget.symbol);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                widget.market,
                style: TextStyle(
                  color: c.textSubtle,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SymbolDisplay.compact(widget.symbol),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
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
            const SizedBox(width: 10),
            FutureBuilder<StockModel?>(
              future: _price,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: c.textSubtle,
                    ),
                  );
                }
                final s = snap.data;
                if (s == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      s.rawPrice,
                      currency: s.currency,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: c.textPrimary,
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: !s.changeAvailable
                            ? c.textMuted
                            : (s.isUp ? c.positive : c.negative),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        s.change,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
