import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/data/market_repository.dart';

/// Temettü Takibi — Elite redesign (Batch 2).
///
/// Net mantık akışı, kullanıcının kafası karışmasın diye 3 ayrı blok:
///   1. Yılda ne kadar?            (hero — tahmini)
///   2. Sıradaki ödemeler           (Ticker · ≈₺ · tarih, açık kartlar)
///   3. Tahsilat & geçmiş           (ne olduğu net anlatılır + buton)
///
/// NOT: Backend overview'ı "şu an tahsil edilebilir kesin tutar"
/// döndürmez (claimable backlog yalnız collect çağrısında sunucuda
/// hesaplanır). Bu yüzden tutarlar dürüstçe "≈ tahmini" etiketlenir;
/// uydurma "şu an X₺ topla" rakamı GÖSTERİLMEZ (client-side finansal
/// uydurma = Modül A/C/F'de kökü kazınan hata sınıfı).
class DividendScreen extends StatefulWidget {
  const DividendScreen({super.key});

  @override
  State<DividendScreen> createState() => _DividendScreenState();
}

class _DividendScreenState extends State<DividendScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _preview; // dry-run: kesin tahsil edilebilir
  bool _loading = true;
  bool _collecting = false;
  bool _error = false; // overview hata/timeout → "boş portföy" ile karıştırma

  // Şirket adı "ferry"si: codebase'in MarketRepository in-flight dedup
  // deseni (TTL yok → bayatlamaz; eşzamanlı yinelenen istek tek HTTP'ye
  // iner). Backend dividend item'ı gerçek ad döndürmüyor ("name": csym),
  // o yüzden alt satır adı buradan lazily çekilir, çözülünce cache'lenir.
  late final MarketRepository _marketRepo = MarketRepository(_api);
  final Map<String, String> _names = {}; // SYMBOL → çözülmüş şirket adı
  final Set<String> _ferrying = {}; // uçuşta olanlar (yinelenen tetik yok)

  void _ferryName(String symbol) {
    final key = symbol.toUpperCase();
    if (key.isEmpty || _names.containsKey(key) || _ferrying.contains(key)) {
      return;
    }
    _ferrying.add(key);
    _marketRepo.fetchOne(symbol).then((m) {
      _ferrying.remove(key);
      if (!mounted) return;
      final n = m?.name.trim() ?? '';
      // StockModel.name boşsa symbol'e düşer → ticker'ı tekrar yazma.
      if (n.isNotEmpty && n.toUpperCase() != key) {
        setState(() => _names[key] = n);
      }
    });
  }

  // Alt satır: ferry geldiyse şirket adı; gelene dek bilinen TR adı
  // (SymbolDisplay.label) — o da ticker'la aynıysa satır gizli (null).
  String? _subtitle(String symbol) {
    final key = symbol.toUpperCase();
    final ferried = _names[key];
    if (ferried != null && ferried.isNotEmpty) return ferried;
    final lbl = SymbolDisplay.label(symbol);
    if (lbl.isNotEmpty &&
        lbl.toUpperCase() != SymbolDisplay.compact(symbol).toUpperCase()) {
      return lbl;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    // TEK istek: genel görünüm + tahsil-edilebilir (dry-run) artık aynı
    // yanıtta gömülü (`claimable` + `claim_events`). Eskiden ayrı bir
    // /preview round-trip'iydi; mobilde/soğuk Render'da iki isteği
    // `Future.wait` ile beklemek açılışı yavaşlatıyordu.
    final data = await _api.fetchDividends(uid);
    if (!mounted) return;
    setState(() {
      _data = data;
      // Gömülü dry-run sonucunu eski şekle map'le (build kodu değişmesin):
      // {credited, events} → _preview.
      _preview = data == null
          ? null
          : {
              'credited': data['claimable'] ?? 0,
              'events': data['claim_events'] ?? const [],
            };
      // null = hata/timeout (api_service yutmuyor → null). Gerçek boş
      // portföy 200 + {has_data:false} döner (null DEĞİL) → ikisi ayrı.
      _error = data == null;
      _loading = false;
    });
  }

  Future<void> _collect() async {
    final uid = context.read<AuthProvider>().userId;
    if (uid == null) return;
    setState(() => _collecting = true);
    final r = await _api.collectDividends(uid);
    if (!mounted) return;
    setState(() => _collecting = false);
    if (r == null) return;
    final credited = (r['credited'] as num?)?.toDouble() ?? 0;
    if (credited > 0) {
      await context.read<PortfolioProvider>().refreshAll();
      await _load();
    }
    if (!mounted) return;
    final c = AppColorsExt.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: c.surfaceAlt,
      content: Text(
        credited > 0
            ? 'Tahsil edildi: ₺${formatMoney(credited)} temettü geliri kaydedildi.'
            : 'Tahsil edilecek yeni kâr payı yok — hepsi güncel.',
        style: TextStyle(color: c.textPrimary),
      ),
    ));
  }

  // 'yyyy-mm-dd' → '17 May 2026'. Geçersizde '—'.
  static const _months = [
    '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
  ];
  ({String day, String mon, String year}) _parseDate(String? iso) {
    if (iso == null || iso.length < 10) {
      return (day: '—', mon: '', year: '');
    }
    final p = iso.split('-');
    if (p.length < 3) return (day: iso, mon: '', year: '');
    final mi = int.tryParse(p[1]) ?? 0;
    final day = int.tryParse(p[2])?.toString() ?? p[2];
    final mon = (mi > 0 && mi < 13) ? _months[mi] : p[1];
    return (day: day, mon: mon, year: p[0]);
  }

  String _fmtDate(String? iso) {
    final d = _parseDate(iso);
    if (d.mon.isEmpty) return d.day;
    return '${d.day} ${d.mon} ${d.year}';
  }

  // Bugüne göre "23 gün sonra" / "yarın" / "bugün" / geçtiyse '—'.
  String? _relative(String? iso) {
    if (iso == null || iso.length < 10) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    final now = DateTime.now();
    final days = DateTime(dt.year, dt.month, dt.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days < 0) return null;
    if (days == 0) return 'bugün';
    if (days == 1) return 'yarın';
    if (days < 7) return '$days gün sonra';
    if (days < 35) return '${(days / 7).round()} hafta sonra';
    return '${(days / 30).round()} ay sonra';
  }

  // Bugünden hedefe gün farkı (geçmiş → negatif). Geçersizde null.
  int? _daysUntil(String? iso) {
    if (iso == null || iso.length < 10) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    final now = DateTime.now();
    return DateTime(dt.year, dt.month, dt.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
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
        title: Text('Temettü Takibi',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
            color: c.warmAccent,
            backgroundColor: c.surface,
            onRefresh: _load,
            child: EliteFade(
              child: _loading
                  ? _loadingState()
                  : KeyedSubtree(
                      key: const ValueKey('div-body'), child: _buildBody(c)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadingState() {
    return ListView(
      key: const ValueKey('div-loading'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          EliteSpace.lg, EliteSpace.xs, EliteSpace.lg, EliteSpace.xl),
      children: const [
        EliteSkeleton(height: 132, radius: EliteRadii.md),
        SizedBox(height: EliteSpace.lg),
        EliteSkeleton(height: 16, width: 160),
        SizedBox(height: EliteSpace.md),
        EliteSkeleton(height: 84, radius: EliteRadii.md),
        SizedBox(height: EliteSpace.sm),
        EliteSkeleton(height: 84, radius: EliteRadii.md),
        SizedBox(height: EliteSpace.lg),
        EliteSkeleton(height: 200, radius: EliteRadii.md),
      ],
    );
  }

  Widget _buildBody(AppColorsExt c) {
    final d = _data;
    if (_error || d == null) {
      return _errorState(c);
    }
    if (d['has_data'] != true) {
      return _emptyState(c);
    }

    final items = ((d['items'] as List?) ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final estTry = (d['est_annual_try'] as num?)?.toDouble() ?? 0;
    final estUsd = (d['est_annual_usd'] as num?)?.toDouble() ?? 0;
    // Birleşik ₺ (TL + USD₺-karşılığı). Eski backend'de alan yoksa estTry'ye
    // düş (geriye uyum). Hero/aylık ortalama/oran HEP bunu kullanır →
    // başlık portföyün USD temettülerini de yansıtır (tahsilatla tutarlı).
    final estTotal = (d['est_annual_total_try'] as num?)?.toDouble() ?? estTry;
    final monthly = estTotal / 12.0;

    final collectedTotal = (d['collected_total_try'] as num?)?.toDouble() ?? 0;
    final collectedCount = (d['collected_count'] as num?)?.toInt() ?? 0;

    // Kesin tahsil-edilebilir (backend dry-run; collect ile birebir).
    final previewOk = _preview != null;
    final claimable = (_preview?['credited'] as num?)?.toDouble() ?? 0.0;
    final claimEvents = ((_preview?['events'] as List?) ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    // Yaklaşık portföy verimi (karışık para birimi → kaba, "≈").
    final holdings = context.read<PortfolioProvider>().totalHoldingsValue;
    final yieldPct = holdings > 0 ? estTotal / holdings * 100 : null;

    // Sıradaki ödemeler: next_ex_date olan + 12 aydan YAKIN olanlar.
    // 12 aydan uzak projeksiyonlar (ör. "40 ay sonra") gösterilmez —
    // o kadar uzakta tahmin güveni anlamsız, kullanıcıyı yanıltır.
    final upcoming = items.where((it) {
      final days = _daysUntil(it['next_ex_date'] as String?);
      return days != null && days >= 0 && days <= 366;
    }).toList()
      ..sort((a, b) =>
          (a['next_ex_date'] as String).compareTo(b['next_ex_date'] as String));

    // Kâr payı dağıtan hisse sayısı (kullanıcıya konuşurken kullanılır).
    final payerCount = items
        .where((it) => ((it['est_annual_income'] as num?) ?? 0) > 0)
        .length;
    final firstUp = upcoming.isNotEmpty ? upcoming.first : null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          EliteSpace.lg, EliteSpace.xs, EliteSpace.lg, EliteSpace.xl),
      children: [
        // ── 1. Hero — yıllık pasif gelir hedefi (insan dili) ────────
        _heroSummary(c, estTotal),

        // ── 2. AI Asistan özeti — duruma göre dinamik ───────────────
        const SizedBox(height: EliteSpace.md),
        _aiInsight(c, payerCount, monthly, firstUp),

        // ── 3. Aksiyon kutusu — Tahsilat ────────────────────────────
        const SizedBox(height: EliteSpace.xl),
        const EliteSectionLabel('Tahsilat'),
        if (previewOk && claimable > 0)
          _actionClaim(c, claimable, claimEvents)
        else
          _actionEmpty(c),

        // ── 4. Sıradaki Ödemeler (≤12 ay, açık etiketli) ────────────
        const SizedBox(height: EliteSpace.xl),
        EliteSectionLabel('Sıradaki Ödemeler',
            trailing: upcoming.isNotEmpty
                ? Text('${upcoming.length} hisse',
                    style: TextStyle(
                        color: c.textSubtle,
                        fontSize: 11,
                        fontWeight: FontWeight.w600))
                : null),
        if (upcoming.isEmpty)
          _inlineNote(
            c,
            'Önümüzdeki 12 ayda planlı bir kâr payı ödemesi görünmüyor.',
          )
        else
          for (int i = 0; i < upcoming.length; i++) ...[
            _upcomingCard(c, upcoming[i]),
            if (i != upcoming.length - 1) const SizedBox(height: EliteSpace.xs),
          ],

        // ── 5. Hisse hisse döküm + kompakt istatistik ───────────────
        const SizedBox(height: EliteSpace.xl),
        const EliteHairline(),
        const SizedBox(height: EliteSpace.lg),
        const EliteSectionLabel('Hisse Hisse Döküm'),
        _overviewCard(
            c, monthly, yieldPct, estUsd, collectedTotal, collectedCount),
        if (items.isNotEmpty) ...[
          const SizedBox(height: EliteSpace.md),
          EliteSurface(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _positionRow(c, items[i]),
                  if (i != items.length - 1) const EliteHairline(indent: 16),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── 1. Hero — "Yıllık Pasif Gelir Hedefin" ─────────────────────────
  Widget _heroSummary(AppColorsExt c, double estTry) {
    return EliteSurface(
      padding: const EdgeInsets.all(EliteSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_outlined, size: 18, color: c.warmAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tahmini Yıllık Kâr Payı Gelirin',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: EliteSpace.sm),
          MoneyText(
            estTry,
            currency: '₺',
            prefix: '≈',
            fontSize: 38,
            fontWeight: FontWeight.w700,
            color: c.warmAccent,
            letterSpacing: -1.0,
          ),
          const SizedBox(height: 8),
          Text(
            'Son 12 ayda dağıtılan kâr paylarına göre projeksiyon — şirketler '
            'aynı tempoda öderse, mevcut pozisyonlarının önümüzdeki 12 ayda '
            'üreteceği toplam gelir.',
            style: TextStyle(color: c.textMuted, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── 2. AI Asistan özeti — duruma göre konuşan metin ────────────────
  Widget _aiInsight(AppColorsExt c, int payerCount, double monthly,
      Map<String, dynamic>? firstUp) {
    final parts = <String>[];
    if (payerCount > 0) {
      parts.add('Portföyündeki $payerCount hisse düzenli olarak kâr payı '
          'dağıtıyor.');
    } else {
      parts.add('Portföyünde henüz düzenli kâr payı dağıtan bir hisse yok.');
    }
    if (monthly > 0) {
      parts.add(
          'Aynı tempoda devam ederse aylık ortalama ≈₺${formatMoney(monthly)} '
          'kâr payı geliri bekleniyor.');
    }
    if (firstUp != null) {
      final rel = _relative(firstUp['next_ex_date'] as String?);
      final sym = (firstUp['symbol'] as String? ?? '').trim();
      if (rel != null && sym.isNotEmpty) {
        parts.add('En yakın ödemen $rel $sym şirketinden gelecek.');
      }
    }
    return EliteSurface(
      padding: const EdgeInsets.all(EliteSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: c.warmAccentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.auto_awesome, color: c.warmAccent, size: 18),
          ),
          const SizedBox(width: EliteSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI ASİSTAN',
                  style: TextStyle(
                    color: c.textSubtle,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  parts.join(' '),
                  style:
                      TextStyle(color: c.textMuted, fontSize: 13, height: 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Boş durum — net, talimat verici ────────────────────────────────
  Widget _emptyState(AppColorsExt c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EliteSpace.xl),
        child: EliteSurface(
          padding: const EdgeInsets.all(EliteSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.savings_outlined, color: c.warmAccent, size: 40),
              const SizedBox(height: EliteSpace.md),
              Text(
                'Burada kâr payı gelirini takip edersin',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3),
              ),
              const SizedBox(height: EliteSpace.xs),
              Text(
                'Düzenli kâr payı dağıtan bir BIST hissesi (ör. bankalar, '
                'TÜPRAŞ, FROTO) aldığında: yılda ne kadar pasif gelir '
                'üreteceğini, hangi tarihte ne kadar ödeneceğini ve şimdiye '
                'dek nakde dönen toplamı buradan net görürsün.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: c.textMuted, fontSize: 13, height: 1.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hata durumu — boş portföyden AYRI (timeout/sunucu hatası) ──────
  // Eskiden hata sessizce "boş portföy" sanılıyordu; artık net + retry.
  Widget _errorState(AppColorsExt c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EliteSpace.xl),
        child: EliteSurface(
          padding: const EdgeInsets.all(EliteSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, color: c.textSubtle, size: 40),
              const SizedBox(height: EliteSpace.md),
              Text(
                'Kâr payı verisi şu an yüklenemedi',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3),
              ),
              const SizedBox(height: EliteSpace.xs),
              Text(
                'Bağlantı zaman aşımına uğramış olabilir. Birkaç saniye '
                'sonra tekrar dene — pozisyonların kayıp değil.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: c.textMuted, fontSize: 13, height: 1.55),
              ),
              const SizedBox(height: EliteSpace.lg),
              IOSPillButton(
                label: 'Tekrar Dene',
                onPressed: _load,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 1. AKSİYON: tahsil edilebilir tutar var ────────────────────────
  Widget _actionClaim(AppColorsExt c, double claimable,
      List<Map<String, dynamic>> claimEvents) {
    return EliteSurface(
      padding: const EdgeInsets.all(EliteSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TAHSİL EDİLEBİLİR KÂR PAYI',
            style: TextStyle(
              color: c.textSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          MoneyText(
            claimable,
            currency: '₺',
            fontSize: 40,
            fontWeight: FontWeight.w700,
            color: c.positive,
            letterSpacing: -1.0,
          ),
          const SizedBox(height: 4),
          Text(
            'Tahsil edince bu tutar işlem geçmişine temettü geliri olarak kaydedilir.',
            style: TextStyle(color: c.textMuted, fontSize: 12.5, height: 1.45),
          ),
          if (claimEvents.isNotEmpty) ...[
            const SizedBox(height: EliteSpace.sm),
            const EliteHairline(),
            const SizedBox(height: EliteSpace.xs),
            for (final e in claimEvents) _claimRow(c, e),
          ],
          const SizedBox(height: EliteSpace.md),
          IOSPillButton(
            label: 'Tahsil Et: ₺${formatMoney(claimable)}',
            width: double.infinity,
            isLoading: _collecting,
            onPressed: _collecting ? null : _collect,
          ),
        ],
      ),
    );
  }

  // ── 1. AKSİYON: tahsil edilecek bir şey yok / dry-run başarısız ────
  // Teknik "idempotent" jargonu YOK — sade, zarif boş durum.
  Widget _actionEmpty(AppColorsExt c) {
    return EliteSurface(
      padding: const EdgeInsets.symmetric(
          horizontal: EliteSpace.lg, vertical: EliteSpace.xl),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: c.textSubtle),
          const SizedBox(width: EliteSpace.sm),
          Expanded(
            child: Text(
              'Şu an tahsil edilecek kâr payı bulunmuyor.',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Genel İstatistikler — kompakt tek kart ──────────────────────
  Widget _overviewCard(AppColorsExt c, double monthly, double? yieldPct,
      double estUsd, double collectedTotal, int collectedCount) {
    return EliteSurface(
      padding: const EdgeInsets.symmetric(horizontal: EliteSpace.md),
      child: Column(
        children: [
          _ovRow(c, 'Aylık ortalama gelir', '₺${formatMoney(monthly)}'),
          const EliteHairline(),
          _ovRow(c, 'Portföyüne oranı',
              yieldPct != null ? '≈%${formatPct(yieldPct)}' : '—'),
          if (estUsd > 0) ...[
            const EliteHairline(),
            _ovRow(c, 'Yabancı hisseler (yıllık)', '≈\$${formatMoney(estUsd)}'),
          ],
          const EliteHairline(),
          _ovRow(
            c,
            'Şimdiye dek tahsil edilen',
            collectedCount > 0
                ? '₺${formatMoney(collectedTotal)} · $collectedCount ödeme'
                : '—',
            valueColor: collectedTotal > 0 ? c.positive : null,
          ),
        ],
      ),
    );
  }

  Widget _ovRow(AppColorsExt c, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: c.textMuted, fontSize: 13, letterSpacing: -0.1)),
          ),
          const SizedBox(width: 12),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? c.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
        ],
      ),
    );
  }

  // ── Referans satır (IMG_1101): solda 2 satır ticker/şirket,
  //    sağda belirgin tutar + altında küçük zarif durum etiketi.
  //    Tutarlar tahmin → MoneyText prefix '≈' ile dürüstlük korunur
  //    (ekran sözleşmesi: uydurma kesin rakam GÖSTERİLMEZ).
  Widget _listRow(
    AppColorsExt c, {
    required String symbol,
    required double amount,
    required String currency,
    required Color amountColor,
    required String status,
    required Color statusColor,
  }) {
    _ferryName(symbol);
    final ticker = SymbolDisplay.compact(symbol);
    final sub = _subtitle(symbol);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ticker,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2)),
              if (sub != null) ...[
                const SizedBox(height: 3),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.textSubtle,
                        fontSize: 11.5,
                        letterSpacing: -0.1)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MoneyText(
              amount,
              currency: currency,
              prefix: '≈',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: amountColor,
              letterSpacing: -0.3,
            ),
            const SizedBox(height: 4),
            Text(status,
                style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
          ],
        ),
      ],
    );
  }

  // ── 2. Sıradaki ödeme — ticker + tutar + tarih (asıl bilgi!) +
  //    "tahmini" rozeti (next_ex_estimated:true ise; backend çoğu sembolde
  //    geçmiş periyot + son ex'ten projeksiyon yapıyor → dürüst etiket).
  Widget _upcomingCard(AppColorsExt c, Map<String, dynamic> it) {
    final cur = it['currency'] as String? ?? '₺';
    final sym = it['symbol'] as String? ?? '';
    final payout = (it['next_payout'] as num?)?.toDouble() ?? 0;
    final nextEx = it['next_ex_date'] as String?;
    final estimated = it['next_ex_estimated'] != false;
    final rel = _relative(nextEx);
    final dateStr = _fmtDate(nextEx);
    _ferryName(sym);
    final ticker = SymbolDisplay.compact(sym);
    final sub = _subtitle(sym);
    return EliteSurface(
      padding: const EdgeInsets.all(EliteSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ticker,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2)),
                    if (sub != null) ...[
                      const SizedBox(height: 3),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.textSubtle,
                              fontSize: 11.5,
                              letterSpacing: -0.1)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              MoneyText(
                payout,
                currency: cur,
                prefix: '≈',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.positive,
                letterSpacing: -0.3,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Tarih satırı — ekranın asıl değeri burada: "ne zaman ödenecek?"
          Row(
            children: [
              Icon(Icons.event_outlined, size: 13, color: c.warmAccent),
              const SizedBox(width: 6),
              Text(dateStr,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1)),
              if (rel != null) ...[
                const SizedBox(width: 6),
                Text('· $rel',
                    style: TextStyle(color: c.textMuted, fontSize: 12)),
              ],
              const Spacer(),
              if (estimated)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.warmAccentSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('tahmini',
                      style: TextStyle(
                          color: c.warmAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Kesin tahsil-edilebilir satır (dry-run event: symbol/date/amount).
  Widget _claimRow(AppColorsExt c, Map<String, dynamic> e) {
    final sym = e['symbol'] as String? ?? '';
    final amt = (e['amount'] as num?)?.toDouble() ?? 0;
    final date = e['date'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, size: 13, color: c.positive),
          const SizedBox(width: 8),
          Expanded(
            child: Text(sym,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1)),
          ),
          Text(_fmtDate(date),
              style: TextStyle(color: c.textSubtle, fontSize: 11.5)),
          const SizedBox(width: 14),
          Text('+₺${formatMoney(amt)}',
              style: TextStyle(
                  color: c.positive,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Açıklama notu ──────────────────────────────────────────────────
  Widget _inlineNote(AppColorsExt c, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, EliteSpace.sm),
      child: Text(
        text,
        style: TextStyle(color: c.textSubtle, fontSize: 11.5, height: 1.5),
      ),
    );
  }

  // ── Hisse hisse satır — referans satır; durum = tahsil hâli ────────
  // Tıklama → detay sayfası (tahsil edilen ₺ orada; satır sade kalır).
  Widget _positionRow(AppColorsExt c, Map<String, dynamic> it) {
    final cur = it['currency'] as String? ?? '₺';
    final sym = it['symbol'] as String? ?? '';
    final annual = (it['est_annual_income'] as num?)?.toDouble() ?? 0;
    final collected = (it['collected_try'] as num?)?.toDouble() ?? 0;

    return InkWell(
      onTap: () => _showDetail(c, it),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: EliteSpace.md, vertical: 13),
        child: _listRow(
          c,
          symbol: sym,
          amount: annual,
          currency: cur,
          amountColor: c.textPrimary,
          status: collected > 0 ? 'TAMAMLANDI' : 'TAKİPTE',
          statusColor: c.textSubtle,
        ),
      ),
    );
  }

  void _showDetail(AppColorsExt c, Map<String, dynamic> it) {
    final cur = it['currency'] as String? ?? '₺';
    final sym = it['symbol'] as String? ?? '';
    final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
    final lastAmt = (it['last_amount'] as num?)?.toDouble() ?? 0;
    final lastDate = it['last_date'] as String? ?? '';
    final ttm = (it['ttm_per_share'] as num?)?.toDouble() ?? 0;
    final annual = (it['est_annual_income'] as num?)?.toDouble() ?? 0;
    final collected = (it['collected_try'] as num?)?.toDouble() ?? 0;
    final nextEx = it['next_ex_date'] as String?;
    final isTry = cur == '₺';

    final estimated = it['next_ex_estimated'] != false;
    final nextStr = nextEx != null
        ? '${_fmtDate(nextEx)}${estimated ? '  (tahmini)' : ''}'
        : 'Açıklanmadı';

    showIOSBottomSheet(
      context: context,
      title: sym,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _statTile(
                      c, 'Yıllık tahmini gelir', '$cur${formatMoney(annual)}'),
                ),
                const SizedBox(width: EliteSpace.xs),
                Expanded(
                  child: _statTile(
                      c, 'Bugüne dek tahsil', '₺${formatMoney(collected)}',
                      highlight: collected > 0 ? c.positive : null),
                ),
              ],
            ),
            const SizedBox(height: EliteSpace.md),
            _detailRow(c, 'Elindeki adet', formatQty(qty)),
            _detailRow(
                c, 'Son ödenen (hisse başı)', '$cur${formatMoney(lastAmt)}'),
            _detailRow(c, 'Son ödeme tarihi', _fmtDate(lastDate)),
            _detailRow(c, 'Son 12 ay (hisse başı)', '$cur${formatMoney(ttm)}'),
            _detailRow(c, 'Sıradaki hak tarihi', nextStr),
            const SizedBox(height: EliteSpace.md),
            EliteSurface(
              elevatedTone: true,
              padding: const EdgeInsets.all(13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, size: 16, color: c.positive),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      isTry
                          ? 'Bu hisseyi aldıktan sonra dağıtılan kâr payları '
                              '₺ olarak temettü geliri kaydedilir.'
                          : 'Yabancı hisse: aldıktan sonraki kâr payları '
                              'tahsil edilirken güncel kurla ₺\'ye çevrilip '
                              'gelir olarak kaydedilir.',
                      style: TextStyle(
                          color: c.textMuted, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(AppColorsExt c, String label, String value,
      {Color? highlight}) {
    return EliteSurface(
      elevatedTone: true,
      padding: const EdgeInsets.symmetric(
          horizontal: EliteSpace.md, vertical: EliteSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: c.textMuted, fontSize: 11.5, letterSpacing: -0.1)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: highlight ?? c.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4)),
        ],
      ),
    );
  }

  Widget _detailRow(AppColorsExt c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child:
                Text(label, style: TextStyle(color: c.textMuted, fontSize: 13)),
          ),
          Text(value,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
