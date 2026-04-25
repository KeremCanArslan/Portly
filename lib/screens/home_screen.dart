import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/screens/stock_detail_screen.dart';
import 'package:portly/screens/behavior_screen.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/screens/stress_test_screen.dart';
import 'dart:async';
import 'package:portly/services/api_service.dart';
import 'package:portly/screens/chat_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortfolioProvider>();
    final auth = context.watch<AuthProvider>();
    final displayName = auth.fullName ?? 'Yatırımcı';
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
                        Text(displayName,
                            style: const TextStyle(
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
                const SizedBox(height: 12),

                // === DAVRANIŞSAL PROFİL KARTI ===
                _buildBehaviorCard(context),
                const SizedBox(height: 30),
                const SizedBox(height: 12),
                _buildStressCard(context),

                // === İzleme Listesi Başlığı + Ekle Butonu ===
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('İzleme Listem',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle,
                          color: Colors.tealAccent, size: 28),
                      onPressed: () => _showAddStockDialog(context),
                    ),
                  ],
                ),
                Text(
                  '💡 Bir hisseyi silmek için sola kaydır',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                const SizedBox(height: 12),

                if (provider.isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child:
                          CircularProgressIndicator(color: Colors.tealAccent),
                    ),
                  )
                else if (provider.marketData.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          Text('İzleme listen boş. + butonuyla hisse ekle.',
                              style: TextStyle(color: Colors.grey[500])),
                        ],
                      ),
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
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ChatScreen()),
      ),
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

  Widget _buildBehaviorCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BehaviorScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE74C3C), Color(0xFFF5A623)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.orangeAccent.withValues(alpha: 0.25),
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
                  const Icon(Icons.psychology, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Yatırımcı Karakterin',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Davranışsal finans önyargılarını keşfet',
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

  Widget _buildStressCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StressTestScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF134E5E), Color(0xFF71B280)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.tealAccent.withValues(alpha: 0.2),
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
              child: const Icon(Icons.analytics_outlined,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stres Testi',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Monte Carlo • 2008 Krizi • COVID Çöküşü',
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

  // ==========================================
  // HİSSE EKLEME DIALOG'U
  // ==========================================
  void _showAddStockDialog(BuildContext context) {
    final controller = TextEditingController();
    List<Map<String, dynamic>> suggestions = [];
    bool isSearching = false;
    Timer? debounceTimer;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) {
          // Debounced arama: kullanıcı 300ms boyunca yazmazsa istek at
          void onQueryChanged(String value) {
            debounceTimer?.cancel();
            if (value.trim().isEmpty) {
              setState(() {
                suggestions = [];
                isSearching = false;
              });
              return;
            }
            setState(() => isSearching = true);
            debounceTimer = Timer(const Duration(milliseconds: 300), () async {
              final results = await ApiService().searchStocks(value);
              if (ctx.mounted) {
                setState(() {
                  suggestions = results;
                  isSearching = false;
                });
              }
            });
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.search,
                      color: Colors.tealAccent, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Hisse Ara',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    onChanged: onQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'Şirket adı, sembol... (örn. apple, garanti)',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      prefixIcon: isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.tealAccent,
                                ),
                              ),
                            )
                          : Icon(Icons.search,
                              color: Colors.grey[500], size: 20),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.white24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.tealAccent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (controller.text.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.tealAccent.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              color: Colors.tealAccent.withValues(alpha: 0.8),
                              size: 18),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'BIST, NASDAQ, NYSE ve kripto piyasalarında arayabilirsin. Türkçe veya İngilizce yazabilirsin.',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isSearching && suggestions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child:
                            CircularProgressIndicator(color: Colors.tealAccent),
                      ),
                    )
                  else if (!isSearching && suggestions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.search_off,
                                color: Colors.grey[600], size: 32),
                            const SizedBox(height: 8),
                            Text(
                              'Eşleşme bulunamadı',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Farklı bir terim dene veya sembolü doğrudan ekle',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        itemBuilder: (_, i) {
                          final s = suggestions[i];
                          final symbol = s['symbol'] as String? ?? '';
                          final name = s['name'] as String? ?? symbol;
                          final market = s['market'] as String? ?? '';

                          Color marketColor;
                          if (market == 'BIST') {
                            marketColor = Colors.redAccent;
                          } else if (market == 'CRYPTO') {
                            marketColor = Colors.orangeAccent;
                          } else if (market == 'NASDAQ' || market == 'NYSE') {
                            marketColor = Colors.blueAccent;
                          } else if (market == 'ETF') {
                            marketColor = Colors.purpleAccent;
                          } else if (market == 'ENDEKS') {
                            marketColor = Colors.tealAccent;
                          } else {
                            marketColor = Colors.grey;
                          }

                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              debounceTimer?.cancel();
                              Navigator.pop(dialogContext);
                              final added = await context
                                  .read<PortfolioProvider>()
                                  .addToWatchlist(symbol);
                              if (context.mounted && !added) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$symbol zaten listende'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          marketColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      market,
                                      style: TextStyle(
                                        color: marketColor,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(symbol,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                        Text(name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.add_circle_outline,
                                      color: Colors.tealAccent, size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  debounceTimer?.cancel();
                  Navigator.pop(dialogContext);
                },
                child: const Text('İptal',
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // HİSSE KARTI (Dismissible + dinamik currency)
  // ==========================================
  Widget _buildStockCard(BuildContext context, Map<String, dynamic> data) {
    final isUp = data['isUp'] as bool;
    final currency = data['currency'] as String? ?? '₺';

    return Dismissible(
      key: Key(data['symbol']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      onDismissed: (_) {
        context.read<PortfolioProvider>().removeFromWatchlist(data['symbol']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${data['symbol']} listeden çıkarıldı'),
            backgroundColor: Colors.grey[800],
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StockDetailScreen(stockData: data),
          ),
        ),
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
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 14)),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$currency${data['price']}',
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
      ),
    );
  }
}
