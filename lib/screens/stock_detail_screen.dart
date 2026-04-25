import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';

class StockDetailScreen extends StatefulWidget {
  final Map<String, dynamic> stockData;

  const StockDetailScreen({super.key, required this.stockData});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  final ApiService _apiService = ApiService();

  List<FlSpot> _priceSpots = [];
  List<Map<String, dynamic>> _priceData = [];
  bool _isLoadingHistory = true;
  String _selectedPeriod = '1mo';

  double _minPrice = 0;
  double _maxPrice = 0;
  String _currency = '₺';

  // Bu hisseye ait haberler (sentiment overlay için)
  List<dynamic> _relatedNews = [];

  @override
  void initState() {
    super.initState();
    _currency =
        widget.stockData['currency'] as String? ?? '₺'; // ← BU SATIRI EKLE
    _loadHistory();
    _loadRelatedNews();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);

    final symbol = widget.stockData['symbol'] as String;
    final result = await _apiService.fetchStockHistory(symbol, _selectedPeriod);

    if (result['data'] != null) {
      final List<dynamic> data = result['data'];
      _priceData = data.cast<Map<String, dynamic>>();

      double minP = double.infinity;
      double maxP = -double.infinity;

      _priceSpots = List.generate(_priceData.length, (i) {
        final close = (_priceData[i]['close'] as num).toDouble();
        if (close < minP) minP = close;
        if (close > maxP) maxP = close;
        return FlSpot(i.toDouble(), close);
      });

      _minPrice = minP;
      _maxPrice = maxP;
    }

