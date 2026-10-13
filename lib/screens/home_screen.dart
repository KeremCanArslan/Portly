import 'dart:async';
import 'package:portly/utils/money.dart';
import 'package:portly/widgets/load_error_card.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/models/holding.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/screens/stock_detail_screen.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/widgets/stock_card.dart';

/// Apple Stocks tarzı sadeleştirilmiş ana ekran:
/// - Editorial üst (greeting + hero portföy)
/// - İzleme listesi (the meat)
/// - Daha fazla — grouped link cards
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortfolioProvider>();
    final auth = context.watch<AuthProvider>();
    final c = AppColorsExt.of(context);
    final displayName = auth.fullName?.split(' ').first ?? 'Yatırımcı';
    final totalAsset = provider.totalAssetValue;
    final range = provider.perfRange;
    // Hafta/Ay sunucudan gelir; henüz gelmediyse null → "—" gösterilir
    // (0 basmak "hiç değişmemiş" diye okunurdu).
    final pnl = provider.rangePnl;
    final pnlPct = provider.rangePnlPercent;
    final hasPerf = pnl != null && pnlPct != null;
    final isProfit = (pnl ?? 0) >= 0;
    final hasHoldings = provider.myHoldings.isNotEmpty;
    final dataColor = isProfit ? c.positive : c.negative;
    const rangeLabel = {
      PerfRange.total: 'Toplam',
      PerfRange.daily: 'Bugün',
      PerfRange.week: 'Bu hafta',
      PerfRange.month: 'Bu ay',
    };

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: c.textPrimary,
          backgroundColor: c.surface,
          onRefresh: () => provider.refreshAll(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Editorial karşılama + hero portföy
                      Text(
                        'Merhaba, $displayName',
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 15,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Portföyün',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.2,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Midas tarzı: büyük tutara dokununca ₺↔$ döner (ayrı
                      // segmented toggle kaldırıldı). Kur yoksa dokunma pasif.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: provider.usdTryRate != null
                            ? provider.toggleDisplayCurrency
                            : null,
                        child: _money(context, provider, totalAsset,
                            size: 44, weight: FontWeight.w700, dim: true),
                      ),
                      if (provider.usdTryRate != null) ...[
                        const SizedBox(height: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: provider.toggleDisplayCurrency,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.swap_horiz_rounded,
                                  size: 14, color: c.textSubtle),
                              const SizedBox(width: 5),
                              Text(
                                provider.showUsd
                                    ? 'USD · ₺ için dokun'
                                    : 'TL · \$ için dokun',
                                style: TextStyle(
                                  color: c.textSubtle,
                                  fontSize: 12,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (hasHoldings)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: hasPerf ? dataColor : c.surfaceAlt,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                hasPerf
                                    ? '${formatPctSigned(pnlPct, decimals: 2)}%'
                                    : '—',
                                style: TextStyle(
                                  color: hasPerf ? Colors.white : c.textSubtle,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (hasPerf)
                              _money(context, provider, pnl.abs(),
                                  size: 13,
                                  weight: FontWeight.w400,
                                  letterSpacing: -0.1,
                                  color: c.textMuted,
                                  prefix: isProfit ? '+' : '−'),
                            Text(
                              hasPerf
                                  ? '  ·  ${rangeLabel[range]}'
                                  : (provider.perfLoading
                                      ? '${rangeLabel[range]} hesaplanıyor…'
                                      : '${rangeLabel[range]} verisi yok'),
                              style: TextStyle(
                                color: c.textMuted,
                                fontSize: 13,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          'Portföyünü ekle, takibe başlayalım',
                          style: TextStyle(
                            color: c.textMuted,
                            fontSize: 13,
                            letterSpacing: -0.1,
                          ),
                        ),
                      if (hasHoldings) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 340,
                          child: IOSSegmented<PerfRange>(
                            value: range,
                            options: const [
                              (PerfRange.total, 'Toplam'),
                              (PerfRange.daily, 'Bugün'),
                              (PerfRange.week, 'Hafta'),
                              (PerfRange.month, 'Ay'),
                            ],
                            onChange: provider.setPerfRange,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      // Belirgin arama — herhangi bir hisse/kripto/dövizin
                      // grafiğini izleme listesine EKLEMEDEN açar (sonuca
                      // dokun → detay/grafik). Eskiden yalnız "+" ikonunun
                      // arkasındaydı, kullanıcı arama butonu bulamıyordu.
                      _buildSearchBar(context),
                      const SizedBox(height: 30),

                      // İzleme listesi başlığı
                      Row(
                        children: [
                          Text(
                            'İzleme Listem',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const Spacer(),
                          _AddIconButton(
                              onTap: () => _showAddStockSheet(context)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sola kaydır → sil  ·  Uzun bas + sürükle → sırala',
                        style: TextStyle(
                          color: c.textSubtle,
                          fontSize: 11,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 14),

                      EliteFade(
                        child: provider.isLoading
                            ? Column(
                                key: const ValueKey('wl-loading'),
                                children: const [
                                  Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8),
                                      child: EliteSkeleton(height: 52)),
                                  Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8),
                                      child: EliteSkeleton(height: 52)),
                                  Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8),
                                      child: EliteSkeleton(height: 52)),
                                  Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8),
                                      child: EliteSkeleton(height: 52)),
                                  Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8),
                                      child: EliteSkeleton(height: 52)),
                                ],
                              )
                            : provider.marketData.isEmpty &&
                                    provider.marketError != null
                                // Sembol var ama fiyat gelmedi → "Listen boş"
                                // demek yanlış; sebebi söyle, tekrar dene.
                                ? Padding(
                                    key: const ValueKey('wl-error'),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 8),
                                    child: LoadErrorCard(
                                      title: 'Fiyatlar alınamadı',
                                      onRetry: () => provider.loadMarketData(),
                                    ),
                                  )
                                : provider.marketData.isEmpty
                                    ? Padding(
                                        key: const ValueKey('wl-empty'),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 36, horizontal: 8),
                                        child: Center(
                                          child: Column(
                                            children: [
                                              Icon(Icons.show_chart_rounded,
                                                  size: 36,
                                                  color: c.textSubtle),
                                              const SizedBox(height: 10),
                                              Text(
                                                'Listen boş',
                                                style: TextStyle(
                                                  color: c.textPrimary,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '+ ile ilk hisseyi ekle',
                                                style: TextStyle(
                                                  color: c.textMuted,
                                                  fontSize: 13,
                                                  letterSpacing: -0.1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : ReorderableListView(
                                        key: const ValueKey('wl-list'),
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        buildDefaultDragHandles: false,
                                        proxyDecorator: (child, _, __) =>
                                            Material(
                                          color: Colors.transparent,
                                          child: Transform.scale(
                                              scale: 1.01, child: child),
                                        ),
                                        onReorder: (oldIndex, newIndex) =>
                                            provider.reorderWatchlist(
                                                oldIndex, newIndex),
                                        children: [
                                          for (int i = 0;
                                              i < provider.marketData.length;
                                              i++)
                                            ReorderableDelayedDragStartListener(
                                              key: ValueKey(provider
                                                  .marketData[i].symbol),
                                              index: i,
                                              child: StockCard(
                                                  data: provider.marketData[i]),
                                            ),
                                        ],
                                      ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ₺ değeri al; gerekiyorsa canlı kurla $'a çevir; ortak MoneyText ile çiz.
  // Küsürat yalnız büyük hero rakamlarında soluk (dim) gösterilir.
  static Widget _money(
    BuildContext context,
    PortfolioProvider p,
    double tryValue, {
    required double size,
    required FontWeight weight,
    double letterSpacing = -1.5,
    Color? color,
    String prefix = '',
    bool dim = false,
  }) {
    final useUsd = p.showUsd && p.usdTryRate != null;
    final v = useUsd ? tryValue / p.usdTryRate! : tryValue;
    return MoneyText(
      v,
      currency: useUsd ? '\$' : '₺',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      dimDecimals: dim,
      prefix: prefix,
    );
  }

  // Ana ekran belirgin arama çubuğu — dokununca "Hisse Ara" sheet'i açar.
  // Sağdaki "grafiğe bak" ipucu, sonucu izleme listesine eklemeden
  // grafiğini görebileceğini belli eder.
  Widget _buildSearchBar(BuildContext context) {
    final c = AppColorsExt.of(context);
    return GestureDetector(
      onTap: () => _showAddStockSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: c.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Hisse, kripto veya döviz ara',
                style: TextStyle(
                    color: c.textMuted, fontSize: 14.5, letterSpacing: -0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddStockSheet(BuildContext context) {
    showIOSBottomSheet(
      context: context,
      title: 'Hisse Ara',
      child: const _AddStockSheetBody(),
    );
  }
}

class _AddIconButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddIconButton({required this.onTap});

  @override
  State<_AddIconButton> createState() => _AddIconButtonState();
}

class _AddIconButtonState extends State<_AddIconButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hover ? c.surfaceAlt : c.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.add_rounded, color: c.textPrimary, size: 20),
        ),
      ),
    );
  }
}

class _AddStockSheetBody extends StatefulWidget {
  const _AddStockSheetBody();

  @override
  State<_AddStockSheetBody> createState() => _AddStockSheetBodyState();
}

class _AddStockSheetBodyState extends State<_AddStockSheetBody> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String _filter = 'ALL';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final r = await ApiService().searchStocks(v);
      if (mounted) {
        setState(() {
          _results = r;
          _searching = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final filtered = _filter == 'ALL'
        ? _results
        : _results.where((s) {
            final m = (s['market'] as String?) ?? '';
            if (_filter == 'NASDAQ') return m == 'NASDAQ' || m == 'NYSE';
            return m == _filter;
          }).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search field
            Container(
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.search, color: c.textSubtle, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: _onChanged,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15,
                        letterSpacing: -0.1,
                      ),
                      cursorColor: c.textPrimary,
                      decoration: InputDecoration(
                        hintText: 'Sembol veya şirket ara',
                        hintStyle: TextStyle(
                          color: c.textSubtle,
                          fontSize: 15,
                          letterSpacing: -0.1,
                        ),
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  if (_searching)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Market filter segmented
            IOSSegmented<String>(
              options: const [
                ('ALL', 'Tümü'),
                ('BIST', 'BIST'),
                ('NASDAQ', 'ABD'),
                ('CRYPTO', 'Kripto'),
                ('ETF', 'ETF'),
              ],
              value: _filter,
              onChange: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _controller.text.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'BIST, NASDAQ ve kripto piyasalarında arayabilirsin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 13,
                          letterSpacing: -0.1,
                        ),
                      ),
                    )
                  : filtered.isEmpty && !_searching
                      ? Center(
                          child: Text(
                            'Eşleşme bulunamadı',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 13,
                              letterSpacing: -0.1,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const EliteHairline(indent: 16),
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final symbol = s['symbol'] as String? ?? '';
                            final name = s['name'] as String? ?? symbol;
                            final market = s['market'] as String? ?? '';
                            return InkWell(
                              // Satıra dokun → izleme listesine EKLEMEDEN
                              // doğrudan grafiği/detayı aç.
                              onTap: () async {
                                final nav = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(context);
                                final stock =
                                    await ApiService().fetchSingleStock(symbol);
                                nav.pop();
                                if (stock == null) {
                                  messenger.showSnackBar(SnackBar(
                                      content:
                                          Text('$symbol verisi alınamadı')));
                                  return;
                                }
                                nav.push(MaterialPageRoute(
                                  builder: (_) =>
                                      StockDetailScreen(stockData: stock),
                                ));
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 12),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      child: Text(
                                        market,
                                        style: TextStyle(
                                          color: c.textSubtle,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            // Ham sembol kullanıcıya anlamsız:
                                            // "CEYREK.ALTIN" / "TLY.FON" yerine
                                            // "Çeyrek Altın" / "TLY". Uygulamanın
                                            // geri kalanı zaten compact() kullanıyor.
                                            SymbolDisplay.compact(symbol),
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.1,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: c.textMuted,
                                              fontSize: 12,
                                              letterSpacing: -0.1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _WatchlistAddButton(symbol: symbol),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// İzleme listesine ekle butonu — basınca: (1) telefonda klavyeyi kapatır,
/// (2) ikon + ikon → check'e bounce animasyonu, (3) modalın ÖNÜNDE duran
/// overlay toast bildirimi gösterir (SnackBar bottom sheet'in arkasında kalıyordu).
class _WatchlistAddButton extends StatefulWidget {
  final String symbol;
  const _WatchlistAddButton({required this.symbol});

  @override
  State<_WatchlistAddButton> createState() => _WatchlistAddButtonState();
}

class _WatchlistAddButtonState extends State<_WatchlistAddButton> {
  bool _busy = false;
  bool _added = false;

  Future<void> _handleTap() async {
    if (_busy) return;
    // (3) Telefonda klavyeyi kapat — sheet'in altındaki içerik görünür olsun.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);

    final added =
        await context.read<PortfolioProvider>().addToWatchlist(widget.symbol);
    if (!mounted) return;

    // (2) Başarı animasyonu: ikon check'e döner + hafif büyür.
    setState(() {
      _busy = false;
      _added = true;
    });
    // (1) Modalın önünde duran bildirim.
    _showWatchlistToast(
      context,
      added
          ? '${SymbolDisplay.compact(widget.symbol)} listene eklendi'
          : '${SymbolDisplay.compact(widget.symbol)} zaten listende',
      positive: added,
    );

    // Kısa süre sonra + ikonuna geri dön.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _added = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _added ? 1.22 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _added
                  ? c.positive.withValues(alpha: 0.16)
                  : c.warmAccentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                _added ? Icons.check_rounded : Icons.add_rounded,
                key: ValueKey<bool>(_added),
                color: _added ? c.positive : c.warmAccent,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Root overlay'e (modal bottom sheet'in ÜSTÜNE) animasyonlu kısa bildirim basar.
/// SnackBar modal route'un arkasında kalıyordu; rootOverlay her şeyin önünde.
void _showWatchlistToast(BuildContext context, String message,
    {bool positive = true}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _WatchlistToast(
      message: message,
      positive: positive,
      onDismissed: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _WatchlistToast extends StatefulWidget {
  final String message;
  final bool positive;
  final VoidCallback onDismissed;
  const _WatchlistToast({
    required this.message,
    required this.positive,
    required this.onDismissed,
  });

  @override
  State<_WatchlistToast> createState() => _WatchlistToastState();
}

class _WatchlistToastState extends State<_WatchlistToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1900), () async {
      if (!mounted) return;
      await _ctrl.reverse();
      widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.of(context).viewInsets.bottom + 36,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(curved),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.positive
                            ? Icons.check_circle_rounded
                            : Icons.info_rounded,
                        color: widget.positive ? c.positive : c.warmAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
