import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/widgets/ai_sheet.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/widgets/fear_greed_gauge.dart';
import 'package:portly/widgets/macro_calendar_widget.dart';
import 'package:url_launcher/url_launcher.dart';

/// RSS haber metnindeki yaygın HTML entity'lerini çözer ("&nbsp;" → boşluk).
/// Backend ham bırakıyor; gösterimden önce tek yerde temizlenir.
String decodeHtmlEntities(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#039;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

enum _NewsScope { all, portfolio, watchlist }

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final ApiService _api = ApiService();
  _NewsScope _scope = _NewsScope.all;

  // Kapsamlı feed'ler ilk seçimde bir kez çekilip cache'lenir (sekme
  // değiştikçe tekrar yüklenmez; "Tekrar Dene"/aşağı çekme force eder).
  List<dynamic>? _portfolioNews;
  List<dynamic>? _watchlistNews;
  bool _scopedLoading = false;
  bool _scopedError = false;

  @override
  void initState() {
    super.initState();
    // Haber verisi artık uygulama açılışında DEĞİL, bu sekme ilk kez
    // kurulduğunda çekiliyor (açılış hızı). Sekme tembel kurulduğu için
    // burası kullanıcı Haber'e ilk geçtiğinde çalışır.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PortfolioProvider>().ensureNewsLoaded();
    });
  }

  List<String> _symbolsFor(PortfolioProvider p, _NewsScope s) {
    final Iterable<String> raw = s == _NewsScope.portfolio
        ? p.holdings.map((h) => h.symbol)
        : s == _NewsScope.watchlist
            ? p.watchlistSymbols
            : const <String>[];
    final seen = <String>{};
    return [
      for (final x in raw)
        if (x.trim().isNotEmpty && seen.add(x.toUpperCase())) x
    ];
  }

  Future<void> _selectScope(_NewsScope s, PortfolioProvider p) async {
    setState(() => _scope = s);
    if (s == _NewsScope.all) return;
    final cached = s == _NewsScope.portfolio ? _portfolioNews : _watchlistNews;
    if (cached != null) return; // zaten yüklü
    await _loadScoped(s, _symbolsFor(p, s));
  }

  Future<void> _loadScoped(_NewsScope s, List<String> symbols,
      {bool force = false}) async {
    if (s == _NewsScope.all) return;
    setState(() {
      _scopedLoading = true;
      _scopedError = false;
      if (force) {
        if (s == _NewsScope.portfolio) {
          _portfolioNews = null;
        } else {
          _watchlistNews = null;
        }
      }
    });
    try {
      final merged = await _aggregateNews(symbols, force: force);
      if (!mounted) return;
      setState(() {
        if (s == _NewsScope.portfolio) {
          _portfolioNews = merged;
        } else {
          _watchlistNews = merged;
        }
        _scopedLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scopedLoading = false;
        _scopedError = true;
      });
    }
  }

  /// Portföyüm/İzleme haberi: sembol sorgularını (hisse detayıyla aynı
  /// `newsQuery`) TEK backend çağrısında toplu çeker (sunucu paralel çekim +
  /// tek LLM enrich), yalnız bu sembollere ALAKALI olanları tutar, tekilleştirir
  /// + tarihe göre sıralar. (Eskiden sembol-başına ayrı çağrıydı → N LLM, yavaş.)
  Future<List<dynamic>> _aggregateNews(List<String> symbols,
      {bool force = false}) async {
    if (symbols.isEmpty) return const [];
    // 12 "demo üst sınırı"ydı: 51 pozisyonlu bir portföyde 39 hissenin haberi
    // HİÇ çekilmiyordu; 24 de gerçek portföyü (38 pozisyon) kapsamıyordu.
    // Sunucu artık sembol sayısını değil TUR BAŞINA ÇEKİMİ sınırlıyor
    // (nlp_sentiment_service._FETCH_BUDGET) → sınır sembol sayısıyla eşit
    // tutulur (_MAX_SYMBOLS).
    final capped = symbols.take(40).toList();
    final queries = capped.map(SymbolDisplay.newsQuery).toList();
    final items = await _api.fetchNewsForSymbols(queries, force: force);

    // Hangi sorgunun hangi sembol için atıldığı (sunucu haberi `matched_query`
    // ile etiketliyor). Bölge öneki ("en|") sunucuda soyuluyor.
    final askedQueries = {
      for (final q in queries) (q.contains('|') ? q.split('|').last : q).trim()
    };
    final ups = capped.map((s) => s.toUpperCase()).toList();
    final shorts = [
      for (final u in ups)
        u.replaceAll('.IS', '').replaceAll('.FON', '').replaceAll('-USD', '')
    ];
    bool relevant(dynamic n) {
      // 1) Haberi zaten BİZİM sorgumuz getirdiyse alakalıdır. Metin eşlemesi
      //    tek başına yetmiyordu: "Lockheed Martin ..." başlığında "LMT"
      //    geçmiyor, `affected_assets` sözlüğü de yalnız ~100 popüler şirketi
      //    tanıyor → canlıda 34 haberin 16'sı burada eleniyordu.
      final matched = (n['matched_query'] as String? ?? '').trim();
      if (matched.isNotEmpty && askedQueries.contains(matched)) return true;
      final assets = (n['affected_assets'] as List?) ?? const [];
      for (final a in assets) {
        if (ups
            .contains(((a as Map)['symbol'] as String? ?? '').toUpperCase())) {
          return true;
        }
      }
      final blob =
          ('${n['title'] ?? ''} ${n['description'] ?? ''}').toUpperCase();
      return shorts.any((sh) => sh.length >= 3 && blob.contains(sh));
    }

    final seen = <String>{};
    final merged = <dynamic>[];
    for (final n in items) {
      if (!relevant(n)) continue;
      final key = '${n['url'] ?? n['title'] ?? ''}';
      if (key.isEmpty || seen.add(key)) merged.add(n);
    }
    merged.sort((a, b) =>
        '${b['published_at'] ?? ''}'.compareTo('${a['published_at'] ?? ''}'));
    // 40'lık gösterim sınırı sembol sınırı 24'ken konmuştu; 40 sembolde liste
    // gereksiz kırpılıyordu (sunucu sınırı 90).
    return merged.take(60).toList();
  }

  Future<void> _refresh(PortfolioProvider provider) async {
    if (_scope == _NewsScope.all) {
      await provider.loadNewsData(force: true);
    } else {
      await _loadScoped(_scope, _symbolsFor(provider, _scope), force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortfolioProvider>();
    final c = AppColorsExt.of(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: c.textPrimary,
          backgroundColor: c.surface,
          onRefresh: () => _refresh(provider),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Haberler',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1.2,
                                height: 1.05,
                              ),
                            ),
                          ),
                          if (provider.isNewsLoading || _scopedLoading)
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: c.textMuted),
                            )
                          else
                            _IconBtn(
                              icon: Icons.refresh_rounded,
                              onTap: () => _refresh(provider),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'NLP modeli ile piyasa haberlerinin anlık duygu analizi.',
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 14,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: EliteSpace.lg),
                      const EliteSectionLabel('Piyasa Nabzı'),
                      const FearGreedGauge(),
                      const SizedBox(height: EliteSpace.sm),
                      const MacroCalendarWidget(),
                      const SizedBox(height: EliteSpace.lg),
                      const EliteSectionLabel('Son Haberler'),
                      const SizedBox(height: EliteSpace.sm),
                      _buildScopeTabs(context, provider),
                      const SizedBox(height: EliteSpace.md),
                      _buildNewsBody(context, provider),
                      const SizedBox(height: EliteSpace.lg),
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

  Widget _buildScopeTabs(BuildContext context, PortfolioProvider provider) {
    final c = AppColorsExt.of(context);
    Widget chip(String label, _NewsScope s) {
      final selected = _scope == s;
      return Expanded(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: selected ? null : () => _selectScope(s, provider),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.warmAccentSoft : c.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? c.warmAccent : c.textMuted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Tümü', _NewsScope.all),
        chip('Portföyüm', _NewsScope.portfolio),
        chip('İzleme Listem', _NewsScope.watchlist),
      ],
    );
  }

  Widget _buildNewsBody(BuildContext context, PortfolioProvider provider) {
    if (_scope == _NewsScope.all) {
      final failed = provider.newsError != null && provider.newsData.isEmpty;
      return _newsBody(
        context,
        items: provider.newsData,
        loading: provider.isNewsLoading && provider.newsData.isEmpty,
        onRetry: () => provider.loadNewsData(force: true),
        // "Haber yok" ile "haber çekilemedi" farkı: ikincisinde sunucu
        // hatasını gerçek sebep olarak söyle.
        emptyTitle: failed ? 'Haberler yüklenemedi' : 'Haber bulunamadı',
        emptyHint: failed
            ? 'Sunucu uyanıyor olabilir — tekrar dene'
            : 'Yenilemeyi dene',
      );
    }

    final symbols = _symbolsFor(provider, _scope);
    final isPortfolio = _scope == _NewsScope.portfolio;
    if (symbols.isEmpty) {
      return _emptyCard(
        context,
        title: isPortfolio ? 'Portföyün boş' : 'İzleme listen boş',
        hint: isPortfolio
            ? 'Hisse aldıkça ilgili haberler burada toplanır'
            : 'İzleme listene sembol ekledikçe haberleri burada toplanır',
      );
    }
    if (_scopedError) {
      return _emptyCard(
        context,
        title: 'Haberler yüklenemedi',
        hint: 'Sunucu uyanıyor olabilir — tekrar dene',
        onRetry: () => _loadScoped(_scope, symbols, force: true),
      );
    }
    final items = isPortfolio ? _portfolioNews : _watchlistNews;
    return _newsBody(
      context,
      items: items ?? const [],
      loading: _scopedLoading && (items == null || items.isEmpty),
      onRetry: () => _loadScoped(_scope, symbols, force: true),
      emptyTitle: 'İlgili haber bulunamadı',
      emptyHint: isPortfolio
          ? 'Portföyündeki sembollerle eşleşen güncel haber yok'
          : 'İzleme listendeki sembollerle eşleşen güncel haber yok',
    );
  }

  Widget _newsBody(
    BuildContext context, {
    required List<dynamic> items,
    required bool loading,
    required VoidCallback onRetry,
    required String emptyTitle,
    required String emptyHint,
  }) {
    return EliteFade(
      child: loading
          ? Column(
              key: const ValueKey('news-loading'),
              children: const [
                EliteSkeleton(height: 124, radius: EliteRadii.md),
                SizedBox(height: 10),
                EliteSkeleton(height: 124, radius: EliteRadii.md),
                SizedBox(height: 10),
                EliteSkeleton(height: 124, radius: EliteRadii.md),
              ],
            )
          : items.isEmpty
              ? _emptyCard(context,
                  title: emptyTitle, hint: emptyHint, onRetry: onRetry)
              : Column(
                  key: const ValueKey('news-list'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final news in items)
                      Builder(builder: (_) {
                        final n = news as Map<String, dynamic>;
                        final sentimentLabel = n['sentiment_label'] ?? 'Nötr';
                        final score =
                            (n['sentiment_score'] as num?)?.toDouble() ?? 0.0;
                        final publishedAt = n['published_at'] ?? '';
                        return _buildNewsCard(context, n, sentimentLabel, score,
                            _formatDate(publishedAt));
                      }),
                  ],
                ),
    );
  }

  Widget _emptyCard(
    BuildContext context, {
    required String title,
    required String hint,
    VoidCallback? onRetry,
  }) {
    final c = AppColorsExt.of(context);
    return EliteSurface(
      key: const ValueKey('news-empty'),
      padding: const EdgeInsets.all(EliteSpace.xl),
      child: Column(
        children: [
          Icon(Icons.article_outlined, size: 38, color: c.textSubtle),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textMuted,
              fontSize: 13,
              letterSpacing: -0.1,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: IOSPillButton(
                label: 'Tekrar Dene',
                secondary: true,
                onPressed: onRetry,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(dynamic iso) {
    try {
      if (iso is! String) return '';
      DateTime date = DateTime.parse(iso);
      final hasOffset =
          iso.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
      if (!date.isUtc && !hasOffset) {
        date = DateTime.utc(date.year, date.month, date.day, date.hour,
            date.minute, date.second);
      }
      final now = DateTime.now();
      final local = date.toLocal();
      final diff = now.difference(local);
      if (diff.isNegative) return 'şimdi';
      if (diff.inSeconds < 60) return 'az önce';
      if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
      if (diff.inHours < 6) return '${diff.inHours} saat önce';

      // 6 saatten eski → kesin saat göster. Tüm haberler "1 gün önce"
      // görünüp ayırt edilemiyordu (NewsAPI ücretsiz katmanı ~24 sa
      // gecikmeli); "Dün 16:46" / "Cts 09:12" hem net hem güvenilir durur.
      String two(int n) => n.toString().padLeft(2, '0');
      final clock = '${two(local.hour)}:${two(local.minute)}';
      final today = DateTime(now.year, now.month, now.day);
      final thatDay = DateTime(local.year, local.month, local.day);
      final dayGap = today.difference(thatDay).inDays;
      if (dayGap == 0) return 'Bugün $clock';
      if (dayGap == 1) return 'Dün $clock';
      if (dayGap < 7) {
        const wd = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
        return '${wd[local.weekday - 1]} $clock';
      }
      const months = [
        'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
        'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
      ];
      final base = '${local.day} ${months[local.month - 1]}';
      return local.year == now.year ? '$base $clock' : '$base ${local.year}';
    } catch (e) {
      return '';
    }
  }

  Widget _buildNewsCard(BuildContext context, Map<String, dynamic> news,
      String sentiment, double score, String time) {
    final c = AppColorsExt.of(context);
    final title = decodeHtmlEntities(news['title'] as String? ?? 'Başlık Yok');
    final description =
        decodeHtmlEntities(news['description'] as String? ?? '');
    final url = news['url'] as String? ?? '';
    final affectedAssets = (news['affected_assets'] as List?) ?? const [];

    // Sentiment = veri → yeşil/kırmızı/gri izinli
    final Color sentimentColor = switch (sentiment) {
      'Pozitif' => c.positive,
      'Negatif' => c.negative,
      _ => c.textSubtle,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: EliteSurface(
        padding: const EdgeInsets.all(EliteSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Rozet haberin TONUNU gösterir (başlık dili Pozitif/Negatif);
                // piyasa etkisi ayrı → detay sheet "AI Piyasa Etkisi" netleştirir.
                // Rozet yalnız GERÇEK sinyalde (Pozitif/Negatif) renkli+dolu+skor.
                // Nötr → sönük nokta + "Nötr" (skor YOK) → "0.00" görsel gürültüsü
                // kalkar, liste sakinleşir (data-ink: renk yalnız anlamlı veride).
                if (sentiment == 'Nötr')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: c.textSubtle,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Nötr',
                        style: TextStyle(
                          color: c.textSubtle,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sentimentColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '$sentiment ${score.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  time,
                  style: TextStyle(
                    color: c.textSubtle,
                    fontSize: 12,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                height: 1.3,
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 13,
                  height: 1.5,
                  letterSpacing: -0.1,
                ),
              ),
            ],
            if (affectedAssets.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: affectedAssets.map<Widget>((asset) {
                  final a = asset as Map<String, dynamic>;
                  final symbol = a['symbol'] as String? ?? '';
                  final rawName = (a['name'] as String?) ?? '';
                  final friendly = rawName.isNotEmpty
                      ? rawName
                      : SymbolDisplay.compact(symbol);
                  // Şifreli Yahoo sembolünü (=X/=F/^) ham gösterme; normal
                  // hisseyi "Ad · SEMBOL" tut (Microsoft · MSFT faydalı).
                  final encoded =
                      symbol.contains('=') || symbol.startsWith('^');
                  final label = encoded ? friendly : '$friendly · $symbol';
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _AnalysisChip(title: title, description: description),
                const Spacer(),
                if (url.isNotEmpty)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () async {
                        final uri = Uri.tryParse(url);
                        if (uri == null) return;
                        try {
                          final ok = await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Haber açılamadı')),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Haber açılamadı')),
                            );
                          }
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Habere git',
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.1,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_new_rounded,
                              color: c.textMuted, size: 13),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
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
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hover ? c.surfaceAlt : c.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, color: c.textPrimary, size: 19),
        ),
      ),
    );
  }
}

class _AnalysisChip extends StatelessWidget {
  final String title;
  final String description;
  const _AnalysisChip({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showAnalysisSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.warmAccentSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined, color: c.warmAccent, size: 13),
              const SizedBox(width: 6),
              Text(
                'AI Detaylı Analiz',
                style: TextStyle(
                  color: c.warmAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAnalysisSheet(BuildContext context) {
    showIOSBottomSheet(
      context: context,
      title: 'AI Piyasa Etkisi',
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        // Yükleniyor/hata/Tekrar Dene ortak sarmalayıcıda (AiSheet): analiz
        // canlıda yaklaşık 3/10 geçici hata veriyordu ve kullanıcının sheet'i
        // kapatıp yeniden açmaktan başka yolu yoktu.
        child: AiSheet(
          fetch: ({bool force = false}) =>
              ApiService().analyzeNews(title, description),
          // Uç, hatayı 200 + {"error": ...} gövdesiyle de bildirebiliyor (LLM
          // kotası/anlık yoğunluk) → onu da başarısız say. Sunucu hatalı
          // sonucu cache'lemiyor, bu yüzden retry gerçekten yeni analiz üretir.
          isFailure: (d) => d.containsKey('error'),
          errorMessage: 'AI piyasa etkisi analizi alınamadı. AI servisi yoğun '
              'olabilir, birazdan tekrar dene.',
          onData: (ctx, data) {
            final c = AppColorsExt.of(ctx);
            final affected = (data['affected'] as List?) ?? const [];
            // Net yön = etkilenen varlıkların ortalama beklenen etkisi
            // (yön etiketi de UP/DOWN ağırlığını destekler).
            double netImpact = 0;
            int up = 0, down = 0;
            for (final a in affected) {
              final m = a as Map<String, dynamic>;
              netImpact += (m['expected_impact_pct'] as num?)?.toDouble() ?? 0;
              final d = m['direction'] as String? ?? 'NEUTRAL';
              if (d == 'UP') up++;
              if (d == 'DOWN') down++;
            }
            if (affected.isNotEmpty) netImpact /= affected.length;
            final bool mixed = up > 0 && down > 0;
            final String verdict;
            final Color vColor;
            final IconData vIcon;
            if (netImpact >= 0.4 && !mixed) {
              verdict = 'Olumlu Etki';
              vColor = c.positive;
              vIcon = Icons.trending_up_rounded;
            } else if (netImpact <= -0.4 && !mixed) {
              verdict = 'Olumsuz Etki';
              vColor = c.negative;
              vIcon = Icons.trending_down_rounded;
            } else if (mixed) {
              verdict = 'Karışık Etki';
              vColor = c.warmAccent;
              vIcon = Icons.swap_vert_rounded;
            } else {
              verdict = 'Nötr Etki';
              vColor = c.textSubtle;
              vIcon = Icons.trending_flat_rounded;
            }
            final sectors = ((data['sectors'] as List?) ?? const [])
                .map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty)
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                IOSVerdictBanner(
                  verdict: verdict,
                  sub: data['summary_tr']?.toString() ?? 'AI haber analizi',
                  color: vColor,
                  icon: vIcon,
                  stats: [
                    ('Etkilenen', '${affected.length} varlık'),
                    if (affected.isNotEmpty)
                      (
                        'Ort. etki',
                        '${formatPctSigned(netImpact, decimals: 1)}%'
                      ),
                    if (sectors.isNotEmpty) ('Sektör', sectors.first),
                  ],
                ),
                const SizedBox(height: 10),
                // Liste rozeti haberin TONUNU (olumlu/olumsuz dil) ölçer; bu
                // banner ise haberin piyasaya tahmini ETKİSİNİ. İkisi farklı
                // olabilir (ör. "petrol düştü" tonu olumlu ama petrol varlığına
                // etkisi olumsuz) → kullanıcı çelişki sanmasın diye açıkça yaz.
                Text(
                  'Haberin piyasaya tahmini etkisi — haber başlığının '
                  'olumlu/olumsuz tonundan farklı olabilir.',
                  style: TextStyle(
                    color: c.textSubtle,
                    fontSize: 11.5,
                    height: 1.4,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 13,
                    height: 1.45,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 16),
                if (sectors.isNotEmpty) ...[
                  const EliteSectionLabel('Etkilenen Sektörler'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: sectors
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 6),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                s,
                                style: TextStyle(
                                  color: c.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                ],
                if ((data['affected'] as List?)?.isNotEmpty ?? false) ...[
                  const EliteSectionLabel('Etkilenen Varlıklar'),
                  ...(data['affected'] as List).map<Widget>((a) {
                    final asset = a as Map<String, dynamic>;
                    final symbol = asset['symbol'] as String? ?? '';
                    final name = asset['name'] as String? ?? symbol;
                    final dir = asset['direction'] as String? ?? 'NEUTRAL';
                    final impact =
                        (asset['expected_impact_pct'] as num?)?.toDouble() ?? 0;
                    final rationale = asset['rationale'] as String? ?? '';
                    // Yön = veri → renk izinli
                    final dataColor = dir == 'UP'
                        ? c.positive
                        : dir == 'DOWN'
                            ? c.negative
                            : c.textSubtle;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: EliteSurface(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$name · $symbol',
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: dataColor,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '${formatPctSigned(impact, decimals: 1)}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (rationale.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                rationale,
                                style: TextStyle(
                                  color: c.textMuted,
                                  fontSize: 11,
                                  height: 1.5,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                ],
                if ((data['horizons'] as Map?) != null) ...[
                  const EliteSectionLabel('Vade Yorumları'),
                  _horizonTimeline(context, [
                    (
                      'Kısa Vade',
                      '1–2 hafta',
                      Icons.bolt_rounded,
                      data['horizons']['short'] as String? ?? '-'
                    ),
                    (
                      'Orta Vade',
                      '1–3 ay',
                      Icons.timeline_rounded,
                      data['horizons']['medium'] as String? ?? '-'
                    ),
                    (
                      'Uzun Vade',
                      '6+ ay',
                      Icons.flag_rounded,
                      data['horizons']['long'] as String? ?? '-'
                    ),
                  ]),
                  const SizedBox(height: 18),
                ],
                if ((data['risks'] as List?)?.isNotEmpty ?? false) ...[
                  const EliteSectionLabel('Belirsizlikler'),
                  _riskCallout(
                      context,
                      (data['risks'] as List)
                          .map((e) => e.toString())
                          .toList()),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Vade yorumları — bağlı timeline (nokta + dikey çizgi), her vade için
  /// ikon + dönem etiketi. Düz 3 gri kart yerine ilişkili, okunaklı akış.
  Widget _horizonTimeline(
      BuildContext context, List<(String, String, IconData, String)> items) {
    final c = AppColorsExt.of(context);
    return EliteSurface(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline rayı: ikon dairesi + alta inen bağlantı çizgisi
                  Column(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c.warmAccentSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(items[i].$3, size: 15, color: c.warmAccent),
                      ),
                      if (i != items.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: c.divider,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          bottom: i == items.length - 1 ? 12 : 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                items[i].$1,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c.warmAccentSoft,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  items[i].$2,
                                  style: TextStyle(
                                    color: c.warmAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            items[i].$4,
                            style: TextStyle(
                              color: c.textMuted,
                              fontSize: 12,
                              height: 1.5,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Belirsizlikler — sol şeritli uyarı callout'u (düz madde yerine).
  Widget _riskCallout(BuildContext context, List<String> risks) {
    final c = AppColorsExt.of(context);
    return EliteSurface(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: c.warmAccent),
              const SizedBox(width: 7),
              Text(
                'Bu analizi değiştirebilecek etkenler',
                style: TextStyle(
                  color: c.textSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < risks.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == risks.length - 1 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.warmAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      risks[i],
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 12,
                        height: 1.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
