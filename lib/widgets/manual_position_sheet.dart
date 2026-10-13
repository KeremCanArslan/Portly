import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/utils/snackbar.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';

/// Manuel pozisyon ekleme sheet'i — kullanıcının GERÇEKTE sahip olduğu bir
/// pozisyonu maliyet + lot ile portföye tanımlar (kayıt defteri; sanal
/// alım-satım yok). Screenshot→AI import da bu akışı besler.
/// [preset] verilirse sembol arama adımı atlanır; sheet doğrudan o hisseyle
/// seçili başlar (hisse detay ekranından "Maliyetimle ekle" akışı).
Future<void> showManualPositionSheet(BuildContext context,
    {StockModel? preset}) {
  return showIOSBottomSheet<void>(
    context: context,
    title: preset == null
        ? 'Mevcut Pozisyon Ekle'
        : '${SymbolDisplay.label(preset.symbol)} — Maliyetimle Ekle',
    child: _ManualPositionSheet(preset: preset),
  );
}

class _ManualPositionSheet extends StatefulWidget {
  const _ManualPositionSheet({this.preset});

  final StockModel? preset;

  @override
  State<_ManualPositionSheet> createState() => _ManualPositionSheetState();
}

class _ManualPositionSheetState extends State<_ManualPositionSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _costController = TextEditingController();

  Timer? _searchDebounce;
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  StockModel? _selected;
  bool _isLoadingPrice = false;
  bool _isSubmitting = false;
  DateTime? _acquiredAt; // null = bugün

  /// Hisse detaydan geldiyse sembol kilitli — arama gizlenir.
  bool get _locked => widget.preset != null;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    if (preset != null) {
      _selected = preset;
      // Maliyeti güncel fiyatla ön-doldur (kullanıcı düzeltebilir).
      if (preset.rawPrice > 0) {
        _costController.text = preset.rawPrice.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearching = true);
      final results = await _api.searchStocks(query.trim());
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  Future<void> _selectSymbol(String symbol, String name) async {
    // Bekleyen aramayı iptal et: dokunduktan sonra geç gelen bir sonuç
    // listeyi parmağın altından değiştirip seçimi kaçırmasın.
    _searchDebounce?.cancel();
    setState(() {
      _isLoadingPrice = true;
      _searchResults = [];
      _searchController.text = SymbolDisplay.pickTitle(symbol, name);
    });
    FocusScope.of(context).unfocus();
    final stock = await _api.fetchSingleStock(symbol);
    if (!mounted) return;
    setState(() {
      _isLoadingPrice = false;
      // Fiyat alınamasa bile sembolü seçili tut: maliyeti kullanıcı girecek,
      // güncel fiyat yalnız referans/P&L önizleme içindir.
      _selected = stock ??
          StockModel(
            symbol: symbol,
            name: name,
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
      // Maliyet alanını güncel fiyatla ön-doldur (kullanıcı düzeltebilir).
      if (stock != null && stock.rawPrice > 0 && _costController.text.isEmpty) {
        _costController.text = stock.rawPrice.toStringAsFixed(2);
      }
    });
  }

  double _parse(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _acquiredAt ?? now,
      firstDate: DateTime(now.year - 25),
      lastDate: now,
      builder: (ctx, child) {
        final c = AppColorsExt.of(ctx);
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme:
                (isDark ? const ColorScheme.dark() : const ColorScheme.light())
                    .copyWith(
              primary: c.textPrimary,
              onPrimary: c.bg,
              surface: c.surface,
              onSurface: c.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _acquiredAt = picked);
    }
  }

  Future<void> _submit() async {
    final stock = _selected;
    if (stock == null) {
      _snack('Önce bir sembol seç', error: true);
      return;
    }
    final qty = _parse(_qtyController.text);
    final cost = _parse(_costController.text);
    if (qty <= 0) {
      _snack(
          SymbolDisplay.isPhysical(_selected?.symbol ?? '')
              ? 'Miktar pozitif olmalı'
              : 'Lot adedi pozitif olmalı',
          error: true);
      return;
    }
    if (cost <= 0) {
      _snack('Birim maliyet pozitif olmalı', error: true);
      return;
    }

    setState(() => _isSubmitting = true);
    final provider = context.read<PortfolioProvider>();
    final result = await provider.executeImportPosition(
      stock.symbol,
      qty,
      cost,
      acquiredAt: _acquiredAt,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.success) {
      Navigator.pop(context);
      _snack('${SymbolDisplay.compact(stock.symbol)} pozisyonu eklendi');
    } else {
      _snack(result.message, error: true);
    }
  }

  // Tema-uyumlu ortak snackbar (40. tur kuralı): ham ScaffoldMessenger +
  // varsayılan SnackBar kullanılmaz — uygulamanın geri kalanıyla aynı
  // yuvarlak/floating görünüm ve renkler.
  void _snack(String msg, {bool error = false}) {
    showAppSnackBar(context, msg, isError: error);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sahip olduğun bir pozisyonu maliyet ve lot ile portföyüne ekle; '
              'haberlerini ve sinyallerini senin için takip edelim. '
              'Elindeki fiziki altın da girilebilir: "çeyrek", "gram altın", '
              '"bilezik" diye ara.',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 13,
                letterSpacing: -0.1,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (!_locked) ...[
              _buildSearchField(),
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildSearchDropdown(),
              ],
            ],
            if (_isLoadingPrice) ...[
              const SizedBox(height: 14),
              const EliteSkeleton(height: 64),
            ] else if (_selected != null) ...[
              const SizedBox(height: 14),
              _buildSelectedCard(_selected!),
              const SizedBox(height: 14),
              _buildInputs(_selected!),
              const SizedBox(height: 14),
              _buildSummary(_selected!),
              const SizedBox(height: 20),
              IOSPillButton(
                label: 'Pozisyonu Ekle',
                width: double.infinity,
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _submit,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final c = AppColorsExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search, color: c.textSubtle, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15,
                letterSpacing: -0.1,
              ),
              cursorColor: c.textPrimary,
              decoration: InputDecoration(
                hintText: 'Ara — THYAO, Apple, çeyrek altın, katılım fonu…',
                hintStyle: TextStyle(color: c.textSubtle, fontSize: 15),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          if (_isSearching)
            SizedBox(
              width: 16,
              height: 16,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: c.textMuted),
            )
          else if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _searchController.clear();
                _searchResults = [];
                _selected = null;
              }),
              child: Icon(Icons.close_rounded, color: c.textSubtle, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchDropdown() {
    final c = AppColorsExt.of(context);
    return IOSGroupedCard(
      children: _searchResults.take(8).map((r) {
        final symbol = r['symbol'] as String? ?? '';
        final name = r['name'] as String? ?? symbol;
        final market = r['market'] as String? ?? '';
        return InkWell(
          onTap: () => _selectSymbol(symbol, name),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
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
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSelectedCard(StockModel stock) {
    final c = AppColorsExt.of(context);
    final hasPrice = stock.rawPrice > 0;
    return EliteSurface(
      padding: const EdgeInsets.all(EliteSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SymbolDisplay.label(stock.symbol),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPrice
                      ? 'Güncel piyasa fiyatı'
                      : 'Fiyat alınamadı — referanssız',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 12,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          if (hasPrice)
            Text(
              '${stock.currency}${formatMoney(stock.rawPrice)}',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputs(StockModel stock) {
    final c = AppColorsExt.of(context);
    return EliteSurface(
      padding:
          const EdgeInsets.symmetric(horizontal: EliteSpace.md, vertical: 4),
      child: Column(
        children: [
          // Fiziki altında ölçü lot değil: çeyrek/tam ADET, gram/bilezik
          // GRAM ile alınır. Yanlış birim maliyeti kat kat yanlış gösterirdi.
          _inputRow(
            label: SymbolDisplay.isPhysical(stock.symbol)
                ? 'Miktar (${SymbolDisplay.physicalUnit(stock.symbol)})'
                : 'Lot (adet)',
            controller: _qtyController,
            hint: '0',
          ),
          const EliteHairline(),
          _inputRow(
            label: SymbolDisplay.isPhysical(stock.symbol)
                ? '${SymbolDisplay.physicalUnit(stock.symbol) == 'adet' ? 'Adet' : 'Gram'} maliyeti'
                : 'Birim maliyet',
            controller: _costController,
            hint: '0.00',
            prefix: stock.currency,
          ),
          const EliteHairline(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Text(
                      'Edinim tarihi',
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 14,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _acquiredAt == null
                          ? 'Bugün'
                          : '${_acquiredAt!.day.toString().padLeft(2, '0')}.'
                              '${_acquiredAt!.month.toString().padLeft(2, '0')}.'
                              '${_acquiredAt!.year}',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.calendar_today_outlined,
                        size: 15, color: c.textSubtle),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputRow({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? prefix,
  }) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.textMuted,
              fontSize: 14,
              letterSpacing: -0.1,
            ),
          ),
          const Spacer(),
          if (prefix != null) ...[
            Text(prefix, style: TextStyle(color: c.textMuted, fontSize: 15)),
            const SizedBox(width: 4),
          ],
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              textAlign: TextAlign.right,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              cursorColor: c.textPrimary,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: c.textSubtle, fontSize: 18),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(StockModel stock) {
    final c = AppColorsExt.of(context);
    final qty = _parse(_qtyController.text);
    final cost = _parse(_costController.text);
    final totalCost = qty * cost;
    final cur = stock.currency;
    final hasPrice = stock.rawPrice > 0;

    // P&L önizleme yalnız güncel fiyat varsa anlamlı.
    final currentValue = hasPrice ? qty * stock.rawPrice : 0.0;
    final pnl = currentValue - totalCost;
    final pnlPct = totalCost > 0 ? (pnl / totalCost) * 100 : 0.0;
    final isProfit = pnl >= 0;

    return EliteSurface(
      padding: const EdgeInsets.all(EliteSpace.md),
      child: Column(
        children: [
          _summaryRow('Toplam maliyet', '$cur${formatMoney(totalCost)}',
              bold: true),
          if (hasPrice && qty > 0 && cost > 0) ...[
            const SizedBox(height: 6),
            _summaryRow('Güncel değer', '$cur${formatMoney(currentValue)}'),
            const SizedBox(height: 6),
            _summaryRow(
              'Tahmini K/Z',
              '${isProfit ? '+' : '−'}$cur${formatMoney(pnl.abs())}  '
                  '(${formatPctSigned(pnlPct, decimals: 2)}%)',
              valueColor: isProfit ? c.positive : c.negative,
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {Color? valueColor, bool bold = false}) {
    final c = AppColorsExt.of(context);
    return Row(
      children: [
        Text(
          label,
          style:
              TextStyle(color: c.textMuted, fontSize: 13, letterSpacing: -0.1),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? c.textPrimary,
            fontSize: 13,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}
