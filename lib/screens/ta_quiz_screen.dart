import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/widgets/price_chart.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/theme/premium.dart';

/// Mum Tahmini — "grafiği oku" oyunu.
///
/// Geçmişten rastgele bir mum penceresi gösterilir, devamı gizlenir. Sembol
/// de gizlidir (sadece varlık sınıfı açık) → ezber değil, gerçek okuma. Tek
/// soru: sıradaki ~1 ayda fiyat YUKARI mı, AŞAĞI mı? Cevaptan sonra gizli
/// mumlar açılır, sonuç + skor/seri gösterilir.
///
/// Eski sürüm vade seçtiriyor + hedef/stop/yatay (3 şık) soruyordu; karmaşık
/// ve kırılgandı. Bu sürüm ikili, hızlı ve oynanır (chartgame tarzı).
class TaQuizScreen extends StatefulWidget {
  const TaQuizScreen({super.key});

  @override
  State<TaQuizScreen> createState() => _TaQuizScreenState();
}

enum _QuizState { loading, showing, revealed, finished }

class _TaQuizScreenState extends State<TaQuizScreen> {
  final ApiService _api = ApiService();
  _QuizState _state = _QuizState.loading;
  Map<String, dynamic>? _question;
  String? _userAnswer; // UP / DOWN
  int _score = 0;
  int _total = 0;
  int _streak = 0;
  int _bestStreak = 0;
  static const int _maxQuestions = 10;

  @override
  void initState() {
    super.initState();
    _loadNext();
  }

