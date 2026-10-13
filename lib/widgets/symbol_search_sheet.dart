import 'dart:async';
import 'package:flutter/material.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/models/stock_model.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/premium.dart';
import 'package:portly/theme/ios_widgets.dart';
import 'package:portly/widgets/search_result_row.dart';

/// Sembol arama picker'ı — seçilen hisseyi (güncel fiyatıyla) [StockModel]
/// olarak döndürür, iptalde null. Toplu portföy girişi + (ileride) screenshot
/// düzeltme akışı bunu paylaşır. Tek-pozisyon sheet'inden bağımsız tutuldu ki
/// "bir hisse seç" adımı her yerde aynı görünsün.
Future<StockModel?> showSymbolSearchSheet(BuildContext context) {
  return showIOSBottomSheet<StockModel>(
    context: context,
    title: 'Hisse Seç',
    child: const _SymbolSearchSheet(),
  );
}

class _SymbolSearchSheet extends StatefulWidget {
  const _SymbolSearchSheet();

  @override
  State<_SymbolSearchSheet> createState() => _SymbolSearchSheetState();
}

class _SymbolSearchSheetState extends State<_SymbolSearchSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _isLoadingPrice = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isSearching = true);
      final results = await _api.searchStocks(query.trim());
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    });
  }

  Future<void> _select(String symbol, String name) async {
    // Bekleyen aramayı iptal et: dokunduktan sonra geç gelen bir sonuç
    // listeyi parmağın altından değiştirip seçimi kaçırmasın.
    _searchDebounce?.cancel();
    setState(() => _isLoadingPrice = true);
    FocusScope.of(context).unfocus();
    final stock = await _api.fetchSingleStock(symbol);
    if (!mounted) return;
    // Fiyat alınamasa bile sembolü döndür: maliyeti kullanıcı girecek.
    final result = stock ??
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
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchField(c),
          if (_isLoadingPrice) ...[
            const SizedBox(height: 16),
            const EliteSkeleton(height: 52),
          ] else if (_results.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildDropdown(c),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSearchField(AppColorsExt c) {
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
              autofocus: true,
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
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown(AppColorsExt c) {
    return IOSGroupedCard(
      children: _results.take(10).map((r) {
        final symbol = r['symbol'] as String? ?? '';
        final name = r['name'] as String? ?? symbol;
        final market = r['market'] as String? ?? '';
        return SearchResultRow(
          key: ValueKey(symbol),
          symbol: symbol,
          name: name,
          market: market,
          onTap: () => _select(symbol, name),
        );
      }).toList(),
    );
  }
}
