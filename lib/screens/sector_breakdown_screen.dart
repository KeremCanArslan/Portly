import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/widgets/allocation_donut.dart';

class SectorBreakdownScreen extends StatefulWidget {
  final bool embedded;
  const SectorBreakdownScreen({super.key, this.embedded = false});

  @override
  State<SectorBreakdownScreen> createState() => _SectorBreakdownScreenState();
}

class _SectorBreakdownScreenState extends State<SectorBreakdownScreen> {
  // Sekme (Liste/Hisseler/Sektör/Borsa) değişince bu ekran yeniden kurulup
  // initState'te tekrar istek atıyordu → her sekme dönüşünde 1-2 sn spinner.
  // Sektör dağılımı dakikalar içinde anlamlı değişmez; kısa ömürlü paylaşılan
  // cache ile dönüş anında açılır. Sayfa yenilemesi (_load(force: true))
  // cache'i atlar.
  static const Duration _cacheTtl = Duration(minutes: 2);
  static int? _cachedUserId;
  static List<dynamic>? _cachedSectors;
  static DateTime? _cachedAt;

  final ApiService _api = ApiService();
  bool _loading = true;
  bool _error = false;
  List<dynamic> _sectors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final userId = context.read<PortfolioProvider>().userId;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    if (!force &&
        _cachedUserId == userId &&
        _cachedSectors != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      setState(() {
        _sectors = _cachedSectors!;
        _loading = false;
        _error = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final data = await _api.fetchSectorBreakdown(userId);
      if (!mounted) return;
      final sectors = data['sectors'] as List? ?? [];
      _cachedUserId = userId;
      _cachedSectors = sectors;
      _cachedAt = DateTime.now();
      setState(() {
        _sectors = sectors;
        _loading = false;
      });
    } catch (_) {
      // Geçici hata/timeout: boş-state DEĞİL, "Tekrar Dene" göster.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    final content = _loading
        ? Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: CircularProgressIndicator(color: c.textPrimary),
            ),
          )
        : _error
            ? Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 38, color: c.textSubtle),
                    const SizedBox(height: 14),
                    Text(
                      'Sektör dağılımı yüklenemedi.',
                      style: TextStyle(
                          color: c.textMuted,
                          fontSize: 14,
                          letterSpacing: -0.1),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => _load(force: true),
                      style:
                          TextButton.styleFrom(foregroundColor: c.textPrimary),
                      child: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              )
            : _sectors.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pie_chart_outline_rounded,
                            size: 38, color: c.textSubtle),
                        const SizedBox(height: 14),
                        Text(
                          'Sektör dağılımı için en az bir hisse pozisyonu gerekli.',
                          style: TextStyle(
                              color: c.textMuted,
                              fontSize: 14,
                              letterSpacing: -0.1),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AllocationDonut(
                        items: [
                          for (final s in _sectors)
                            (
                              label:
                                  (s as Map<String, dynamic>)['name'] as String,
                              value: (s['value'] as num).toDouble(),
                            ),
                        ],
                        centerUnit: 'sektör',
                        // Dilime dokununca içindeki hisseler aynı donut'ta
                        // açılır — "Diğer"de ne olduğu görünsün diye.
                        breakdowns: _memberMap(),
                      ),
                      const SizedBox(height: 12),
                      _buildConcentrationWarning(),
                    ],
                  );

    if (widget.embedded) return content;

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
        title: Text('Sektör Dağılımı',
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
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              children: [content],
            ),
          ),
        ),
      ),
    );
  }

  /// Sektör adı → içindeki pozisyonlar (backend `members`). Sembol yerine
  /// donut'un kendi kısa gösterimi kullanılır ki alt görünüm üst görünümle
  /// aynı dili konuşsun.
  Map<String, List<({String label, double value})>> _memberMap() {
    final out = <String, List<({String label, double value})>>{};
    for (final raw in _sectors) {
      final s = raw as Map<String, dynamic>;
      final members = s['members'] as List?;
      if (members == null || members.length < 2) continue;
      out[s['name'] as String] = [
        for (final m in members)
          (
            label: SymbolDisplay.compact((m as Map<String, dynamic>)['symbol']
                as String),
            value: (m['value'] as num).toDouble(),
          ),
      ];
    }
    return out;
  }

  Widget _buildConcentrationWarning() {
    final c = AppColorsExt.of(context);
    if (_sectors.isEmpty) return const SizedBox.shrink();
    final topSector = _sectors.first as Map<String, dynamic>;
    final topPct = (topSector['percent'] as num).toDouble();
    final ok = topPct < 50;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: ok ? c.positive : c.warmAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok
                  ? 'Portföyün dengeli dağılmış. Konsantrasyon riski düşük.'
                  : 'Portföyünün %${topPct.toStringAsFixed(0)}\'i tek sektörde (${topSector['name']}). Çeşitlendirme önerilir.',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 13,
                height: 1.5,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
