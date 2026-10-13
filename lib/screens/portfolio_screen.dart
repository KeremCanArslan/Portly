import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/widgets/load_error_card.dart';
import 'package:portly/providers/chat_provider.dart';
import 'package:portly/screens/chat_screen.dart';
import 'package:portly/screens/behavior_screen.dart';
import 'package:portly/screens/stress_test_screen.dart';
import 'package:portly/screens/missions_screen.dart';
import 'package:portly/screens/gold_rates_screen.dart';
import 'package:portly/screens/stock_detail_screen.dart';
import 'package:portly/screens/import_portfolio_screen.dart';
import 'package:portly/screens/import_statement_screen.dart';
import 'package:portly/screens/sector_breakdown_screen.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/screens/transaction_history_screen.dart';
import 'package:portly/screens/risk_profile_test_screen.dart';
import 'package:portly/screens/ai_portfolio_builder_screen.dart';
import 'package:portly/screens/ta_quiz_screen.dart';
import 'package:portly/screens/education_screen.dart';
import 'package:portly/screens/what_if_screen.dart';
import 'package:portly/screens/dividend_screen.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/widgets/benchmark_widget.dart';
import 'package:portly/widgets/portfolio_health_card.dart';
import 'package:portly/widgets/holdings_allocation_card.dart';
import 'package:portly/widgets/exchange_allocation_card.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/utils/haptics.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/utils/app_tabs.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

/// Pozisyon listesinin sıralama ölçütü. `exchange` bugünkü davranıştır
/// (borsaya göre gruplu); diğerleri düz tek liste verir — "en büyük payım
/// hangisi / bugün ne oldu / toplamda ne kazandım" soruları grup sınırlarını
/// aşar, gruplu gösterim o soruların cevabını böler.
enum HoldingSort { exchange, weight, daily, total }

class _PortfolioScreenState extends State<PortfolioScreen> {
  int _viewMode = 0; // 0=Liste, 1=Hisseler, 2=Sektör, 3=Borsa
  static const _sortPrefKey = 'portfolio_holding_sort';
  HoldingSort _sort = HoldingSort.exchange;
  // İlk başarılı yüklemeden sonra refresh'ler "sessiz" — skeleton'a dönmüyoruz,
  // ListView ayakta kalıyor, scroll konumu korunuyor. (Refresh spinner zaten
  // RefreshIndicator'da gösteriliyor; ikinci skeleton swap = scroll sıfırlanır.)
  bool _everLoaded = false;

  @override
  void initState() {
    super.initState();
    _restoreSortPreference();
  }

