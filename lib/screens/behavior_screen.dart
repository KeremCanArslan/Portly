import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/providers/chat_provider.dart';
import 'package:portly/screens/chat_screen.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

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
    final c = AppColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: AppColorsExt.of(context)
            .bg, // opak: şeffaf AppBar açık temada ghost bırakıyor
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Yatırımcı Karakterin',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: c.textMuted, size: 20),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading
                ? Center(child: CircularProgressIndicator(color: c.textPrimary))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!,
                              style:
                                  TextStyle(color: c.textMuted, fontSize: 14),
                              textAlign: TextAlign.center),
                        ),
                      )
                    : _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final c = AppColorsExt.of(context);
    if (_data == null) return const SizedBox.shrink();

    if (_data!['has_enough_data'] != true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.psychology_outlined, size: 38, color: c.textSubtle),
              const SizedBox(height: 14),
              Text(
                _data!['message'] as String? ??
                    'Davranışsal profil için yeterli veri yok',
                style: TextStyle(color: c.textMuted, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Yatırımcı karakterini görmek için piyasalardan birkaç işlem yap.',
                style: TextStyle(color: c.textSubtle, fontSize: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        _buildPersonaCard(persona),
        const SizedBox(height: 12),
        _buildExplainerCard(),
        const SizedBox(height: 24),
        IOSSectionHeader(label: 'Davranışsal Önyargı Skorların'),
        const SizedBox(height: 6),
        _buildBiasCard(
          title: 'Disposition Effect',
          academic: 'Shefrin & Statman, 1985',
          score: (de['score'] as num).toDouble(),
          minVal: -1.0,
          maxVal: 1.0,
          description:
              'Kazançları erken satıp, kayıpları elinde tutma eğilimi. Pozitif skor bu önyargının varlığını gösterir.',
          metric:
              'Realize kazanç: ${de['realized_gains']}  ·  Realize kayıp: ${de['realized_losses']}',
        ),
        const SizedBox(height: 12),
        _buildBiasCard(
          title: 'Loss Aversion',
          academic: 'Kahneman & Tversky, 1979 (Nobel 2002)',
          score: (la['score'] as num).toDouble(),
          minVal: 0.0,
          maxVal: 1.0,
          description:
              'Kayıp acısı eşdeğer kazanç sevincinin ~2 katıdır. Yüksek skor zarardaki pozisyonu uzun süre tutmayı gösterir.',
          metric:
              'Kazançta tutuş: ${la['avg_gain_holding_days']}g  ·  Zararda tutuş: ${la['avg_loss_holding_days']}g',
        ),
        const SizedBox(height: 12),
        _buildBiasCard(
          title: 'Overconfidence',
          academic: 'Barber & Odean, 2001',
          score: (oc['score'] as num).toDouble(),
          minVal: 0.0,
          maxVal: 1.0,
          description:
              'Aşırı güven yüksek işlem sıklığına yol açar. Çalışma: aşırı işlem yapan yatırımcılar uzun vadede %6 daha az getiri elde ediyor.',
          metric:
              'Günlük sıklık: ${oc['trades_per_day']}  ·  Toplam işlem: ${oc['total_trades']}',
        ),
        const SizedBox(height: 20),
        _buildCoachCta(persona, de, oc, la),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.school_outlined, color: c.textSubtle, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bu analiz Davranışsal Finans literatüründeki klasik metrikleri kullanır. Eğitim amaçlıdır.',
                  style:
                      TextStyle(color: c.textSubtle, fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPersonaCard(Map<String, dynamic> persona) {
    final colorHex = persona['color'] as String;
    final personaColor =
        Color(int.parse(colorHex.replaceFirst('#', 'FF'), radix: 16));

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: personaColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology,
                  color: Colors.white.withValues(alpha: 0.9), size: 22),
              const SizedBox(width: 8),
              Text('KARAKTERİN',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 14),
          Text(persona['title'] as String,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.1)),
          const SizedBox(height: 12),
          Text(persona['description'] as String,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  height: 1.55)),
        ],
      ),
    );
  }

  /// Bias kartı — skor barı + seviye rozeti + metrik + bottom sheet'e link.
  /// Önyargılarda DÜŞÜK = sağlıklı, YÜKSEK = dikkat → renk buna göre.
  Widget _buildBiasCard({
    required String title,
    required String academic,
    required double score,
    required double minVal,
    required double maxVal,
    required String description,
    required String metric,
  }) {
    final c = AppColorsExt.of(context);
    // Normalize 0..1 (önyargı şiddeti). Disposition -1..1 → mutlak değer.
    final double intensity = (minVal < 0)
        ? (score.abs() / maxVal).clamp(0.0, 1.0)
        : ((score - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);

    final Color dataColor = intensity > 0.5
        ? c.negative
        : (intensity > 0.25 ? c.warmAccent : c.positive);
    final String levelText =
        intensity > 0.5 ? 'Yüksek' : (intensity > 0.25 ? 'Orta' : 'İyi');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Text(academic,
                        style: TextStyle(
                            color: c.textSubtle,
                            fontSize: 11,
                            fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(score.toStringAsFixed(2),
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      )),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: dataColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(levelText,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 6, color: c.surfaceAlt),
                FractionallySizedBox(
                  widthFactor: intensity == 0 ? 0.02 : intensity,
                  child: Container(height: 6, color: dataColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(description,
              style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(metric,
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 12,
                  letterSpacing: -0.1,
                )),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: IOSTextLink(
              label: 'Nasıl hesaplandı?  →',
              color: c.warmAccent,
              fontWeight: FontWeight.w600,
              onTap: () => _showCalculationSheet(title),
            ),
          ),
        ],
      ),
    );
  }

  void _showCalculationSheet(String title) {
    final c = AppColorsExt.of(context);
    showIOSBottomSheet(
      context: context,
      title: title,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nasıl hesaplandı?',
                style: TextStyle(
                    color: c.warmAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3)),
            const SizedBox(height: 12),
            Text(
              _getCalculationExplanation(title),
              style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.65),
            ),
          ],
        ),
      ),
    );
  }

  String _getCalculationExplanation(String biasTitle) {
    switch (biasTitle) {
      case 'Disposition Effect':
        return 'İşlem geçmişin incelenir. Realize ettiğin kazançlı pozisyonların oranı (PGR) ile zarardaki pozisyonların oranı (PLR) hesaplanır. Skor = PGR - PLR formülü ile bulunur.\n\nPozitif skor → kazançları erken satıp kayıpları tutuyorsun (yaygın bir önyargı). Negatif skor → tam tersi davranış.';
      case 'Loss Aversion':
        return 'Her satış işleminde, o pozisyonu kaç gün tuttuğun ölçülür. Kazançtaki pozisyonların ortalama tutuş süresi ile zarardaki pozisyonların ortalama tutuş süresi karşılaştırılır.\n\nZararlı pozisyonları kazançlılardan çok daha uzun tutuyorsan, skor yüksek çıkar. Bu Kahneman & Tversky\'nin "kayıp acısı kazanç sevincinin 2 katıdır" bulgusunu yansıtır.';
      case 'Overconfidence':
        return 'Aktif olduğun gün başına düşen ortalama işlem sayın hesaplanır. Günde 1\'den fazla işlem aşırı işlem sıklığına işaret eder.\n\nBarber & Odean (2001) çalışmasına göre, en aktif yatırımcılar piyasa ortalamasına göre yıllık %6 daha az kazanır. Aşırı güven, gereksiz alım-satıma yol açar.';
      default:
        return 'İşlem geçmişin akademik literatürdeki standart formüllerle değerlendirildi.';
    }
  }

  Widget _buildCoachCta(
    Map<String, dynamic> persona,
    Map<String, dynamic> de,
    Map<String, dynamic> oc,
    Map<String, dynamic> la,
  ) {
    final c = AppColorsExt.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final prompt = 'Yatırımcı karakterim "${persona['title']}" çıktı. '
              'Disposition Effect skorum ${de['score']}, '
              'Overconfidence skorum ${oc['score']}, '
              'Loss Aversion skorum ${la['score']}. '
              'Bu profilime göre nasıl daha iyi bir yatırımcı olabilirim? '
              'Hangi davranışsal önyargıma dikkat etmeliyim?';
          context.read<ChatProvider>().setPendingPrompt(prompt);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: c.warmAccentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome, color: c.warmAccent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Koç\'tan Tavsiye Al',
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text(
                      'Profilin için kişiselleştirilmiş davranışsal koçluk',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textSubtle, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExplainerCard() {
    final c = AppColorsExt.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology, color: c.textMuted, size: 18),
              const SizedBox(width: 8),
              Text(
                'Bu skorlar ne anlama geliyor?',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'İşlem geçmişin, davranışsal finans literatüründeki üç klasik metrikle analiz edildi. Bu metrikler Nobel ödüllü çalışmalardan geliyor — profesyonel yatırımcılar bile bu önyargılara düşer.\n\nDüşük skor = sağlıklı davranış. Yüksek skor = dikkat edilmesi gereken eğilim.',
            style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _legendBox(c.positive, 'Düşük (iyi)'),
              const SizedBox(width: 16),
              _legendBox(c.warmAccent, 'Orta'),
              const SizedBox(width: 16),
              _legendBox(c.negative, 'Yüksek (dikkat)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendBox(Color color, String label) {
    final c = AppColorsExt.of(context);
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c.textMuted, fontSize: 11)),
      ],
    );
  }
}
