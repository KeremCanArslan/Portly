import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/providers/chat_provider.dart';
import 'package:portly/screens/chat_screen.dart';
import 'package:portly/screens/stock_detail_screen.dart';
import 'package:portly/screens/sector_breakdown_screen.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  int _viewMode = 0; // 0 = Liste, 1 = Sektör

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortfolioProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: provider.isPortfolioLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.tealAccent))
            : RefreshIndicator(
                color: Colors.tealAccent,
                onRefresh: () => provider.refreshAll(),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSummaryCard(provider),
                    const SizedBox(height: 16),
                    _buildSegmentToggle(),
                    const SizedBox(height: 16),
                    if (_viewMode == 0)
                      ..._buildListView(context, provider)
                    else
                      const SectorBreakdownScreen(embedded: true),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSegmentToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _segmentButton('Liste', 0, Icons.list)),
          Expanded(child: _segmentButton('Sektör', 1, Icons.pie_chart_outline)),
        ],
      ),
    );
  }

  Widget _segmentButton(String label, int index, IconData icon) {
    final isSelected = _viewMode == index;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.tealAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16, color: isSelected ? Colors.black : Colors.grey[400]),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: isSelected ? Colors.black : Colors.grey[400],
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildListView(
      BuildContext context, PortfolioProvider provider) {
    return [
      const Text('Varlıklarım',
          style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      _buildAssetCard('Nakit Bakiye', 'TRY', provider.balance,
          Colors.cyanAccent),
      const SizedBox(height: 12),
      if (provider.myHoldings.isEmpty)
        _buildEmptyState(context)
      else
        ...provider.myHoldings.map((holding) {
          final symbol = holding['symbol'] ?? 'Bilinmiyor';
          final quantity =
              (holding['quantity'] as num?)?.toDouble() ?? 0.0;
          final averageCost =
              (holding['average_cost'] as num?)?.toDouble() ?? 0.0;
          final totalValue =
              (holding['total_value'] as num?)?.toDouble() ?? 0.0;
          final pnlPercent =
              (holding['pnl_percent'] as num?)?.toDouble() ?? 0.0;
          final isProfit = pnlPercent >= 0;
          final cardColor =
              isProfit ? Colors.greenAccent : Colors.redAccent;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StockDetailScreen(
                      stockData: {
                        'symbol': symbol,
                        'name': symbol,
                        'rawPrice': 0.0, 
                        'change': '%0.00',
                        'isUp': true,
                        'currency': symbol.contains('.IS') || symbol.contains('TRY') ? '₺' : '\$',
                      },
                    ),
                  ),
                );
              },
              onLongPress: () => _showStockActionsSheet(
                  context,
                  symbol,
                  quantity,
                  averageCost,
                  totalValue,
                  pnlPercent),
              child: _buildAssetCard(
                symbol,
                '${quantity.toStringAsFixed(0)} Adet • Maliyet: ₺${averageCost.toStringAsFixed(2)}',
                totalValue,
                cardColor,
              ),
            ),
          );
        }),
    ];
  }

  Widget _buildSummaryCard(PortfolioProvider provider) {
    final total = provider.totalAssetValue;
    final pnl = provider.totalPnl;
    final pnlPct = provider.totalPnlPercent;
    final isProfit = pnl >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isProfit
              ? [const Color(0xFF0F3443), const Color(0xFF34E89E)]
              : [const Color(0xFF3D2C2E), const Color(0xFFE74C3C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Toplam Varlık',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 8),
          Text('₺${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (provider.myHoldings.isNotEmpty)
            Row(
              children: [
                Icon(isProfit ? Icons.arrow_upward : Icons.arrow_downward,
                    color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${isProfit ? '+' : ''}${pnl.toStringAsFixed(2)} TL  •  ${isProfit ? '+' : ''}${pnlPct.toStringAsFixed(2)}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.trending_up, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 18),
          const Text('İlk yatırımına başla',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Piyasalar ekranından bir hisse seç ve gerçek piyasa fiyatıyla risksiz alım yap. Davranışsal profilin işlemlerinle şekillenecek.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.purpleAccent,
                side: BorderSide(
                    color: Colors.purpleAccent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                context.read<ChatProvider>().setPendingPrompt(
                    'Yeni başlıyorum, ilk yatırım için neler önerirsin? Risk profilime göre nasıl başlamalıyım?');
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatScreen()),
                );
              },
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('AI Koç\'a Sor',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetCard(
      String title, String subtitle, double amount, Color leftColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: leftColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                ],
              ),
            ],
          ),
          Text('₺${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showStockActionsSheet(
    BuildContext context,
    String symbol,
    double quantity,
    double avgCost,
    double totalValue,
    double pnlPercent,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final isProfit = pnlPercent >= 0;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isProfit ? Colors.greenAccent : Colors.redAccent)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isProfit ? Icons.trending_up : Icons.trending_down,
                        color: isProfit ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(symbol,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text(
                            '${quantity.toStringAsFixed(0)} lot • ${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toStringAsFixed(2)}%',
                            style: TextStyle(
                                color: isProfit
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Divider(color: Colors.white.withValues(alpha: 0.06)),
                const SizedBox(height: 8),
                _buildSheetAction(
                  icon: Icons.auto_awesome,
                  iconColor: Colors.purpleAccent,
                  title: 'AI Koç\'a Sor',
                  subtitle: 'Bu pozisyonun hakkında detaylı yorum al',
                  isFeatured: true,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    final prompt =
                        '$symbol pozisyonum hakkında detaylı yorum yapar mısın? '
                        'Şu an ${quantity.toStringAsFixed(0)} lotum var, ortalama maliyet ₺${avgCost.toStringAsFixed(2)}, '
                        'getirim ${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toStringAsFixed(2)}%.';
                    context.read<ChatProvider>().setPendingPrompt(prompt);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatScreen()),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildSheetAction(
                  icon: Icons.show_chart,
                  iconColor: Colors.tealAccent,
                  title: 'Detayları Gör',
                  subtitle: 'Fiyat grafiği, alım/satım işlemleri',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StockDetailScreen(
                          stockData: {
                            'symbol': symbol,
                            'name': symbol,
                            'rawPrice': 0.0,
                            'change': '%0.00',
                            'isUp': true,
                            'currency': symbol.contains('.IS') || symbol.contains('TRY') ? '₺' : '\$',
                          },
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildSheetAction(
                  icon: Icons.close,
                  iconColor: Colors.grey,
                  title: 'Kapat',
                  subtitle: null,
                  onTap: () => Navigator.pop(sheetCtx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSheetAction({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    bool isFeatured = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isFeatured
              ? LinearGradient(
                  colors: [
                    Colors.purpleAccent.withValues(alpha: 0.12),
                    Colors.blueAccent.withValues(alpha: 0.06),
                  ],
                )
              : null,
          color: isFeatured ? null : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: isFeatured
              ? Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 11)),
                  ],
                ],
              ),
            ),
            if (!isFeatured)
              Icon(Icons.arrow_forward_ios, color: Colors.grey[600], size: 14),
          ],
        ),
      ),
    );
  }
}