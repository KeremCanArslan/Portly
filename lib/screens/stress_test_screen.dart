import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';

class StressTestScreen extends StatefulWidget {
  const StressTestScreen({super.key});

  @override
  State<StressTestScreen> createState() => _StressTestScreenState();
}

class _StressTestScreenState extends State<StressTestScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _scenarios = [];
  Map<String, dynamic>? _result;
  String _selectedScenario = 'normal';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _scenarios = await _api.fetchStressScenarios();
    await _runTest('normal');
  }

  Future<void> _runTest(String scenario) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedScenario = scenario;
    });
    final userId = context.read<PortfolioProvider>().userId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Kullanıcı bulunamadı';
      });
      return;
    }
    final result = await _api.runStressTest(userId, scenario);
    if (!mounted) return;
    if (result.containsKey('error')) {
      setState(() {
        _loading = false;
        _error = result['error'] as String;
      });
    } else {
      setState(() {
        _loading = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Monte Carlo Stres Testi',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _scenarios.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent))
          : Column(
              children: [
                _buildScenarioSelector(),
                Expanded(child: _buildContent()),
              ],
            ),
    );
  }

  Widget _buildScenarioSelector() {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _scenarios.length,
        itemBuilder: (_, i) {
          final s = _scenarios[i] as Map<String, dynamic>;
          final id = s['id'] as String;
          final isSelected = id == _selectedScenario;
          final isCrisis = id != 'normal';
          return GestureDetector(
            onTap: _loading ? null : () => _runTest(id),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: isCrisis
                            ? [Colors.redAccent, Colors.deepOrange]
                            : [Colors.tealAccent.shade700, Colors.teal])
                    : null,
                color: isSelected ? null : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isSelected
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Icon(
                    isCrisis ? Icons.warning_amber : Icons.show_chart,
                    color: isSelected ? Colors.white : Colors.grey[400],
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(s['name'] as String,
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[300],
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.tealAccent),
          const SizedBox(height: 16),
          Text('10,000 simülasyon çalışıyor...',
              style: TextStyle(color: Colors.grey[400])),
        ],
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_result == null) return const SizedBox.shrink();

    if (_result!['has_portfolio'] != true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science_outlined, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text(
                _result!['message'] as String? ?? 'Portföy yok',
                style: TextStyle(color: Colors.grey[400], fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final sim = _result!['simulation'] as Map<String, dynamic>;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildScenarioInfo(),
        const SizedBox(height: 16),
        _buildKeyMetrics(sim),
        const SizedBox(height: 20),
        _buildSamplePathsChart(sim),
        const SizedBox(height: 20),
        _buildHistogram(sim),
        const SizedBox(height: 20),
        _buildAcademicNote(),
      ],
    );
  }

  Widget _buildScenarioInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_result!['scenario_name'] as String,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(_result!['scenario_description'] as String,
              style: TextStyle(
                  color: Colors.grey[400], fontSize: 13, height: 1.4)),
          const SizedBox(height: 8),
          Text('📚 ${_result!['academic_reference']}',
              style: TextStyle(
                  color: Colors.tealAccent.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildKeyMetrics(Map<String, dynamic> sim) {
    final initial = (sim['initial_value'] as num).toDouble();
    final mean = (sim['mean'] as num).toDouble();
    final p5 = (sim['p5_worst_case'] as num).toDouble();
    final p95 = (sim['p95_best_case'] as num).toDouble();
    final var95 = (sim['var_95'] as num).toDouble();
    final expectedPct = (sim['expected_return_pct'] as num).toDouble();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: expectedPct >= 0
                  ? [const Color(0xFF00B4DB), const Color(0xFF0083B0)]
                  : [const Color(0xFFE74C3C), const Color(0xFFC0392B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('30 Gün Sonra Beklenen Değer',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              Text('₺${mean.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  '${expectedPct >= 0 ? '+' : ''}${expectedPct.toStringAsFixed(2)}% • Başlangıç: ₺${initial.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _metricBox(
                'En Kötü %5',
                '₺${p5.toStringAsFixed(0)}',
                '${((p5 - initial) / initial * 100).toStringAsFixed(1)}%',
                Colors.redAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metricBox(
                'En İyi %5',
                '₺${p95.toStringAsFixed(0)}',
                '+${((p95 - initial) / initial * 100).toStringAsFixed(1)}%',
                Colors.greenAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined,
                  color: Colors.redAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Value at Risk (95%)',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    Text(
                        '₺${var95.toStringAsFixed(2)} maksimum kayıp olasılığı',
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricBox(String title, String value, String pct, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          Text(pct,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSamplePathsChart(Map<String, dynamic> sim) {
    final fanData = sim['fan_chart'] as List?;
    if (fanData == null || fanData.isEmpty) return const SizedBox.shrink();

    // Her percentile için spot listesi oluştur
    final p5Spots = <FlSpot>[];
    final p25Spots = <FlSpot>[];
    final p50Spots = <FlSpot>[];
    final p75Spots = <FlSpot>[];
    final p95Spots = <FlSpot>[];

    double minY = double.infinity;
    double maxY = -double.infinity;

    for (var i = 0; i < fanData.length; i++) {
      final point = fanData[i] as Map<String, dynamic>;
      final day = (point['day'] as num).toDouble();
      final p5 = (point['p5'] as num).toDouble();
      final p25 = (point['p25'] as num).toDouble();
      final p50 = (point['p50'] as num).toDouble();
      final p75 = (point['p75'] as num).toDouble();
      final p95 = (point['p95'] as num).toDouble();

      p5Spots.add(FlSpot(day, p5));
      p25Spots.add(FlSpot(day, p25));
      p50Spots.add(FlSpot(day, p50));
      p75Spots.add(FlSpot(day, p75));
      p95Spots.add(FlSpot(day, p95));

      if (p5 < minY) minY = p5;
      if (p95 > maxY) maxY = p95;
    }

    final padding = (maxY - minY) * 0.05;
    minY -= padding;
    maxY += padding;

    return Container(
      padding: const EdgeInsets.all(16),
      height: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Olasılık Aralığı (30 Günlük Projeksiyon)',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Ortanca senaryo • %50 ve %90 güven aralıkları',
            style: TextStyle(color: Colors.grey[500], fontSize: 11),
          ),
          const SizedBox(height: 12),
          Expanded(
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
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 5,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${value.toInt()}g',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) => Text(
                        '₺${(value / 1000).toStringAsFixed(0)}K',
                        style: TextStyle(color: Colors.grey[600], fontSize: 10),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  // Dış band: %5 - %95 (alttan üste hafif dolgu)
                  LineChartBarData(
                    spots: p5Spots,
                    color: Colors.tealAccent.withValues(alpha: 0.0),
                    barWidth: 0,
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: p95Spots,
                    color: Colors.tealAccent.withValues(alpha: 0.3),
                    barWidth: 1,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.tealAccent.withValues(alpha: 0.08),
                      cutOffY: 0,
                      applyCutOffY: false,
                    ),
                  ),
                  // İç band: %25 - %75 (daha koyu dolgu)
                  LineChartBarData(
                    spots: p25Spots,
                    color: Colors.tealAccent.withValues(alpha: 0.5),
                    barWidth: 1,
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: p75Spots,
                    color: Colors.tealAccent.withValues(alpha: 0.5),
                    barWidth: 1,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.tealAccent.withValues(alpha: 0.18),
                    ),
                  ),
                  // Ortanca çizgi (en belirgin)
                  LineChartBarData(
                    spots: p50Spots,
                    color: Colors.tealAccent,
                    barWidth: 2.5,
                    isCurved: true,
                    dotData: const FlDotData(show: false),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF2A2A2A),
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (spots) {
                      if (spots.isEmpty) return [];
                      final spot = spots.last;
                      final dayIdx = spot.x.toInt();
                      if (dayIdx >= fanData.length) return [];
                      final point = fanData[dayIdx] as Map<String, dynamic>;
                      return [
                        LineTooltipItem(
                          'Gün ${point['day']}\n'
                          'Ortanca: ₺${(point['p50'] as num).toStringAsFixed(0)}\n'
                          '%50 aralık: ₺${(point['p25'] as num).toStringAsFixed(0)} - ₺${(point['p75'] as num).toStringAsFixed(0)}\n'
                          '%90 aralık: ₺${(point['p5'] as num).toStringAsFixed(0)} - ₺${(point['p95'] as num).toStringAsFixed(0)}',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                        ...List.generate(spots.length - 1, (_) => null),
                      ];
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Legend
          Row(
            children: [
              _legendItem(Colors.tealAccent, 'Ortanca'),
              const SizedBox(width: 12),
              _legendItem(
                  Colors.tealAccent.withValues(alpha: 0.4), '%50 aralık'),
              const SizedBox(width: 12),
              _legendItem(
                  Colors.tealAccent.withValues(alpha: 0.15), '%90 aralık'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10)),
      ],
    );
  }

  Widget _buildHistogram(Map<String, dynamic> sim) {
    final hist = sim['histogram'] as List;
    if (hist.isEmpty) return const SizedBox.shrink();

    final maxCount = hist
        .map((e) => (e['count'] as num).toInt())
        .reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      height: 240,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Olası Sonuç Dağılımı (10,000 simülasyon)',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: hist.asMap().entries.map((e) {
                  final count = (e.value['count'] as num).toDouble();
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: count,
                        color: Colors.tealAccent,
                        width: 8,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  );
                }).toList(),
                maxY: maxCount.toDouble() * 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.school_outlined,
              color: Colors.tealAccent.withValues(alpha: 0.8), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Geometric Brownian Motion ile 10,000 Monte Carlo simülasyonu. '
              'Markowitz Modern Portföy Teorisi metodolojisi.',
              style: TextStyle(color: Colors.grey[400], fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
