import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';

class SectorBreakdownScreen extends StatefulWidget {
  final bool embedded;
  const SectorBreakdownScreen({super.key, this.embedded = false});

  @override
  State<SectorBreakdownScreen> createState() => _SectorBreakdownScreenState();
}

class _SectorBreakdownScreenState extends State<SectorBreakdownScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<dynamic> _sectors = [];
  double _totalValue = 0.0;
  int _touchedIndex = -1;

  static const _palette = [
    Color(0xFF00B4DB),
    Color(0xFF26C281),
    Color(0xFFF5A623),
    Color(0xFFE74C3C),
    Color(0xFF9B59B6),
    Color(0xFF3498DB),
    Color(0xFF1ABC9C),
    Color(0xFFE67E22),
    Color(0xFF34495E),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = context.read<PortfolioProvider>().userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    final data = await _api.fetchSectorBreakdown(userId);
    if (!mounted) return;
    setState(() {
      _sectors = data['sectors'] as List? ?? [];
      _totalValue = (data['total_value'] as num?)?.toDouble() ?? 0.0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: CircularProgressIndicator(color: Colors.tealAccent),
            ),
          )
        : _sectors.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pie_chart_outline,
                        size: 64, color: Colors.grey[600]),
                    const SizedBox(height: 16),
                    Text(
                      'Sektör dağılımı için en az bir hisse pozisyonu gerekli.',
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPieCard(),
                  const SizedBox(height: 16),
                  _buildLegend(),
                  const SizedBox(height: 16),
                  _buildConcentrationWarning(),
                ],
              );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Sektör Dağılımı',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [content],
      ),
    );
  }

  Widget _buildPieCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            'Toplam Hisse Değeri',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '₺${_totalValue.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          response == null ||
                          response.touchedSection == null) {
                        _touchedIndex = -1;
                        return;
                      }
                      _touchedIndex =
                          response.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                sectionsSpace: 2,
                centerSpaceRadius: 60,
                sections: List.generate(_sectors.length, (i) {
                  final s = _sectors[i] as Map<String, dynamic>;
                  final isTouched = i == _touchedIndex;
                  final radius = isTouched ? 90.0 : 80.0;
                  final color = _palette[i % _palette.length];
                  return PieChartSectionData(
                    color: color,
                    value: (s['percent'] as num).toDouble(),
                    title: '${(s['percent'] as num).toStringAsFixed(0)}%',
                    radius: radius,
                    titleStyle: TextStyle(
                      fontSize: isTouched ? 14 : 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: List.generate(_sectors.length, (i) {
          final s = _sectors[i] as Map<String, dynamic>;
          final color = _palette[i % _palette.length];
          return Padding(
            padding: EdgeInsets.only(bottom: i < _sectors.length - 1 ? 12 : 0),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s['name'] as String,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  '₺${(s['value'] as num).toStringAsFixed(0)}',
                  style:
                      TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(s['percent'] as num).toStringAsFixed(1)}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// Konsantrasyon riski uyarısı - en büyük sektör %50'yi geçtiyse
  Widget _buildConcentrationWarning() {
    if (_sectors.isEmpty) return const SizedBox.shrink();
    final topSector = _sectors.first as Map<String, dynamic>;
    final topPct = (topSector['percent'] as num).toDouble();

    if (topPct < 50) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Portföyün dengeli dağılmış. Konsantrasyon riski düşük.',
                style: TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined,
              color: Colors.orangeAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.4),
                children: [
                  const TextSpan(text: 'Portföyünün '),
                  TextSpan(
                    text: '%${topPct.toStringAsFixed(0)}\'i',
                    style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: ' tek bir sektörde (${topSector['name']}). '),
                  const TextSpan(
                      text:
                          'Markowitz çeşitlendirme prensibi gereği farklı sektörlere dağılım önerilir.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}