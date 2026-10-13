import 'dart:async';
import 'package:portly/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

class WhatIfScreen extends StatefulWidget {
  const WhatIfScreen({super.key});

  @override
  State<WhatIfScreen> createState() => _WhatIfScreenState();
}

class _WhatIfScreenState extends State<WhatIfScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _amountController =
      TextEditingController(text: '1000');
  Timer? _debounce;
  List<Map<String, dynamic>> _searchResults = [];
  String? _selectedSymbol;
  double _yearsBack = 1.0;
  DateTime? _startDate; // net başlangıç (slider yerine, opsiyonel)
  DateTime? _endDate; // net bitiş (yoksa bugün), opsiyonel
  bool _loading = false;
  bool _dcaMode = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _searchController.dispose();
    _amountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    final tooShort = q.trim().length < 2;
    setState(() {
      // Kutuya yeni bir şey yazmak önceki seçimi geçersiz kılar. Aksi halde
      // öneri listesi (_selectedSymbol == null koşuluyla gizli) bir daha hiç
      // açılmaz ve Hesapla eski sembolle çalışırdı.
      _selectedSymbol = null;
      if (tooShort) _searchResults = [];
    });
    if (tooShort) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final r = await _api.searchStocks(q.trim());
      if (!mounted) return;
      setState(() => _searchResults = r);
    });
  }

  // Başlangıç: 2005 ile (bitiş − 1 gün) arası. initialDate sınırlar içine kıstırılır.
  Future<void> _pickStartDate() async {
    final last = (_endDate ?? DateTime.now()).subtract(const Duration(days: 1));
    var init = _startDate ?? DateTime.now().subtract(const Duration(days: 365));
    if (init.isAfter(last)) init = last;
    if (init.isBefore(DateTime(2005))) init = DateTime(2005);
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2005),
      lastDate: last,
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  // Bitiş: (başlangıç + 1 gün) ile dün arası. Boş = bugün (son işlem günü).
  Future<void> _pickEndDate() async {
    final first =
        _startDate?.add(const Duration(days: 1)) ?? DateTime(2005);
    final last = DateTime.now().subtract(const Duration(days: 1));
    var init = _endDate ?? last;
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  String? _fmtDate(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _calculate() async {
    if (_selectedSymbol == null) return;
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;
    setState(() {
      _loading = true;
      _result = null;
    });
    final start = _fmtDate(_startDate);
    final end = _fmtDate(_endDate);
    final r = _dcaMode
        ? await _api.fetchDca(
            symbol: _selectedSymbol!,
            monthlyAmount: amount,
            yearsBack: _yearsBack,
            startDate: start,
            endDate: end,
          )
        : await _api.fetchWhatIf(
            symbol: _selectedSymbol!,
            amount: amount,
            yearsBack: _yearsBack,
            startDate: start,
            endDate: end,
          );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = r;
    });
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
        title: Text('Ya Almış Olsaydım?',
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Geçmişte bir hisseye yatırım yapsaydın bugün ne kadar olurdu?',
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 14,
                      height: 1.5,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Arama
                  Container(
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
                            onChanged: _onSearch,
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15,
                                letterSpacing: -0.1),
                            cursorColor: c.textPrimary,
                            decoration: InputDecoration(
                              hintText: 'Hisse ara — AAPL, THYAO',
                              hintStyle:
                                  TextStyle(color: c.textSubtle, fontSize: 15),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_searchResults.isNotEmpty && _selectedSymbol == null) ...[
                    const SizedBox(height: 8),
                    IOSGroupedCard(
                      children: _searchResults.take(6).map((r) {
                        final symbol = r['symbol'] as String? ?? '';
                        final name = r['name'] as String? ?? symbol;
                        final market = r['market'] as String? ?? '';
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedSymbol = symbol;
                              _searchController.text = SymbolDisplay.pickTitle(symbol, name);
                              _searchResults = [];
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 52,
                                  child: Text(market,
                                      style: TextStyle(
                                          color: c.textSubtle,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5)),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(SymbolDisplay.compact(symbol),
                                          style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.1)),
                                      const SizedBox(height: 2),
                                      Text(name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: c.textMuted,
                                              fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  IOSSegmented<bool>(
                    options: const [
                      (false, 'Tek Seferlik'),
                      (true, 'Aylık (DCA)'),
                    ],
                    value: _dcaMode,
                    onChange: (v) => setState(() {
                      _dcaMode = v;
                      _result = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  Text(_dcaMode ? 'Aylık tutar' : 'Tutar',
                      style: TextStyle(
                          color: c.textMuted,
                          fontSize: 13,
                          letterSpacing: -0.1)),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                            _selectedSymbol != null
                                ? SymbolDisplay.currencyOf(_selectedSymbol!)
                                : '₺',
                            style: TextStyle(color: c.textMuted, fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            cursorColor: c.textPrimary,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                      _dcaMode
                          ? 'Kaç yıldır: ${_yearsBack.toStringAsFixed(1)} yıl'
                          : 'Kaç yıl önce: ${_yearsBack.toStringAsFixed(1)} yıl',
                      style: TextStyle(
                          color: c.textMuted,
                          fontSize: 13,
                          letterSpacing: -0.1)),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: c.warmAccent,
                      inactiveTrackColor: c.surfaceAlt,
                      thumbColor: c.warmAccent,
                      overlayColor: c.warmAccent.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: _yearsBack,
                      min: 0.5,
                      max: 10,
                      divisions: 19,
                      label: '${_yearsBack.toStringAsFixed(1)} yıl',
                      onChanged: (v) => setState(() => _yearsBack = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _dateRow(
                    icon: Icons.event_outlined,
                    emptyLabel: 'Veya net bir başlangıç tarihi seç',
                    filledLabel: (d) =>
                        'Başlangıç: ${d.day}.${d.month}.${d.year}',
                    value: _startDate,
                    onPick: _pickStartDate,
                    onClear: () => setState(() => _startDate = null),
                  ),
                  const SizedBox(height: 6),
                  _dateRow(
                    icon: Icons.event_available_outlined,
                    emptyLabel: 'Bitiş tarihi seç',
                    filledLabel: (d) => 'Bitiş: ${d.day}.${d.month}.${d.year}',
                    value: _endDate,
                    onPick: _pickEndDate,
                    onClear: () => setState(() => _endDate = null),
                  ),
                  const SizedBox(height: 10),
                  IOSPillButton(
                    label: 'Hesapla',
                    width: double.infinity,
                    isLoading: _loading,
                    onPressed:
                        _loading || _selectedSymbol == null ? null : _calculate,
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 18),
                    _buildResult(_result!),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    if (r.containsKey('error')) {
      return Text(r['error'].toString(),
          style: TextStyle(color: c.negative, fontSize: 14));
    }
    if (r.containsKey('series')) return _buildDcaResult(r);
    final symbol = r['symbol'] as String;
    final invested = (r['amount_invested'] as num).toDouble();
    final current = (r['current_value'] as num).toDouble();
    final profit = (r['profit'] as num).toDouble();
    final profitPct = (r['profit_pct'] as num).toDouble();
    final cagr = (r['cagr_pct'] as num).toDouble();
    final years = (r['years'] as num).toDouble();
    final qty = (r['quantity'] as num).toDouble();
    final startPrice = (r['start_price'] as num).toDouble();
    final startDate = r['start_date'] as String;
    final endPrice = (r['end_price'] as num).toDouble();
    final endDate = r['end_date'] as String?;
    final currency = SymbolDisplay.currencyOf(symbol);
    final isProfit = profit >= 0;
    final dataColor = isProfit ? c.positive : c.negative;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${years.toStringAsFixed(1)} yıl önce yatırım yapsaydın',
              style: TextStyle(
                  color: c.textMuted, fontSize: 13, letterSpacing: -0.1)),
          const SizedBox(height: 8),
          Text(
            '$currency${formatMoney(current)}',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: dataColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${formatPctSigned(profitPct, decimals: 2)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isProfit ? '+' : '−'}$currency${formatMoney(profit.abs())}  ·  $currency${formatMoney(invested, decimals: 0)} yatırım',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 13,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _kv('Yıllık ortalama (CAGR)',
              '${formatPctSigned(cagr, decimals: 2)}%'),
          _kv('Alacağın adet', '${qty.toStringAsFixed(4)} lot'),
          _kv('Başlangıç ($startDate)', '$currency${formatMoney(startPrice)}'),
          _kv(
              _endDate == null
                  ? 'Bugünkü fiyat'
                  : 'Bitiş fiyatı (${endDate ?? ''})',
              '$currency${formatMoney(endPrice)}'),
          if (currency == '\$') _foreignCurrencyNote(c),
        ],
      ),
    );
  }

  // ABD hissesi $ ile işlem görür → tutarlar $ cinsinde. Sade, tek satır
  // bilgilendirme (kullanıcı "neden ₺ değil?" diye şaşırmasın).
  Widget _foreignCurrencyNote(AppColorsExt c) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Tutarlar ABD doları (\$) cinsindendir — bu hisse ABD borsasında '
        'işlem görür.',
        style: TextStyle(color: c.textSubtle, fontSize: 11.5, height: 1.45),
      ),
    );
  }

  Widget _buildDcaResult(Map<String, dynamic> r) {
    final c = AppColorsExt.of(context);
    final symbol = r['symbol'] as String;
    final months = (r['months'] as num).toInt();
    final invested = (r['total_invested'] as num).toDouble();
    final current = (r['current_value'] as num).toDouble();
    final profit = (r['profit'] as num).toDouble();
    final profitPct = (r['profit_pct'] as num).toDouble();
    final avgCost = (r['avg_cost'] as num).toDouble();
    final qty = (r['quantity'] as num).toDouble();
    final endPrice = (r['end_price'] as num).toDouble();
    final endDate = r['end_date'] as String?;
    final lumpPct = (r['lump_sum_profit_pct'] as num).toDouble();
    final currency = SymbolDisplay.currencyOf(symbol);
    final isProfit = profit >= 0;
    final dataColor = isProfit ? c.positive : c.negative;
    final dcaWins = profitPct >= lumpPct;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$months ay boyunca her ay düzenli alsaydın',
              style: TextStyle(
                  color: c.textMuted, fontSize: 13, letterSpacing: -0.1)),
          const SizedBox(height: 8),
          Text(
            '$currency${formatMoney(current)}',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: dataColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${formatPctSigned(profitPct, decimals: 2)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isProfit ? '+' : '−'}$currency${formatMoney(profit.abs())}  ·  $currency${formatMoney(invested, decimals: 0)} toplam yatırım',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 13,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _kv('Ortalama maliyet', '$currency${formatMoney(avgCost)}'),
          _kv('Biriken adet', '${qty.toStringAsFixed(4)} lot'),
          _kv(
              _endDate == null
                  ? 'Bugünkü fiyat'
                  : 'Bitiş fiyatı (${endDate ?? ''})',
              '$currency${formatMoney(endPrice)}'),
          _kv('Tek seferde yatırsaydın',
              '${formatPctSigned(lumpPct, decimals: 2)}%'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              dcaWins
                  ? 'Bu dönemde düzenli alım (DCA), tek seferde yatırmaktan daha iyi sonuç verdi. DCA fiyat dalgalanmasında ortalama maliyeti düşürür.'
                  : 'Bu dönemde tek seferde yatırmak daha kârlıydı (piyasa genelde yükseldiği için). DCA ise düşüş riskini zamana yayar.',
              style: TextStyle(
                  color: c.textMuted,
                  fontSize: 12,
                  height: 1.5,
                  letterSpacing: -0.1),
            ),
          ),
          if (currency == '\$') _foreignCurrencyNote(c),
        ],
      ),
    );
  }

  // Opsiyonel tarih satırı (başlangıç/bitiş ortak): dolu→tarih+temizle, boş→ipucu.
  Widget _dateRow({
    required IconData icon,
    required String emptyLabel,
    required String Function(DateTime) filledLabel,
    required DateTime? value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final c = AppColorsExt.of(context);
    return GestureDetector(
      onTap: onPick,
      child: Row(
        children: [
          Icon(icon, size: 17, color: c.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value == null ? emptyLabel : filledLabel(value),
              style: TextStyle(
                  color: value == null ? c.textMuted : c.textPrimary,
                  fontSize: 13,
                  letterSpacing: -0.1),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close, size: 16, color: c.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    final c = AppColorsExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(k,
              style: TextStyle(
                  color: c.textMuted, fontSize: 12, letterSpacing: -0.1)),
          const Spacer(),
          Text(v,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
