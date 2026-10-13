import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/auth_provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/utils/pdf_pick.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

/// Aracı kurum ekstresi (Midas PDF) → portföy içe aktarma.
///
/// Ekran görüntüsü OCR'ından (ImportPortfolioScreen) farkı: PDF metin katmanı
/// taşıdığı için okuma deterministik — AI yok, hata payı yok, tarih ve
/// komisyon da geliyor.
///
/// İKİ MOD (ikisi de aynı ekstreden çıkar, kullanıcı seçer):
///  - **Portföy Özeti**: aracı kurumun kendi adet + ortalama maliyet kaydı.
///    TEK dosyayla portföy doğru kurulur. Hesap yıllar önce açılmışsa ve elde
///    yalnız son ayların ekstresi varsa doğru seçim budur (varsayılan).
///  - **İşlem Geçmişi**: alış/satışları kronolojik oynatır. Ancak hesap
///    açılışından beri TÜM ekstreler yüklendiyse portföyü doğru kurar.
///
/// Akış her zaman iki adım: önce oku (hiçbir şey kaydedilmez), sonra kullanıcı
/// önizlemede kontrol edip onaylar. Kaynak PDF formatı değişirse sessizce
/// yanlış veri girmemesinin tek güvencesi bu.
class ImportStatementScreen extends StatefulWidget {
  const ImportStatementScreen({super.key});

  @override
  State<ImportStatementScreen> createState() => _ImportStatementScreenState();
}

/// Düzenleme alanları Türkçe biçim gösterir (`formatMoney` → "1.234,56",
/// `formatQty` → "0,802980132"). Geri okurken binlik noktası atılır, ondalık
/// virgül noktaya çevrilir; kullanıcı nokta ile de yazabilir. Test edilebilsin
/// diye sınıf dışında.
double? parseEditedNumber(String s) {
  var t = s.trim();
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.'); // 1.234,56 → 1234.56
  }
  return double.tryParse(t);
}

enum _Mode { positions, trades }

class _PositionDraft {
  final String symbol;
  final String name;
  double quantity;
  double avgCost;
  final String currency;
  bool include = true;

  _PositionDraft({
    required this.symbol,
    required this.name,
    required this.quantity,
    required this.avgCost,
    required this.currency,
  });

  /// Maliyeti olmayan satır (bedelsiz/rüçhan kaydı) portföy değerini bozar.
  bool get importable => quantity > 0 && avgCost > 0;
}

class _TradeDraft {
  final String date;
  final String symbol;
  final String side;
  final double quantity;
  final double price;
  final String currency;
  bool include = true;

  _TradeDraft({
    required this.date,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.price,
    required this.currency,
  });
}

class _ImportStatementScreenState extends State<ImportStatementScreen> {
  final _api = ApiService();

  bool _isParsing = false;
  bool _isSubmitting = false;
  String? _parseLabel;

  _Mode _mode = _Mode.positions;
  List<_PositionDraft> _positions = [];
  List<_TradeDraft> _trades = [];
  List<String> _failedFiles = [];
  int _fileCount = 0;
  int _cancelledOrders = 0;
  String _asOf = '';
  List<String> _dateRange = [];
  List<String> _brokers = [];
  bool _generic = false;
  bool _parsed = false;

  Future<void> _pickAndParse() async {
    final files = await pickPdfsWeb();
    if (files.isEmpty || !mounted) return;

    setState(() {
      _isParsing = true;
      _parseLabel = files.length > 1
          ? '${files.length} ekstre okunuyor…'
          : 'Ekstre okunuyor…';
    });

    Map<String, dynamic> data;
    try {
      data = await _api.parseBrokerStatements(
        files.map((f) => (bytes: f.bytes, filename: f.filename)).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
        _parseLabel = null;
      });
      _snack(
        e is ApiException ? e.message : 'Ekstre okunamadı, dosyaları kontrol et',
        error: true,
      );
      return;
    }
    if (!mounted) return;