  Future<void> _loadNext() async {
    setState(() {
      _state = _QuizState.loading;
      _userAnswer = null;
    });
    final q = await _api.fetchQuizQuestion();
    if (!mounted) return;
    if (q == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Grafik verisi alınamadı — tekrar denenecek'),
      ));
      // Yumuşak yeniden dene (ağ/Yahoo dalgalanması).
      await Future.delayed(const Duration(seconds: 1));
      if (mounted && _state == _QuizState.loading) _loadNext();
      return;
    }
    setState(() {
      _question = q;
      _state = _QuizState.showing;
    });
  }

  void _submitAnswer(String dir) {
    final ans = _question!['answer'] as Map;
    final correct = (ans['direction'] as String? ?? '').toUpperCase();
    final isCorrect = correct == dir;
    setState(() {
      _userAnswer = dir;
      _state = _QuizState.revealed;
      _total++;
      if (isCorrect) {
        _score++;
        _streak++;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    });
  }

  void _nextOrFinish() {
    if (_total >= _maxQuestions) {
      setState(() => _state = _QuizState.finished);
    } else {
      _loadNext();
    }
  }

  void _restart() {
    setState(() {
      _score = 0;
      _total = 0;
      _streak = 0;
      _bestStreak = 0;
    });
    _loadNext();
  }

  // Tahmin anında sembol gizli ama varlık sınıfı açık — BIST/ABD/kripto/emtia
  // çok farklı dinamiklere sahip; bu bağlam olmadan tahmin "atış" olur.
  String _assetCategory(String sym) {
    final u = sym.toUpperCase();
    if (u.endsWith('.FON')) return 'Yatırım Fonu';
    if (u.endsWith('.IS') || u.endsWith('.TR')) return 'BIST Hissesi';
    if (u.endsWith('-USD') || u.endsWith('USDT')) return 'Kripto';
    if (u.endsWith('=F')) return 'Emtia';
    if (u.endsWith('=X')) return 'Döviz';
    return 'ABD Hissesi';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Mum Tahmini',
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
            constraints: const BoxConstraints(maxWidth: 720),
            child: _buildContent(c),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AppColorsExt c) {
    switch (_state) {
      case _QuizState.loading:
        return Center(child: CircularProgressIndicator(color: c.textPrimary));
      case _QuizState.showing:
      case _QuizState.revealed:
        return _buildQuestion(c);
      case _QuizState.finished:
        return _buildFinished(c);
    }
  }

  // ── Soru + grafik ───────────────────────────────────────────────────────
  Widget _buildQuestion(AppColorsExt c) {
    final q = _question!;
    final symbol = q['symbol'] as String;
    final visible = (q['visible'] as List).cast<Map<String, dynamic>>();
    final hidden = (q['hidden'] as List).cast<Map<String, dynamic>>();
    final answer = q['answer'] as Map<String, dynamic>;
    final reference = (q['reference'] as num).toDouble();
    final revealed = _state == _QuizState.revealed;

    final chartData = revealed ? [...visible, ...hidden] : visible;
    final currency =
        symbol.endsWith('.IS') ||
                symbol.endsWith('.FON') ||
                symbol.contains('TRY')
            ? '₺'
            : '\$';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst: ilerleme + skor + seri
          Row(
            children: [
              Text('Soru ${_total + (revealed ? 0 : 1)} / $_maxQuestions',
                  style: TextStyle(color: c.textMuted, fontSize: 12)),
              const Spacer(),
              if (_streak >= 2) ...[
                Icon(Icons.local_fire_department,
                    color: c.warmAccent, size: 15),
                const SizedBox(width: 3),
                Text('$_streak',
                    style: TextStyle(
                        color: c.warmAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
              ],
              Text('Skor $_score / $_total',
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          // Sembol gizli (showing) / açık (revealed)
          Text(
            revealed
                ? '${SymbolDisplay.compact(symbol)} · ${SymbolDisplay.label(symbol)}'
                : 'Sembol gizli · ${_assetCategory(symbol)}',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: c.surface,
              padding: const EdgeInsets.all(8),
              child: PriceChart(
                data: chartData,
                currency: currency,
                priceLines: [
                  PriceLine(
                      price: reference,
                      color: c.textSubtle,
                      label: 'tahmin anı'),
                ],
                height: 340,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!revealed)
            _buildPrompt(c, visible, reference, currency)
          else
            _buildRevealCard(c, answer, currency),
        ],
      ),
    );
  }

  // ── Tahmin istemi (showing) ───────────────────────────────────────────
  Widget _buildPrompt(AppColorsExt c, List<Map<String, dynamic>> visible,
      double reference, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _readingHint(c, visible),
        const SizedBox(height: 14),
        Text(
          'Sıradaki ~1 ayın (20 işlem günü) sonunda fiyat\nşu seviyenin neresinde olur?',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.4,
              letterSpacing: -0.2),
        ),
        const SizedBox(height: 4),
        Text('Referans: $currency${formatMoney(reference)}',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSubtle, fontSize: 12)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _answerButton(
                    c, 'YUKARI', 'UP', c.positive, Icons.arrow_upward_rounded)),
            const SizedBox(width: 12),
            Expanded(
                child: _answerButton(c, 'AŞAĞI', 'DOWN', c.negative,
                    Icons.arrow_downward_rounded)),
          ],
        ),
      ],
    );
  }

  // Görünür kısmın son ~20 mumundaki eğilim — öğretici bağlam (geleceği
  // ELE VERMEZ; eğilim tersine de dönebilir, oyunun amacı bu).
  Widget _readingHint(AppColorsExt c, List<Map<String, dynamic>> visible) {
    final n = visible.length;
    final lookback = n >= 20 ? 20 : n;
    final past = (visible[n - lookback]['close'] as num).toDouble();
    final last = (visible[n - 1]['close'] as num).toDouble();
    final pct = past > 0 ? (last - past) / past * 100 : 0.0;
    final up = pct >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, size: 16, color: c.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Son $lookback mumdaki eğilim: ${up ? '+' : '−'}%${formatMoney(pct.abs())}',
              style: TextStyle(color: c.textMuted, fontSize: 12.5),
            ),
          ),
          Text('ipucu',
              style: TextStyle(
                  color: c.textSubtle,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _answerButton(
      AppColorsExt c, String label, String dir, Color color, IconData icon) {
    return GestureDetector(
      onTap: () => _submitAnswer(dir),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }

  // ── Sonuç kartı (revealed) ────────────────────────────────────────────
  Widget _buildRevealCard(
      AppColorsExt c, Map<String, dynamic> answer, String currency) {
    final correct = (answer['direction'] as String? ?? '').toUpperCase();
    final pct = (answer['pct_change'] as num).toDouble();
    final endPrice = (answer['end_price'] as num).toDouble();
    final isCorrect = _userAnswer == correct;
    final dirColor = correct == 'UP' ? c.positive : c.negative;
    final resultColor = isCorrect ? c.positive : c.negative;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: resultColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isCorrect ? Icons.check_circle : Icons.cancel,
                      color: resultColor, size: 22),
                  const SizedBox(width: 8),
                  Text(isCorrect ? 'Doğru' : 'Yanlış',
                      style: TextStyle(
                          color: resultColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Fiyat 20 işlem gününde ${correct == 'UP' ? 'YUKARI' : 'AŞAĞI'} '
                'gitti: ${pct >= 0 ? '+' : '−'}%${formatMoney(pct.abs())} '
                '→ $currency${formatMoney(endPrice)}',
                style: TextStyle(
                    color: c.textPrimary, fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 6),
              Text(
                'Senin tahminin: ${_userAnswer == 'UP' ? 'Yukarı' : 'Aşağı'}'
                '  ·  Gerçek: ${correct == 'UP' ? 'Yukarı' : 'Aşağı'}',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: dirColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Tepe $currency${formatMoney((answer['max_high'] as num).toDouble())} · Dip $currency${formatMoney((answer['min_low'] as num).toDouble())}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        IOSPillButton(
          label: _total >= _maxQuestions ? 'Sonuçları Gör' : 'Sonraki',
          width: double.infinity,
          onPressed: _nextOrFinish,
        ),
      ],
    );
  }

  // ── Bitiş ekranı ──────────────────────────────────────────────────────
  Widget _buildFinished(AppColorsExt c) {
    final pct = _total > 0 ? (_score / _total * 100) : 0.0;
    final (title, sub) = _verdict(pct);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(child: IOSLogoMark(size: 56)),
          const SizedBox(height: 20),
          Center(
            child: Text('$_score / $_total',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Doğruluk: %${formatMoney(pct)}',
                style: TextStyle(color: c.textMuted, fontSize: 13)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(title,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                const SizedBox(height: 6),
                Text(sub,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: c.textMuted, fontSize: 13, height: 1.5)),
                const SizedBox(height: 14),
                const EliteHairline(),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat(c, 'En uzun seri', '$_bestStreak'),
                    _stat(c, 'Soru', '$_total'),
                    _stat(c, 'Doğru', '$_score'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          IOSPillButton(
              label: 'Yeniden Oyna',
              width: double.infinity,
              onPressed: _restart),
        ],
      ),
    );
  }

  (String, String) _verdict(double pct) {
    // 50 = rastgele atış. Üstü gerçek okuma demektir.
    if (pct >= 80) {
      return ('Keskin göz', 'Grafiği gerçekten okuyorsun — rastgelenin çok üstünde.');
    }
    if (pct >= 60) {
      return ('İyi sezgi', 'Yazı-turanın üstündesin; eğilim okuman çalışıyor.');
    }
    if (pct >= 45) {
      return ('Rastgele bandı', 'Bu skor neredeyse yazı-tura. Eğilim + hacme bakmayı dene.');
    }
    return ('Tersine bak', 'İlginç biçimde tahminlerin sık ters çıkmış — eğilimi tersten okuyor olabilirsin.');
  }

  Widget _stat(AppColorsExt c, String label, String value) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5)),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(color: c.textMuted, fontSize: 11.5)),
      ],
    );
  }
}
