import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
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
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Risk Analizi',
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
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: _scenarios.length,
        itemBuilder: (_, i) {
          final s = _scenarios[i] as Map<String, dynamic>;
          final id = s['id'] as String;
          final isSelected = id == _selectedScenario;
          return GestureDetector(
            onTap: _loading ? null : () => _runTest(id),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.tealAccent
                    : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isSelected
                        ? Colors.tealAccent
                        : Colors.white.withValues(alpha: 0.1)),
              ),
              child: Center(
                child: Text(s['name'] as String,
                    style: TextStyle(
                        color: isSelected ? Colors.black : Colors.grey[300],
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.tealAccent),
            SizedBox(height: 16),
            Text('Hesaplanıyor...',
                style: TextStyle(color: Colors.white54)),
          ],
        ),
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
              Icon(Icons.shield_outlined, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text(
                'Risk analizi için en az bir hisse pozisyonu gerekli.',
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
        _buildHeroCard(sim),
        const SizedBox(height: 16),
        _buildOutcomeBars(sim),
        const SizedBox(height: 16),
        _buildEducationalNote(),
      ],
    );
  }
  Widget _buildHeroCard(Map<String, dynamic> sim) {
    final initial = (sim['initial_value'] as num).toDouble();
    final p5 = (sim['p5_worst_case'] as num).toDouble();
    final p95 = (sim['p95_best_case'] as num).toDouble();
    final var95 = (sim['var_95'] as num).toDouble();

    // Risk skoru: VaR'ın portföye oranı (0-1)
    final riskRatio = (var95 / initial).clamp(0.0, 0.5) * 2; // %50 kayıp = 1.0
    final riskLabel = _riskLabel(riskRatio);
    final riskColor = _riskColor(riskRatio);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: riskColor.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: riskColor, size: 22),
              const SizedBox(width: 10),
              Text(
                _result!['scenario_name'] as String,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // GAUGE - kapsayıcı genişliği sınırla, taşma olmasın
          Center(
            child: SizedBox(
              width: 220,
              height: 130,
              child: CustomPaint(
                size: const Size(220, 130),
                painter: _GaugePainter(value: riskRatio, color: riskColor),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        riskLabel,
                        style: TextStyle(
                            color: riskColor,
                            fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Risk Seviyesi',
                        style: TextStyle(
                            color: Colors.grey[400], fontSize: 11),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.5),
                    children: [
                      const TextSpan(text: '30 gün sonra %95 ihtimalle\n'),
                      TextSpan(
                        text: '₺${p5.toStringAsFixed(0)} ',
                        style: TextStyle(
                            color: riskColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                      const TextSpan(
                          text: 'değerinin altına düşmez.',
                          style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Maksimum risk: ₺${var95.toStringAsFixed(0)} kayıp (₺${initial.toStringAsFixed(0)} → ₺${p5.toStringAsFixed(0)})',
                  style: TextStyle(
                      color: Colors.grey[400], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeBars(Map<String, dynamic> sim) {
    final initial = (sim['initial_value'] as num).toDouble();
    final mean = (sim['mean'] as num).toDouble();
    final p5 = (sim['p5_worst_case'] as num).toDouble();
    final p95 = (sim['p95_best_case'] as num).toDouble();

    final worstPct = (p5 - initial) / initial * 100;
    final meanPct = (mean - initial) / initial * 100;
    final bestPct = (p95 - initial) / initial * 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '30 gün sonra olası 3 sonuç',
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          _outcomeRow(
            label: 'Kötü senaryo',
            sublabel: '%5 ihtimal',
            value: p5,
            pct: worstPct,
            color: Colors.redAccent,
            icon: Icons.trending_down,
          ),
          const SizedBox(height: 14),
          _outcomeRow(
            label: 'En olası sonuç',
            sublabel: 'Ortalama beklenti',
            value: mean,
            pct: meanPct,
            color: Colors.tealAccent,
            icon: Icons.trending_flat,
            isHighlighted: true,
          ),
          const SizedBox(height: 14),
          _outcomeRow(
            label: 'İyi senaryo',
            sublabel: '%5 ihtimal',
            value: p95,
            pct: bestPct,
            color: Colors.greenAccent,
            icon: Icons.trending_up,
          ),
        ],
      ),
    );
  }

  Widget _outcomeRow({
    required String label,
    required String sublabel,
    required double value,
    required double pct,
    required Color color,
    required IconData icon,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlighted
            ? color.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted
            ? Border.all(color: color.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sublabel,
                    style:
                        TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₺${value.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEducationalNote() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: Colors.tealAccent,
          collapsedIconColor: Colors.grey,
          title: Row(
            children: [
              Icon(Icons.school_outlined,
                  color: Colors.tealAccent.withValues(alpha: 0.8), size: 18),
              const SizedBox(width: 10),
              const Text('Bu nasıl hesaplandı?',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          children: [
            Text(
              _result!['scenario_description'] as String,
              style: TextStyle(
                  color: Colors.grey[300], fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Geometric Brownian Motion ile 10.000 farklı senaryo simüle edildi. Sonuçlar olasılık dağılımının uç noktalarından alındı.',
              style: TextStyle(
                  color: Colors.grey[400], fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              '📚 ${_result!['academic_reference']}',
              style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  String _riskLabel(double ratio) {
    if (ratio < 0.2) return 'DÜŞÜK';
    if (ratio < 0.5) return 'ORTA';
    if (ratio < 0.75) return 'YÜKSEK';
    return 'KRİTİK';
  }

  Color _riskColor(double ratio) {
    if (ratio < 0.2) return Colors.greenAccent;
    if (ratio < 0.5) return Colors.tealAccent;
    if (ratio < 0.75) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}


class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;

  _GaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width / 2.5).clamp(60.0, 90.0);
    final center = Offset(size.width / 2, size.height - 10);

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    final fgPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.6), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi * value.clamp(0.0, 1.0),
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}