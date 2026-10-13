import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

/// Portföy Sağlık Skoru — tek hero skor + 5 alt boyut (IOSScoreBar) + öneriler.
class PortfolioHealthCard extends StatefulWidget {
  const PortfolioHealthCard({super.key});

  @override
  State<PortfolioHealthCard> createState() => _PortfolioHealthCardState();
}

class _PortfolioHealthCardState extends State<PortfolioHealthCard> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final r = await _api.fetchPortfolioHealth(uid);
      if (!mounted) return;
      setState(() {
        _data = r;
        _loading = false;
      });
    } catch (_) {
      // Geçici hata/timeout: kartı sessizce gizleme; son iyi veri yoksa
      // "Tekrar Dene" göster. (Gerçek "veri yok" 200+has_data:false → ayrı.)
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// Metrik açıklama sheet'i — hero (skor + durum rozeti + bar + hedef) +
  /// yapısal bölümler (Ne ölçer · Senin durumun · Yapılması gereken).
  void _showMetricInfo(BuildContext context, Map<String, dynamic> dim) {
    final c = AppColorsExt.of(context);
    final score = (dim['score'] as num).toDouble();
    final col =
        score >= 70 ? c.positive : (score >= 40 ? c.warmAccent : c.negative);
    final verdict = score >= 70 ? 'Güçlü' : (score >= 40 ? 'Orta' : 'Zayıf');

    showIOSBottomSheet(
      context: context,
      title: dim['key']?.toString() ?? '',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IOSSheetHero(
              value: score.toStringAsFixed(0),
              unit: '/ 100',
              color: col,
              verdict: verdict,
              progress: score.clamp(0, 100) / 100.0,
              footnote: dim['ideal']?.toString(),
            ),
            const SizedBox(height: 24),
            if (dim['what'] != null)
              IOSInfoBlock(
                  icon: Icons.straighten,
                  label: 'NE ÖLÇER',
                  body: dim['what'].toString()),
            if (dim['reading'] != null) ...[
              const SizedBox(height: 20),
              IOSInfoBlock(
                  icon: Icons.analytics_outlined,
                  label: 'SENİN DURUMUN',
                  body: dim['reading'].toString()),
            ],
            if (dim['action'] != null) ...[
              const SizedBox(height: 20),
              IOSInfoBlock(
                  icon: Icons.arrow_forward_rounded,
                  label: 'YAPILMASI GEREKEN',
                  body: dim['action'].toString(),
                  emphasize: true),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    if (_loading) {
      return SizedBox(
        height: 80,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: c.textSubtle),
          ),
        ),
      );
    }
    final d = _data;
    if (_error && d == null) {
      return Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: c.textSubtle),
          const SizedBox(width: 9),
          Expanded(
            child: Text('Sağlık skoru yüklenemedi',
                style: TextStyle(color: c.textMuted, fontSize: 13)),
          ),
          TextButton(
            onPressed: _load,
            style: TextButton.styleFrom(
              foregroundColor: c.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Tekrar Dene', style: TextStyle(fontSize: 13)),
          ),
        ],
      );
    }
    if (d == null || d['has_data'] != true) return const SizedBox.shrink();

    final score = (d['score'] as num).toDouble();
    final grade = d['grade'] as String? ?? '';
    final dims = (d['dimensions'] as List?) ?? [];
    final recs = (d['recommendations'] as List?) ?? [];
    final scoreColor =
        score >= 70 ? c.positive : (score >= 50 ? c.warmAccent : c.negative);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Portföy Sağlık Skoru',
              style: TextStyle(
                  color: c.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                score.toStringAsFixed(0),
                style: TextStyle(
                  color: scoreColor,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  height: 1.0,
                ),
              ),
              Text(' / 100',
                  style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(grade,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final dim in dims) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dim['what'] != null
                  ? () => _showMetricInfo(context, dim as Map<String, dynamic>)
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: IOSScoreBar(
                      label: '${dim['key']}  ·  ${dim['detail']}',
                      score: (dim['score'] as num).toDouble(),
                    ),
                  ),
                  if (dim['what'] != null) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.info_outline, size: 15, color: c.textSubtle),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (recs.isNotEmpty) ...[
            const SizedBox(height: 2),
            Divider(color: c.divider, height: 1),
            const SizedBox(height: 14),
            for (final r in recs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.warmAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.toString(),
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 12.5,
                            height: 1.5,
                            letterSpacing: -0.1),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
