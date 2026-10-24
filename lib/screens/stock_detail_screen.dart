import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/utils/snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/widgets/market_state_dot.dart';
import 'package:portly/widgets/price_chart.dart';
import 'package:portly/widgets/horizontal_wheel_scroll.dart';
import 'package:portly/widgets/manual_position_sheet.dart';
import 'package:portly/widgets/ai_sheet.dart';
import 'package:portly/screens/pro_chart_screen.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/utils/haptics.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/providers/notes_provider.dart';
import 'package:portly/models/note.dart';
import 'package:portly/widgets/note_editor.dart';

class StockDetailScreen extends StatefulWidget {
  final StockModel stockData;

  const StockDetailScreen({super.key, required this.stockData});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _priceData = [];
  bool _isLoadingHistory = true;
  // Canlı tek-sembol quote — pre/post-market (extended) alanlarını taşır (yalnız
  // ABD hissesi + pre/post seansında dolu). Başlıktaki uzatılmış-seans chip'ini besler.
  StockModel? _liveQuote;
  // TradingView-tarzı zaman dilimleri: (period, interval, etiket).
  // yfinance limitleri gözetildi (15m≤60g, 1h≤730g).
  static const List<(String, String, String)> _timeframes = [
    ('1d', '1m', '1dk'),
    ('5d', '5m', '5dk'),
    ('1mo', '15m', '15dk'),
    ('1mo', '30m', '30dk'),
    ('3mo', '1h', '1sa'),
    ('6mo', '2h', '2sa'),
    ('1y', '4h', '4sa'),
    ('2y', '1d', 'Günlük'),
    ('5y', '1wk', 'Haftalık'),
    ('max', '1mo', 'Aylık'),
  ];
  int _tfIndex = 7; // Günlük
  String _currency = '₺';

  List<dynamic> _relatedNews = [];
  // Hisseye özel alakalı haber yoksa _relatedNews'e fallback olarak genel
  // piyasa haberleri dolduruluyor; başlık o zaman "Piyasa Haberleri" yazılsın
  // (kullanıcıyı "bu THYAO ile ilgili" diye yanıltmasın).
  bool _newsIsFallback = false;

  // Grafik verisini canlı tazele (kullanıcı "veriler canlı yenilenmiyor" dedi).
  Timer? _chartRefreshTimer;
  bool _chartRefreshing = false;
  // Zaman dilimi tercihi oturumlar arası kalıcı (pro_chart ile aynı anahtar).
  static const String _tfPrefsKey = 'chart_tf_index_v1';

