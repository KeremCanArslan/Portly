import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortfolioProvider>();
    final totalAsset = provider.totalAssetValue;
    final pnl = provider.totalPnl;
    final pnlPct = provider.totalPnlPercent;
    final isProfit = pnl >= 0;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: RefreshIndicator(
          color: Colors.tealAccent,
          onRefresh: () => provider.refreshAll(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // === Üst bar ===
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hoş Geldin,',
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 14)),
                        const Text('Standart Kullanıcı',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const CircleAvatar(
                      backgroundColor: Colors.tealAccent,
                      child: Icon(Icons.person, color: Colors.black),
                    )
                  ],
                ),
                const SizedBox(height: 30),

                // === Toplam varlık kartı ===
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.tealAccent.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Toplam Sanal Varlık',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('₺ ${totalAsset.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                Icon(
                                    isProfit
                                        ? Icons.trending_up
                                        : Icons.trending_down,
                                    color: Colors.white,
                                    size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '${isProfit ? '+' : ''}₺${pnl.toStringAsFixed(2)} (${pnlPct.toStringAsFixed(2)}%)',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          const Text('Toplam',
                              style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // === AI KOÇ KARTI ===
                _buildAICoachCard(context),
                const SizedBox(height: 30),

                const Text('Popüler Hisseler',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                if (provider.isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child:
                          CircularProgressIndicator(color: Colors.tealAccent),
                    ),
                  )
                else if (provider.marketData.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text(
                          'Piyasa verisi alınamadı. Aşağı çekerek deneyin.',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  )
                else
                  ...provider.marketData
                      .map((data) => _buildStockCard(context, data)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // AI KOÇ KARTI
  // ==========================================
  Widget _buildAICoachCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showCoachSheet(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.purpleAccent.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Portly AI Koç',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Portföyünü analiz et, kişisel yorumu al',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  void _showCoachSheet(BuildContext mainContext) {
    final provider = mainContext.read<PortfolioProvider>();
    provider.loadCoachAdvice();

    showModalBottomSheet(
      context: mainContext,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollController) {
            return Consumer<PortfolioProvider>(
              builder: (_, prov, __) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.auto_awesome,
                                color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text('Portly AI Koç',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh,
                                color: Colors.white70),
                            onPressed: prov.isCoachLoading
                                ? null
                                : () => prov.loadCoachAdvice(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          child: _buildCoachContent(prov),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.grey[400], size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bu yorum eğitim amaçlıdır, yatırım tavsiyesi değildir.',
                                style: TextStyle(
                                    color: Colors.grey[400], fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCoachContent(PortfolioProvider prov) {
    if (prov.isCoachLoading) {
      return Column(
        children: [
          const SizedBox(height: 40),
          const CircularProgressIndicator(color: Colors.purpleAccent),
          const SizedBox(height: 20),
          Text('Llama 3.3 70B portföyünü analiz ediyor...',
              style: TextStyle(color: Colors.grey[400])),
        ],
      );
    }

    if (prov.coachError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(prov.coachError!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (prov.coachAdvice == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Tavsiye almak için yenile butonuna bas.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
      ),
      child: Text(
        prov.coachAdvice!,
        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
      ),
    );
  }

  // ==========================================
  // HİSSE KARTI
  // ==========================================
  Widget _buildStockCard(BuildContext context, Map<String, dynamic> data) {
    final isUp = data['isUp'] as bool;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showTradeSheet(context, data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.2), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isUp
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  child: Icon(
                      isUp ? Icons.show_chart : Icons.stacked_line_chart,
                      color: isUp ? Colors.greenAccent : Colors.redAccent),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['symbol'],
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    SizedBox(
                      width: 180,
                      child: Text(data['name'],
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 14)),
                    ),
                  ],
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₺${data['price']}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text(data['change'],
                    style: TextStyle(
                        color: isUp ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ALIM-SATIM PANELİ
  // ==========================================
  void _showTradeSheet(
      BuildContext mainContext, Map<String, dynamic> stockData) {
    final qtyController = TextEditingController(text: '1');
    final symbol = stockData['symbol'] as String;
    final name = stockData['name'] as String;
    final price = (stockData['rawPrice'] as double?) ??
        double.tryParse(stockData['price'].toString()) ??
        0.0;

    final provider = mainContext.read<PortfolioProvider>();
    final held = provider.heldQuantity(symbol);

    showModalBottomSheet(
      context: mainContext,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('İşlem Emri',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('$symbol — $name',
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Fiyat: ₺${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              if (held > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Elinde: ${held.toStringAsFixed(0)} lot',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Lot adedi',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.tealAccent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon:
                          const Icon(Icons.shopping_cart, color: Colors.white),
                      label: const Text('Al',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final qty = int.tryParse(qtyController.text) ?? 0;
                        if (qty <= 0) return;
                        final result =
                            await provider.executeBuyOrder(symbol, qty, price);
                        if (mainContext.mounted) {
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(mainContext).showSnackBar(
                            SnackBar(
                              content: Text(result.success
                                  ? '✅ $qty lot $symbol alındı'
                                  : '❌ ${result.message}'),
                              backgroundColor:
                                  result.success ? Colors.green : Colors.red,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: held > 0
                            ? Colors.greenAccent.shade700
                            : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.sell, color: Colors.white),
                      label: const Text('Sat',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      onPressed: held <= 0
                          ? null
                          : () async {
                              final qty = int.tryParse(qtyController.text) ?? 0;
                              if (qty <= 0) return;
                              final result =
                                  await provider.executeSellOrder(symbol, qty);
                              if (mainContext.mounted) {
                                Navigator.pop(sheetContext);
                                ScaffoldMessenger.of(mainContext).showSnackBar(
                                  SnackBar(
                                    content: Text(result.success
                                        ? '✅ $qty lot $symbol satıldı'
                                        : '❌ ${result.message}'),
                                    backgroundColor: result.success
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
