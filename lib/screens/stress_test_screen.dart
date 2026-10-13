import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/utils/symbol_display.dart';

class StressTestScreen extends StatefulWidget {
  const StressTestScreen({super.key});

  @override
  State<StressTestScreen> createState() => _StressTestScreenState();
}

class _StressTestScreenState extends State<StressTestScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _scenarios = [];
  Map<String, dynamic>? _result;
  String _selectedScenario = 'subprime_2008';
  bool _loading = true;
  bool _inTry = false; // false: kendi para birimi · true: ₺ karşılığı
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _scenarios = await _api.fetchStressScenarios();
    await _runTest('subprime_2008');
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
        title: Text('Risk Analizi',
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
            child: _scenarios.isEmpty
                ? Center(child: CircularProgressIndicator(color: c.textPrimary))
                : Column(
                    children: [
                      _scenarioSelector(),
                      Expanded(child: _content()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _scenarioSelector() {
    final c = AppColorsExt.of(context);
    return SizedBox(
      height: 58,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        itemCount: _scenarios.length,
        itemBuilder: (_, i) {
          final s = _scenarios[i] as Map<String, dynamic>;
          final id = s['id'] as String;
          final sel = id == _selectedScenario;
          return GestureDetector(
            onTap: _loading ? null : () => _runTest(id),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? c.warmAccentSoft : c.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(s['name'] as String,
                    style: TextStyle(
                        color: sel ? c.warmAccent : c.textMuted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        fontSize: 13)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content() {
    final c = AppColorsExt.of(context);
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: c.textPrimary),
            const SizedBox(height: 16),
            Text('Hesaplanıyor…',
                style: TextStyle(color: c.textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: TextStyle(color: c.textMuted, fontSize: 14),
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
              Icon(Icons.shield_outlined, size: 38, color: c.textSubtle),
              const SizedBox(height: 14),
              Text('Risk analizi için en az bir hisse pozisyonu gerekli.',
                  style: TextStyle(color: c.textMuted, fontSize: 14),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final r = _result!;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        _hero(r),
        const SizedBox(height: 12),
        _shrinkBar(r),
        const SizedBox(height: 12),
        _insights(r),
        const SizedBox(height: 12),
        _breakdown(r),
        const SizedBox(height: 12),
        _worstCase(r),
        const SizedBox(height: 12),
        _methodNote(r),
        const SizedBox(height: 24),
      ],
    );
  }

  String _f(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  String _qty(num q) {
    if (q == q.roundToDouble()) return q.toStringAsFixed(0);
    return q.toStringAsFixed(q < 1 ? 4 : 2);
  }

  // ── Hero: tek bakışta cevap ─────────────────────────────────────────
  Widget _hero(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    final initial = (r['initial_value'] as num).toDouble();
    final expected = (r['expected_value'] as num).toDouble();
    final pct = (r['expected_change_pct'] as num).toDouble();
    final loss = expected - initial;
    final resilience = r['resilience'] as String;
    final down = pct < 0;
    final dataColor = down ? c.negative : c.positive;

    Color badgeColor;
    switch (resilience) {
      case 'DAYANIKLI':
        badgeColor = c.positive;
        break;
      case 'ORTA':
        badgeColor = c.warmAccent;
        break;
      default:
        badgeColor = c.negative;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text((r['scenario_name'] as String).toUpperCase(),
                  style: TextStyle(
                      color: c.warmAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(resilience,
                    style: TextStyle(
                        color: badgeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Bu senaryoda portföyün tahmini değeri',
              style: TextStyle(color: c.textMuted, fontSize: 13)),
          const SizedBox(height: 6),
          Text('₺${_f(expected)}',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              )),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(down ? Icons.south_east : Icons.north_east,
                  size: 16, color: dataColor),
              const SizedBox(width: 5),
              Text(
                '${loss >= 0 ? '+' : '−'}₺${_f(loss.abs())}  (${formatPctSigned(pct, decimals: 1)}%)',
                style: TextStyle(
                  color: dataColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text('bugünkü ₺${_f(initial)} değerine göre',
                  style: TextStyle(color: c.textSubtle, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Toparlanma süresi + zayıf halka ─────────────────────────────────
  Widget _insights(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    final recovery = (r['recovery_months'] as num?)?.toInt() ?? 0;
    final weak =
        (r['weak_links'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    String recoveryText;
    if (recovery <= 0) {
      recoveryText = 'Kayıp yok — toparlanma gerekmez.';
    } else if (recovery >= 120) {
      recoveryText = 'Tarihsel ortalama büyümeyle 10+ yıl.';
    } else if (recovery >= 12) {
      final y = recovery / 12.0;
      recoveryText =
          'Tarihsel ortalama büyümeyle ~${y.toStringAsFixed(y >= 10 ? 0 : 1)} yıl.';
    } else {
      recoveryText = 'Tarihsel ortalama büyümeyle ~$recovery ay.';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.restore_rounded, size: 18, color: c.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Toparlanma süresi',
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2)),
                    const SizedBox(height: 3),
                    Text(recoveryText,
                        style: TextStyle(
                            color: c.textPrimary, fontSize: 14, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          if (weak.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.link_off_rounded, size: 18, color: c.negative),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Zayıf halka',
                          style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2)),
                      const SizedBox(height: 6),
                      ...weak.map((w) {
                        final sym =
                            SymbolDisplay.compact(w['symbol'] as String? ?? '');
                        final chg = (w['change_pct'] as num?)?.toDouble() ?? 0;
                        final loss = (w['loss_try'] as num?)?.toDouble() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(sym,
                                    style: TextStyle(
                                        color: c.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500)),
                              ),
                              Text('${chg.toStringAsFixed(1)}%  ·  −₺${_f(loss)}',
                                  style: TextStyle(
                                      color: c.negative,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 2),
                      Text(
                          'Bu senaryoda en sert düşen (en kırılgan) pozisyon(lar). '
                          'Çeşitlendirme bu riski azaltır.',
                          style: TextStyle(
                              color: c.textSubtle, fontSize: 12, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Küçülme çubuğu: ne kadar eriyor, görsel ─────────────────────────
  Widget _shrinkBar(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    final initial = (r['initial_value'] as num).toDouble();
    final expected = (r['expected_value'] as num).toDouble();
    final worst = (r['band']['p5_worst_case'] as num).toDouble();
    final expFrac = (expected / initial).clamp(0.0, 1.0);
    final worstFrac = (worst / initial).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Değerin nasıl küçülür',
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, cons) {
            final w = cons.maxWidth;
            return SizedBox(
              height: 34,
              child: Stack(
                children: [
                  // Bugünkü değer (tam genişlik, sönük)
                  Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  // Tahmini değer (renkli, oranlı)
                  Container(
                    height: 34,
                    width: w * expFrac,
                    decoration: BoxDecoration(
                      color: c.textPrimary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  // Kötü senaryo işaretçisi
                  Positioned(
                    left: (w * worstFrac).clamp(0.0, w - 2),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: c.negative),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _barLegend(c.negative, 'Kötü: ₺${_f(worst)}'),
              _barLegend(c.textPrimary.withValues(alpha: 0.85),
                  'Tahmini: ₺${_f(expected)}'),
              _barLegend(c.surfaceAlt, 'Bugün: ₺${_f(initial)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _barLegend(Color color, String label) {
    final c = AppColorsExt.of(context);
    return Row(
      children: [
        Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              color: c.textMuted,
              fontSize: 11,
            )),
      ],
    );
  }

  // ── Hisse kırılımı: hangi pozisyon ne kadar batırıyor ───────────────
  Widget _breakdown(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    final list = (r['breakdown'] as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const SizedBox.shrink();
    final period = r['crisis_period'] as String?;
    final histCount = (r['historical_count'] as num?)?.toInt() ?? 0;
    final totalH = (r['total_holdings'] as num?)?.toInt() ?? list.length;
    final usdCount = (r['usd_holdings_count'] as num?)?.toInt() ?? 0;
    final canToggle = usdCount > 0;

    String subtitle;
    if (period != null) {
      subtitle = histCount == totalH
          ? 'Her hissenin $period dönemindeki yüzde hareketi pozisyonuna uygulandı'
          : '$totalH hisseden $histCount\'i için $period dönemindeki hareket '
              'kullanıldı; kalanlar oynaklığına göre tahmin edildi';
    } else {
      subtitle =
          'Tarihsel karşılığı yok — her hisse kendi oynaklığına göre tahmin edildi';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Hisse hisse etki',
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3)),
              if (canToggle)
                GestureDetector(
                  onTap: () => setState(() => _inTry = !_inTry),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz, size: 14, color: c.warmAccent),
                        const SizedBox(width: 5),
                        Text(_inTry ? '₺ karşılığı' : 'Kendi birimi',
                            style: TextStyle(
                                color: c.warmAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(canToggle ? '$subtitle · birime dokun: \$ ↔ ₺' : subtitle,
              style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 14),
          for (int i = 0; i < list.length; i++) ...[
            _holdingRow(list[i],
                isWorst: i == 0 && list.length > 1, period: period),
            if (i != list.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _holdingRow(Map<String, dynamic> h,
      {required bool isWorst, String? period}) {
    final c = AppColorsExt.of(context);
    final sym = SymbolDisplay.compact(h['symbol'] as String? ?? '');
    final isUsd = (h['currency'] as String?) == 'USD';
    // Toggle yalnız USD pozisyonları etkiler; ₺ pozisyon her zaman ₺.
    final showTry = _inTry && isUsd;
    final cs = showTry ? '₺' : (isUsd ? '\$' : '₺');
    final qty = (h['quantity'] as num?)?.toDouble() ?? 0;

    double v(String k) => (h[k] as num?)?.toDouble() ?? 0;
    final priceB = showTry ? v('price_before_try') : v('price_before');
    final priceA = showTry ? v('price_after_try') : v('price_after');
    final balB = showTry ? v('value_before_try') : v('value_before');
    final balA = showTry ? v('value_after_try') : v('value_after');
    final pct = v('change_pct');
    final vol = v('annual_vol_pct');
    final basis = h['basis'] as String? ?? 'estimated';
    final down = pct < 0;
    final dataColor = down ? c.negative : c.positive;

    final String how;
    if (basis == 'historical') {
      how = '${period ?? 'Kriz'} dönemindeki hareketi';
    } else if (basis == 'estimated') {
      how = 'Tahmini · oynaklık %${vol.toStringAsFixed(0)}/yıl';
    } else {
      how = 'Oynaklık %${vol.toStringAsFixed(0)}/yıl';
    }

    Widget pair(String label, double a, double b, bool bold) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: c.textMuted, fontSize: 11.5)),
            Text('$cs${_f(a)} → $cs${_f(b)}',
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: bold ? 14 : 12.5,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
                )),
          ],
        );

    return GestureDetector(
      onTap: isUsd ? () => setState(() => _inTry = !_inTry) : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isWorst ? c.warmAccentSoft : c.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                      color: dataColor, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 10),
                Text(sym,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1)),
                const SizedBox(width: 8),
                if (isWorst)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: c.warmAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('En çok zarar gören',
                        style: TextStyle(
                            color: c.warmAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: dataColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${formatPctSigned(pct, decimals: 1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            pair('Birim fiyat', priceB, priceA, false),
            const SizedBox(height: 5),
            pair('${qty > 0 ? '${_qty(qty)} adet · ' : ''}Değer', balB, balA,
                true),
            const SizedBox(height: 6),
            Text(how, style: TextStyle(color: c.textSubtle, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  // ── Kötü senaryo ────────────────────────────────────────────────────
  Widget _worstCase(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    final initial = (r['initial_value'] as num).toDouble();
    final worst = (r['band']['p5_worst_case'] as num).toDouble();
    final var95 = (r['band']['var_95'] as num).toDouble();
    final pct = (worst / initial - 1) * 100;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: c.negative),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.5,
                    height: 1.55,
                    letterSpacing: -0.1),
                children: [
                  const TextSpan(
                      text:
                          'Kötü bir senaryoda portföyün '),
                  TextSpan(
                      text: '₺${_f(worst)}',
                      style: TextStyle(
                        color: c.negative,
                        fontWeight: FontWeight.w700,
                      )),
                  TextSpan(
                      text:
                          '\'ye kadar düşebilir — yani ₺${_f(var95)} (%${pct.abs().toStringAsFixed(1)}) kaybedersin. '),
                  const TextSpan(
                      text: 'Benzer 100 durumun 95\'inde kaybın bundan daha azdır; bu, en olumsuz uçtaki sonuçtur.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Yöntem ──────────────────────────────────────────────────────────
  Widget _methodNote(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    final p = r['portfolio'] as Map<String, dynamic>;
    final src = p['data_source'] as String?;
    final annual = (p['annual_vol_pct'] as num).toDouble();
    final applied = (p['applied_annual_vol_pct'] as num).toDouble();
    final shock = (r['market_shock_pct'] as num).toDouble();
    final period = r['crisis_period'] as String?;
    final histCount = (r['historical_count'] as num?)?.toInt() ?? 0;
    final totalH = (r['total_holdings'] as num?)?.toInt() ?? 0;
    final usdCount = (r['usd_holdings_count'] as num?)?.toInt() ?? 0;
    final usdtry = (r['usdtry_rate'] as num?)?.toDouble();

    final String methodNote;
    if (period != null) {
      methodNote = histCount == totalH
          ? 'Her hissenin $period dönemindeki yüzde getirisi hesaplanıp bugünkü pozisyonuna uygulandı. Sabit bir yüzde değil — her hisse o dönemde kendi yaptığını yapar.'
          : '$totalH hisseden $histCount\'i için $period dönemindeki yüzde hareketi kullanıldı. Kalanlar, kendi oynaklığının piyasaya oranına göre (~%${shock.abs().toStringAsFixed(0)} piyasa şoku) tahmin edildi.';
    } else {
      methodNote =
          'Bu senaryonun gerçek bir tarihsel karşılığı yok. Her hisse, kendi oynaklığının piyasaya oranına göre ~%${shock.abs().toStringAsFixed(0)}\'lık şoktan farklı etkilenir — oynak hisseler daha sert düşer.';
    }

    String dataNote;
    if (src == 'fallback') {
      dataNote =
          'Oynaklık ölçümü için hisselerinin fiyat geçmişine ulaşılamadı, tipik bir hisse oynaklığı varsayıldı.';
    } else if (src == 'partial') {
      dataNote =
          'Belirsizlik bandı için portföyünün bir kısmının son 1 yıllık oynaklığı ölçüldü.';
    } else {
      dataNote =
          'Belirsizlik bandı için her hissenin son 1 yıllık oynaklığı ölçüldü.';
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: c.warmAccent,
          collapsedIconColor: c.textMuted,
          title: Text('Bu nasıl hesaplandı?',
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1)),
          children: [
            _note(r['scenario_description'] as String),
            const SizedBox(height: 10),
            _note(methodNote),
            const SizedBox(height: 10),
            _note(dataNote),
            if (usdCount > 0 && usdtry != null) ...[
              const SizedBox(height: 10),
              _note(
                  'Portföyün farklı para birimleri içeriyor. Üstteki toplam, kötü senaryo ve grafik ortak birim ₺ üzerinden hesaplandı; ABD hisseleri 1\$ = ₺${formatMoney(usdtry)} kuruyla çevrildi. Aşağıdaki hisse satırları kendi para biriminde (₺ veya \$) gösterilir.'),
            ],
            const SizedBox(height: 10),
            _note(
                'Oynaklık, fiyatın ne kadar sert savrulduğudur. Portföyün sakin dönemde yılda ~%${annual.toStringAsFixed(1)} oynar; kriz dönemlerinde fiyatlar çok daha sert hareket ettiği için bu, senaryonun şiddetine göre ~%${applied.toStringAsFixed(0)}\'a genişletildi. Bu genişletilmiş oynaklıkla 10.000 olası gidişat simüle edilip (Monte Carlo) en kötü/en iyi %5 uçları belirsizlik bandı olarak alındı.'),
            const SizedBox(height: 10),
            _note(
                'Bu bir tahmindir, garanti değildir; geçmiş performans geleceği garanti etmez.'),
            const SizedBox(height: 10),
            Text(r['academic_reference'].toString(),
                style: TextStyle(
                    color: c.textSubtle,
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _note(String text) {
    final c = AppColorsExt.of(context);
    return Text(text,
        style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.55));
  }
}
