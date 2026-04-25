import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';

class BehaviorScreen extends StatefulWidget {
  const BehaviorScreen({super.key});

  @override
  State<BehaviorScreen> createState() => _BehaviorScreenState();
}

class _BehaviorScreenState extends State<BehaviorScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final userId = context.read<PortfolioProvider>().userId;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Kullanıcı bulunamadı';
      });
      return;
    }
    final result = await _api.fetchBehaviorProfile(userId);
    if (!mounted) return;
    if (result.containsKey('error')) {
      setState(() {
        _loading = false;
        _error = result['error'] as String;
      });
    } else {
      setState(() {
        _loading = false;
        _data = result;
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
        title: const Text('Yatırımcı Karakterin',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_data == null) return const SizedBox.shrink();

    if (_data!['has_enough_data'] != true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.psychology_outlined,
                  size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text(
                _data!['message'] as String? ??
                    'Davranışsal profil için yeterli veri yok',
                style: TextStyle(color: Colors.grey[400], fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Yatırımcı karakterini görmek için piyasalardan birkaç işlem yap.',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final persona = _data!['persona'] as Map<String, dynamic>;
    final de = _data!['disposition_effect'] as Map<String, dynamic>;
    final oc = _data!['overconfidence'] as Map<String, dynamic>;
    final la = _data!['loss_aversion'] as Map<String, dynamic>;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildPersonaCard(persona),
        const SizedBox(height: 24),
        Text('Davranışsal Önyargı Skorların',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildBiasCard(
          title: 'Disposition Effect',
          academic: 'Shefrin & Statman, 1985',
          score: (de['score'] as num).toDouble(),
          range: '-1.0 ile +1.0',
          description:
              'Kazançları erken satıp, kayıpları elinde tutma eğilimi. Pozitif skor bu önyargının varlığını gösterir.',
          metric:
              'Realize edilen kazançlar: ${de['realized_gains']} • Realize edilen kayıplar: ${de['realized_losses']}',
        ),
        _buildBiasCard(
          title: 'Loss Aversion',
          academic: 'Kahneman & Tversky, 1979 (Nobel 2002)',
          score: (la['score'] as num).toDouble(),
          range: '0.0 ile 1.0',
          description:
              'Kayıp acısı eşdeğer kazanç sevincinin ~2 katıdır. Yüksek skor zarardaki pozisyonu uzun süre tutmayı gösterir.',
          metric:
              'Kazançta tutuş: ${la['avg_gain_holding_days']}g • Zararda tutuş: ${la['avg_loss_holding_days']}g',
        ),
        _buildBiasCard(
          title: 'Overconfidence',
          academic: 'Barber & Odean, 2001',
          score: (oc['score'] as num).toDouble(),
          range: '0.0 ile 1.0',
          description:
              'Aşırı güven yüksek işlem sıklığına yol açar. Çalışma: aşırı işlem yapan yatırımcılar uzun vadede %6 daha az getiri elde ediyor.',
          metric:
              'Günlük işlem sıklığı: ${oc['trades_per_day']} • Toplam işlem: ${oc['total_trades']}',
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Icon(Icons.school_outlined, color: Colors.tealAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bu analiz Davranışsal Finans literatüründeki klasik metrikleri kullanır. Eğitim amaçlıdır.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPersonaCard(Map<String, dynamic> persona) {
    final colorHex = persona['color'] as String;
    final color = Color(int.parse(colorHex.replaceFirst('#', 'FF'), radix: 16));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.6), color.withValues(alpha: 0.3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    const Icon(Icons.psychology, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Karakterin',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(persona['title'] as String,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(persona['description'] as String,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildBiasCard({
    required String title,
    required String academic,
    required double score,
    required String range,
    required String description,
    required String metric,
  }) {
    final pct = score.abs().clamp(0.0, 1.0);
    final color = score > 0.4
        ? Colors.redAccent
        : score > 0.2
            ? Colors.orangeAccent
            : Colors.greenAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(academic,
                        style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                            fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(score.toStringAsFixed(2),
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text('Aralık: $range',
              style: TextStyle(color: Colors.grey[600], fontSize: 10)),
          const SizedBox(height: 10),
          Text(description,
              style: TextStyle(
                  color: Colors.grey[400], fontSize: 12, height: 1.4)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(metric,
                style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
