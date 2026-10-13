import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/theme/app_theme.dart';

class _Mission {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final int reward;
  final bool Function(BuildContext) check;
  const _Mission({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.reward,
    required this.check,
  });
}

class _Badge {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final bool Function(BuildContext) earned;
  const _Badge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.earned,
  });
}

class MissionsScreen extends StatelessWidget {
  const MissionsScreen({super.key});

  // --- Sembol → piyasa sınıfı yardımcıları (tüm görev/rozetler ortak) ---
  static String _sym(dynamic h) => (h['symbol'] as String? ?? '').toUpperCase();
  static bool _isBist(String s) => s.endsWith('.IS');
  static bool _isCrypto(String s) => s.endsWith('-USD');
  static bool _isCommodity(String s) => s.endsWith('=F');
  static bool _isFx(String s) => s.contains('=X');
  static bool _isIndex(String s) => s.startsWith('^');
  static bool _isUsStock(String s) =>
      !_isBist(s) &&
      !_isCrypto(s) &&
      !_isCommodity(s) &&
      !_isFx(s) &&
      !_isIndex(s);

  static List<_Mission> _missions(BuildContext c) => [
        _Mission(
          id: 'first_buy',
          title: 'İlk Alımını Yap',
          description: 'Trade sekmesinden herhangi bir hisse al',
          icon: Icons.shopping_cart,
          reward: 50,
          check: (ctx) => ctx.read<PortfolioProvider>().myHoldings.isNotEmpty,
        ),
        _Mission(
          id: 'risk_test',
          title: 'Risk Profili Testi',
          description: 'Risk profili testini tamamla',
          icon: Icons.psychology,
          reward: 30,
          check: (ctx) => ctx.read<AuthProvider>().riskProfile != null,
        ),
        _Mission(
          id: 'watchlist_start',
          title: 'Radarını Kur',
          description: 'İzleme listene 5 sembol ekle',
          icon: Icons.visibility,
          reward: 30,
          check: (ctx) =>
              ctx.read<PortfolioProvider>().watchlistSymbols.length >= 5,
        ),
        _Mission(
          id: 'first_profit',
          title: 'İlk Kâr',
          description: 'Herhangi bir pozisyonda artıya geç',
          icon: Icons.trending_up,
          reward: 50,
          check: (ctx) => ctx
              .read<PortfolioProvider>()
              .myHoldings
              .any((s) => ((s['pnl'] as num?)?.toDouble() ?? 0.0) > 0),
        ),
        _Mission(
          id: 'diversify',
          title: 'Çeşitlendir',
          description: '3 farklı sembole pozisyon aç',
          icon: Icons.donut_large,
          reward: 70,
          check: (ctx) => ctx.read<PortfolioProvider>().myHoldings.length >= 3,
        ),
        _Mission(
          id: 'crypto_buy',
          title: 'Kripto Maceracısı',
          description: 'Bir kripto varlığa pozisyon aç',
          icon: Icons.currency_bitcoin,
          reward: 60,
          check: (ctx) => ctx
              .read<PortfolioProvider>()
              .myHoldings
              .any((s) => _isCrypto(_sym(s))),
        ),
        _Mission(
          id: 'commodity_buy',
          title: 'Güvenli Liman',
          description: 'Bir emtia/altın pozisyonu aç',
          icon: Icons.diamond_outlined,
          reward: 70,
          check: (ctx) => ctx
              .read<PortfolioProvider>()
              .myHoldings
              .any((s) => _isCommodity(_sym(s))),
        ),
        _Mission(
          id: 'cross_market',
          title: 'Çoklu Piyasa',
          description: 'BIST ve ABD pazarlarından birer hisse al',
          icon: Icons.public,
          reward: 100,
          check: (ctx) {
            final h = ctx.read<PortfolioProvider>().myHoldings;
            return h.any((s) => _isBist(_sym(s))) &&
                h.any((s) => _isUsStock(_sym(s)));
          },
        ),
        _Mission(
          id: 'green_portfolio',
          title: 'Yeşil Portföy',
          description: 'Toplam kâr/zararın artıda olsun',
          icon: Icons.savings,
          reward: 80,
          check: (ctx) => ctx.read<PortfolioProvider>().totalPnl > 0,
        ),
        _Mission(
          id: 'ten_percent',
          title: 'Çift Haneli Getiri',
          description: 'Bir pozisyonda +%10 getiri yakala',
          icon: Icons.local_fire_department,
          reward: 110,
          check: (ctx) => ctx.read<PortfolioProvider>().myHoldings.any(
              (s) => ((s['pnl_percent'] as num?)?.toDouble() ?? 0.0) >= 10),
        ),
        _Mission(
          id: 'diversify_pro',
          title: 'Geniş Yelpaze',
          description: 'Portföyünü 6 farklı sembole yay',
          icon: Icons.grid_view,
          reward: 120,
          check: (ctx) => ctx.read<PortfolioProvider>().myHoldings.length >= 6,
        ),
        _Mission(
          id: 'big_position',
          title: 'Ağır Top',
          description: 'Tek pozisyonda ₺50.000 değere ulaş',
          icon: Icons.account_balance_wallet,
          reward: 90,
          check: (ctx) => ctx.read<PortfolioProvider>().myHoldings.any(
              (s) => ((s['total_value'] as num?)?.toDouble() ?? 0.0) >= 50000),
        ),
        _Mission(
          id: 'all_markets',
          title: 'Üç Cephe',
          description: 'BIST, ABD ve kripto — üçünü birden tut',
          icon: Icons.hub,
          reward: 150,
          check: (ctx) {
            final h = ctx.read<PortfolioProvider>().myHoldings;
            return h.any((s) => _isBist(_sym(s))) &&
                h.any((s) => _isUsStock(_sym(s))) &&
                h.any((s) => _isCrypto(_sym(s)));
          },
        ),
        _Mission(
          id: 'quarter_million',
          title: 'Çeyrek Milyon',
          description: 'Toplam varlığın ₺250.000\'i aşsın',
          icon: Icons.trending_up,
          reward: 130,
          check: (ctx) =>
              ctx.read<PortfolioProvider>().totalAssetValue >= 250000,
        ),
      ];

