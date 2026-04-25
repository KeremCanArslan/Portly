import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';

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
                                final success = await context
                                    .read<PortfolioProvider>()
                                    .generateDemoTrades();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(success
                                          ? '8 demo işlem oluşturuldu'
                                          : 'İşlem üretilemedi'),
                                      backgroundColor:
                                          success ? Colors.green : Colors.red,
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
                                  child: _buildAssetCard(
                                    symbol,
                                    '${quantity.toStringAsFixed(0)} Adet • Maliyet: ₺${averageCost.toStringAsFixed(2)}',
                                    totalValue,
                                    cardColor,
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
}
