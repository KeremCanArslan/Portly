import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/widgets/price_chart.dart';
import 'package:portly/widgets/horizontal_wheel_scroll.dart';

/// Tam ekran TradingView-tarzı pro grafik — çizim/ölçüm/replay/fib
/// rahat kullanılsın diye geniş tuval, sayfa kaydırma çakışması yok.
class ProChartScreen extends StatefulWidget {
  final String symbol;
  final String name;
  final String currency;
  final List<PriceLine> priceLines;

  const ProChartScreen({
    super.key,
    required this.symbol,
    required this.name,
    required this.currency,
    this.priceLines = const [],
  });

  @override
  State<ProChartScreen> createState() => _ProChartScreenState();
}

class _ProChartScreenState extends State<ProChartScreen> {
  final ApiService _api = ApiService();

  // stock_detail ile aynı TradingView-tarzı zaman dilimleri.
  static const List<(String, String, String)> _timeframes = [
    ('1d', '1m', '1dk'),
    ('5d', '5m', '5dk'),
    ('1mo', '15m', '15dk'),
    ('1mo', '30m', '30dk'),
    ('3mo', '1h', '1sa'),
    ('6mo', '2h', '2sa'),
    ('1y', '4h', '4sa'),
    ('5y', '1d', 'Günlük'), // ~1250 mum (backtest/replay için daha derin)
    ('max', '1wk', 'Haftalık'),
    ('max', '1mo', 'Aylık'),
  ];
  int _tfIndex = 7; // Günlük (kayıtlı tercih yüklenene kadar)
  bool _loading = true;
  List<Map<String, dynamic>> _data = const [];
  // Canlı yenileme (kullanıcı "veriler canlı yenilenmiyor" dedi). SESSİZ:
  // spinner göstermez, yalnız veriyi tazeler → çizim/zoom/indikatör korunur.
  Timer? _refreshTimer;
  bool _refreshing = false;
  // Zaman dilimi seçimi oturumlar arası KALICI (kullanıcı "elle ayarladığımı
  // her oturumda görmeliyim" dedi). stock_detail ile aynı anahtar → tutarlı.
  static const String _tfPrefsKey = 'chart_tf_index_v1';

  @override
  void initState() {
    super.initState();
    _restoreTimeframeThenLoad();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  Future<void> _restoreTimeframeThenLoad() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getInt(_tfPrefsKey);
      if (saved != null && saved >= 0 && saved < _timeframes.length) {
        _tfIndex = saved;
      }
    } catch (_) {/* kayıt okunamadı — varsayılan timeframe */}
    if (mounted) _load();
  }

  void _persistTimeframe() {
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_tfPrefsKey, _tfIndex))
        .catchError((_) => false);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (silent && _refreshing) return; // üst üste binmesin
    if (silent) {
      _refreshing = true;
    } else {
      setState(() => _loading = true);
    }
    final tf = _timeframes[_tfIndex];
    try {
      final result =
          await _api.fetchStockHistory(widget.symbol, tf.$1, interval: tf.$2);
      if (!mounted) return;
      final fresh = result['data'] != null
          ? (result['data'] as List).cast<Map<String, dynamic>>()
          : const <Map<String, dynamic>>[];
      // Sessiz yenilemede boş sonuç gelirse mevcut veriyi KORU (boş grafik yok).
      if (silent && fresh.isEmpty) return;
      setState(() {
        _data = fresh;
        _loading = false;
      });
    } finally {
      if (silent) _refreshing = false;
    }
  }

  Future<void> _createAlert(double price) async {
    final last = _data.isNotEmpty
        ? (_data.last['close'] as num?)?.toDouble() ?? price
        : price;
    final dir = price >= last ? 'ABOVE' : 'BELOW';
    final res = await _api.createPriceAlert(
      symbol: widget.symbol,
      thresholdPrice: double.parse(price.toStringAsFixed(2)),
      direction: dir,
    );
    if (!mounted) return;
    final ok = res != null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Alarm kuruldu: ${widget.currency}${price.toStringAsFixed(2)} ($dir)'
            : 'Alarm kurulamadı'),
      ),
    );
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
        // Daha sıkı başlık → grafiğe daha çok dikey alan (tester "ekran kısıtlı" dedi).
        toolbarHeight: 48,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(SymbolDisplay.compact(widget.symbol),
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3)),
            Text(widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textMuted, fontSize: 11)),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 34,
              child: HorizontalWheelScroll(
                builder: (ctrl) => ListView.separated(
                  controller: ctrl,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _timeframes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final sel = _tfIndex == i;
                    return GestureDetector(
                      onTap: () {
                        if (_tfIndex == i) return;
                        setState(() => _tfIndex = i);
                        _persistTimeframe();
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? c.warmAccentSoft : c.surface,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: Text(_timeframes[i].$3,
                            style: TextStyle(
                                color: sel ? c.warmAccent : c.textMuted,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                letterSpacing: -0.1)),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                // Veri YOKKEN spinner/hata; veri varken chart HER ZAMAN mounted
                // kalır. Zaman dilimi değişince chart'ı spinner'la DEĞİŞTİRMİYORUZ
                // (eskiden State'i yok edip backtest/replay'i kapatıyordu —
                // tester şikâyeti). Çizim/zoom/replay State'i korunur; yükleniyor
                // geri bildirimi üstteki ince çizgi ile verilir.
                child: _data.isEmpty
                    ? (_loading
                        ? Center(
                            child:
                                CircularProgressIndicator(color: c.textPrimary))
                        : Center(
                            child: Text('Grafik verisi alınamadı',
                                style: TextStyle(
                                    color: c.textMuted, fontSize: 13)),
                          ))
                    : LayoutBuilder(
                        builder: (_, cns) => Stack(
                          children: [
                            SingleChildScrollView(
                              // Dikey sürüklemeyi YUTMA → grafiğin sağ fiyat
                              // ekseninde yukarı/aşağı sürükleyerek dikey zoom
                              // çalışsın. İçerik clamp'li yükseklikle sığar.
                              physics: const NeverScrollableScrollPhysics(),
                              child: PriceChart(
                                data: _data,
                                currency: widget.currency,
                                priceLines: widget.priceLines,
                                onCreateAlert: _createAlert,
                                pro: true,
                                symbolLabel: SymbolDisplay.compact(widget.symbol),
                                timeframeLabel: _timeframes[_tfIndex].$3,
                                symbol: widget.symbol, // çizimleri hesaba kaydet
                                // Tuvalin büyük kısmını grafiğe ver
                                height:
                                    (cns.maxHeight - 96).clamp(280.0, 1400.0),
                              ),
                            ),
                            if (_loading)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: LinearProgressIndicator(
                                  minHeight: 2,
                                  backgroundColor: Colors.transparent,
                                  color: c.warmAccent,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
