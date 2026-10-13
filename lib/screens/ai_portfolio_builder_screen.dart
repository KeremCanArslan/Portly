import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

class AiPortfolioBuilderScreen extends StatefulWidget {
  const AiPortfolioBuilderScreen({super.key});

  @override
  State<AiPortfolioBuilderScreen> createState() =>
      _AiPortfolioBuilderScreenState();
}

class _AiPortfolioBuilderScreenState extends State<AiPortfolioBuilderScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _amountController =
      TextEditingController(text: '100000');
  String _horizon = 'medium';
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  String? get _profile => context.read<AuthProvider>().riskProfile;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    final profile = _profile;
    if (profile == null) {
      setState(
          () => _error = 'Önce Portföy ekranından risk profili testini yap.');
      return;
    }
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '.').trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Geçerli bir tutar gir');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    final r = await _api.buildAiPortfolio(
      riskProfile: profile,
      horizon: _horizon,
      amount: amount,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r == null) {
        _error = 'Portföy üretilemedi. Daha sonra tekrar dene.';
      } else {
        _result = r;
      }
    });
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
        title: Text('AI Portföy Oluşturucu',
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileBanner(),
                  const SizedBox(height: 20),
                  IOSSectionHeader(label: 'Vade'),
                  const SizedBox(height: 4),
                  IOSSegmented<String>(
                    value: _horizon,
                    onChange: (v) => setState(() => _horizon = v),
                    options: const [
                      ('short', 'Kısa · 1 ay'),
                      ('medium', 'Orta · 6 ay'),
                      ('long', 'Uzun · 1 yıl'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  IOSSectionHeader(label: 'Yatırım Tutarı'),
                  const SizedBox(height: 4),
                  IOSGroupedCard(
                    children: [
                      IOSField(
                        controller: _amountController,
                        label: 'Tutar (₺)',
                        icon: Icons.payments_outlined,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  IOSPillButton(
                    label: 'Portföy Oluştur',
                    icon: Icons.auto_awesome,
                    isLoading: _loading,
                    onPressed: _loading ? null : _build,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.negative, fontSize: 13)),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 24),
                    _buildResultCard(_result!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileBanner() {
    final c = AppColorsExt.of(context);
    return Container(
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
                Text(
                  _profile == null
                      ? 'Risk profilin yok'
                      : 'Profilin: $_profile',
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2),
                ),
                const SizedBox(height: 3),
                Text(
                  'AI sana uygun bir portföy önerip vade sonu getirisi için backtest yapacak.',
                  style:
                      TextStyle(color: c.textMuted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    final allocations = (r['allocations'] as List?) ?? [];
    final expectedReturn = (r['expected_return_pct'] as num?)?.toDouble();
    final rationale = r['rationale'] as String? ?? '';
    final backtest = r['backtest'] as Map<String, dynamic>? ?? {};
    final actual = (backtest['actual_return_pct'] as num?)?.toDouble() ?? 0;
    final horizonDays = backtest['horizon_days'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Beklenen vs Gerçekleşen — büyük verdict banner
        IOSVerdictBanner(
          verdict: '${formatPctSigned(actual, decimals: 2)}%',
          sub: 'Gerçekleşen getiri · $horizonDays gün backtest',
          color: actual >= 0 ? c.positive : c.negative,
          icon: actual >= 0 ? Icons.trending_up : Icons.trending_down,
          stats: [
            (
              'Beklenen yıllık',
              expectedReturn != null
                  ? '%${expectedReturn.toStringAsFixed(2)}'
                  : '—'
            ),
            ('Vade', '$horizonDays gün'),
          ],
        ),
        if (rationale.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, color: c.warmAccent, size: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(rationale,
                      style: TextStyle(
                          color: c.textMuted, fontSize: 12.5, height: 1.55)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        IOSSectionHeader(label: 'Tahsisat'),
        const SizedBox(height: 6),
        ...allocations.map<Widget>((a) {
          final alloc = a as Map<String, dynamic>;
          final symbol = alloc['symbol'] as String;
          final weight = (alloc['weight'] as num).toDouble();
          final amountTry = (alloc['amount_try'] as num?)?.toDouble() ?? 0;
          final reason = alloc['reason'] as String? ?? '';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(SymbolDisplay.label(symbol),
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2)),
                          const SizedBox(height: 2),
                          Text(SymbolDisplay.secondaryLabel(symbol),
                              style: TextStyle(
                                  color: c.textSubtle,
                                  fontSize: 11,
                                  letterSpacing: -0.1)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('%${(weight * 100).toStringAsFixed(1)}',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            )),
                        const SizedBox(height: 2),
                        Text('₺${formatMoney(amountTry, decimals: 0)}',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12,
                            )),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(height: 5, color: c.surfaceAlt),
                      FractionallySizedBox(
                        widthFactor: weight.clamp(0.02, 1.0),
                        child: Container(height: 5, color: c.warmAccent),
                      ),
                    ],
                  ),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(reason,
                      style: TextStyle(
                          color: c.textMuted, fontSize: 11.5, height: 1.45)),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}
