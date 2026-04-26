import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/providers/chat_provider.dart';
import 'package:portly/screens/chat_screen.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortfolioProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: provider.isPortfolioLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.tealAccent))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text('📊 Portföy Dağılımı',
                          style: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8E44AD), Color(0xFF3498DB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.science_outlined,
                              color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Demo İşlem Üret',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                SizedBox(height: 2),
                                Text(
                                    'Davranışsal profilin için 8 örnek işlem oluştur',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF8E44AD),
                            ),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E1E1E),
                                  title: const Text('Demo İşlem Üret',
                                      style: TextStyle(color: Colors.white)),
                                  content: const Text(
                                    'Mevcut işlem geçmişin silinecek ve 8 demo işlem oluşturulacak. Bakiyen yeniden ₺100.000 olacak. Devam edilsin mi?',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('İptal'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.tealAccent),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Üret',
                                          style:
                                              TextStyle(color: Colors.black)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && context.mounted) {
                                // Loading dialog göster
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(
                                    child: CircularProgressIndicator(
                                        color: Colors.tealAccent),
                                  ),
                                );

                                final success = await context
                                    .read<PortfolioProvider>()
                                    .generateDemoTrades();

                                if (!context.mounted) return;
                                Navigator.pop(context); // loading kapat

                                if (success) {
                                  final provider =
                                      context.read<PortfolioProvider>();
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: const Color(0xFF1E1E1E),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      title: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.greenAccent
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                                Icons.check_circle,
                                                color: Colors.greenAccent,
                                                size: 22),
                                          ),
                                          const SizedBox(width: 12),
                                          const Text('Demo Hazır',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18)),
                                        ],
                                      ),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Son 30 gün içinde rastgele tarihlerde 8 işlem oluşturuldu. Artık davranışsal profilini görebilirsin.',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                height: 1.5),
                                          ),
                                          const SizedBox(height: 16),
                                          _demoSummaryRow(
                                              'Bakiye',
                                              '₺${provider.balance.toStringAsFixed(2)}',
                                              Icons.account_balance_wallet),
                                          _demoSummaryRow(
                                              'Hisse pozisyonları',
                                              '${provider.myHoldings.length} farklı hisse',
                                              Icons.show_chart),
                                          _demoSummaryRow(
                                              'Toplam varlık',
                                              '₺${provider.totalAssetValue.toStringAsFixed(2)}',
                                              Icons.trending_up),
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.tealAccent
                                                  .withValues(alpha: 0.08),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                  color: Colors.tealAccent
                                                      .withValues(alpha: 0.25)),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.lightbulb_outline,
                                                    color: Colors.tealAccent
                                                        .withValues(alpha: 0.8),
                                                    size: 18),
                                                const SizedBox(width: 10),
                                                const Expanded(
                                                  child: Text(
                                                    'Şimdi "Yatırımcı Karakterin" ekranına gidip davranışsal profilini görebilirsin',
                                                    style: TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('Tamam',
                                              style: TextStyle(
                                                  color: Colors.tealAccent)),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Demo işlem üretilemedi'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('Üret',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    const Text('Varlıklarım',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // NAKİT BAKİYE
                    _buildAssetCard('Nakit Bakiye', 'TRY', provider.balance,
                        Colors.cyanAccent),
                    const SizedBox(height: 12),

                    // HİSSE SENETLERİ LİSTESİ
                    Expanded(
                      child: provider.myHoldings.isEmpty
                          ? const Center(
                              child: Text("Henüz hisse senedi almadınız.",
                                  style: TextStyle(color: Colors.white54)))
                          : ListView.builder(
                              itemCount: provider.myHoldings.length,
                              itemBuilder: (context, index) {
                                final holding = provider.myHoldings[index];

                                final symbol =
                                    holding['symbol'] ?? 'Bilinmiyor';
                                final quantity =
                                    (holding['quantity'] as num?)?.toDouble() ??
                                        0.0;
                                final averageCost =
                                    (holding['average_cost'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                final totalValue =
                                    (holding['total_value'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                final pnlPercent =
                                    (holding['pnl_percent'] as num?)
                                            ?.toDouble() ??
                                        0.0;

                                final isProfit = pnlPercent >= 0;
                                final cardColor = isProfit
                                    ? Colors.greenAccent
                                    : Colors.redAccent;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: GestureDetector(
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
                              },
                            ),
                    ),
                  ],
                ),
              ),
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

  Widget _demoSummaryRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.tealAccent.withValues(alpha: 0.6), size: 16),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
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
                // Drag handle
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
                // Stock header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:
                            (isProfit ? Colors.greenAccent : Colors.redAccent)
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
                // AI'a Sor — featured
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
                        'getirim ${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toStringAsFixed(2)}%. '
                        'Bu pozisyonu nasıl değerlendirmeliyim?';
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
                    // Stock detail screen'e git (varsa)
                    // TODO: navigate to stock detail
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
            if (isFeatured)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                    color: Colors.purpleAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
