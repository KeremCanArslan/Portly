import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

class _Question {
  final String text;
  // (etiket, skor). Skor 1=muhafazakar, 4=agresif.
  final List<MapEntry<String, int>> options;
  const _Question(this.text, this.options);
}

const List<_Question> _kQuestions = [
  _Question(
    'Yatırım yapmaktaki ana hedefin nedir?',
    [
      MapEntry('Sermayemi korumak', 1),
      MapEntry('Düşük riskle istikrarlı büyüme', 2),
      MapEntry('Yüksek getiri için risk almak', 3),
      MapEntry('Ne pahasına olursa olsun maksimum getiri', 4),
    ],
  ),
  _Question(
    'Yatırımının %20\'si bir ayda erirse ne yapardın?',
    [
      MapEntry('Hepsini hemen satarım', 1),
      MapEntry('Bir kısmını satarım', 2),
      MapEntry('Beklerim, toparlamasını umarım', 3),
      MapEntry('Düşmüşken daha çok alırım', 4),
    ],
  ),
  _Question(
    'Yatırım vade planın ne kadar?',
    [
      MapEntry('1 yıldan az', 1),
      MapEntry('1-3 yıl', 2),
      MapEntry('3-7 yıl', 3),
      MapEntry('7+ yıl', 4),
    ],
  ),
  _Question(
    'Aylık gelirinin ne kadarını yatırıma ayırabilirsin?',
    [
      MapEntry('%5\'ten az', 1),
      MapEntry('%5 – %15', 2),
      MapEntry('%15 – %30', 3),
      MapEntry('%30+', 4),
    ],
  ),
  _Question(
    'Hangi senaryoyu tercih edersin?',
    [
      MapEntry('Garanti +%4 yıllık getiri', 1),
      MapEntry('%50 ihtimal +%10, %50 +%2', 2),
      MapEntry('%50 ihtimal +%25, %50 −%5', 3),
      MapEntry('%50 ihtimal +%50, %50 −%20', 4),
    ],
  ),
  _Question(
    'Daha önce yatırımda kayıp yaşadın mı?',
    [
      MapEntry('Hayır, riskten kaçınıyorum', 1),
      MapEntry('Evet, ama çok stres ettim', 2),
      MapEntry('Evet, ders aldım ve devam ettim', 3),
      MapEntry('Evet, kayıplar işin doğal parçası', 4),
    ],
  ),
  _Question(
    'Yüksek volatiliteli yatırımlar (kripto, opsiyon) hakkında ne düşünüyorsun?',
    [
      MapEntry('Asla yapmam', 1),
      MapEntry('Çok küçük bir kısım için olabilir', 2),
      MapEntry('Portföyümün önemli bir parçası olabilir', 3),
      MapEntry('Asıl odağım bunlar', 4),
    ],
  ),
];

class RiskProfileTestScreen extends StatefulWidget {
  const RiskProfileTestScreen({super.key});

  @override
  State<RiskProfileTestScreen> createState() => _RiskProfileTestScreenState();
}

class _RiskProfileTestScreenState extends State<RiskProfileTestScreen> {
  int _index = 0;
  final List<int> _answers = List.filled(_kQuestions.length, 0);
  bool _submitting = false;

  bool get _isLast => _index == _kQuestions.length - 1;
  bool get _hasAnswer => _answers[_index] != 0;

  String _profileFor(double avg) {
    if (avg < 1.8) return 'Muhafazakar';
    if (avg < 2.8) return 'Dengeli';
    return 'Agresif';
  }

  String _descFor(String profile) {
    switch (profile) {
      case 'Muhafazakar':
        return 'Sermayeni korumayı öne çıkarıyorsun. Düşük volatilite, '
            'tahvil ve büyük şirket hisseleri profilinle uyumlu.';
      case 'Dengeli':
        return 'Risk-getiri dengesini önemsiyorsun. Hisse + sabit getirili '
            'karma portföyler senin için uygun.';
      case 'Agresif':
        return 'Yüksek getiri için yüksek riski göze alıyorsun. Büyüme '
            'hisseleri, kripto ve volatil enstrümanlar profilinle uyumlu.';
      default:
        return '';
    }
  }

  IconData _iconFor(String profile) {
    switch (profile) {
      case 'Muhafazakar':
        return Icons.security;
      case 'Dengeli':
        return Icons.balance;
      case 'Agresif':
        return Icons.local_fire_department;
      default:
        return Icons.psychology;
    }
  }

  Future<void> _saveAndShowResult() async {
    final total = _answers.fold<int>(0, (s, a) => s + a);
    final avg = total / _kQuestions.length;
    final profile = _profileFor(avg);

    setState(() => _submitting = true);
    final ok = await context.read<AuthProvider>().setRiskProfile(profile);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil kaydedilemedi, internet bağlantını kontrol et'),
          backgroundColor: Color(0xFFFB7185),
        ),
      );
      return;
    }

    _showResultSheet(profile, avg);
  }

  void _showResultSheet(String profile, double avg) {
    showIOSBottomSheet(
      context: context,
      title: 'Risk Profilin',
      child: Builder(builder: (ctx) {
        final c = AppColorsExt.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: c.warmAccentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconFor(profile), color: c.warmAccent, size: 40),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(profile,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text('Ortalama ${avg.toStringAsFixed(2)} / 4',
                    style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 12,
                    )),
              ),
              const SizedBox(height: 16),
              Text(
                _descFor(profile),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.textMuted,
                    fontSize: 14,
                    height: 1.55,
                    letterSpacing: -0.1),
              ),
              const SizedBox(height: 22),
              IOSPillButton(
                label: 'Tamam',
                width: double.infinity,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_index + 1) / _kQuestions.length;
    final q = _kQuestions[_index];

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
        title: Text('Risk Profili Testi',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('${_index + 1} / ${_kQuestions.length}',
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: c.surfaceAlt,
                            valueColor: AlwaysStoppedAnimation(c.warmAccent),
                            minHeight: 5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(q.text,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.separated(
                      itemCount: q.options.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final opt = q.options[i];
                        final selected = _answers[_index] == opt.value;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _answers[_index] = opt.value),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: selected ? c.warmAccentSoft : c.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected
                                        ? c.warmAccent
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: selected
                                          ? c.warmAccent
                                          : c.textSubtle,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: selected
                                      ? Icon(Icons.check, color: c.bg, size: 13)
                                      : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(opt.key,
                                      style: TextStyle(
                                          color: selected
                                              ? c.textPrimary
                                              : c.textMuted,
                                          fontSize: 14,
                                          letterSpacing: -0.1,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w500)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_index > 0) ...[
                        Expanded(
                          child: IOSPillButton(
                            label: 'Geri',
                            secondary: true,
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _index--),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 2,
                        child: IOSPillButton(
                          label: _isLast ? 'Sonucu Gör' : 'Devam',
                          isLoading: _submitting,
                          onPressed: !_hasAnswer || _submitting
                              ? null
                              : () {
                                  if (_isLast) {
                                    _saveAndShowResult();
                                  } else {
                                    setState(() => _index++);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
