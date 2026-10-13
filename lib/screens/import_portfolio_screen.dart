import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/utils/image_pick.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/widgets/symbol_search_sheet.dart';

/// Toplu portföy girişi — kullanıcının GERÇEKTE sahip olduğu birden çok
/// pozisyonu tek ekranda (sembol + lot + maliyet) tanımlar. Screenshot→AI
/// import'un döktüğü "review" ekranı da budur: AI satırları doldurur,
/// kullanıcı düzeltip kaydeder.
class ImportPortfolioScreen extends StatefulWidget {
  const ImportPortfolioScreen({super.key});

  @override
  State<ImportPortfolioScreen> createState() => _ImportPortfolioScreenState();
}

class _Draft {
  StockModel? stock;
  final TextEditingController lot = TextEditingController();
  final TextEditingController cost = TextEditingController();

  /// Screenshot'tan gelip eşlenemeyen pozisyonun ham okunan adı — kullanıcı
  /// "Hisse seç"e basıp düzeltsin diye ipucu olarak gösterilir.
  String? unmatchedHint;

  void dispose() {
    lot.dispose();
    cost.dispose();
  }
}

class _ImportPortfolioScreenState extends State<ImportPortfolioScreen> {
  final ApiService _api = ApiService();
  final List<_Draft> _rows = [_Draft()];
  bool _isSubmitting = false;
  bool _isParsing = false;
  String? _parseLabel;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  double _parse(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? 0;

  bool _isValid(_Draft d) =>
      d.stock != null && _parse(d.lot.text) > 0 && _parse(d.cost.text) > 0;

  int get _validCount => _rows.where(_isValid).length;

  /// Hiç doldurulmamış yer-tutucu satır — screenshot içe aktarırken bunlar
  /// atılır, dolu satırlar korunup üstüne yeni pozisyonlar eklenir.
  bool _isEmptyDraft(_Draft d) =>
      d.stock == null &&
      d.lot.text.trim().isEmpty &&
      d.cost.text.trim().isEmpty &&
      d.unmatchedHint == null;

  void _addRow() {
    setState(() => _rows.add(_Draft()));
  }

  void _removeRow(int i) {
    setState(() {
      _rows.removeAt(i).dispose();
      if (_rows.isEmpty) _rows.add(_Draft());
    });
  }

  Future<void> _pickSymbol(int i) async {
    FocusScope.of(context).unfocus();
    final stock = await showSymbolSearchSheet(context);
    if (stock == null || !mounted) return;
    setState(() {
      _rows[i].stock = stock;
      _rows[i].unmatchedHint = null;
      // Maliyeti güncel fiyatla ön-doldur (kullanıcı düzeltebilir).
      if (stock.rawPrice > 0 && _rows[i].cost.text.isEmpty) {
        _rows[i].cost.text = stock.rawPrice.toStringAsFixed(2);
      }
    });
  }

  Future<void> _importFromScreenshot() async {
    var images = await pickImagesWeb();
    if (images.isEmpty || !mounted) return;

    // Tek seferde en fazla 10 görsel — fazlası ağır OCR yükü, çökme riski.
    var capped = false;
    if (images.length > 10) {
      images = images.sublist(0, 10);
      capped = true;
    }

    setState(() {
      _isParsing = true;
      _parseLabel = images.length > 1 ? 'Görseller okunuyor…' : null;
    });
    if (capped) _snack('En fazla 10 görsel — ilk 10 alındı');

    // Her görseli sırayla OCR'dan geçir; okunan tüm pozisyonları biriktir.
    final drafts = <_Draft>[];
    var unmatched = 0;
    var failedImages = 0;
    for (var idx = 0; idx < images.length; idx++) {
      final img = images[idx];
      if (mounted && images.length > 1) {
        setState(
            () => _parseLabel = 'Görsel ${idx + 1}/${images.length} okunuyor…');
      }
      List<Map<String, dynamic>> positions;
      try {
        positions = await _api.parsePortfolioScreenshot(
            img.bytes, img.filename, img.mime);
      } catch (_) {
        failedImages++;
        continue;
      }
      for (final p in positions) {
        final d = _draftFromPosition(p);
        if (d.stock == null) unmatched++;
        drafts.add(d);
      }
    }
    if (!mounted) return;

    if (drafts.isEmpty) {
      setState(() {
        _isParsing = false;
        _parseLabel = null;
      });
      _snack(
        failedImages > 0
            ? 'AI görseli şu an okuyamadı (meşgul olabilir) — birazdan tekrar dene ya da elle gir'
            : 'Görselde pozisyon bulunamadı — elle girebilirsin',
        error: true,
      );
      return;
    }

    setState(() {
      // Mevcut DOLU satırları koru; sadece boş yer-tutucuları at, üstüne ekle.
      final kept = _rows.where((r) => !_isEmptyDraft(r)).toList();
      for (final r in _rows) {
        if (!kept.contains(r)) r.dispose();
      }
      _rows
        ..clear()
        ..addAll(kept)
        ..addAll(drafts);
      _isParsing = false;
      _parseLabel = null;
    });

    final parts = <String>['${drafts.length} pozisyon eklendi'];
    if (unmatched > 0) parts.add('$unmatched tanesi eşlenemedi, hisseyi sen seç');
    if (failedImages > 0) parts.add('$failedImages görsel okunamadı');
    _snack(parts.join(' · '), error: failedImages > 0);
  }

  /// Tek bir OCR pozisyon kaydını taslak satıra çevirir; eşlenemezse
  /// `unmatchedHint` ile bırakır (kullanıcı hisseyi elle seçsin).
  _Draft _draftFromPosition(Map<String, dynamic> p) {
    final d = _Draft();
    final symbol = (p['symbol'] as String?) ?? '';
    final matched = (p['matched'] as bool?) ?? false;
    final qty = (p['quantity'] as num?)?.toDouble() ?? 0;
    final cost = (p['avg_cost'] as num?)?.toDouble() ?? 0;
    if (qty > 0) d.lot.text = _trim(qty);
    if (cost > 0) d.cost.text = _trim(cost);
    if (matched && symbol.isNotEmpty) {
      d.stock = StockModel(
        symbol: symbol,
        name: (p['name'] as String?) ?? symbol,
        price: '0.00',
        change: '0.00%',
        isUp: true,
        rawPrice: 0,
        currency: SymbolDisplay.currencyOf(symbol),
        isTurkish: symbol.endsWith('.IS') ||
            symbol.endsWith('.TR') ||
            SymbolDisplay.isFund(symbol) ||
            SymbolDisplay.isPhysical(symbol),
      );
    } else {
      d.unmatchedHint = (p['raw_name'] as String?) ?? (p['name'] as String?);
    }
    return d;
  }

  String _trim(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  Future<void> _submit() async {
    final valid = _rows.where(_isValid).toList();
    if (valid.isEmpty) {
      _snack('En az bir pozisyon için hisse, lot ve maliyet gir', error: true);
      return;
    }

    setState(() => _isSubmitting = true);
    final provider = context.read<PortfolioProvider>();
    final result = await provider.executeImportPositions(
      [
        for (final d in valid)
          (
            symbol: d.stock!.symbol,
            quantity: _parse(d.lot.text),
            avgCost: _parse(d.cost.text),
            acquiredAt: null,
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.failed.isEmpty) {
      Navigator.pop(context);
      _snack('${result.ok} pozisyon portföyüne eklendi');
    } else if (result.ok > 0) {
      _snack(
        '${result.ok} eklendi · ${result.failed.length} eklenemedi '
        '(${result.failed.map((e) => e.$1).join(", ")})',
        error: true,
      );
    } else {
      _snack('Hiçbir pozisyon eklenemedi: ${result.failed.first.$2}',
          error: true);
    }
  }

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
        title: const Text('Portföyümü Gir'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Sahip olduğun pozisyonları lot ve maliyetle ekle. K/Z gerçek '
              'maliyetinden hesaplanır; haberleri ve sinyalleri otomatik '
              'takibe alınır.',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 13,
                letterSpacing: -0.1,
                height: 1.5,
              ),
            ),
            // Screenshot içe aktarma şu an sadece web'de — dart:html FileInput
            // mobil platformlarda yok. Mobile UI'da butonu gizliyoruz;
            // kullanıcı manuel satır eklemeye devam eder.
            if (kIsWeb) ...[
              const SizedBox(height: 16),
              IOSPillButton(
                label: _isParsing
                    ? (_parseLabel ?? 'Ekran görüntüsü okunuyor…')
                    : 'Ekran görüntüsünden içe aktar',
                icon: Icons.auto_awesome_outlined,
                width: double.infinity,
                isLoading: _isParsing,
                onPressed: _isParsing ? null : _importFromScreenshot,
              ),
              const SizedBox(height: 6),
              Text(
                'Midas / aracı kurum portföy ekranının görüntüsünü yükle; AI '
                'hisseleri, lotu ve maliyeti otomatik doldursun. En fazla 10 '
                'görsel seçebilirsin, hepsi alt alta eklenir. Kaydetmeden önce '
                'kontrol edersin.',
                style: TextStyle(
                  color: c.textSubtle,
                  fontSize: 12,
                  letterSpacing: -0.1,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 18),
            for (int i = 0; i < _rows.length; i++) ...[
              _buildRow(c, i),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 2),
            IOSPillButton(
              label: 'Satır Ekle',
              icon: Icons.add_rounded,
              secondary: true,
              width: double.infinity,
              onPressed: _addRow,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildFooter(c),
    );
  }

  Widget _buildRow(AppColorsExt c, int i) {
    final d = _rows[i];
    final stock = d.stock;
    final cur = stock?.currency ?? '₺';
    final lot = _parse(d.lot.text);
    final cost = _parse(d.cost.text);
    final lineTotal = lot * cost;

    return EliteSurface(
      padding: const EdgeInsets.fromLTRB(EliteSpace.md, 6, 6, EliteSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pickSymbol(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            stock == null
                                ? Icons.search
                                : Icons.candlestick_chart_outlined,
                            size: 17,
                            color: stock == null ? c.textSubtle : c.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              stock != null
                                  ? SymbolDisplay.label(stock.symbol)
                                  : (d.unmatchedHint != null
                                      ? '"${d.unmatchedHint}" — hisseyi seç'
                                      : 'Hisse seç'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: stock != null
                                    ? c.textPrimary
                                    : (d.unmatchedHint != null
                                        ? c.warmAccent
                                        : c.textSubtle),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (stock != null && stock.rawPrice > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '$cur${formatMoney(stock.rawPrice)}',
                              style: TextStyle(
                                color: c.textMuted,
                                fontSize: 12,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _removeRow(i),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child:
                      Icon(Icons.close_rounded, size: 18, color: c.textSubtle),
                ),
              ),
            ],
          ),
          const EliteHairline(),
          Row(
            children: [
              Expanded(
                child: _numField(c, d.lot, label: 'Lot', hint: '0'),
              ),
              Container(width: 1, height: 28, color: c.divider),
              Expanded(
                child: _numField(c, d.cost,
                    label: 'Birim maliyet', hint: '0.00', prefix: cur),
              ),
            ],
          ),
          if (_isValid(d)) ...[
            const SizedBox(height: 8),
            Text(
              'Toplam maliyet  $cur${formatMoney(lineTotal)}',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _numField(
    AppColorsExt c,
    TextEditingController controller, {
    required String label,
    required String hint,
    String? prefix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (prefix != null) ...[
                Text(prefix,
                    style: TextStyle(color: c.textMuted, fontSize: 15)),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                  cursorColor: c.textPrimary,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: c.textSubtle, fontSize: 17),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(AppColorsExt c) {
    final n = _validCount;
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
              n == 0 ? 'Henüz hazır pozisyon yok' : '$n pozisyon hazır',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 10),
            IOSPillButton(
              label: n == 0 ? 'Hepsini Ekle' : 'Hepsini Ekle ($n)',
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
