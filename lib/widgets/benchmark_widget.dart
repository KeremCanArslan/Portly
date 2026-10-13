import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

/// Portföy getirisini BIST100 / S&P 500 / Dolar / Gram Altın / Mevduat /
/// Enflasyon ile karşılaştırır ("paranı bankada/altında tutsaydın").
class BenchmarkWidget extends StatefulWidget {
  const BenchmarkWidget({super.key});

  @override
  State<BenchmarkWidget> createState() => _BenchmarkWidgetState();
}

class _BenchmarkWidgetState extends State<BenchmarkWidget> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _error = false;
  String _period = '3m';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = context.read<PortfolioProvider>().userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final d = await _api.fetchBenchmark(userId, period: _period);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (_) {
      // Geçici hata/timeout: kartı sessizce gizleme; son iyi veri varsa
      // koru, yoksa "Tekrar Dene" göster.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  /// Sharpe açıklama sheet'i — hero (değer + durum rozeti) + yapısal bölümler
  /// (Ne ölçer + formül · Senin durumun · Yapılması gereken).
  void _showSharpeInfo(BuildContext context, double sharpe) {
    final c = AppColorsExt.of(context);
    final col =
        sharpe > 1 ? c.positive : (sharpe > 0 ? c.warmAccent : c.negative);
    final verdict = sharpe > 1
        ? 'İyi risk-getiri'
        : (sharpe > 0 ? 'Pozitif ama zayıf' : 'Riske değmemiş');
    final reading = sharpe > 1
        ? 'Aldığın risk getiriye değmiş — portföy, oynaklığına rağmen TL '
            'mevduatı belirgin biçimde geçmiş.'
        : sharpe > 0
            ? 'Pozitif ama zayıf — risksiz TL mevduatın ancak biraz '
                'üzerindesin; üstlendiğin dalgalanmaya göre kazanç düşük.'
            : 'Negatif — bu dönemde aldığın risk, parayı TL mevduatta '
                'tutmaya kıyasla değmemiş.';
    final action = sharpe > 1
        ? 'Bu dengeyi koru; aşırı riske girmeden mevcut çeşitlendirmeyi '
            'sürdür.'
        : sharpe > 0
            ? 'Getiriyi kovalamak yerine oynaklığı düşür: tek-varlık '
                'ağırlığını ve aynı yönde hareket eden benzer pozisyonları '
                'azalt.'
            : 'Riskin işe yaramadığı bu tabloda, getirisi mevduatı geçmeyen '
                'yüksek oynaklıklı pozisyonları gözden geçir; daha '
                'çeşitlendirilmiş/düşük oynaklıklı varlıklara ağırlık ver.';

    showIOSBottomSheet(
      context: context,
      title: 'Sharpe Oranı',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IOSSheetHero(
                value: sharpe.toStringAsFixed(2), color: col, verdict: verdict),
            const SizedBox(height: 24),
            IOSInfoBlock(
              icon: Icons.straighten,
              label: 'NE ÖLÇER',
              formula: 'Sharpe = (Getiri − Risksiz Faiz) ÷ Oynaklık',
              body: 'Aldığın risk başına ne kadar getiri ürettiğini gösterir. '
                  'Risksiz faiz = TL mevduat; oynaklık = günlük getirilerin '
                  'ne kadar dalgalandığı. Skor, portföyün birleşik '
                  'getirisinden hesaplanır — böylece varlıkların birbirini '
                  'dengelemesi (çeşitlendirme) de hesaba katılır.',
            ),
            const SizedBox(height: 20),
            IOSInfoBlock(
                icon: Icons.analytics_outlined,
                label: 'SENİN DURUMUN',
                body: reading),
            const SizedBox(height: 20),
            IOSInfoBlock(
                icon: Icons.arrow_forward_rounded,
                label: 'YAPILMASI GEREKEN',
                body: action,
                emphasize: true),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    if (_loading) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: CircularProgressIndicator(color: c.textPrimary),
        ),
      );
    }
    if (_data == null) {
      if (!_error) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 17, color: c.textSubtle),
            const SizedBox(width: 9),
            Expanded(
              child: Text('Karşılaştırma yüklenemedi',
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
        ),
      );
    }

    final portfolio = _data!['portfolio'] as Map<String, dynamic>;
    final benchmarks = _data!['benchmarks'] as Map<String, dynamic>;
    final portfolioReturnRaw = (portfolio['return_pct'] as num?)?.toDouble();
    final portfolioReturn = portfolioReturnRaw ?? 0;
    final portfolioSharpe = (portfolio['sharpe'] as num?)?.toDouble();
    final hasHoldings = portfolio['has_holdings'] as bool;
    // Getiri sayı değilse (null) ya da hiçbir pozisyonun dönem verisi
    // yoksa (yfinance fiyat serisi gelmedi) yanıltıcı "+0,00%" basma →
    // dürüstçe "hesaplanamadı" göster (0% gerçek getiri sanılmasın).
    final includedCount = (portfolio['symbols_included'] as num?)?.toInt();
    final returnUnavailable = portfolioReturnRaw == null ||
        (includedCount != null && includedCount == 0);

    // En büyük absolute return'e göre normalize bar widths
    double maxAbs = portfolioReturn.abs();
    benchmarks.forEach((_, v) {
      final r = (v['return_pct'] as num?)?.toDouble();
      if (r != null && r.abs() > maxAbs) maxAbs = r.abs();
    });
    if (maxAbs < 1) maxAbs = 1;

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
              Icon(Icons.compare_arrows, color: c.textMuted, size: 17),
              const SizedBox(width: 7),
              Text('Portföy vs. Endeksler',
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2)),
              const Spacer(),
              _periodChip('1m', '1A'),
              _periodChip('3m', '3A'),
              _periodChip('6m', '6A'),
              _periodChip('1y', '1Y'),
            ],
          ),
          const SizedBox(height: 16),
          if (hasHoldings && returnUnavailable)
            _portfolioUnavailable(context)
          else if (hasHoldings) ...[
            _bar('Portföyün', portfolioReturn, maxAbs, isPortfolio: true),
            if (portfolioSharpe != null)
              Padding(
                padding: const EdgeInsets.only(left: 74, top: 6, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showSharpeInfo(context, portfolioSharpe),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: c.warmAccentSoft,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                                'Sharpe ${portfolioSharpe.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: c.warmAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                          const SizedBox(width: 7),
                          Text(
                              portfolioSharpe > 1
                                  ? 'İyi risk-getiri'
                                  : portfolioSharpe > 0
                                      ? 'Pozitif ama düşük'
                                      : 'Negatif',
                              style:
                                  TextStyle(color: c.textSubtle, fontSize: 10)),
                          const SizedBox(width: 5),
                          Icon(Icons.info_outline,
                              size: 13, color: c.textSubtle),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      portfolioSharpe > 1
                          ? 'Aldığınız riske değiyor: getiri, üstlenilen '
                              'dalgalanmayı risksiz faizin belirgin üzerinde '
                              'karşılıyor.'
                          : portfolioSharpe > 0
                              ? 'Getiri pozitif ama üstlendiğiniz riske göre '
                                  'zayıf; oynaklık başına kazanç düşük kalıyor.'
                              : 'Negatif skor, aldığınız riskin risksiz '
                                  'getiriye kıyasla değmediğini gösterir.',
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 10.5,
                        height: 1.45,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Portföyünde varlık yok',
                  style: TextStyle(color: c.textMuted, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          for (final e in const [
            ['BIST100', 'BIST 100'],
            ['SP500', 'S&P 500'],
            ['USDTRY', 'Dolar'],
            ['GRAM_ALTIN', 'Gram Altın'],
            ['MEVDUAT', 'Mevduat'],
            ['ENFLASYON', 'Enflasyon'],
          ])
            // `?? 0` YOKKEN: piyasa verisi gelmeyen endeks "+0,00%" olarak
            // basılıyordu — "bu dönem hiç hareket etmemiş" gibi okunuyor.
            // Veri yoksa bar çizilmez, yüzde yerine "—" gösterilir.
            _bar(
                e[1],
                ((benchmarks[e[0]] as Map<String, dynamic>?)?['return_pct']
                        as num?)
                    ?.toDouble(),
                maxAbs),
          const SizedBox(height: 8),
          Text(
            'Mevduat ve enflasyon yaklaşık yıllık orandır; "paranı bankada/altında/dolarda tutsaydın" kıyası. '
            'Pozisyonların dönem boyunca sabit kaldığı varsayılır.',
            style: TextStyle(color: c.textSubtle, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    final c = AppColorsExt.of(context);
    final selected = _period == value;
    return GestureDetector(
      onTap: () {
        setState(() => _period = value);
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.warmAccentSoft : c.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? c.warmAccent : c.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  // Getiri hesaplanamadığında (piyasa verisi gelmedi) bar yerine dürüst not.
  // "+0,00%" basıp gerçek getiri sanılmasını önler.
  Widget _portfolioUnavailable(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text('Portföyün',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1)),
          ),
          Expanded(
            child: Text(
              'Getiri şu an hesaplanamadı — piyasa verisi alınamadı, '
              'birazdan tekrar dene.',
              style: TextStyle(
                  color: c.textSubtle, fontSize: 12, letterSpacing: -0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(String name, double? value, double maxAbs,
      {bool isPortfolio = false}) {
    final c = AppColorsExt.of(context);
    // value null → piyasa verisi yok. Sıfırmış gibi göstermek yanlış bilgi.
    final missing = value == null || !value.isFinite;
    final v = missing ? 0.0 : value;
    final isPos = v >= 0;
    final dataColor = missing ? c.textSubtle : (isPos ? c.positive : c.negative);
    // NaN/inf koruması: maxAbs sıfırsa veya value NaN ise 0 bar göster.
    double fraction = 0;
    if (!missing && maxAbs > 0) {
      fraction = (v.abs() / maxAbs).clamp(0.0, 1.0);
      if (!fraction.isFinite) fraction = 0;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(name,
                style: TextStyle(
                    color: isPortfolio ? c.textPrimary : c.textMuted,
                    fontSize: 12,
                    fontWeight: isPortfolio ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.1)),
          ),
          Expanded(
            child: SizedBox(
              height: 14,
              child: Align(
                alignment: isPos ? Alignment.centerLeft : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: missing ? 0.0 : (fraction == 0 ? 0.01 : fraction),
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: dataColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 58,
            child: Text(
              missing ? '—' : '${formatPctSigned(v, decimals: 2)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: dataColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
