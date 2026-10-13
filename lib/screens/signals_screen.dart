import 'package:flutter/material.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/utils/symbol_display.dart';

/// Alım-satım sinyalleri sekmesi.
///
/// Portföy + izleme listesindeki sembollerin kural tabanlı AL/TUT/SAT
/// taramasını gösterir (backend signal_service; teknik göstergeler + temel
/// oranlar, LLM yok). Uygulamanın eski "İşlem" sekmesinin yerini aldı:
/// sanal alım-satım kaldırıldı, uygulama gerçek portföyü izleyip sinyal
/// üreten bir asistana dönüştü.
class SignalsScreen extends StatefulWidget {
  const SignalsScreen({super.key});

  @override
  State<SignalsScreen> createState() => _SignalsScreenState();
}

class _SignalsScreenState extends State<SignalsScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _signals = [];
  List<dynamic> _failed = [];
  String? _disclaimer;
  bool _loading = true;
  bool _error = false;
  String _filter = 'TÜMÜ'; // TÜMÜ | AL | TUT | SAT
  final Set<String> _expanded = {}; // gerekçeleri açık kartlar (sembol)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = _signals.isEmpty; // yenilemede liste kaybolmasın (SWR hissi)
      _error = false;
    });
    final data = await _api.getSignals(force: force);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data == null) {
        _error = _signals.isEmpty;
      } else {
        _signals = (data['signals'] as List?) ?? [];
        _failed = (data['failed'] as List?) ?? [];
        _disclaimer = data['disclaimer'] as String?;
      }
    });
  }

  List<dynamic> get _visible => _filter == 'TÜMÜ'
      ? _signals
      : _signals.where((s) => s['signal'] == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading
                ? Center(child: CircularProgressIndicator(color: c.textPrimary))
                : _error
                    ? _errorState()
                    : _signals.isEmpty
                        ? _emptyState()
                        : _list(),
          ),
        ),
      ),
    );
  }

  Widget _list() {
    final c = AppColorsExt.of(context);
    final items = _visible;
    return RefreshIndicator(
      color: c.textPrimary,
      backgroundColor: c.surface,
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _header(),
          const SizedBox(height: 12),
          _filterRow(),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'Bu filtrede sinyal yok',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
            )
          else
            ...items.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _signalCard(s as Map<String, dynamic>),
                )),
          if (_failed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Veri alınamayan semboller: '
              '${_failed.map((s) => SymbolDisplay.compact(s as String)).join(', ')}',
              style: TextStyle(color: c.textSubtle, fontSize: 11),
            ),
          ],
          if (_disclaimer != null) ...[
            const SizedBox(height: 16),
            Text(
              _disclaimer!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textSubtle, fontSize: 11, letterSpacing: -0.1),
            ),
          ],
          const SizedBox(height: 80), // FAB payı
        ],
      ),
    );
  }

  Widget _header() {
    final c = AppColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sinyaller',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4)),
        const SizedBox(height: 3),
        Text(
          'Portföyün ve izleme listen için teknik + temel analize dayalı '
          'alım-satım sinyalleri',
          style: TextStyle(color: c.textMuted, fontSize: 12.5, height: 1.35),
        ),
      ],
    );
  }

  Widget _filterRow() {
    return Row(
      children: [
        for (final f in const ['TÜMÜ', 'AL', 'TUT', 'SAT']) ...[
          Expanded(child: _filterPill(f)),
          if (f != 'SAT') const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _filterPill(String value) {
    final c = AppColorsExt.of(context);
    final selected = _filter == value;
    final count = value == 'TÜMÜ'
        ? _signals.length
        : _signals.where((s) => s['signal'] == value).length;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.textPrimary : c.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          '$value · $count',
          style: TextStyle(
            color: selected ? c.bg : c.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  Color _signalColor(String signal) {
    final c = AppColorsExt.of(context);
    switch (signal) {
      case 'AL':
        return c.positive;
      case 'SAT':
        return c.negative;
      default:
        return c.textSubtle;
    }
  }

  Widget _signalCard(Map<String, dynamic> s) {
    final c = AppColorsExt.of(context);
    final symbol = s['symbol'] as String? ?? '';
    final signal = s['signal'] as String? ?? 'TUT';
    final score = (s['score'] as num?)?.toInt();
    final techScore = (s['technical_score'] as num?)?.toInt();
    final fundScore = (s['fundamental_score'] as num?)?.toInt();
    final price = (s['current_price'] as num?)?.toDouble();
    final reasons = (s['reasons'] as List?)?.cast<String>() ?? const <String>[];
    final source = s['source'] as String?;
    final expanded = _expanded.contains(symbol);
    final shown = expanded ? reasons : reasons.take(2).toList();
    final color = _signalColor(signal);
    final currency = SymbolDisplay.currencyOf(symbol);

    final sourceLabel = source == 'both'
        ? 'Portföy + İzleme'
        : source == 'portfolio'
            ? 'Portföy'
            : source == 'watchlist'
                ? 'İzleme'
                : null;

    // Skor bileşen satırı: temel oran yoksa dürüstçe "teknik" de.
    final scoreDetail = fundScore != null
        ? 'Teknik $techScore · Temel $fundScore'
        : 'Teknik $techScore · Temel veri yok';

    return GestureDetector(
      onTap: reasons.length > 2
          ? () => setState(() =>
              expanded ? _expanded.remove(symbol) : _expanded.add(symbol))
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Sinyal rozeti — renk = veri (AL yeşil / SAT kırmızı / TUT sönük)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: signal == 'TUT' ? c.surfaceAlt : color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    signal,
                    style: TextStyle(
                      color: signal == 'TUT' ? c.textMuted : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        SymbolDisplay.label(symbol),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (sourceLabel != null) ...[
                        const SizedBox(height: 1),
                        Text(sourceLabel,
                            style:
                                TextStyle(color: c.textSubtle, fontSize: 10.5)),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (price != null)
                      Text(
                        // Fon birim pay değeri (₺1,0962) 2 basamağa
                        // yuvarlanınca portföydeki doğru gösterimle
                        // çelişiyordu (orada ₺1,0962, burada ₺1,10).
                        '$currency${formatMoney(price, decimals: SymbolDisplay.priceDecimals(symbol, price))}',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 1),
                    Text(
                      score != null ? 'Skor $score' : '',
                      style: TextStyle(color: c.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...shown.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: c.textSubtle,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                                color: c.textMuted,
                                fontSize: 12,
                                height: 1.35,
                                letterSpacing: -0.1),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 2),
              Text(
                scoreDetail +
                    (reasons.length > 2
                        ? (expanded ? '  ·  daralt' : '  ·  tümü')
                        : ''),
                style: TextStyle(color: c.textSubtle, fontSize: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final c = AppColorsExt.of(context);
    // "Sembol yok" ile "semboller var ama fiyat verisi gelmedi" AYNI ekranı
    // gösteriyordu: portföyü dolu kullanıcıya "portföyüne pozisyon ekle"
    // deniyordu. `failed` doluysa sorun veri kaynağında, kullanıcıda değil.
    final dataFailed = _failed.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(dataFailed ? Icons.cloud_off_rounded : Icons.radar_rounded,
                size: 38, color: c.textSubtle),
            const SizedBox(height: 14),
            Text(dataFailed ? 'Sinyal üretilemedi' : 'Henüz sinyal yok',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2)),
            const SizedBox(height: 4),
            Text(
              dataFailed
                  ? '${_failed.length} sembolün piyasa verisi şu an '
                      'alınamadı.\nBirazdan tekrar dene.'
                  : 'Portföyüne pozisyon ya da izleme listene sembol ekle;\n'
                      'senin için teknik + temel analize dayalı sinyal üretelim.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textMuted, fontSize: 13, letterSpacing: -0.1),
            ),
            if (dataFailed) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _load(force: true),
                style: TextButton.styleFrom(foregroundColor: c.textPrimary),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    final c = AppColorsExt.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 38, color: c.textSubtle),
            const SizedBox(height: 14),
            Text('Sinyaller alınamadı',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Bağlantını kontrol edip tekrar dene.',
                style: TextStyle(color: c.textMuted, fontSize: 13)),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => _load(force: true),
              child: Text('Tekrar Dene',
                  style: TextStyle(
                      color: c.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