  Future<void> _restoreSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_sortPrefKey);
    if (saved == null || !mounted) return;
    final match = HoldingSort.values.where((v) => v.name == saved);
    if (match.isNotEmpty) setState(() => _sort = match.first);
  }

  Future<void> _applySort(HoldingSort sort) async {
    setState(() => _sort = sort);
    Haptics.selection();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefKey, sort.name);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortfolioProvider>();
    final c = AppColorsExt.of(context);
    if (!provider.isPortfolioLoading) _everLoaded = true;
    // Diskteki son portföy varsa ONU göster — iskelet yalnız gerçekten
    // gösterecek hiçbir şey yokken çıksın (soğuk backend 50sn+ uyanabiliyor).
    final showSkeleton = provider.isPortfolioLoading &&
        !_everLoaded &&
        provider.myHoldings.isEmpty;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: showSkeleton
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: const [
                        EliteSkeleton(height: 140, radius: EliteRadii.md),
                        SizedBox(height: 14),
                        EliteSkeleton(height: 56, radius: EliteRadii.md),
                        SizedBox(height: 18),
                        EliteSkeleton(height: 76, radius: EliteRadii.md),
                        SizedBox(height: 10),
                        EliteSkeleton(height: 76, radius: EliteRadii.md),
                        SizedBox(height: 10),
                        EliteSkeleton(height: 76, radius: EliteRadii.md),
                        SizedBox(height: 10),
                        EliteSkeleton(height: 76, radius: EliteRadii.md),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: c.textPrimary,
                    backgroundColor: c.surface,
                    onRefresh: () => provider.refreshAll(),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      children: [
                        _buildEditorialHero(provider),
                        const SizedBox(height: 28),
                        // Yeni kullanıcı yönlendirmesi: pozisyon yokken "ne
                        // yapacağım?" anını giderir (3 somut adım). Pozisyon
                        // gelince kendiliğinden kaybolur.
                        // Pozisyon yoksa iki ayrı sebep var: kullanıcı
                        // gerçekten hiç eklememiş VEYA istek başarısız oldu.
                        // İkincisinde "BAŞLANGIÇ" rehberi yalan söylüyordu.
                        if (provider.myHoldings.isEmpty) ...[
                          if (provider.portfolioError != null)
                            LoadErrorCard(
                              title: 'Portföy yüklenemedi',
                              icon: Icons.cloud_off_rounded,
                              onRetry: () => provider.loadMyPortfolio(),
                            )
                          else
                            _buildGettingStarted(context),
                          const SizedBox(height: 16),
                        ],
                        IOSGroupedCard(
                          children: [
                            IOSListRow(
                              icon: Icons.playlist_add_rounded,
                              title: 'Portföyümü Gir',
                              subtitle:
                                  'Başka yerdeki pozisyonlarını lot + maliyetle içe aktar',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const ImportPortfolioScreen()),
                              ),
                            ),
                            IOSListRow(
                              icon: Icons.description_outlined,
                              title: 'Ekstreden İçe Aktar',
                              subtitle:
                                  'Midas PDF ekstreni yükle; adet, maliyet ve '
                                  'işlem geçmişi birebir okunsun',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const ImportStatementScreen()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const EliteSectionLabel('Profil & Geçmiş'),
                        _buildProfileAndHistoryCard(context),
                        const SizedBox(height: 16),
                        const EliteSectionLabel('AI & Pratik'),
                        _buildAiToolsCard(context),
                        const SizedBox(height: 18),
                        const BenchmarkWidget(),
                        const SizedBox(height: 18),
                        const PortfolioHealthCard(),
                        const SizedBox(height: 22),
                        IOSSegmented<int>(
                          options: const [
                            (0, 'Liste'),
                            (1, 'Hisseler'),
                            (2, 'Sektör'),
                            (3, 'Borsa'),
                          ],
                          value: _viewMode,
                          onChange: (v) => setState(() => _viewMode = v),
                        ),
                        const SizedBox(height: 18),
                        if (_viewMode == 0)
                          ..._buildListView(context, provider)
                        else if (_viewMode == 1)
                          const HoldingsAllocationCard()
                        else if (_viewMode == 2)
                          const SectorBreakdownScreen(embedded: true)
                        else
                          const ExchangeAllocationCard(),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────── editorial hero
  // ₺ değeri al; showUsd ise canlı kurla $'a çevir. Toplam/nakit gibi
  // büyük rakamlarda dim=true (küsürat soluk); hisse/satır rakamlarında dim yok.
  Widget _money(
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

  Widget _currencyHint(PortfolioProvider p) {
    if (p.usdTryRate == null) return const SizedBox.shrink();
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        p.showUsd ? 'USD · ₺ için dokun' : '₺ · USD için dokun',
        style:
            TextStyle(color: c.textSubtle, fontSize: 11, letterSpacing: -0.1),
      ),
    );
  }

  Widget _buildEditorialHero(PortfolioProvider provider) {
    final c = AppColorsExt.of(context);
    final total = provider.totalAssetValue;
    final hasHoldings = provider.myHoldings.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Toplam Varlık',
          style: TextStyle(
            color: c.textMuted,
            fontSize: 14,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: provider.toggleDisplayCurrency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _money(provider, total,
                  size: 46,
                  weight: FontWeight.w700,
                  letterSpacing: -1.6,
                  dim: true,
                  color: c.textPrimary),
              _currencyHint(provider),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (hasHoldings) ...[
          _pnlLine(
              provider, 'Bugün', provider.dailyPnl, provider.dailyPnlPercent),
          _pnlLine(
              provider, 'Toplam', provider.totalPnl, provider.totalPnlPercent),
          // USD pozisyonların ₺ maliyeti ALIŞ günündeki kurla tutuluyor →
          // kurdan gelen kâr toplam K/Z'nin içinde. Kullanıcı "hisse mi
          // kazandırdı, kur mu" diye sorabilsin diye kur payı ayrı yazılır.
          // Etkisi önemsizse (toplamın %1'inden azı) satır hiç çıkmaz.
          if (provider.totalFxGain.abs() > provider.totalPnl.abs() * 0.01 + 1)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: Text(
                      'Kur payı',
                      style: TextStyle(
                        color: c.textSubtle,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  _money(provider, provider.totalFxGain.abs(),
                      size: 13,
                      weight: FontWeight.w400,
                      letterSpacing: -0.1,
                      color: c.textMuted,
                      prefix: provider.totalFxGain >= 0 ? '+' : '−'),
                ],
              ),
            ),
          // Fiyatı alınamayan pozisyonlar toplamı EKSİK bırakır (o satırlar
          // maliyetle sayılır) → toplamı olduğundan doğru sanmasın diye
          // sayıyı açıkça söyle. Hepsi canlıysa bu satır hiç çıkmaz.
          if (provider.unpricedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${provider.unpricedCount} pozisyonun güncel fiyatı alınamadı '
                '— bu satırlar maliyetle sayıldı',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 11.5,
                  letterSpacing: -0.1,
                ),
              ),
            ),
        ] else
          Text(
            'Henüz pozisyonun yok',
            style: TextStyle(
              color: c.textMuted,
              fontSize: 13,
              letterSpacing: -0.1,
            ),
          ),
      ],
    );
  }

  // Bugün / Toplam PnL satırı — etiket + %badge + tutar (ana sayfayla aynı dil).
  Widget _pnlLine(
      PortfolioProvider provider, String label, double pnl, double pnlPct) {
    final c = AppColorsExt.of(context);
    final isProfit = pnl >= 0;
    final dataColor = isProfit ? c.positive : c.negative;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              label,
              style: TextStyle(
                color: c.textSubtle,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: dataColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '${formatPctSigned(pnlPct, decimals: 2)}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _money(provider, pnl.abs(),
              size: 13,
              weight: FontWeight.w400,
              letterSpacing: -0.1,
              color: c.textMuted,
              prefix: isProfit ? '+' : '−'),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────── başlangıç rehberi (boş portföy)
  // Yeni kullanıcının "ne yapacağım?" anını giderir: kısa bilgilendirme +
  // 3 somut, dokunulabilir adım. Mevcut görsel dil (etiket + gruplu kart);
  // çift kart sarmalaması yok.
  Widget _buildGettingStarted(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flag_outlined, size: 16, color: c.warmAccent),
            const SizedBox(width: 7),
            Text(
              'BAŞLANGIÇ',
              style: TextStyle(
                color: c.textSubtle,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 8, bottom: 12),
          child: Text(
            'Gerçek portföyünü ekle; haberlerini tek yerden izle, teknik + '
            'temel analize dayalı alım-satım sinyalleri al. Şuradan başla:',
            style: TextStyle(color: c.textMuted, fontSize: 12.5, height: 1.5),
          ),
        ),
        IOSGroupedCard(
          children: [
            // En hızlı yol en üstte: elle 38 satır girmek yerine aracı kurum
            // ekranının görüntüsü. (Yalnız web — OCR yolu dart:html'e bağlı,
            // mobil derlemede o buton zaten gizli.)
            if (kIsWeb)
              IOSListRow(
                icon: Icons.auto_awesome_outlined,
                title: 'Ekran görüntüsünden aktar',
                subtitle: 'Midas / aracı kurum portföy ekranının görüntüsünü '
                    'yükle; lot ve maliyeti AI doldursun',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ImportPortfolioScreen()),
                ),
              ),
            IOSListRow(
              icon: Icons.playlist_add_rounded,
              title: 'Portföyünü elle ekle',
              subtitle: 'Hisselerini lot + maliyetle gir '
                  '(PDF ekstre de yüklenebilir)',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ImportPortfolioScreen()),
              ),
            ),
            IOSListRow(
              icon: Icons.insights_rounded,
              title: 'Sinyalleri gör',
              subtitle: 'Sembollerin için AL/TUT/SAT taraması',
              onTap: () => kRequestedTab.value = 2, // → Sinyaller sekmesi
            ),
            IOSListRow(
              icon: Icons.psychology_outlined,
              title: 'Risk profilini belirle',
              subtitle: '2 dakikalık testle yatırımcı tipini öğren',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const RiskProfileTestScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── profil & history grouped
  Widget _buildProfileAndHistoryCard(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.riskProfile;
    final hasProfile = profile != null && profile.isNotEmpty;

    return IOSGroupedCard(
      children: [
        IOSListRow(
          icon: Icons.psychology_outlined,
          title: hasProfile ? 'Risk Profili: $profile' : 'Risk Profili Testi',
          subtitle:
              hasProfile ? 'Tekrar yapmak için dokun' : '7 soru, 1 dakika',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RiskProfileTestScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.receipt_long_outlined,
          title: 'İşlem Geçmişi',
          subtitle: 'AL/SAT kayıtları',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── AI tools grouped
  Widget _buildAiToolsCard(BuildContext context) {
    return IOSGroupedCard(
      children: [
        IOSListRow(
          icon: Icons.auto_awesome_outlined,
          title: 'AI Portföy',
          subtitle: 'Profil + backtest',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiPortfolioBuilderScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.psychology_outlined,
          title: 'Davranış Profilim',
          subtitle: 'Yatırım alışkanlıkların',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BehaviorScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.crisis_alert_outlined,
          title: 'Stres Testi',
          subtitle: 'Portföyün kötü günleri',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StressTestScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.candlestick_chart_outlined,
          title: 'Mum Pratiği',
          subtitle: 'Geçmişle test',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TaQuizScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.history_rounded,
          title: 'Ya Almış Olsaydım?',
          subtitle: 'Geçmiş hesap + DCA',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WhatIfScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.savings_outlined,
          title: 'Temettü Takibi',
          subtitle: 'Temettü gelirini izle',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DividendScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.school_outlined,
          title: 'Akademi',
          subtitle: 'Finans eğitimi',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EducationScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.emoji_events_outlined,
          title: 'Görevler & Rozetler',
          subtitle: 'XP topla, başarımları gör',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MissionsScreen()),
          ),
        ),
        IOSListRow(
          icon: Icons.account_balance_outlined,
          title: 'Banka Altın',
          subtitle: 'Alış-satış karşılaştır',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GoldRatesScreen()),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────── liste görünümü
  List<Widget> _buildListView(
      BuildContext context, PortfolioProvider provider) {
    return [
      if (provider.myHoldings.isEmpty)
        // Hata varken "Portföyünü ekle" gösterilmez — yukarıdaki
        // LoadErrorCard zaten sebebi söylüyor, iki kart üst üste binmesin.
        if (provider.portfolioError != null)
          const SizedBox.shrink()
        else
          _buildEmptyState(context)
      else ...[
        EliteSectionLabel(
          'Pozisyonlar',
          trailing: _buildSortButton(context),
        ),
        ..._buildSortedHoldings(context, provider),
      ],
      const SizedBox(height: 16),
    ];
  }

  String _exchangeOf(String symbol) => SymbolDisplay.exchangeOf(symbol);

  static const _sortLabels = {
    HoldingSort.exchange: 'Borsaya göre',
    HoldingSort.weight: 'Portföy ağırlığına göre',
    HoldingSort.daily: 'Bugünkü getiriye göre',
    HoldingSort.total: "Toplam K/Z'ye göre",
  };

  Widget _buildSortButton(BuildContext context) {
    final c = AppColorsExt.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showSortSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Icon(Icons.swap_vert_rounded, size: 18, color: c.textMuted),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    Haptics.selection();
    showIOSBottomSheet(
      context: context,
      title: 'Sıralama',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: IOSGroupedCard(
          children: [
            for (final entry in _sortLabels.entries)
              Builder(builder: (ctx) {
                final c = AppColorsExt.of(ctx);
                final selected = entry.key == _sort;
                return IOSListRow(
                  icon: switch (entry.key) {
                    HoldingSort.exchange => Icons.account_balance_outlined,
                    HoldingSort.weight => Icons.pie_chart_outline,
                    HoldingSort.daily => Icons.today_outlined,
                    HoldingSort.total => Icons.trending_up_rounded,
                  },
                  iconColor: selected ? c.textPrimary : null,
                  title: entry.value,
                  trailing: selected
                      ? Icon(Icons.check_rounded,
                          size: 18, color: c.textPrimary)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _applySort(entry.key);
                  },
                );
              }),
          ],
        ),
      ),
    );
  }

  /// Seçili ölçüte göre pozisyon listesi. `exchange` gruplu (bugünkü görünüm),
  /// diğerleri tek düz liste — sıralama grup sınırını aşmalı.
  List<Widget> _buildSortedHoldings(
      BuildContext context, PortfolioProvider provider) {
    if (_sort == HoldingSort.exchange) {
      return _buildGroupedHoldings(context, provider);
    }

    final holdings = List<Map<String, dynamic>>.from(
        provider.myHoldings.map((h) => h as Map<String, dynamic>));

    // Değeri BİLİNMEYEN pozisyon (fiyat gelmedi / günlük değişim yok) sona
    // düşer: sıfır sayıp en alta sıralamak "en kötü performans" der, oysa
    // VERİ YOK (kalıcı kural).
    double? metric(Map<String, dynamic> h) => switch (_sort) {
          // Ağırlıkta TEK para birimi şart: total_value karışık (₺ ve $),
          // ham sıralanırsa TSLA $1.266 ≈ ₺1.266 sayılırdı.
          HoldingSort.weight => (h['total_value_try'] as num?)?.toDouble() ??
              (h['total_value'] as num?)?.toDouble(),
          HoldingSort.daily => (h['change_available'] as bool? ?? true)
              ? (h['change_percent'] as num?)?.toDouble()
              : null,
          HoldingSort.total => (h['price_available'] as bool? ?? true)
              ? (h['pnl_percent'] as num?)?.toDouble()
              : null,
          HoldingSort.exchange => null,
        };

    holdings.sort((a, b) {
      final va = metric(a);
      final vb = metric(b);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      return vb.compareTo(va);
    });

    return [
      IOSGroupedCard(
        children: [for (final h in holdings) _buildHoldingRow(context, h)],
      ),
    ];
  }

  List<Widget> _buildGroupedHoldings(
      BuildContext context, PortfolioProvider provider) {
    final c = AppColorsExt.of(context);
    final groups = <String, List<dynamic>>{};
    for (final h in provider.myHoldings) {
      final symbol = (h['symbol'] as String?) ?? '';
      final ex = _exchangeOf(symbol);
      groups.putIfAbsent(ex, () => []).add(h);
    }

    final ordered = groups.keys.toList()
      ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));

    final widgets = <Widget>[];
    for (final ex in ordered) {
      final list = groups[ex]!;
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          '$ex · ${list.length}',
          style: TextStyle(
            color: c.textSubtle,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ));
      widgets.add(IOSGroupedCard(
        children: [
          for (int i = 0; i < list.length; i++)
            _buildHoldingRow(context, list[i] as Map<String, dynamic>),
        ],
      ));
    }
    return widgets;
  }

  Widget _buildHoldingRow(BuildContext context, Map<String, dynamic> holding) {
    final c = AppColorsExt.of(context);
    final symbol = holding['symbol'] ?? 'Bilinmiyor';
    final quantity = (holding['quantity'] as num?)?.toDouble() ?? 0.0;
    final averageCost = (holding['average_cost'] as num?)?.toDouble() ?? 0.0;
    final totalValue = (holding['total_value'] as num?)?.toDouble() ?? 0.0;
    final pnlPercent = (holding['pnl_percent'] as num?)?.toDouble() ?? 0.0;
    final currentPrice = (holding['current_price'] as num?)?.toDouble() ?? 0.0;
    // Günlük değişim backend'de zaten vardı (change_percent) ama satırda
    // gösterilmiyordu: yalnız TOPLAM K/Z görünüyordu, yani yıllar önceki
    // maliyete göre. "Bugün ne oldu" bilgisi kayıptı.
    // Fiyat canlı olsa bile günlük değişim bilinmiyor olabilir (altın/gümüş
    // spot kaynağı fiyatı verir, dünkü kapanışı vermez) → backend
    // `change_available: false` der; sıfır basmak yerine satırı hiç gösterme.
    final dailyPercent = (holding['change_available'] as bool? ?? true)
        ? (holding['change_percent'] as num?)?.toDouble()
        : null;
    // Fiyat CANLI gelmediyse backend maliyeti fiyat yerine koyuyor (toplamlar
    // bozulmasın diye) ve K/Z matematiksel olarak 0 çıkıyor. Bunu "+%0,00"
    // diye basmak kullanıcıya "hiç değişmemiş" der — oysa VERİ YOK.
    // KALICI KURAL: veri yoksa sıfır gösterme, "—" göster.
    final priceLive = holding['price_available'] as bool? ?? true;
    final isProfit = pnlPercent >= 0;
    final dataColor =
        priceLive ? (isProfit ? c.positive : c.negative) : c.textMuted;
    final apiCurrency = holding['currency'] as String?;
    final curr = apiCurrency == 'TRY'
        ? '₺'
        : apiCurrency == 'USD'
            ? '\$'
            : SymbolDisplay.currencyOf(symbol);

    // Sola kaydır → sil (onay ister). Kaydırma keşfedilemez olduğu için
    // aynı iş uzun-basma sheet'inde de duruyor.
    return Dismissible(
      key: ValueKey('holding-$symbol'),
      direction: DismissDirection.endToStart,
      // confirmDismiss BİLEREK hep false döner: silme burada yapılır ve
      // portföy yeniden yüklenince satır kendiliğinden gider. true dönmek
      // satırı ağaçtan atar ama liste hâlâ eski veriyi taşıdığı için
      // "dismissed widget still in tree" hatasına açık olurdu; hata
      // durumunda da satırın yerinde kalması doğru davranış.
      confirmDismiss: (_) async {
        // Kaydırma eşiği geçildi — onay diyaloğu açılmadan önce elde karşılığı.
        Haptics.light();
        await _confirmAndDeletePosition(context, symbol);
        return false;
      },
      background: Builder(builder: (ctx) {
        final cc = AppColorsExt.of(ctx);
        return Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          color: cc.negative.withValues(alpha: 0.9),
          child:
              const Icon(Icons.delete_outline, color: Colors.white, size: 22),
        );
      }),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // opaque: satırdaki boşluklara dokununca da ilk tıkta açılsın
          // (deferToChild ile boşluklar yutuluyor, "iki kez basma" derdi).
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StockDetailScreen(
                stockData: _stockModelFor(symbol, currentPrice, pnlPercent),
              ),
            ),
          ),
          onLongPress: () => _showStockActionsSheet(context, symbol, quantity,
              averageCost, totalValue, pnlPercent, currentPrice),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
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
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        priceLive
                            ? '${quantity.toStringAsFixed(0)} adet  ·  Fiyat $curr${formatMoney(currentPrice, decimals: SymbolDisplay.priceDecimals(symbol, currentPrice))}  ·  Maliyet $curr${formatMoney(averageCost, decimals: SymbolDisplay.priceDecimals(symbol, averageCost))}'
                            : '${quantity.toStringAsFixed(0)} adet  ·  Fiyat —  ·  Maliyet $curr${formatMoney(averageCost, decimals: SymbolDisplay.priceDecimals(symbol, averageCost))}',
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      totalValue,
                      currency: curr,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: c.textPrimary,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: dataColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        priceLive
                            ? '${formatPctSigned(pnlPercent, decimals: 2)}%'
                            : 'fiyat yok',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Günlük değişim: rozetin ALTINDA, dolgusuz ve küçük —
                    // toplam K/Z ana bilgi olarak kalsın, ikisi yarışmasın.
                    if (priceLive && dailyPercent != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Bugün ${formatPctSigned(dailyPercent, decimals: 2)}%',
                        style: TextStyle(
                          color: dailyPercent >= 0 ? c.positive : c.negative,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Silme onayı + silme. Onay ŞART: kayıt defterinden kalıcı veri siliniyor
  /// (pozisyon + o sembolün işlem kayıtları) ve geri alınamıyor.
  Future<void> _confirmAndDeletePosition(
      BuildContext context, String symbol) async {
    final c = AppColorsExt.of(context);
    final label = SymbolDisplay.label(symbol);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('$label silinsin mi?',
            style: TextStyle(color: c.textPrimary, fontSize: 16)),
        content: Text(
          'Bu pozisyon ve $label için girdiğin işlem kayıtları kalıcı olarak '
          'silinir; geri alınamaz.\n\n'
          'Hisseyi gerçekten sattıysan bunun yerine hisse detayından satış '
          'kaydı gir — o zaman geçmişin defterde kalır.',
          style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç', style: TextStyle(color: c.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: c.negative)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result =
        await context.read<PortfolioProvider>().deletePosition(symbol);
    if (result.success) Haptics.medium();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? '$label portföyden silindi'
            : 'Silinemedi: ${result.message}'),
        backgroundColor: c.surfaceAlt,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: EliteSurface(
        padding: const EdgeInsets.all(EliteSpace.xl),
        child: Column(
          children: [
            Icon(Icons.trending_up_rounded, size: 32, color: c.textMuted),
            const SizedBox(height: 14),
            Text(
              'Portföyünü ekle',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sahip olduğun hisseleri lot + maliyetle ekle; haberlerini ve '
              'sinyallerini senin için takip edelim.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textMuted,
                fontSize: 13,
                letterSpacing: -0.1,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (kIsWeb) ...[
              IOSPillButton(
                label: 'Ekran Görüntüsünden Aktar',
                icon: Icons.auto_awesome_outlined,
                width: double.infinity,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ImportPortfolioScreen()),
                ),
              ),
              const SizedBox(height: 10),
            ],
            IOSPillButton(
              label: 'Portföyümü Gir',
              icon: Icons.playlist_add_rounded,
              secondary: kIsWeb,
              width: double.infinity,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ImportPortfolioScreen()),
              ),
            ),
            const SizedBox(height: 10),
            IOSPillButton(
              label: 'AI Koç\'a Sor',
              icon: Icons.auto_awesome_outlined,
              secondary: true,
              width: double.infinity,
              onPressed: () {
                context.read<ChatProvider>().setPendingPrompt(
                    'Yeni başlıyorum, ilk yatırım için neler önerirsin? Risk profilime göre nasıl başlamalıyım?');
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  StockModel _stockModelFor(
      String symbol, double currentPrice, double pnlPercent) {
    final currency = SymbolDisplay.currencyOf(symbol);
    final isTurkish = currency == '₺';
    return StockModel(
      symbol: symbol,
      name: symbol,
      price: currentPrice.toStringAsFixed(2),
      change: '${formatPctSigned(pnlPercent, decimals: 2)}%',
      isUp: pnlPercent >= 0,
      rawPrice: currentPrice,
      currency: currency,
      isTurkish: isTurkish,
    );
  }

  void _showStockActionsSheet(
    BuildContext context,
    String symbol,
    double quantity,
    double avgCost,
    double totalValue,
    double pnlPercent,
    double currentPrice,
  ) {
    showIOSBottomSheet(
      context: context,
      title: symbol,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (ctx) {
              final c = AppColorsExt.of(ctx);
              final isProfit = pnlPercent >= 0;
              final dataColor = isProfit ? c.positive : c.negative;
              return Row(
                children: [
                  Text(
                    '${quantity.toStringAsFixed(0)} adet',
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 13,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: dataColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${formatPctSigned(pnlPercent, decimals: 2)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 16),
            IOSGroupedCard(
              children: [
                IOSListRow(
                  icon: Icons.auto_awesome_outlined,
                  title: 'AI Koç\'a Sor',
                  subtitle: 'Bu pozisyon için detaylı yorum',
                  onTap: () {
                    Navigator.pop(context);
                    final prompt =
                        '$symbol pozisyonum hakkında detaylı yorum yapar mısın? '
                        'Şu an ${quantity.toStringAsFixed(0)} lotum var, ortalama maliyet ₺${formatMoney(avgCost)}, '
                        'getirim ${formatPctSigned(pnlPercent, decimals: 2)}%.';
                    context.read<ChatProvider>().setPendingPrompt(prompt);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatScreen()),
                    );
                  },
                ),
                IOSListRow(
                  icon: Icons.show_chart_rounded,
                  title: 'Detayları Gör',
                  subtitle: 'Fiyat grafiği, işlemler',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StockDetailScreen(
                          stockData:
                              _stockModelFor(symbol, currentPrice, pnlPercent),
                        ),
                      ),
                    );
                  },
                ),
                Builder(builder: (ctx) {
                  final c = AppColorsExt.of(ctx);
                  return IOSListRow(
                    icon: Icons.delete_outline,
                    iconColor: c.negative,
                    title: 'Portföyden Kaldır',
                    subtitle:
                        'Yanlış giriş — işlem kayıtlarıyla birlikte siler',
                    onTap: () {
                      Navigator.pop(context);
                      _confirmAndDeletePosition(context, symbol);
                    },
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