    final positions = ((data['positions'] as List?) ?? const [])
        .map((p) => _PositionDraft(
              symbol: '${p['symbol']}',
              name: '${p['name'] ?? ''}',
              quantity: (p['quantity'] as num?)?.toDouble() ?? 0,
              avgCost: (p['avg_cost'] as num?)?.toDouble() ?? 0,
              currency: '${p['currency'] ?? 'USD'}',
            ))
        .toList();
    // Maliyeti olmayan satırlar baştan işaretsiz gelsin — kullanıcı isterse açar.
    for (final p in positions) {
      if (!p.importable) p.include = false;
    }

    final trades = ((data['rows'] as List?) ?? const [])
        .map((r) => _TradeDraft(
              date: '${r['date']}',
              symbol: '${r['symbol']}',
              side: '${r['side']}',
              quantity: (r['quantity'] as num?)?.toDouble() ?? 0,
              price: (r['price'] as num?)?.toDouble() ?? 0,
              currency: '${r['currency'] ?? 'USD'}',
            ))
        .toList();

    setState(() {
      _isParsing = false;
      _parseLabel = null;
      _parsed = true;
      _positions = positions;
      _trades = trades;
      _fileCount = (data['file_count'] as num?)?.toInt() ?? files.length;
      _cancelledOrders = (data['cancelled_orders'] as num?)?.toInt() ?? 0;
      _asOf = '${data['positions_as_of'] ?? ''}';
      _dateRange =
          ((data['date_range'] as List?) ?? const []).map((e) => '$e').toList();
      _failedFiles = ((data['failed_files'] as List?) ?? const [])
          .map((f) => '${f['file']}: ${f['error']}')
          .toList();
      _brokers =
          ((data['brokers'] as List?) ?? const []).map((e) => '$e').toList();
      _generic = data['generic'] == true;
      // Portföy özeti yoksa tek anlamlı mod işlem geçmişidir.
      if (positions.isEmpty && trades.isNotEmpty) _mode = _Mode.trades;
    });
  }

  int get _selectedCount => _mode == _Mode.positions
      ? _positions.where((p) => p.include && p.importable).length
      : _trades.where((t) => t.include).length;

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    if (userId == null) {
      _snack('Oturum bulunamadı, tekrar giriş yap', error: true);
      return;
    }

    setState(() => _isSubmitting = true);
    Map<String, dynamic> res;
    try {
      if (_mode == _Mode.positions) {
        res = await _api.commitStatementImport(
          userId: userId,
          mode: 'positions',
          positions: _positions
              .where((p) => p.include && p.importable)
              .map((p) => {
                    'symbol': p.symbol,
                    'quantity': p.quantity,
                    'avg_cost': p.avgCost,
                  })
              .toList(),
          positionsAsOf: _isoAsOf(),
        );
      } else {
        res = await _api.commitStatementImport(
          userId: userId,
          mode: 'trades',
          rows: _trades
              .where((t) => t.include)
              .map((t) => {
                    'date': t.date,
                    'symbol': t.symbol,
                    'side': t.side,
                    'quantity': t.quantity,
                    'price': t.price,
                  })
              .toList(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _snack(e is ApiException ? e.message : 'Aktarım başarısız', error: true);
      return;
    }
    if (!mounted) return;

    // Aktarım BİTTİ; veri kaydedildi. Portföy yenilemesini BEKLEME:
    // yeni gelen 24 sembolün fiyatı çekilirken (soğuk Render'da iki denemeyle
    // dakikalarca sürebiliyor) bu ekran ölü kalıyordu — buton yeniden aktif
    // görünüyor ama hiçbir şey olmuyordu. Yenilemeyi tetikleyip hemen geri
    // dönüyoruz; portföy ekranının kendi yükleniyor durumu var.
    final provider = context.read<PortfolioProvider>();
    final skipped = (res['skipped'] as List?) ?? const [];

    _snack('${res['message'] ?? 'Aktarım tamamlandı'}');
    if (skipped.isNotEmpty) {
      await _showSkippedDialog(skipped.map((e) => '$e').toList());
      if (!mounted) return;
    }

    unawaited(provider.loadMyPortfolio());
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    Navigator.pop(context, true);
  }

  /// 'gg/aa/yy' → ISO. Portföy özetinin kesim tarihi, kaydedilen işlemlerin
  /// zaman damgası olur (temettü cutoff'u tutarlı kalsın).
  String? _isoAsOf() {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{2})$').firstMatch(_asOf);
    if (m == null) return null;
    final yy = int.parse(m.group(3)!);
    final year = yy < 80 ? 2000 + yy : 1900 + yy;
    return '$year-${m.group(2)}-${m.group(1)}T00:00:00';
  }

  Future<void> _showSkippedDialog(List<String> skipped) {
    final c = AppColorsExt.of(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('${skipped.length} satır aktarılamadı',
            style: TextStyle(color: c.textPrimary, fontSize: 16)),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: skipped
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $s',
                            style: TextStyle(
                                color: c.textMuted, fontSize: 12, height: 1.4)),
                      ))
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _editPosition(_PositionDraft p) async {
    final c = AppColorsExt.of(context);
    final qty = TextEditingController(text: formatQty(p.quantity, maxDecimals: 9));
    final cost = TextEditingController(text: formatMoney(p.avgCost));

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${SymbolDisplay.compact(p.symbol)} düzelt',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            IOSField(
              controller: qty,
              label: 'Adet',
              icon: Icons.numbers_rounded,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            IOSField(
              controller: cost,
              label: 'Hisse başı ortalama maliyet (${p.currency})',
              icon: Icons.payments_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            IOSPillButton(
              label: 'Kaydet',
              width: double.infinity,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;
    setState(() {
      p.quantity = _parseNum(qty.text) ?? p.quantity;
      p.avgCost = _parseNum(cost.text) ?? p.avgCost;
      if (p.importable) p.include = true;
    });
  }

  static double? _parseNum(String s) => parseEditedNumber(s);

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFFB7185) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: const Text('Ekstreden İçe Aktar'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: _parsed ? _buildPreview(c) : _buildIntro(c),
        ),
      ),
      bottomNavigationBar: _parsed ? _buildFooter(c) : null,
    );
  }

  // ── Başlangıç: nasıl alınır + yükle ────────────────────────────────────
  List<Widget> _buildIntro(AppColorsExt c) {
    return [
      Text(
        'Aracı kurum ekstreni (PDF) yükle; pozisyonların, maliyetlerin ve '
        'işlem geçmişin otomatik okunsun. Ekran görüntüsünün aksine PDF '
        'birebir okunur — tarih ve komisyon da gelir.',
        style: TextStyle(
            color: c.textMuted, fontSize: 13, letterSpacing: -0.1, height: 1.5),
      ),
      const SizedBox(height: 18),
      _card(c, [
        Text('Midas ekstresi nasıl alınır',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2)),
        const SizedBox(height: 10),
        _step(c, '1', 'Midas uygulaması → Menü'),
        _step(c, '2', 'Profil ve Ayarlar → Belgeler → Ekstreler'),
        _step(c, '3', 'İncelemek istediğin ayı seç ve PDF olarak indir'),
        const SizedBox(height: 8),
        Text(
          'Midas ekstreyi yalnız aylık veriyor. Birden çok ayı bir kerede '
          'seçebilirsin — hepsi birleştirilir, iki ekstrede birden geçen '
          'işlem bir kez sayılır.',
          style: TextStyle(color: c.textSubtle, fontSize: 12, height: 1.45),
        ),
      ]),
      if (kIsWeb) ...[
        const SizedBox(height: 16),
        IOSPillButton(
          label: _isParsing ? (_parseLabel ?? 'Okunuyor…') : 'Ekstre Yükle (PDF)',
          icon: Icons.description_outlined,
          width: double.infinity,
          isLoading: _isParsing,
          onPressed: _isParsing ? null : _pickAndParse,
        ),
        const SizedBox(height: 8),
        Text(
          'Kaydetmeden önce okunanları kontrol edersin. En fazla 36 dosya.',
          style: TextStyle(color: c.textSubtle, fontSize: 12, height: 1.45),
        ),
      ] else ...[
        const SizedBox(height: 16),
        Text(
          'Ekstre yükleme şu an yalnız web sürümünde. Telefondan girmek için '
          '"Portföyümü Gir" ekranını kullanabilirsin.',
          style: TextStyle(color: c.textSubtle, fontSize: 12, height: 1.45),
        ),
      ],
    ];
  }

  /// IOSGroupedCard `children` alır ve aralarına ayraç koyar; buradaki
  /// kartlar tek gövde olduğundan içeriği tek Padding'e sarıyoruz.
  Widget _card(AppColorsExt c, List<Widget> children) => IOSGroupedCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      );

  Widget _step(AppColorsExt c, String no, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              child: Text(no,
                  style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: c.textMuted, fontSize: 13, height: 1.4)),
            ),
          ],
        ),
      );

  // ── Önizleme ───────────────────────────────────────────────────────────
  List<Widget> _buildPreview(AppColorsExt c) {
    return [
      _summaryCard(c),
      if (_generic) ...[
        const SizedBox(height: 10),
        _warnCard(
          c,
          'Tahmini okuma',
          'Bu ekstrenin kurumu için hazır bir profil yok; satırlar sütun '
              'başlıklarından ve adet × fiyat = tutar ilişkisinden çıkarıldı. '
              'Midas ekstresi kadar kesin DEĞİL — aktarmadan önce adet ve '
              'fiyatları tek tek kontrol et.',
        ),
      ],
      if (_failedFiles.isNotEmpty) ...[
        const SizedBox(height: 10),
        _warnCard(c, 'Okunamayan dosya', _failedFiles.join('\n')),
      ],
      const SizedBox(height: 16),
      IOSSegmented<_Mode>(
        options: [
          (_Mode.positions, 'Portföy Özeti (${_positions.length})'),
          (_Mode.trades, 'İşlem Geçmişi (${_trades.length})'),
        ],
        value: _mode,
        onChange: (m) => setState(() => _mode = m),
      ),
      const SizedBox(height: 10),
      Text(
        _mode == _Mode.positions
            ? 'Aracı kurumun kendi adet ve ortalama maliyet kaydı. Mevcut '
                'pozisyonlarının üstüne EKLENMEZ, onlarla değiştirilir — '
                'bu yüzden tek ekstre yeterlidir.'
            : 'Alış/satışlar tarih sırasıyla işlenir. Portföyün doğru çıkması '
                'için hesap açılışından bugüne TÜM ekstreler yüklenmiş olmalı; '
                'eksik dönem varsa maliyet yanlış hesaplanır.',
        style: TextStyle(color: c.textSubtle, fontSize: 12, height: 1.45),
      ),
      if (_mode == _Mode.trades && _trades.isNotEmpty) ...[
        const SizedBox(height: 10),
        _warnCard(
          c,
          'Dikkat',
          'Yalnız ${_dateRange.isNotEmpty ? "${_dateRange.first} – ${_dateRange.last}" : "seçilen dönem"} '
              'arası yüklendi. Daha eski işlemlerin varsa portföy eksik kurulur — '
              'onun yerine Portföy Özeti modunu kullan.',
        ),
      ],
      const SizedBox(height: 14),
      if (_mode == _Mode.positions)
        ..._positions.map((p) => _positionRow(c, p))
      else
        ..._trades.map((t) => _tradeRow(c, t)),
      const SizedBox(height: 8),
      IOSPillButton(
        label: 'Başka Ekstre Yükle',
        icon: Icons.refresh_rounded,
        secondary: true,
        width: double.infinity,
        onPressed: _isParsing ? null : _pickAndParse,
      ),
    ];
  }

  Widget _summaryCard(AppColorsExt c) {
    final parts = <String>[
      '$_fileCount dosya okundu',
      '${_trades.length} işlem',
      '${_positions.length} pozisyon',
    ];
    return _card(c, [
      Text(parts.join(' · '),
          style: TextStyle(
              color: c.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2)),
      const SizedBox(height: 8),
      if (_dateRange.length == 2)
        _kv(c, 'İşlem aralığı', '${_dateRange.first} – ${_dateRange.last}'),
      if (_brokers.isNotEmpty) _kv(c, 'Kurum', _brokers.join(', ')),
      if (_asOf.isNotEmpty) _kv(c, 'Portföy kesiti', _asOf),
      if (_cancelledOrders > 0) _kv(c, 'Atlanan iptal emri', '$_cancelledOrders'),
    ]);
  }

  Widget _kv(AppColorsExt c, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: c.textSubtle, fontSize: 12)),
            Text(v,
                style: TextStyle(
                    color: c.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _warnCard(AppColorsExt c, String title, String body) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.warmAccentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    color: c.warmAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body,
                style:
                    TextStyle(color: c.textMuted, fontSize: 12, height: 1.45)),
          ],
        ),
      );

  Widget _positionRow(AppColorsExt c, _PositionDraft p) {
    final blocked = !p.importable;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _check(c, p.include && !blocked, blocked ? null : () {
            setState(() => p.include = !p.include);
          }),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(SymbolDisplay.compact(p.symbol),
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (p.name.isNotEmpty)
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSubtle, fontSize: 11)),
                if (blocked)
                  Text('maliyet yok — düzeltmeden aktarılamaz',
                      style: TextStyle(color: c.warmAccent, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${formatQty(p.quantity, maxDecimals: 6)} adet',
                  style: TextStyle(
                      color: c.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text('${formatMoney(p.avgCost)} ${p.currency}',
                  style: TextStyle(color: c.textSubtle, fontSize: 11)),
            ],
          ),
          IconButton(
            onPressed: () => _editPosition(p),
            icon: Icon(Icons.edit_outlined, size: 17, color: c.textSubtle),
            tooltip: 'Düzelt',
          ),
        ],
      ),
    );
  }

  Widget _tradeRow(AppColorsExt c, _TradeDraft t) {
    final isBuy = t.side == 'BUY';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _check(c, t.include, () => setState(() => t.include = !t.include)),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            child: Text(isBuy ? 'AL' : 'SAT',
                style: TextStyle(
                    color: isBuy ? c.positive : c.negative,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(SymbolDisplay.compact(t.symbol),
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(t.date.length >= 10 ? t.date.substring(0, 10) : t.date,
                    style: TextStyle(color: c.textSubtle, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${formatQty(t.quantity, maxDecimals: 6)} adet',
                  style: TextStyle(
                      color: c.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text('${formatMoney(t.price)} ${t.currency}',
                  style: TextStyle(color: c.textSubtle, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _check(AppColorsExt c, bool on, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: on ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            border: on ? null : Border.all(color: c.divider, width: 1.4),
          ),
          // Tik, accent'in ÜSTÜNE çizilir: accent koyu temada beyaz, açık
          // temada siyah → zıt renk her zaman arka plan rengidir.
          child: on
              ? Icon(Icons.check_rounded, size: 14, color: c.bg)
              : null,
        ),
      );

  Widget _buildFooter(AppColorsExt c) {
    final n = _selectedCount;
    final label = _mode == _Mode.positions ? 'pozisyon' : 'işlem';
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              n == 0 ? 'Seçili $label yok' : '$n $label aktarılacak',
              style:
                  TextStyle(color: c.textMuted, fontSize: 12, letterSpacing: -0.1),
            ),
            const SizedBox(height: 10),
            IOSPillButton(
              label: n == 0 ? 'Aktar' : 'Aktar ($n)',
              width: double.infinity,
              isLoading: _isSubmitting,
              onPressed: (_isSubmitting || n == 0) ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
