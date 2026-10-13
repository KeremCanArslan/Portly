import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';

/// Korku & Açgözlülük endeksi — piyasa duyarlılığı göstergesi.
/// Skor renkleri = veri (sentiment) → data-ink kuralında izinli, tema token'ı.
class FearGreedGauge extends StatefulWidget {
  const FearGreedGauge({super.key});

  @override
  State<FearGreedGauge> createState() => _FearGreedGaugeState();
}

class _FearGreedGaugeState extends State<FearGreedGauge> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _loading = true);
    final d = await _api.fetchFearGreed(force: force);
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
    });
  }

  // 3 kademeli, uygulama genelindeki IOSScoreBar mantığıyla uyumlu.
  Color _scoreColor(BuildContext context, double s) {
    final c = AppColorsExt.of(context);
    if (s < 40) return c.negative; // korku
    if (s < 60) return c.warmAccent; // nötr
    return c.positive; // açgözlülük
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    if (_loading) {
      return Container(
        height: 130,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: CircularProgressIndicator(color: c.textPrimary),
        ),
      );
    }

    if (_data == null) {
      return Container(
        height: 110,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text('Korku & Açgözlülük verisi alınamadı',
              style: TextStyle(color: c.textMuted, fontSize: 13)),
        ),
      );
    }

    final score = (_data!['score'] as num).toDouble();
    final label = _data!['label'] as String;
    final components = _data!['components'] as Map<String, dynamic>;
    final color = _scoreColor(context, score);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: CustomPaint(
              painter: _GaugePainter(
                  score: score, color: color, track: c.surfaceAlt),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),
                    Text(score.toStringAsFixed(0),
                        style: TextStyle(
                          color: color,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        )),
                    Text('/ 100',
                        style: TextStyle(
                          color: c.textSubtle,
                          fontSize: 10,
                        )),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Korku & Açgözlülük',
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1)),
                    const Spacer(),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _load(force: true),
                        child:
                            Icon(Icons.refresh, color: c.textSubtle, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4)),
                const SizedBox(height: 10),
                _componentBar(context, 'Volatilite (VIX)',
                    (components['volatility']['score'] as num).toDouble()),
                const SizedBox(height: 5),
                _componentBar(context, 'Momentum (S&P)',
                    (components['momentum']['score'] as num).toDouble()),
                const SizedBox(height: 5),
                _componentBar(context, 'Haber Sentiment',
                    (components['sentiment']['score'] as num).toDouble()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _componentBar(BuildContext context, String label, double score) {
    final c = AppColorsExt.of(context);
    final color = _scoreColor(context, score);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child:
              Text(label, style: TextStyle(color: c.textMuted, fontSize: 10)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(height: 5, color: c.surfaceAlt),
                FractionallySizedBox(
                  widthFactor: (score / 100).clamp(0.02, 1.0),
                  child: Container(height: 5, color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 22,
          child: Text(score.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: c.textMuted,
                fontSize: 10,
              )),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double score;
  final Color color;
  final Color track;
  _GaugePainter(
      {required this.score, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.65);
    final radius = math.min(size.width, size.height) * 0.42;

    final bgPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    final scorePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final sweep = (score / 100) * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      sweep,
      false,
      scorePaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.score != score || old.color != color || old.track != track;
}