  @override
  void initState() {
    super.initState();
    _currency = widget.stockData.currency;
    _restoreTimeframeThenLoad();
    _loadRelatedNews();
    _loadQuote();
    _chartRefreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadHistory(silent: true));
  }

  Future<void> _restoreTimeframeThenLoad() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getInt(_tfPrefsKey);
      if (saved != null && saved >= 0 && saved < _timeframes.length) {
        _tfIndex = saved;
      }
    } catch (_) {/* kayıt okunamadı — varsayılan timeframe */}
    if (mounted) _loadHistory();
  }

  void _persistTimeframe() {
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_tfPrefsKey, _tfIndex))
        .catchError((_) => false);
  }

  @override
  void dispose() {
    _chartRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory({bool silent = false}) async {
    if (silent && _chartRefreshing) return;
    if (silent) {
      _chartRefreshing = true;
    } else {
      setState(() => _isLoadingHistory = true);
    }
    final symbol = widget.stockData.symbol;
    final tf = _timeframes[_tfIndex];
    try {
      final result =
          await _apiService.fetchStockHistory(symbol, tf.$1, interval: tf.$2);
      if (!mounted) return;
      final fresh = result['data'] != null
          ? (result['data'] as List).cast<Map<String, dynamic>>()
          : const <Map<String, dynamic>>[];
      // Sessiz yenilemede boş gelirse mevcut veriyi koru.
      if (silent && fresh.isEmpty) return;
      setState(() {
        if (fresh.isNotEmpty) _priceData = fresh;
        _isLoadingHistory = false;
      });
    } finally {
      if (silent) _chartRefreshing = false;
    }
  }

  Future<void> _loadRelatedNews() async {
    final target = widget.stockData.symbol.toUpperCase();
    final shortCode = target.replaceAll('.IS', '').replaceAll('-USD', '');
    final query = SymbolDisplay.newsQuery(target);
    List<dynamic> targetedNews;
    try {
      targetedNews = await _apiService.fetchNews(query: query);
    } catch (e) {
      // Detay ekranında haber ikincil: çekilemezse bölüm boş kalır.
      debugPrint('İlgili haber alınamadı ($target): $e');
      targetedNews = const [];
    }

    bool isRelated(dynamic news) {
      final assets = (news['affected_assets'] as List?) ?? const [];
      for (final a in assets) {
        final s = ((a as Map)['symbol'] as String? ?? '').toUpperCase();
        if (s == target) return true;
      }
      final blob =
          ('${news['title'] ?? ''} ${news['description'] ?? ''}').toUpperCase();
      if (shortCode.length >= 3 && blob.contains(shortCode)) return true;
      return false;
    }

    // Önce gerçekten alakalı haberleri bul; varsa "İlgili Haberler" başlığıyla
    // göster. Yoksa boş bölüm bırakmak yerine genel piyasa haberlerinden ilk 5'i
    // "Piyasa Haberleri" başlığıyla göster (THYAO gibi büyük bir hissede demo'da
    // "haber yok" görmek kötü UX; "İlgili" diye yanıltmadan göstermek doğru).
    final hits = targetedNews.where(isRelated).toList();
    if (hits.isNotEmpty) {
      _relatedNews = hits;
      _newsIsFallback = false;
    } else {
      _relatedNews = targetedNews.take(5).toList();
      _newsIsFallback = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadQuote() async {
    // Tek-sembol /price → pre/post-market (extended) alanlarını getirir; yalnız
    // ABD hissesinde + pre/post seansında dolu döner. Başlıktaki chip'i besler.
    final q = await _apiService.fetchSingleStock(widget.stockData.symbol);
    if (mounted && q != null) setState(() => _liveQuote = q);
  }

  /// Pre/post-market seansında başlığın altına "Piyasa Öncesi/Sonrası" satırı.
  /// Diğer sembol/saatlerde hiçbir şey çizmez (normal seans fiyatı yeterli).
  Widget _buildExtendedRow() {
    final q = _liveQuote;
    if (q == null || q.extendedPrice == null) return const SizedBox.shrink();
    if (q.marketState != 'PRE' && q.marketState != 'POST') {
      return const SizedBox.shrink();
    }
    final c = AppColorsExt.of(context);
    final label = q.marketState == 'PRE' ? 'Piyasa Öncesi' : 'Piyasa Sonrası';
    final chg = q.extendedChangePct ?? 0.0;
    final up = chg >= 0;
    final col = up ? c.positive : c.negative;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 13, color: col),
          const SizedBox(width: 4),
          Text(
            '$label  $_currency${q.extendedPrice!.toStringAsFixed(2)}',
            style: TextStyle(
                color: c.textMuted, fontSize: 13, letterSpacing: -0.1),
          ),
          const SizedBox(width: 6),
          Text(
            '${formatPctSigned(chg, decimals: 2)}%',
            style: TextStyle(
                color: col, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  List<NewsMarker> _buildNewsMarkers() {
    if (_relatedNews.isEmpty || _priceData.isEmpty) return const [];
    final step = _priceData.length / _relatedNews.length;
    return List.generate(_relatedNews.length, (i) {
      final idx = (i * step).toInt().clamp(0, _priceData.length - 1);
      final score =
          (_relatedNews[i]['sentiment_score'] as num?)?.toDouble() ?? 0.0;
      return NewsMarker(idx, score);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final symbol = widget.stockData.symbol;
    // Şifreli Yahoo sembolleri (GC=F→"Gold Jun 26", USDTRY=X) için yfinance
    // adı kullanıcıya anlamsız → varlık sınıfını göster ("Emtia"/"Döviz").
    // Normal hisse adı (Apple Inc.) anlaşılır, dokunma.
    final name = (symbol.contains('=') || symbol.startsWith('^'))
        ? SymbolDisplay.secondaryLabel(symbol)
        : widget.stockData.name;
    final price = widget.stockData.rawPrice;
    final change = widget.stockData.change;
    final isUp = widget.stockData.isUp;
    // Günlük değişim bilinmiyorsa (altın/gümüş spot) rozet nötr — uydurma
    // yeşil "+%0,00" yok.
    final dataColor = !widget.stockData.changeAvailable
        ? c.textMuted
        : (isUp ? c.positive : c.negative);

    final provider = context.watch<PortfolioProvider>();
    final held = provider.heldQuantity(symbol);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        // Opak: şeffafsa açık temada üstteki içerik bara sızıp "hayalet"
        // yarım-kesik tekrar bırakıyor (15. tur bug #2 ile aynı gotcha).
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: c.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          SymbolDisplay.compact(symbol),
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: 14,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Piyasa açık/kapalı — canlı fiyatın "şu an mı" sorusu.
                      MarketStateDot(
                          state: _liveQuote?.marketState ??
                              widget.stockData.marketState),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MoneyText(
                        price,
                        currency: _currency,
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.2,
                        color: c.textPrimary,
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: dataColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            change,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildExtendedRow(),
                  if (held > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        SymbolDisplay.isPhysical(symbol)
                            ? 'Portföyünde ${held.toStringAsFixed(held == held.roundToDouble() ? 0 : 2)} '
                                '${SymbolDisplay.physicalUnit(symbol)}'
                            : 'Portföyünde ${held.toStringAsFixed(0)} lot',
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 13,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  // Fiziki altının ZAMAN SERİSİ yok → aralık seçici de,
                  // tam ekran grafik de gösterilmez (boş grafiğe götüren
                  // düğmeler kullanıcıyı yanıltıyordu).
                  if (!SymbolDisplay.isPhysical(symbol)) ...[
                    Row(
                      children: [
                        Expanded(child: _buildPeriodSelector()),
                        const SizedBox(width: 8),
                        _FullscreenBtn(onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ProChartScreen(
                              symbol: widget.stockData.symbol,
                              name: widget.stockData.name,
                              currency: _currency,
                            ),
                          ));
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildChart(),
                  const SizedBox(height: 22),
                  const EliteSectionLabel('Portföyüm'),
                  EliteSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _eliteNavRow(
                          c,
                          icon: Icons.playlist_add_rounded,
                          title: 'Pozisyon Ekle',
                          subtitle: SymbolDisplay.isPhysical(symbol)
                              ? 'Elindeki miktarı maliyetiyle portföyüne kaydet'
                              : 'Sahip olduğun lotu maliyetiyle portföyüne kaydet',
                          onTap: () => showManualPositionSheet(context,
                              preset: widget.stockData),
                        ),
                        if (held > 0) ...[
                          const EliteHairline(indent: 52),
                          _eliteNavRow(
                            c,
                            icon: Icons.remove_circle_outline,
                            title: 'Satış Kaydet',
                            subtitle:
                                'Sattığın lotu defterden düş (${held.toStringAsFixed(0)} lot var)',
                            onTap: () =>
                                _showSellRecordSheet(context, symbol, held),
                          ),
                        ],
                        const EliteHairline(indent: 52),
                        _eliteNavRow(
                          c,
                          icon: provider.watchlistSymbols
                                  .contains(symbol.toUpperCase())
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          title: provider.watchlistSymbols
                                  .contains(symbol.toUpperCase())
                              ? 'İzlemeden Çıkar'
                              : 'İzlemeye Al',
                          // Başlık duruma göre değişiyordu ama alt yazı sabitti:
                          // "İzlemeden Çıkar" satırının altında "…dahil et"
                          // yazıyordu (tarayıcıda görüldü, 3 Eyl).
                          subtitle: provider.watchlistSymbols
                                  .contains(symbol.toUpperCase())
                              ? 'Haber + sinyal taramasından çıkar'
                              : 'Haber + sinyal taramasına dahil et',
                          onTap: () async {
                            final inList = provider.watchlistSymbols
                                .contains(symbol.toUpperCase());
                            if (inList) {
                              await provider
                                  .removeFromWatchlist(symbol.toUpperCase());
                            } else {
                              await provider
                                  .addToWatchlist(symbol.toUpperCase());
                            }
                            if (!context.mounted) return;
                            showAppSnackBar(
                              context,
                              inList
                                  ? '${SymbolDisplay.compact(symbol)} izleme listesinden çıkarıldı'
                                  : '${SymbolDisplay.compact(symbol)} izleme listesine eklendi',
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Fiziki altında ne mum (SMA/RSI/MACD) ne bilanço (F/K,
                  // ROE) var — backend bu sınıfı zaten "physical" sayıp sinyal
                  // üretmiyor; ekran da aynı şeyi söylemeli, yoksa kullanıcı
                  // üretilemeyecek bir analizi bekliyor.
                  if (!SymbolDisplay.isPhysical(symbol)) ...[
                  const SizedBox(height: EliteSpace.xl),
                  const EliteSectionLabel('AI Analiz'),
                  EliteSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _eliteNavRow(
                          c,
                          icon: Icons.insights_outlined,
                          title: 'AI Teknik Tahmin',
                          subtitle: 'SMA, RSI, MACD — yön + hedef + stop',
                          onTap: () => _showPredictionSheet(context, symbol),
                        ),
                        const EliteHairline(indent: 52),
                        _eliteNavRow(
                          c,
                          icon: Icons.account_balance_outlined,
                          title: 'AI Temel Analiz',
                          subtitle: (symbol.endsWith('-USD') ||
                                  symbol.endsWith('=X') ||
                                  symbol.endsWith('=F'))
                              ? 'Varlık sınıfına uygun analiz + tavsiye'
                              : 'F/K, ROE, büyüme — değerleme + tavsiye',
                          onTap: () => _showFundamentalSheet(context, symbol),
                        ),
                      ],
                    ),
                  ),
                  ],
                  _buildNotesSection(symbol),
                  if (_relatedNews.isNotEmpty) ...[
                    const SizedBox(height: EliteSpace.xl),
                    EliteSectionLabel(_newsIsFallback
                        ? 'Piyasa Haberleri · ${_relatedNews.length}'
                        : 'İlgili Haberler · ${_relatedNews.length}'),
                    EliteSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (int i = 0; i < _relatedNews.length; i++) ...[
                            _buildNewsRow(_relatedNews[i]),
                            if (i != _relatedNews.length - 1)
                              const EliteHairline(indent: 16),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Notlarım (yatırımcı günlüğü, bu hisseye bağlı) ──
  // Yatırımcı Günlüğü ekranıyla aynı NotesProvider + showNoteEditor (tek kaynak);
  // burada symbol sabit (lockedSymbol) → eklenen not bu hisseye bağlanır.
  Widget _buildNotesSection(String symbol) {
    final c = AppColorsExt.of(context);
    final notes = context.watch<NotesProvider>().notesFor(symbol);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: EliteSpace.xl),
        EliteSectionLabel(
            notes.isEmpty ? 'Notlarım' : 'Notlarım · ${notes.length}'),
        EliteSurface(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < notes.length; i++) ...[
                _noteRow(notes[i]),
                const EliteHairline(indent: 16),
              ],
              _eliteNavRow(
                c,
                icon: Icons.add,
                title: 'Not Ekle',
                subtitle: notes.isEmpty
                    ? 'Bu hisse için ilk gözlemini yaz'
                    : 'Yeni gözlem ekle',
                onTap: () => showNoteEditor(context, lockedSymbol: symbol),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _noteRow(Note note) {
    final c = AppColorsExt.of(context);
    return InkWell(
      onTap: () => showNoteEditor(context, existing: note),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note.content,
                style: TextStyle(
                    color: c.textPrimary, fontSize: 14, height: 1.35)),
            const SizedBox(height: 4),
            Text(formatNoteDate(note.updatedAt ?? note.createdAt),
                style: TextStyle(color: c.textSubtle, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final c = AppColorsExt.of(context);
    return SizedBox(
      height: 36,
      child: HorizontalWheelScroll(
        builder: (ctrl) => ListView.separated(
          controller: ctrl,
          scrollDirection: Axis.horizontal,
          itemCount: _timeframes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final tf = _timeframes[i];
            final isSelected = _tfIndex == i;
            return GestureDetector(
              onTap: () {
                if (_tfIndex == i) return;
                setState(() => _tfIndex = i);
                _persistTimeframe();
                _loadHistory();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? c.warmAccentSoft : c.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Text(
                  tf.$3,
                  style: TextStyle(
                    color: isSelected ? c.warmAccent : c.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChart() {
    final c = AppColorsExt.of(context);
    if (_isLoadingHistory) {
      return SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator(color: c.textPrimary)),
      );
    }
    if (_priceData.isEmpty) {
      // Fiziki altında geçmiş seri YOK (kuyumcu fiyatı anlık kote edilir) —
      // "veri alınamadı" demek hata sanılıyordu; sebebini söyle.
      final physical = SymbolDisplay.isPhysical(widget.stockData.symbol);
      return SizedBox(
        height: physical ? 120 : 320,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              physical
                  ? 'Fiziki altının geçmiş fiyat grafiği yok; serbest piyasada '
                      'anlık alış-satış fiyatı üzerinden değerlenir.'
                  : 'Grafik verisi alınamadı',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.5),
            ),
          ),
        ),
      );
    }
    return PriceChart(
      data: _priceData,
      currency: _currency,
      newsMarkers: _buildNewsMarkers(),
      height: 360,
      symbolLabel: SymbolDisplay.compact(widget.stockData.symbol),
      timeframeLabel: _timeframes[_tfIndex].$3,
      symbol: widget.stockData.symbol, // çizimleri hesaba kaydet
    );
  }

  Future<void> _openNewsUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showAppSnackBar(context, 'Haber açılamadı', isError: true);
    }
  }

  Widget _buildNewsRow(dynamic news) {
    final c = AppColorsExt.of(context);
    final title = news['title'] ?? '';
    final url = news['url'] as String? ?? '';
    final sentimentLabel = news['sentiment_label'] ?? 'Nötr';
    final score = (news['sentiment_score'] as num?)?.toDouble() ?? 0.0;
    // Sadece gerçek sinyalde (poz/neg) renkli skor rozeti göster; nötr haberde
    // anlamsız "0.00" yerine sönük nokta — markörler yalnızca veride renklenir.
    final hasSignal =
        sentimentLabel == 'Pozitif' || sentimentLabel == 'Negatif';
    final dataColor = sentimentLabel == 'Pozitif' ? c.positive : c.negative;
    // Markör alanını sabit genişlikte tut ki başlık sol kenarları hizalı kalsın.
    final Widget marker = hasSignal
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: dataColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              score.toStringAsFixed(2),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: c.textMuted,
              shape: BoxShape.circle,
            ),
          );
    return InkWell(
      onTap: url.isEmpty ? null : () => _openNewsUrl(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 44,
              alignment: Alignment.centerLeft,
              child: marker,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            if (url.isNotEmpty) ...[
              const SizedBox(width: 8),
              Icon(Icons.arrow_outward, size: 14, color: c.textSubtle),
            ],
          ],
        ),
      ),
    );
  }

  // Elite navigasyon satırı — AI analiz sheet'lerini açar.
  Widget _eliteNavRow(
    AppColorsExt c, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: EliteSpace.md, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.warmAccentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: c.warmAccent, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 12,
                            letterSpacing: -0.1)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textSubtle, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── satış kaydı sheet'i
  // Sanal emir DEĞİL: kullanıcının gerçekte yaptığı satışı deftere işler
  // (pozisyon azalır, işlem geçmişine SATIŞ kaydı düşer).
  void _showSellRecordSheet(BuildContext context, String symbol, double held) {
    final qtyCtrl = TextEditingController(text: held.toStringAsFixed(0));
    // Kayıt uçuşta: buton dönüyor, sheet AÇIK kalıyor. Eskiden sheet istek
    // gönderilmeden ÖNCE kapanıyordu → Render uykudan kalkarken kullanıcı
    // 40+ saniye hiçbir geri bildirim görmeden bekliyordu, sonuç en sonda
    // alttaki ekranda bir SnackBar olarak beliriyordu.
    var submitting = false;
    showIOSBottomSheet(
      context: context,
      title: 'Satış Kaydet',
      child: StatefulBuilder(builder: (sheetCtx, setSt) {
        final c = AppColorsExt.of(sheetCtx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Gerçekte sattığın lotu gir; pozisyonundan düşülür ve işlem '
                'geçmişine satış kaydı eklenir.',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 13,
                  letterSpacing: -0.1,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              EliteSurface(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Text('Lot',
                        style: TextStyle(color: c.textMuted, fontSize: 13)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        cursorColor: c.textPrimary,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setSt(() {
                        qtyCtrl.text = held.toStringAsFixed(0);
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text('Tümü',
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              IOSPillButton(
                label: submitting ? 'Kaydediliyor…' : 'Satışı Kaydet',
                width: double.infinity,
                isLoading: submitting,
                onPressed: submitting
                    ? null
                    : () async {
                        final qty = double.tryParse(
                                qtyCtrl.text.trim().replaceAll(',', '.')) ??
                            0;
                        if (qty <= 0) {
                          showAppSnackBar(sheetCtx, 'Geçerli bir lot gir',
                              isError: true);
                          return;
                        }
                        if (qty > held) {
                          showAppSnackBar(
                              sheetCtx,
                              'En fazla ${held.toStringAsFixed(0)} lot '
                              'kaydedebilirsin',
                              isError: true);
                          return;
                        }
                        setSt(() => submitting = true);
                        final result = await context
                            .read<PortfolioProvider>()
                            .recordSell(symbol, qty);
                        // Sheet hâlâ açıksa kapat; kullanıcı kendi
                        // kapattıysa Navigator'a dokunma (alttaki ekranı
                        // pop'lardık).
                        if (sheetCtx.mounted) {
                          setSt(() => submitting = false);
                          Navigator.pop(sheetCtx);
                        }
                        if (result.success) Haptics.medium();
                        if (!context.mounted) return;
                        showAppSnackBar(
                          context,
                          result.success
                              ? '${formatQty(qty)} lot ${SymbolDisplay.compact(symbol)} satışı kaydedildi'
                              : result.message,
                          isError: !result.success,
                        );
                      },
              ),
            ],
          ),
        );
      }),
    );
  }

  // ─────────────────────────── AI Teknik Tahmin sheet
  void _showPredictionSheet(BuildContext context, String symbol) {
    showIOSBottomSheet(
      context: context,
      title: 'AI Teknik Tahmin',
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: AiSheet(
          fetch: ({bool force = false}) =>
              _apiService.fetchPrediction(symbol, force: force),
          errorMessage:
              'AI teknik tahmin yüklenemedi. AI servisi yoğun olabilir, birazdan tekrar dene.',
          onData: (ctx, data) {
            final c = AppColorsExt.of(ctx);
            final pred = data['prediction'] as Map<String, dynamic>;
            final indicators = data['indicators'] as Map<String, dynamic>;
            final direction = pred['direction'] as String? ?? 'NEUTRAL';
            final confidence = (pred['confidence'] as num?)?.toDouble() ?? 0;
            final target = (pred['target_price'] as num?)?.toDouble() ?? 0;
            final sl = (pred['stop_loss'] as num?)?.toDouble() ?? 0;
            final summary = pred['summary'] as String? ?? '';
            final signals =
                (pred['key_signals'] as List?)?.cast<String>() ?? [];
            final dataColor = direction == 'BULLISH'
                ? c.positive
                : direction == 'BEARISH'
                    ? c.negative
                    : c.textSubtle;
            final dirTr = direction == 'BULLISH'
                ? 'YÜKSELİŞ'
                : direction == 'BEARISH'
                    ? 'DÜŞÜŞ'
                    : 'NÖTR';

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                IOSVerdictBanner(
                  verdict: dirTr,
                  sub: 'AI teknik yön tahmini',
                  color: dataColor,
                  icon: direction == 'BULLISH'
                      ? Icons.trending_up_rounded
                      : direction == 'BEARISH'
                          ? Icons.trending_down_rounded
                          : Icons.trending_flat_rounded,
                  stats: [
                    ('Güven', '%${confidence.toStringAsFixed(0)}'),
                    ('Hedef', '$_currency${formatMoney(target)}'),
                    ('Stop', '$_currency${formatMoney(sl)}'),
                  ],
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _accentCard(context, 'AI YORUMU', summary, dataColor),
                ],
                if (signals.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const IOSSectionHeader(label: 'Anahtar Sinyaller'),
                  IOSGroupedCard(
                    children: signals
                        .map((s) =>
                            _signalRow(context, s, _toneColor(context, s)))
                        .toList(),
                  ),
                ],
                if ((pred['risks'] as List?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 14),
                  const IOSSectionHeader(label: 'Riskler'),
                  IOSGroupedCard(
                    children: (pred['risks'] as List)
                        .map<Widget>((r) => _signalRow(
                            context, r.toString(), c.negative,
                            icon: Icons.warning_amber_rounded))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 18),
                const IOSSectionHeader(label: 'Göstergeler'),
                Row(
                  children: [
                    Expanded(
                      child: IOSStatTile(
                          label: 'RSI(14)',
                          value: '${indicators['rsi14']}',
                          onTap: () => _showRatioInfo(
                              context, 'rsi', _asd(indicators['rsi14']))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: IOSStatTile(
                          label: '30g Vol.',
                          value: '%${indicators['volatility_30d_pct']}',
                          onTap: () => _showRatioInfo(context, 'vol',
                              _asd(indicators['volatility_30d_pct']))),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: IOSStatTile(
                          label: 'SMA20',
                          value: '${indicators['sma20']}',
                          onTap: () => _showRatioInfo(
                              context, 'sma', _asd(indicators['sma20']))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: IOSStatTile(
                          label: 'SMA50',
                          value: '${indicators['sma50']}',
                          onTap: () => _showRatioInfo(
                              context, 'sma', _asd(indicators['sma50']))),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────── AI Temel Analiz sheet
  void _showFundamentalSheet(BuildContext context, String symbol) {
    showIOSBottomSheet(
      context: context,
      title: 'AI Temel Analiz',
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: AiSheet(
          fetch: ({bool force = false}) =>
              _apiService.fetchFundamental(symbol, force: force),
          errorMessage:
              'AI temel analiz yüklenemedi. AI servisi yoğun olabilir ya da veri gelmedi. Birazdan tekrar dene.',
          onData: (ctx, data) {
            // Hisse-dışı (kripto/forex/emtia) → varlık sınıfına uygun render.
            if ((data['asset_class'] as String? ?? 'stock') != 'stock') {
              return _buildMacroAnalysis(ctx, symbol, data);
            }
            final c = AppColorsExt.of(ctx);
            final analysis = data['analysis'] as Map<String, dynamic>;
            final fund = data['fundamentals'] as Map<String, dynamic>;
            final rec = (analysis['recommendation'] ?? 'TUT').toString();
            final recColor = rec == 'AL'
                ? c.positive
                : rec == 'SAT'
                    ? c.negative
                    : c.textSubtle;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Text(
                  '${fund['company_name'] ?? SymbolDisplay.compact(symbol)}',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                if (fund['sector'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${fund['sector']} · ${fund['industry'] ?? ''}',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                IOSVerdictBanner(
                  verdict: rec,
                  sub: 'AI temel analiz tavsiyesi',
                  color: recColor,
                  icon: rec == 'AL'
                      ? Icons.trending_up_rounded
                      : rec == 'SAT'
                          ? Icons.trending_down_rounded
                          : Icons.trending_flat_rounded,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      IOSScoreBar(
                        label: 'Değerleme',
                        score:
                            (analysis['valuation_score'] as num?)?.toDouble() ??
                                50,
                      ),
                      const SizedBox(height: 14),
                      IOSScoreBar(
                        label: 'Büyüme',
                        score: (analysis['growth_score'] as num?)?.toDouble() ??
                            50,
                      ),
                      const SizedBox(height: 14),
                      IOSScoreBar(
                        label: 'Finansal Sağlık',
                        score: (analysis['health_score'] as num?)?.toDouble() ??
                            50,
                      ),
                    ],
                  ),
                ),
                if (analysis['summary'] != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      analysis['summary'].toString(),
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 13,
                        height: 1.55,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
                if ((analysis['key_strengths'] as List?)?.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 18),
                  const IOSSectionHeader(label: 'Güçlü Yönler'),
                  IOSGroupedCard(
                    children: (analysis['key_strengths'] as List)
                        .map<Widget>((s) => _signalRow(
                            context, s.toString(), c.positive,
                            icon: Icons.check_circle_rounded))
                        .toList(),
                  ),
                ],
                if ((analysis['key_weaknesses'] as List?)?.isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 14),
                  const IOSSectionHeader(label: 'Zayıf Yönler'),
                  IOSGroupedCard(
                    children: (analysis['key_weaknesses'] as List)
                        .map<Widget>((s) => _signalRow(
                            context, s.toString(), c.negative,
                            icon: Icons.remove_circle_rounded))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 16),
                const IOSSectionHeader(label: 'Temel Göstergeler'),
                IOSGroupedCard(
                  children: [
                    _kvRow(
                        context, 'F/K (Trailing)', _fnum(fund['pe_trailing']),
                        infoKey: 'pe', raw: _asd(fund['pe_trailing'])),
                    _kvRow(context, 'F/K (Forward)', _fnum(fund['pe_forward']),
                        infoKey: 'pe', raw: _asd(fund['pe_forward'])),
                    _kvRow(context, 'PD/DD', _fnum(fund['pb']),
                        infoKey: 'pb', raw: _asd(fund['pb'])),
                    _kvRow(context, 'ROE', _fpct(fund['roe_pct']),
                        infoKey: 'roe', raw: _asd(fund['roe_pct'])),
                    _kvRow(
                        context, 'Kâr Marjı', _fpct(fund['profit_margin_pct']),
                        infoKey: 'margin',
                        raw: _asd(fund['profit_margin_pct'])),
                    _kvRow(context, 'Gelir Büyümesi',
                        _fpct(fund['revenue_growth_pct']),
                        infoKey: 'growth',
                        raw: _asd(fund['revenue_growth_pct'])),
                    _kvRow(
                        context, 'Borç/Özkaynak', _fnum(fund['debt_to_equity']),
                        infoKey: 'de', raw: _asd(fund['debt_to_equity'])),
                    _kvRow(context, 'Temettü Verimi',
                        _fpct(fund['dividend_yield_pct']),
                        infoKey: 'divyield',
                        raw: _asd(fund['dividend_yield_pct'])),
                    _kvRow(context, 'Beta', _fnum(fund['beta']),
                        infoKey: 'beta', raw: _asd(fund['beta'])),
                    _kvRow(context, 'Analist Hedefi',
                        '$_currency${_fnum(fund['analyst_target'])}'),
                  ],
                ),
                const SizedBox(height: 18),
                _FinancialsSection(
                    symbol: symbol,
                    currency: _currency,
                    apiService: _apiService),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────── Varlık-sınıfı (kripto/forex/emtia) analiz
  // Hisse-özel F/K/bilanço yerine sınıfa uygun: dinamik skor etiketleri
  // (backend score_labels) + piyasa verileri kartı (fiyat/52H/performans,
  // kripto: piyasa değeri/arz/hacim). Şema: data['asset_class'] + 'overview'.
  Widget _buildMacroAnalysis(
      BuildContext context, String symbol, Map<String, dynamic> data) {
    final c = AppColorsExt.of(context);
    final analysis = (data['analysis'] as Map).cast<String, dynamic>();
    final ov = (data['overview'] as Map?)?.cast<String, dynamic>() ?? {};
    final assetClass = (data['asset_class'] ?? '').toString();
    final rec = (analysis['recommendation'] ?? 'TUT').toString();
    final recColor = rec == 'AL'
        ? c.positive
        : rec == 'SAT'
            ? c.negative
            : c.textSubtle;
    final scores = (analysis['scores'] as List?) ?? const [];
    final pfx = (ov['currency_prefix'] ?? '').toString();
    final name =
        (ov['display_name'] ?? SymbolDisplay.compact(symbol)).toString();
    final kindLabel = const {
          'crypto': 'Kripto Para',
          'forex': 'Döviz Paritesi',
          'commodity': 'Emtia',
        }[assetClass] ??
        'Varlık';
    final recSub = assetClass == 'forex'
        ? 'AI makro analiz tavsiyesi'
        : assetClass == 'commodity'
            ? 'AI arz-talep analiz tavsiyesi'
            : 'AI analiz tavsiyesi';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text(name,
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2)),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('$kindLabel · ${SymbolDisplay.compact(symbol)}',
              style: TextStyle(color: c.textMuted, fontSize: 12)),
        ),
        const SizedBox(height: 16),
        IOSVerdictBanner(
          verdict: rec,
          sub: recSub,
          color: recColor,
          icon: rec == 'AL'
              ? Icons.trending_up_rounded
              : rec == 'SAT'
                  ? Icons.trending_down_rounded
                  : Icons.trending_flat_rounded,
        ),
        if (scores.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (int i = 0; i < scores.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  IOSScoreBar(
                    label: (scores[i]['label'] ?? '').toString(),
                    score: (scores[i]['score'] as num?)?.toDouble() ?? 50,
                  ),
                ],
              ],
            ),
          ),
        ],
        if (analysis['summary'] != null &&
            analysis['summary'].toString().isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: c.surface, borderRadius: BorderRadius.circular(12)),
            child: Text(analysis['summary'].toString(),
                style: TextStyle(
                    color: c.textMuted,
                    fontSize: 13,
                    height: 1.55,
                    letterSpacing: -0.1)),
          ),
        ],
        if ((analysis['key_strengths'] as List?)?.isNotEmpty ?? false) ...[
          const SizedBox(height: 18),
          const IOSSectionHeader(label: 'Güçlü Yönler'),
          IOSGroupedCard(
            children: (analysis['key_strengths'] as List)
                .map<Widget>((s) => _signalRow(
                    context, s.toString(), c.positive,
                    icon: Icons.check_circle_rounded))
                .toList(),
          ),
        ],
        if ((analysis['key_weaknesses'] as List?)?.isNotEmpty ?? false) ...[
          const SizedBox(height: 14),
          const IOSSectionHeader(label: 'Riskler / Zayıf Yönler'),
          IOSGroupedCard(
            children: (analysis['key_weaknesses'] as List)
                .map<Widget>((s) => _signalRow(
                    context, s.toString(), c.negative,
                    icon: Icons.remove_circle_rounded))
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        const IOSSectionHeader(label: 'Piyasa Verileri'),
        IOSGroupedCard(
          children: [
            _kvRow(
                context, 'Cari Fiyat', '$pfx${_macroNum(ov['current_price'])}'),
            _kvRow(context, '52 Hafta Aralık',
                '$pfx${_macroNum(ov['week52_low'])} – $pfx${_macroNum(ov['week52_high'])}'),
            _kvRow(context, 'Performans (1A)', _macroPct(ov['perf_1m_pct'])),
            _kvRow(context, 'Performans (6A)', _macroPct(ov['perf_6m_pct'])),
            _kvRow(context, 'Performans (1Y)', _macroPct(ov['perf_1y_pct'])),
            if (assetClass == 'crypto') ...[
              _kvRow(context, 'Piyasa Değeri',
                  '$pfx${_macroCompact(ov['market_cap'])}'),
              _kvRow(context, 'Dolaşan Arz',
                  _macroCompact(ov['circulating_supply'])),
              _kvRow(
                  context, 'Hacim (24s)', '$pfx${_macroCompact(ov['volume'])}'),
            ],
          ],
        ),
      ],
    );
  }

  String _macroNum(dynamic v) {
    if (v == null) return '—';
    final d = (v as num).toDouble();
    return formatMoney(d, decimals: d.abs() >= 100 ? 0 : 2);
  }

  String _macroPct(dynamic v) => v == null
      ? '—'
      : '${formatPctSigned((v as num).toDouble(), decimals: 2)}%';

  // Büyük sayı → kısa (T=trilyon, Mr=milyar, Mn=milyon, B=bin).
  String _macroCompact(dynamic v) {
    if (v == null) return '—';
    final d = (v as num).toDouble();
    final a = d.abs();
    if (a >= 1e12) return '${(d / 1e12).toStringAsFixed(2)}T';
    if (a >= 1e9) return '${(d / 1e9).toStringAsFixed(2)}Mr';
    if (a >= 1e6) return '${(d / 1e6).toStringAsFixed(2)}Mn';
    if (a >= 1e3) return '${(d / 1e3).toStringAsFixed(1)}B';
    return formatMoney(d, decimals: 0);
  }

  // Sol gold şeritli vurgu kartı (AI yorumu / önemli not).
  Widget _accentCard(
      BuildContext context, String label, String body, Color accent) {
    final c = AppColorsExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4)),
                    const SizedBox(height: 6),
                    Text(body,
                        style: TextStyle(
                            color: c.textMuted,
                            fontSize: 13,
                            height: 1.55,
                            letterSpacing: -0.1)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Sinyal metnindeki yön kelimelerine göre veri rengi (data-ink istisnası).
  Color _toneColor(BuildContext context, String s) {
    final c = AppColorsExt.of(context);
    final t = s.toLowerCase();
    const pos = [
      'yükseliş',
      'yukarı',
      'güçlü',
      'pozitif',
      'alış',
      'destek',
      'artış'
    ];
    const neg = [
      'düşüş',
      'aşırı alım',
      'aşırı satım',
      'geri çekilme',
      'risk',
      'zayıf',
      'negatif',
      'satış',
      'baskı',
      'direnç',
      'dikkat'
    ];
    if (neg.any(t.contains)) return c.negative;
    if (pos.any(t.contains)) return c.positive;
    return c.textSubtle;
  }

  Widget _signalRow(BuildContext context, String text, Color tone,
      {IconData? icon}) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, color: tone, size: 16))
              : Container(
                  margin: const EdgeInsets.only(top: 6, right: 2),
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: tone, shape: BoxShape.circle),
                ),
          SizedBox(width: icon != null ? 10 : 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: c.textMuted,
                    fontSize: 12.5,
                    height: 1.45,
                    letterSpacing: -0.1)),
          ),
        ],
      ),
    );
  }

  // Oran/sayı: Türkçe virgül, 2 ondalık, gruplu. null → '—'.
  double? _asd(dynamic v) {
    if (v == null) return null;
    return (v is num) ? v.toDouble() : double.tryParse(v.toString());
  }

  String _fnum(dynamic v, {int d = 2}) {
    if (v == null) return '—';
    final x = (v is num) ? v.toDouble() : double.tryParse(v.toString());
    if (x == null) return '—';
    return formatMoney(x, decimals: d);
  }

  // Yüzde: '%' + Türkçe virgül. null → '—'.
  String _fpct(dynamic v, {int d = 2}) {
    if (v == null) return '—';
    final x = (v is num) ? v.toDouble() : double.tryParse(v.toString());
    if (x == null) return '—';
    return '%${formatPct(x, decimals: d)}';
  }

  Widget _kvRow(BuildContext context, String label, String value,
      {String? infoKey, double? raw}) {
    final c = AppColorsExt.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  color: c.textMuted, fontSize: 13, letterSpacing: -0.1)),
          if (infoKey != null) ...[
            const SizedBox(width: 5),
            Icon(Icons.info_outline, size: 13, color: c.textSubtle),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (infoKey == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showRatioInfo(context, infoKey, raw),
      child: row,
    );
  }

  /// Temel gösterge açıklama sheet'i — değere göre yorum (IOSSheetHero +
  /// IOSInfoBlock). 12-tur sheet infra'sını kullanır; tek varlık için yeşil/
  /// kırmızı yalnız değerin "iyi/kötü" durumunu vurgular (data-ink istisnası).
  void _showRatioInfo(BuildContext context, String key, double? v) {
    final c = AppColorsExt.of(context);
    final pos = c.positive, warm = c.warmAccent, neg = c.negative;
    final sub = c.textSubtle;
    const pctKeys = {'roe', 'margin', 'growth', 'divyield', 'vol'};
    final display =
        v == null ? '—' : (pctKeys.contains(key) ? _fpct(v) : _fnum(v));

    late String title, what, action, verdict, reading;
    String? formula;
    late Color color;

    switch (key) {
      case 'pe':
        title = 'F/K Oranı';
        formula = 'F/K = Hisse Fiyatı ÷ Hisse Başı Kâr';
        what =
            'Şirketin yıllık kârının kaç katı bir fiyata alındığını gösterir. '
            'Tek başına değil; aynı sektördeki şirketler ve büyüme hızıyla '
            'birlikte okunmalı.';
        action =
            'F/K\'yı sektör ortalaması ve büyümeyle kıyasla: hızlı büyüyen bir '
            'şirkette yüksek F/K normal olabilir; durağan bir şirkette aynı '
            'oran pahalı demektir.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'F/K verisi yok — şirket zarar ediyorsa oran hesaplanamaz.';
        } else if (v < 0) {
          verdict = 'Zarar';
          color = neg;
          reading =
              'Negatif F/K son dönemde zarar edildiğini gösterir; oran anlamını yitirir.';
        } else if (v < 10) {
          verdict = 'Düşük';
          color = warm;
          reading =
              'Düşük F/K ucuz görünür ama bazen zayıf büyüme veya bilinen bir riski yansıtır. Nedenini araştır.';
        } else if (v <= 25) {
          verdict = 'Makul';
          color = pos;
          reading = 'F/K makul aralıkta — fiyat, kârla dengeli görünüyor.';
        } else if (v <= 40) {
          verdict = 'Yüksek';
          color = warm;
          reading =
              'Yüksek F/K piyasanın güçlü büyüme beklediğini gösterir; beklenti tutmazsa düşüş riski var.';
        } else {
          verdict = 'Çok Yüksek';
          color = neg;
          reading =
              'Çok yüksek F/K agresif büyüme fiyatlaması demek; hayal kırıklığında sert düzeltme riski taşır.';
        }
        break;
      case 'pb':
        title = 'PD/DD (Piyasa/Defter)';
        formula = 'PD/DD = Piyasa Değeri ÷ Özkaynak (Defter Değeri)';
        what = 'Şirketin piyasa değerinin, defterdeki net varlık değerinin kaç '
            'katı olduğunu gösterir. Banka/sanayi gibi varlık-ağırlıklı '
            'sektörlerde daha anlamlıdır.';
        action = 'Sektörle kıyasla: 1 altı "defter değerinin altında" olabilir '
            '(fırsat ya da sorun); teknoloji gibi varlık-hafif şirketlerde '
            'yüksek PD/DD olağandır.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'PD/DD verisi sağlanamadı.';
        } else if (v < 1) {
          verdict = 'Defter altı';
          color = warm;
          reading =
              'Piyasa, şirketi defter değerinin altında fiyatlıyor — değer fırsatı ya da algılanan bir risk olabilir.';
        } else if (v <= 3) {
          verdict = 'Makul';
          color = pos;
          reading = 'PD/DD makul; piyasa değeri varlıklarla dengeli.';
        } else {
          verdict = 'Yüksek';
          color = warm;
          reading =
              'Yüksek PD/DD güçlü büyüme/karlılık beklentisini ya da pahalılığı işaret eder.';
        }
        break;
      case 'roe':
        title = 'Özkaynak Kârlılığı (ROE)';
        formula = 'ROE = Net Kâr ÷ Özkaynak';
        what = 'Şirketin hissedar parasıyla ne kadar verimli kâr ürettiğini '
            'gösterir. Yüksek ve istikrarlı ROE güçlü bir iş modelinin '
            'işaretidir.';
        action =
            'Borçla şişirilmiş ROE\'ye dikkat — Borç/Özkaynak ile birlikte oku; '
            'yüksek ROE + düşük borç en sağlıklısıdır.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'ROE verisi sağlanamadı.';
        } else if (v < 0) {
          verdict = 'Negatif';
          color = neg;
          reading =
              'Negatif ROE, özkaynak üzerinden zarar edildiğini gösterir.';
        } else if (v < 10) {
          verdict = 'Düşük';
          color = warm;
          reading = 'Düşük ROE, sermayenin verimsiz kullanıldığını düşündürür.';
        } else if (v <= 20) {
          verdict = 'İyi';
          color = pos;
          reading = 'Sağlıklı ROE — sermaye verimli çalışıyor.';
        } else {
          verdict = 'Güçlü';
          color = pos;
          reading =
              'Çok güçlü ROE; sürdürülebilirliğini ve borç etkisini kontrol et.';
        }
        break;
      case 'margin':
        title = 'Net Kâr Marjı';
        formula = 'Kâr Marjı = Net Kâr ÷ Gelir';
        what = 'Her 100 TL gelirin ne kadarının net kâra dönüştüğünü gösterir. '
            'Fiyatlama gücü ve maliyet kontrolünün özetidir.';
        action =
            'Sektörle kıyasla: marketler düşük, yazılım yüksek marjla çalışır. '
            'Marjın zaman içindeki yönü (artıyor mu?) seviyesinden önemlidir.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'Kâr marjı verisi sağlanamadı.';
        } else if (v < 0) {
          verdict = 'Zarar';
          color = neg;
          reading = 'Negatif marj, faaliyetin zararla sonuçlandığını gösterir.';
        } else if (v < 5) {
          verdict = 'İnce';
          color = warm;
          reading = 'İnce marj; maliyet şoklarına karşı kırılgan.';
        } else if (v <= 20) {
          verdict = 'Sağlıklı';
          color = pos;
          reading = 'Sağlıklı marj — kâra dönüşüm iyi.';
        } else {
          verdict = 'Yüksek';
          color = pos;
          reading = 'Yüksek marj güçlü fiyatlama gücüne işaret eder.';
        }
        break;
      case 'growth':
        title = 'Gelir Büyümesi';
        formula = 'Gelir Büyümesi = (Bu dönem − Geçen dönem) ÷ Geçen dönem';
        what = 'Şirketin satışlarının yıllık ne hızla arttığını gösterir. '
            'Yüksek F/K\'yı haklı çıkaran ana etken çoğu zaman budur.';
        action = 'Büyümeyi F/K ile birlikte oku: yüksek büyüme yüksek çarpanı '
            'destekler; büyüme yavaşlıyorsa yüksek F/K riski artar.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'Gelir büyümesi verisi sağlanamadı.';
        } else if (v < 0) {
          verdict = 'Daralma';
          color = neg;
          reading = 'Negatif büyüme, satışların gerilediğini gösterir.';
        } else if (v < 8) {
          verdict = 'Yavaş';
          color = warm;
          reading = 'Yavaş büyüme; olgun/durağan bir iş olabilir.';
        } else if (v <= 20) {
          verdict = 'Sağlıklı';
          color = pos;
          reading = 'Sağlıklı büyüme temposu.';
        } else {
          verdict = 'Hızlı';
          color = pos;
          reading = 'Hızlı büyüme; sürdürülebilirliği ve kârlılığı kontrol et.';
        }
        break;
      case 'de':
        title = 'Borç / Özkaynak';
        formula = 'Borç/Özkaynak = Toplam Borç ÷ Özkaynak';
        what = 'Şirketin özkaynağına göre ne kadar borç kullandığını gösterir. '
            'Yüksek kaldıraç getiriyi büyütür ama faiz ve iflas riskini de '
            'artırır.';
        action =
            'Sektörle kıyasla (bankalarda doğal olarak yüksektir). Faizlerin '
            'yüksek olduğu dönemde yüksek borç daha risklidir.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'Borç/Özkaynak verisi sağlanamadı.';
        } else if (v < 50) {
          verdict = 'Düşük';
          color = pos;
          reading = 'Düşük borç — finansal olarak sağlam, esnekliği yüksek.';
        } else if (v <= 150) {
          verdict = 'Orta';
          color = warm;
          reading = 'Orta düzey kaldıraç; nakit akışıyla yönetilebilir olmalı.';
        } else {
          verdict = 'Yüksek';
          color = neg;
          reading =
              'Yüksek kaldıraç; faiz artışlarına ve gelir düşüşüne karşı kırılgan.';
        }
        break;
      case 'divyield':
        title = 'Temettü Verimi';
        formula = 'Temettü Verimi = Yıllık Temettü ÷ Hisse Fiyatı';
        what = 'Hisse fiyatına göre yıllık ne kadar nakit temettü ödendiğini '
            'gösterir. Düzenli gelir arayan yatırımcı için önemlidir.';
        action =
            'Çok yüksek verim bazen fiyatın düşmesinden kaynaklanır (tuzak); '
            'temettünün sürdürülebilirliğini (kârdan ödenen pay) kontrol et.';
        if (v == null || v == 0) {
          verdict = 'Yok';
          color = sub;
          reading =
              'Şirket temettü ödemiyor — getiriyi tamamen fiyat artışından bekliyorsun.';
        } else if (v < 2) {
          verdict = 'Düşük';
          color = warm;
          reading = 'Düşük verim; şirket kârı büyümeye yatırıyor olabilir.';
        } else if (v <= 6) {
          verdict = 'İyi';
          color = pos;
          reading = 'Makul, sürdürülebilir görünen bir temettü verimi.';
        } else {
          verdict = 'Çok Yüksek';
          color = warm;
          reading =
              'Çok yüksek verim cazip ama dikkat: fiyat düşüşünden kaynaklanıp temettü kesintisini işaret edebilir.';
        }
        break;
      case 'beta':
        title = 'Beta';
        formula = 'Beta = Hissenin piyasaya göre oynaklığı (piyasa = 1)';
        what = 'Hissenin piyasa endeksine kıyasla ne kadar oynak olduğunu '
            'gösterir. 1 = piyasayla aynı; >1 daha hareketli, <1 daha sakin.';
        action =
            'Risk iştahına göre oku: yüksek beta hem daha çok kazandırır hem '
            'daha çok kaybettirir. Portföy oynaklığını dengelemek için beta '
            'dağılımına bak.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'Beta verisi sağlanamadı.';
        } else if (v < 0) {
          verdict = 'Ters';
          color = warm;
          reading =
              'Negatif beta, hissenin piyasayla ters yönde hareket etme eğilimini gösterir (nadir).';
        } else if (v < 0.8) {
          verdict = 'Sakin';
          color = pos;
          reading = 'Piyasadan daha az oynak — savunmacı, daha durağan.';
        } else if (v <= 1.2) {
          verdict = 'Piyasa gibi';
          color = pos;
          reading = 'Piyasayla benzer oynaklıkta hareket ediyor.';
        } else {
          verdict = 'Oynak';
          color = warm;
          reading = 'Piyasadan daha oynak; sert hareketlere hazırlıklı ol.';
        }
        break;
      case 'rsi':
        title = 'RSI — Göreceli Güç Endeksi';
        formula = 'RSI = 100 − 100 / (1 + Ort. Kazanç ÷ Ort. Kayıp)';
        what = 'Son 14 günde fiyatın ne kadar hızlı yükselip düştüğünü 0–100 '
            'arası bir momentum skoruna çevirir; yükseliş ve düşüş günlerinin '
            'büyüklüğünü kıyaslar.';
        action =
            'Tek başına al-sat sinyali sayma; trend ve hacimle birlikte oku. '
            'Aşırı bölgeler dönüş "olabileceğini" söyler, kesinlik değil.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'RSI hesaplanamadı.';
        } else if (v >= 70) {
          verdict = 'Aşırı Alım';
          color = neg;
          reading =
              'RSI 70 üstü — alıcılar momentumu zorluyor; kâr satışı / geri '
              'çekilme riski artmış olabilir.';
        } else if (v <= 30) {
          verdict = 'Aşırı Satım';
          color = pos;
          reading = 'RSI 30 altı — satış abartılmış olabilir, tepki yükselişi '
              'gelebilir. Düşen trendde "ucuz" yanıltıcı olur, teyit ara.';
        } else if (v >= 55) {
          verdict = 'Güçlü';
          color = warm;
          reading =
              'RSI 55–70 arası — yukarı momentum sağlıklı, henüz aşırı değil.';
        } else if (v <= 45) {
          verdict = 'Zayıf';
          color = warm;
          reading = 'RSI 30–45 arası — aşağı baskı var ama aşırı satım değil.';
        } else {
          verdict = 'Nötr';
          color = sub;
          reading = 'RSI 45–55 arası — yön belirsiz, momentum dengede.';
        }
        break;
      case 'vol':
        title = 'Volatilite (30 Günlük)';
        formula = 'Son 30 günlük getirilerin standart sapması';
        what = 'Fiyatın ortalaması etrafında ne kadar dalgalandığını ölçer — '
            'riskin en yaygın sayısal göstergesi.';
        action = 'Getiriyi tek başına değil, üstlendiğin bu oynaklığa GÖRE '
            'değerlendir (bkz. Sharpe). Yüksek oynaklık, pozisyonu küçük '
            'tutmak için sebeptir.';
        if (v == null) {
          verdict = 'Veri yok';
          color = sub;
          reading = 'Volatilite hesaplanamadı.';
        } else if (v >= 6) {
          verdict = 'Çok Yüksek';
          color = neg;
          reading = 'Sert iniş-çıkış — yüksek kazanç kadar yüksek kayıp '
              'potansiyeli; haber/duyarlılık etkisi büyük olur.';
        } else if (v >= 3) {
          verdict = 'Yüksek';
          color = warm;
          reading = 'Belirgin dalgalanma — normalin üstü hareketlilik var.';
        } else if (v >= 1.5) {
          verdict = 'Orta';
          color = pos;
          reading = 'Ölçülü dalgalanma — tipik piyasa hareketliliği.';
        } else {
          verdict = 'Düşük';
          color = pos;
          reading = 'Sakin seyir — fiyat dar bir bantta hareket ediyor.';
        }
        break;
      case 'sma':
        title = 'SMA — Basit Hareketli Ortalama';
        formula = 'SMA = Son N günün kapanış ortalaması';
        what =
            'Belirli gün sayısındaki kapanışların ortalamasını alarak günlük '
            'gürültüyü temizler ve trendin genel yönünü gösterir.';
        action = 'Fiyat ortalamanın üstündeyse kısa vadeli eğilim yukarı, '
            'altındaysa aşağı. Kısa ortalama (SMA20) uzun ortalamayı (SMA50) '
            'yukarı keserse "altın kesişim" (pozitif), aşağı keserse "ölüm '
            'kesişimi" (negatif) olarak yorumlanır.';
        verdict = 'Trend Ortalaması';
        color = sub;
        reading =
            'Bu değer, gösterilen pencere için ortalama fiyat seviyesidir. '
            'Anlamı, güncel fiyatın ve diğer ortalamanın bu seviyeye göre '
            'konumunda saklıdır — tek başına al-sat sinyali değildir.';
        break;
      default:
        return;
    }

    showIOSBottomSheet(
      context: context,
      title: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IOSSheetHero(value: display, color: color, verdict: verdict),
            const SizedBox(height: 24),
            IOSInfoBlock(
                icon: Icons.straighten,
                label: 'NE ÖLÇER',
                formula: formula,
                body: what),
            const SizedBox(height: 20),
            IOSInfoBlock(
                icon: Icons.analytics_outlined,
                label: 'SENİN HİSSEN',
                body: reading),
            const SizedBox(height: 20),
            IOSInfoBlock(
                icon: Icons.lightbulb_outline,
                label: 'NASIL OKUMALI',
                body: action,
                emphasize: true),
          ],
        ),
      ),
    );
  }
}

// ─────────────────── Bilanço (yıllık/çeyreklik) + Analist ───────────────────
class _FinancialsSection extends StatefulWidget {
  final String symbol;
  final String currency;
  final ApiService apiService;
  const _FinancialsSection({
    required this.symbol,
    required this.currency,
    required this.apiService,
  });

  @override
  State<_FinancialsSection> createState() => _FinancialsSectionState();
}

class _FinancialsSectionState extends State<_FinancialsSection> {
  late final Future<Map<String, dynamic>?> _future;
  bool _quarterly = false;

  @override
  void initState() {
    super.initState();
    _future = widget.apiService.fetchFinancials(widget.symbol);
  }

  String _money(num? v, String cur) {
    if (v == null) return '—';
    final a = v.abs();
    final s = a >= 1e9
        ? '${formatMoney(v / 1e9, decimals: 2)} Mr'
        : a >= 1e6
            ? '${formatMoney(v / 1e6, decimals: 1)} Mn'
            : formatMoney(v.toDouble(), decimals: 0);
    return '$s $cur';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final d = snap.data;
        if (d == null || d['has_data'] != true) {
          return const SizedBox.shrink();
        }
        final hist = (d['history'] as List?) ?? [];
        final quar = (d['quarterly'] as List?) ?? [];
        final fc = d['forecast'] as Map<String, dynamic>?;
        final cur = d['currency'] as String? ?? '';
        final analyst = d['analyst'] as Map<String, dynamic>?;
        final rows = _quarterly ? quar : hist;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IOSSectionHeader(label: 'Bilanço'),
            IOSSegmented<bool>(
              options: const [(false, 'Yıllık'), (true, 'Çeyreklik')],
              value: _quarterly,
              onChange: (v) => setState(() => _quarterly = v),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _quarterly
                      ? 'Çeyreklik veri bulunamadı.'
                      : 'Yıllık veri bulunamadı.',
                  style: TextStyle(color: c.textSubtle, fontSize: 12.5),
                ),
              )
            else
              IOSGroupedCard(
                children: [
                  for (final p in rows)
                    _finRow(
                      context,
                      (p as Map)['period'].toString(),
                      _money(p['revenue'] as num?, cur),
                      _money(p['net_income'] as num?, cur),
                      (p['net_margin_pct'] as num?)?.toDouble(),
                      false,
                    ),
                  if (!_quarterly && fc != null)
                    _finRow(
                      context,
                      fc['period'].toString(),
                      _money(fc['revenue'] as num?, cur),
                      _money(fc['net_income'] as num?, cur),
                      (fc['net_margin_pct'] as num?)?.toDouble(),
                      true,
                    ),
                ],
              ),
            if (analyst != null) _analyst(context, analyst, cur),
          ],
        );
      },
    );
  }

  Widget _finRow(BuildContext context, String period, String rev, String net,
      double? margin, bool isForecast) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(period,
                style: TextStyle(
                    color: isForecast ? c.warmAccent : c.textPrimary,
                    fontSize: 12.5,
                    fontWeight: isForecast ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: -0.1)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Gelir $rev',
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  'Net $net'
                  '${margin != null ? '  ·  %${margin.toStringAsFixed(1)} marj' : ''}',
                  style: TextStyle(color: c.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────── Analist görüşü
  Widget _analyst(BuildContext context, Map a, String cur) {
    final c = AppColorsExt.of(context);
    final pt = a['price_target'] as Map?;
    final rec = a['recommendation'] as Map?;
    final eps = (a['eps_estimate'] as List?) ?? [];
    final rev = (a['revenue_estimate'] as List?) ?? [];
    final eh = a['earnings_history'] as Map?;
    final revis = (a['eps_revisions'] as List?) ?? [];
    if (pt == null &&
        rec == null &&
        eps.isEmpty &&
        rev.isEmpty &&
        eh == null &&
        revis.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const IOSSectionHeader(label: 'Analist Görüşü'),
        if (pt != null) _priceTarget(context, pt),
        if (rec != null) ...[
          const SizedBox(height: 10),
          _recBar(context, rec),
        ],
        if (eps.isNotEmpty) ...[
          const SizedBox(height: 14),
          _estCard(context, 'Hisse Başı Kâr (EPS) Tahmini', eps,
              (v) => '${formatMoney(v, decimals: 2)} $cur'),
        ],
        if (rev.isNotEmpty) ...[
          const SizedBox(height: 10),
          _estCard(context, 'Gelir Tahmini', rev, (v) => _money(v, cur)),
        ],
        if (eh != null || revis.isNotEmpty) ...[
          const SizedBox(height: 20),
          const IOSSectionHeader(label: 'Tahmin İsabeti'),
          if (eh != null)
            _earningsHistory(context, eh, cur)
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Bu hisse için geçmiş analist tahmini / gerçekleşen kâr '
                'verisi yok (BIST hisselerinde sık). Aşağıda analist '
                'tahminlerinin son 30 günde hangi yöne çekildiği var.',
                style: TextStyle(color: c.textMuted, fontSize: 12, height: 1.5),
              ),
            ),
          if (revis.isNotEmpty) ...[
            const SizedBox(height: 10),
            _epsRevisions(context, revis),
          ],
        ],
      ],
    );
  }

  // Geçmiş: analist EPS tahmini → gerçekleşen + sürpriz (tutmuş mu).
  Widget _earningsHistory(BuildContext context, Map eh, String cur) {
    final c = AppColorsExt.of(context);
    final rows = (eh['rows'] as List?) ?? [];
    final beats = (eh['beats'] as num?)?.toInt() ?? 0;
    final total = (eh['total'] as num?)?.toInt() ?? rows.length;
    final avg = (eh['avg_surprise_pct'] as num?)?.toDouble();
    final good = total > 0 && beats * 2 >= total;
    final tone = good ? c.positive : c.negative;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _accentBox(
          context,
          tone,
          'Son $total çeyrekte $beats kez tahmin tutturuldu',
          avg == null
              ? 'Ortalama kâr sürprizi: —'
              : 'Ortalama kâr sürprizi: ${avg >= 0 ? '+' : ''}${formatPct(avg, decimals: 1)}%',
        ),
        const SizedBox(height: 10),
        IOSGroupedCard(
          children: [
            for (final r in rows) _ehRow(context, r as Map, cur),
          ],
        ),
      ],
    );
  }

  Widget _ehRow(BuildContext context, Map r, String cur) {
    final c = AppColorsExt.of(context);
    final beat = r['beat'] == true;
    final tone = beat ? c.positive : c.negative;
    final sp = (r['surprise_pct'] as num?)?.toDouble();
    final est = (r['eps_estimate'] as num?)?.toDouble();
    final act = (r['eps_actual'] as num?)?.toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(r['quarter'].toString(),
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tahmin ${est == null ? '—' : formatMoney(est, decimals: 2)}'
                  '  →  Gerçek ${act == null ? '—' : formatMoney(act, decimals: 2)} $cur',
                  style: TextStyle(color: c.textMuted, fontSize: 11.5),
                ),
                const SizedBox(height: 3),
                Text(beat ? 'Beklentiyi aştı' : 'Beklentinin altında',
                    style: TextStyle(
                        color: tone,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              sp == null
                  ? (beat ? 'İSABET' : 'ISKA')
                  : '${sp >= 0 ? '+' : ''}${formatPct(sp, decimals: 1)}%',
              style: TextStyle(
                  color: tone, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accentBox(
      BuildContext context, Color accent, String title, String sub) {
    final c = AppColorsExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 4),
                    Text(sub,
                        style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Analist revizyon yönü — tahminler yukarı mı aşağı mı çekiliyor.
  Widget _epsRevisions(BuildContext context, List revis) {
    final c = AppColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text('ANALİST REVİZYONLARI (SON 30 GÜN)',
              style: TextStyle(
                  color: c.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4)),
        ),
        IOSGroupedCard(
          children: [
            for (final r in revis)
              Builder(builder: (_) {
                final m = r as Map;
                final up = (m['up'] as num?)?.toInt() ?? 0;
                final dn = (m['down'] as num?)?.toInt() ?? 0;
                final net = up - dn;
                final tone = net > 0
                    ? c.positive
                    : (net < 0 ? c.negative : c.textSubtle);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${m['period']} tahmini',
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                      Icon(Icons.arrow_upward_rounded,
                          color: c.positive, size: 14),
                      const SizedBox(width: 3),
                      Text('$up',
                          style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 14),
                      Icon(Icons.arrow_downward_rounded,
                          color: c.negative, size: 14),
                      const SizedBox(width: 3),
                      Text('$dn',
                          style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          net > 0 ? 'Yukarı' : (net < 0 ? 'Aşağı' : 'Sabit'),
                          style: TextStyle(
                              color: tone,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }

  Widget _priceTarget(BuildContext context, Map pt) {
    final c = AppColorsExt.of(context);
    final cur = (pt['current'] as num?)?.toDouble();
    final low = (pt['low'] as num?)?.toDouble();
    final mean = (pt['mean'] as num?)?.toDouble();
    final high = (pt['high'] as num?)?.toDouble();
    final pre = widget.currency;
    final upside = (cur != null && mean != null && cur != 0)
        ? (mean - cur) / cur * 100
        : null;
    final upColor =
        upside == null ? c.textSubtle : (upside >= 0 ? c.positive : c.negative);

    String fmt(double? v) =>
        v == null ? '—' : '$pre${formatMoney(v, decimals: 2)}';

    // Skala alanı analist [low, high] + GÜNCEL fiyatı da kapsar: hisse tüm
    // hedeflerin üstünde/altındaysa nokta uçta üst üste binmesin, "aralık
    // dışında" doğru okunsun. %4 nefes payı.
    final domainPts =
        [low, high, mean, cur].whereType<double>().toList(growable: false);
    final dMin =
        domainPts.isEmpty ? 0.0 : domainPts.reduce((a, b) => a < b ? a : b);
    final dMax =
        domainPts.isEmpty ? 1.0 : domainPts.reduce((a, b) => a > b ? a : b);
    final dPad = (dMax - dMin) * 0.04;
    final lo = dMin - dPad;
    final hi = dMax + dPad;

    double pos(double? v) {
      if (v == null || hi <= lo) return 0;
      return ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    }

    final upText = upside == null
        ? null
        : (upside >= 0
            ? '▲ %${formatPct(upside, decimals: 1)} potansiyel'
            : '▼ %${formatPct(upside.abs(), decimals: 1)} risk');

    // Değere yapışık fiyat etiketi (grafikteki price-tag diline benzer).
    Widget chip(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(text,
              style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('12 AYLIK FİYAT HEDEFİ',
                    style: TextStyle(
                        color: c.textSubtle,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6)),
              ),
              if (upText != null)
                Text(upText,
                    style: TextStyle(
                        color: upColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2)),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (ctx, bc) {
            final w = bc.maxWidth;
            const lw = 110.0; // etiket şeridi (clamp lane'i)
            final pc = pos(cur);
            final pm = pos(mean);
            final cx = pc * w;
            final mx = pm * w;
            final segL = (pc < pm ? pc : pm) * w;
            final segR = (pc < pm ? pm : pc) * w;
            const barTop = 62.0;
            const barH = 10.0;
            const barMid = barTop + barH / 2;

            double laneLeft(double x) => (x - lw / 2).clamp(0.0, w - lw);

            return SizedBox(
              height: 134,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // ── GÜNCEL: caption + chip + bağlantı çizgisi (çubuğun üstü)
                  if (cur != null) ...[
                    Positioned(
                      top: 0,
                      left: laneLeft(cx),
                      width: lw,
                      child: Column(
                        children: [
                          Text('GÜNCEL',
                              style: TextStyle(
                                  color: c.textSubtle,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          chip(fmt(cur), c.textPrimary, c.surface),
                        ],
                      ),
                    ),
                    Positioned(
                      left: (cx - 1).clamp(0.0, w - 2),
                      top: 40,
                      child: Container(
                          width: 2, height: barMid - 40, color: c.textSubtle),
                    ),
                  ],
                  // ── Track (düşük→yüksek ısı gradyanı)
                  Positioned(
                    top: barTop,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: barH,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(barH / 2),
                        gradient: LinearGradient(
                          colors: [
                            c.surfaceAlt,
                            c.warmAccent.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Güncel → hedef arası: beklenen hareket
                  if (cur != null && mean != null)
                    Positioned(
                      top: barTop,
                      left: segL,
                      width: (segR - segL).clamp(0.0, w),
                      child: Container(
                        height: barH,
                        decoration: BoxDecoration(
                          color: c.warmAccent,
                          borderRadius: BorderRadius.circular(barH / 2),
                        ),
                      ),
                    ),
                  // Uç çentikleri (skala hissi)
                  for (final ex in [0.0, w - 2])
                    Positioned(
                      left: ex,
                      top: barTop - 3,
                      child: Container(
                          width: 2, height: barH + 6, color: c.surfaceAlt),
                    ),
                  // Güncel nokta — surface halkalı (Border.all'sız knockout)
                  if (cur != null) ...[
                    Positioned(
                      left: (cx - 9).clamp(0.0, w - 18),
                      top: barMid - 9,
                      child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                              color: c.surface, shape: BoxShape.circle)),
                    ),
                    Positioned(
                      left: (cx - 6).clamp(3.0, w - 15),
                      top: barMid - 6,
                      child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                              color: c.textPrimary, shape: BoxShape.circle)),
                    ),
                  ],
                  // Ortalama hedef noktası — altın, surface halkalı
                  if (mean != null) ...[
                    Positioned(
                      left: (mx - 12).clamp(0.0, w - 24),
                      top: barMid - 12,
                      child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                              color: c.surface, shape: BoxShape.circle)),
                    ),
                    Positioned(
                      left: (mx - 9).clamp(3.0, w - 21),
                      top: barMid - 9,
                      child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                              color: c.warmAccent, shape: BoxShape.circle)),
                    ),
                    // bağlantı çizgisi + chip (çubuğun altı)
                    Positioned(
                      left: (mx - 1).clamp(0.0, w - 2),
                      top: barMid,
                      child: Container(
                          width: 2, height: 92 - barMid, color: c.warmAccent),
                    ),
                    Positioned(
                      top: 92,
                      left: laneLeft(mx),
                      width: lw,
                      child: Column(
                        children: [
                          chip(fmt(mean), c.warmAccent, c.surface),
                          const SizedBox(height: 4),
                          Text('ORTALAMA HEDEF',
                              style: TextStyle(
                                  color: c.textSubtle,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('En düşük  ${fmt(low)}',
                  style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              Text('${fmt(high)}  En yüksek',
                  style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recBar(BuildContext context, Map rec) {
    final c = AppColorsExt.of(context);
    int g(String k) => (rec[k] as num?)?.toInt() ?? 0;
    final buy = g('strongBuy') + g('buy');
    final hold = g('hold');
    final sell = g('sell') + g('strongSell');
    final total = buy + hold + sell;
    if (total == 0) return const SizedBox.shrink();
    final label =
        buy >= hold && buy >= sell ? 'AL' : (sell >= hold ? 'SAT' : 'TUT');
    final lc = label == 'AL'
        ? c.positive
        : (label == 'SAT' ? c.negative : c.warmAccent);

    Widget seg(int n, Color color) => n == 0
        ? const SizedBox.shrink()
        : Expanded(flex: n, child: Container(height: 8, color: color));

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
              Expanded(
                child: Text('Analist Tavsiyesi',
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              Text('Çoğunluk: $label',
                  style: TextStyle(
                      color: lc, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(children: [
              seg(buy, c.positive),
              seg(hold, c.warmAccent),
              seg(sell, c.negative),
            ]),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legend(context, c.positive, 'Al', buy),
              const SizedBox(width: 16),
              _legend(context, c.warmAccent, 'Tut', hold),
              const SizedBox(width: 16),
              _legend(context, c.negative, 'Sat', sell),
              const Spacer(),
              Text('$total analist',
                  style: TextStyle(color: c.textSubtle, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label, int n) {
    final c = AppColorsExt.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text('$label $n',
            style: TextStyle(
                color: c.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _estCard(BuildContext context, String title, List rows,
      String Function(double) fmt) {
    final c = AppColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  color: c.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4)),
        ),
        IOSGroupedCard(
          children: [
            for (final r in rows)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((r as Map)['period'].toString(),
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            '${r['low'] != null ? fmt((r['low'] as num).toDouble()) : '—'}'
                            ' – ${r['high'] != null ? fmt((r['high'] as num).toDouble()) : '—'}'
                            '${r['analysts'] != null ? '  ·  ${r['analysts']} analist' : ''}',
                            style: TextStyle(color: c.textSubtle, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          r['avg'] != null
                              ? fmt((r['avg'] as num).toDouble())
                              : '—',
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2),
                        ),
                        if (r['growth_pct'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${(r['growth_pct'] as num) >= 0 ? '+' : ''}${formatPct((r['growth_pct'] as num).toDouble(), decimals: 1)}% yıllık',
                              style: TextStyle(
                                  color: (r['growth_pct'] as num) >= 0
                                      ? c.positive
                                      : c.negative,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FullscreenBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _FullscreenBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.warmAccentSoft,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_full, size: 14, color: c.warmAccent),
              const SizedBox(width: 6),
              Text('Pro',
                  style: TextStyle(
                      color: c.warmAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1)),
            ],
          ),
        ),
      ),
    );
  }
}