    if (mounted) setState(() => _isLoadingHistory = false);
  }

  Future<void> _loadRelatedNews() async {
    // Tüm haberleri al, sembolü başlıkta geçenleri filtrele
    final allNews = await _apiService.fetchNews();
    final symbol = (widget.stockData['symbol'] as String).replaceAll('.IS', '');

    _relatedNews = allNews.where((news) {
      final title = (news['title'] ?? '').toString().toUpperCase();
      return title.contains(symbol);
    }).toList();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final symbol = widget.stockData['symbol'] as String;
    final name = widget.stockData['name'] as String;
    final price = (widget.stockData['rawPrice'] as double?) ?? 0.0;
    final change = widget.stockData['change'] as String;
    final isUp = widget.stockData['isUp'] as bool;

    final provider = context.watch<PortfolioProvider>();
    final held = provider.heldQuantity(symbol);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(symbol,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === Başlık + Fiyat ===
              Text(name,
                  style: TextStyle(color: Colors.grey[400], fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$_currency${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isUp
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        change,
                        style: TextStyle(
                            color: isUp ? Colors.greenAccent : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              if (held > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '📦 Elinde: ${held.toStringAsFixed(0)} lot',
                    style:
                        const TextStyle(color: Colors.tealAccent, fontSize: 14),
                  ),
                ),
              const SizedBox(height: 24),

              // === Periyot Seçici ===
              _buildPeriodSelector(),
              const SizedBox(height: 16),

              // === Grafik ===
              _buildChart(),
              const SizedBox(height: 24),

              // === Alım-Satım Butonları ===
              _buildActionButtons(context, symbol, name, price, held),
              const SizedBox(height: 24),

              // === Sentiment Overlay Açıklaması ===
              if (_relatedNews.isNotEmpty) _buildSentimentLegend(),

              // === İlgili Haberler ===
              if (_relatedNews.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Bu Hisseyle İlgili Haberler (${_relatedNews.length})',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ..._relatedNews.map((n) => _buildNewsItem(n)),
              ] else if (!_isLoadingHistory) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Bu hisseyle ilgili güncel haber bulunamadı.',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final periods = [
      ('5d', '5G'),
      ('1mo', '1A'),
      ('3mo', '3A'),
      ('6mo', '6A'),
      ('1y', '1Y'),
    ];

    return Row(
      children: periods.map((p) {
        final isSelected = _selectedPeriod == p.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedPeriod = p.$1);
              _loadHistory();
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.tealAccent.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? Colors.tealAccent
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Center(
                child: Text(
                  p.$2,
                  style: TextStyle(
                    color: isSelected ? Colors.tealAccent : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChart() {
    if (_isLoadingHistory) {
      return const SizedBox(
        height: 280,
        child:
            Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
      );
    }

    if (_priceSpots.isEmpty) {
      return SizedBox(
        height: 280,
        child: Center(
          child: Text('Grafik verisi alınamadı',
              style: TextStyle(color: Colors.grey[500])),
        ),
      );
    }

    final padding = (_maxPrice - _minPrice) * 0.1;
    final minY = _minPrice - padding;
    final maxY = _maxPrice + padding;

    // Sentiment overlay noktalarını hesapla
    final sentimentSpots = _calculateSentimentSpots(minY, maxY);

    return Container(
      height: 280,
      padding: const EdgeInsets.only(top: 16, right: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.05),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: _priceSpots.length / 4,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _priceData.length)
                    return const SizedBox();
                  final dateStr = _priceData[idx]['date'] as String;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      dateStr.substring(5), // MM-DD
                      style: TextStyle(color: Colors.grey[500], fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) => Text(
                  '$_currency${value.toStringAsFixed(0)}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 10),
                ),
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            // Ana fiyat çizgisi
            LineChartBarData(
              spots: _priceSpots,
              isCurved: true,
              color: Colors.tealAccent,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    Colors.tealAccent.withValues(alpha: 0.25),
                    Colors.tealAccent.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // Sentiment noktaları (eğer varsa)
            if (sentimentSpots.isNotEmpty)
              LineChartBarData(
                spots: sentimentSpots,
                color: Colors.transparent,
                barWidth: 0,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) {
                    final newsIndex = sentimentSpots.indexOf(spot);
                    if (newsIndex >= _relatedNews.length) {
                      return FlDotCirclePainter(radius: 4, color: Colors.grey);
                    }
                    final score =
                        (_relatedNews[newsIndex]['sentiment_score'] as num?)
                                ?.toDouble() ??
                            0;
                    Color color;
                    if (score > 0.05) {
                      color = Colors.greenAccent;
                    } else if (score < -0.05) {
                      color = Colors.redAccent;
                    } else {
                      color = Colors.grey;
                    }
                    return FlDotCirclePainter(
                      radius: 5,
                      color: color,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    );
                  },
                ),
              ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E1E1E),
              tooltipRoundedRadius: 8,
              getTooltipItems: (spots) => spots.map((spot) {
                final idx = spot.x.toInt();
                if (idx < 0 || idx >= _priceData.length) return null;
                final date = _priceData[idx]['date'];
                return LineTooltipItem(
                  '$date\n$_currency${spot.y.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  List<FlSpot> _calculateSentimentSpots(double minY, double maxY) {
    // Haberlerin sentiment'larını grafik üzerine nokta olarak yerleştir
    // Haberlerin sayısını fiyat grafiğine dağıt
    if (_relatedNews.isEmpty || _priceSpots.isEmpty) return [];

    final spots = <FlSpot>[];
    final step = _priceSpots.length / _relatedNews.length;

    for (int i = 0; i < _relatedNews.length; i++) {
      final xIndex = (i * step).toInt().clamp(0, _priceSpots.length - 1);
      final priceAtX = _priceSpots[xIndex].y;
      spots.add(FlSpot(xIndex.toDouble(), priceAtX));
    }
    return spots;
  }

  Widget _buildSentimentLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Grafikteki noktalar: haberlerin AI sentiment skoru',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
          _legendDot(Colors.greenAccent, 'Pozitif'),
          const SizedBox(width: 8),
          _legendDot(Colors.redAccent, 'Negatif'),
          const SizedBox(width: 8),
          _legendDot(Colors.grey, 'Nötr'),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
      ],
    );
  }

  Widget _buildNewsItem(dynamic news) {
    final title = news['title'] ?? '';
    final sentimentLabel = news['sentiment_label'] ?? 'Nötr';
    final score = (news['sentiment_score'] as num?)?.toDouble() ?? 0.0;

    final Color color = switch (sentimentLabel) {
      'Pozitif' => Colors.greenAccent,
      'Negatif' => Colors.redAccent,
      _ => Colors.grey,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$sentimentLabel (${score.toStringAsFixed(2)})',
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, String symbol, String name,
      double price, double held) {
    final qtyController = TextEditingController(text: '1');
    final provider = context.read<PortfolioProvider>();

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Lot',
              labelStyle: const TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.white30),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.tealAccent),
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.shopping_cart, color: Colors.white),
            label: const Text('Al',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final qty = int.tryParse(qtyController.text) ?? 0;
              if (qty <= 0) return;
              final result = await provider.executeBuyOrder(symbol, qty, price);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.success
                      ? '✅ $qty lot $symbol alındı'
                      : '❌ ${result.message}'),
                  backgroundColor: result.success ? Colors.green : Colors.red,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  held > 0 ? Colors.greenAccent.shade700 : Colors.grey,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.sell, color: Colors.white),
            label: const Text('Sat',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: held <= 0
                ? null
                : () async {
                    final qty = int.tryParse(qtyController.text) ?? 0;
                    if (qty <= 0) return;
                    final result = await provider.executeSellOrder(symbol, qty);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result.success
                            ? '✅ $qty lot $symbol satıldı'
                            : '❌ ${result.message}'),
                        backgroundColor:
                            result.success ? Colors.green : Colors.red,
                      ),
                    );
                  },
          ),
        ),
      ],
    );
  }
}