  static List<_Badge> _badges(BuildContext c) => [
        _Badge(
          id: 'newcomer',
          title: 'Yeni Yatırımcı',
          description: 'Hesap oluşturdun',
          icon: Icons.emoji_events,
          earned: (_) => true,
        ),
        _Badge(
          id: 'risk_aware',
          title: 'Bilinçli Yatırımcı',
          description: 'Risk profilini öğrendin',
          icon: Icons.shield,
          earned: (ctx) => ctx.read<AuthProvider>().riskProfile != null,
        ),
        _Badge(
          id: 'trader',
          title: 'İşlemci',
          description: 'İlk pozisyonunu açtın',
          icon: Icons.bolt,
          earned: (ctx) => ctx.read<PortfolioProvider>().myHoldings.isNotEmpty,
        ),
        _Badge(
          id: 'diversified',
          title: 'Çeşitlendirici',
          description: '3+ varlığa yayıldın',
          icon: Icons.donut_large,
          earned: (ctx) => ctx.read<PortfolioProvider>().myHoldings.length >= 3,
        ),
        _Badge(
          id: 'diversifier_pro',
          title: 'Portföy Mimarı',
          description: '6+ farklı sembol tutuyorsun',
          icon: Icons.grid_view,
          earned: (ctx) => ctx.read<PortfolioProvider>().myHoldings.length >= 6,
        ),
        _Badge(
          id: 'crypto_pioneer',
          title: 'Kripto Öncüsü',
          description: 'Kripto varlık tuttun',
          icon: Icons.currency_bitcoin,
          earned: (ctx) => ctx
              .read<PortfolioProvider>()
              .myHoldings
              .any((s) => _isCrypto(_sym(s))),
        ),
        _Badge(
          id: 'gold_bug',
          title: 'Altın Avcısı',
          description: 'Emtia/altın pozisyonu açtın',
          icon: Icons.diamond_outlined,
          earned: (ctx) => ctx
              .read<PortfolioProvider>()
              .myHoldings
              .any((s) => _isCommodity(_sym(s))),
        ),
        _Badge(
          id: 'global',
          title: 'Global Yatırımcı',
          description: 'Hem BIST hem ABD pazarında işlem yaptın',
          icon: Icons.public,
          earned: (ctx) {
            final h = ctx.read<PortfolioProvider>().myHoldings;
            return h.any((s) => _isBist(_sym(s))) &&
                h.any((s) => _isUsStock(_sym(s)));
          },
        ),
        _Badge(
          id: 'all_rounder',
          title: 'Çok Yönlü',
          description: 'BIST + ABD + kripto, üçü birden',
          icon: Icons.hub,
          earned: (ctx) {
            final h = ctx.read<PortfolioProvider>().myHoldings;
            return h.any((s) => _isBist(_sym(s))) &&
                h.any((s) => _isUsStock(_sym(s))) &&
                h.any((s) => _isCrypto(_sym(s)));
          },
        ),
        _Badge(
          id: 'profit_taker',
          title: 'Kâr Tadı',
          description: 'Bir pozisyonu artıya taşıdın',
          icon: Icons.trending_up,
          earned: (ctx) => ctx
              .read<PortfolioProvider>()
              .myHoldings
              .any((s) => ((s['pnl'] as num?)?.toDouble() ?? 0.0) > 0),
        ),
        _Badge(
          id: 'bull',
          title: 'Boğa',
          description: 'Toplam getirin +%10\'u aştı',
          icon: Icons.local_fire_department,
          earned: (ctx) => ctx.read<PortfolioProvider>().totalPnlPercent >= 10,
        ),
        _Badge(
          id: 'whale',
          title: 'Balina',
          description: 'Toplam varlık değerin ₺500.000\'i aştı',
          icon: Icons.waves,
          earned: (ctx) =>
              ctx.read<PortfolioProvider>().totalAssetValue >= 500000,
        ),
        _Badge(
          id: 'tycoon',
          title: 'Tycoon',
          description: 'Toplam varlığın ₺1.000.000\'i geçti',
          icon: Icons.workspace_premium,
          earned: (ctx) =>
              ctx.read<PortfolioProvider>().totalAssetValue >= 1000000,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final missions = _missions(context);
    final badges = _badges(context);
    final completedMissions = missions.where((m) => m.check(context)).toList();
    final earnedBadges = badges.where((b) => b.earned(context)).toList();
    final totalReward = completedMissions.fold<int>(0, (s, m) => s + m.reward);

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
        title: Text('Görevler & Rozetler',
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Editorial XP hero
                  Text(
                    'Toplam XP',
                    style: TextStyle(
                        color: c.textMuted, fontSize: 14, letterSpacing: -0.1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalReward',
                    style: TextStyle(
                      color: c.warmAccent,
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${completedMissions.length}/${missions.length} görev · ${earnedBadges.length}/${badges.length} rozet',
                    style: TextStyle(
                        color: c.textSubtle, fontSize: 13, letterSpacing: -0.1),
                  ),
                  const SizedBox(height: 28),
                  Text('Görevler',
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.6)),
                  const SizedBox(height: 12),
                  ...missions.map((m) {
                    final done = m.check(context);
                    final tone = done ? c.warmAccent : c.textMuted;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(m.icon, color: tone, size: 22),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(m.title,
                                          style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.1,
                                              decoration: done
                                                  ? TextDecoration.lineThrough
                                                  : null)),
                                    ),
                                    Text('+${m.reward} XP',
                                        style: TextStyle(
                                          color: c.warmAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(m.description,
                                    style: TextStyle(
                                        color: c.textMuted,
                                        fontSize: 12,
                                        letterSpacing: -0.1)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                              done
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                              color: done ? c.warmAccent : c.textSubtle,
                              size: 22),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  Text('Rozetler',
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.6)),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      childAspectRatio: 2.4,
                    ),
                    itemCount: badges.length,
                    itemBuilder: (_, i) {
                      final b = badges[i];
                      final got = b.earned(context);
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(b.icon,
                                color: got ? c.warmAccent : c.textSubtle,
                                size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(b.title,
                                      style: TextStyle(
                                          color:
                                              got ? c.textPrimary : c.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.1)),
                                  const SizedBox(height: 2),
                                  Text(b.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: c.textSubtle,
                                          fontSize: 10,
                                          height: 1.3)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
