import 'package:flutter/material.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/utils/money.dart';

class GoldRatesScreen extends StatefulWidget {
  const GoldRatesScreen({super.key});

  @override
  State<GoldRatesScreen> createState() => _GoldRatesScreenState();
}

class _GoldRatesScreenState extends State<GoldRatesScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await _api.fetchGoldRates();
    if (!mounted) return;
    setState(() {
      _data = d;
      _loading = false;
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
        title: Text('Banka Altın',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: c.textMuted, size: 21),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading
                ? Center(child: CircularProgressIndicator(color: c.textPrimary))
                : _data == null || _data!.containsKey('error')
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_data?['error'] ?? 'Veri alınamadı',
                              style:
                                  TextStyle(color: c.textMuted, fontSize: 14)),
                        ),
                      )
                    : RefreshIndicator(
                        color: c.textPrimary,
                        backgroundColor: c.surface,
                        onRefresh: _load,
                        child: _buildContent(),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final c = AppColorsExt.of(context);
    final reference = (_data!['reference_gram_try'] as num).toDouble();
    final refChange = _data!['reference_change'] as String? ?? '';
    final banks = _data!['banks'] as List<dynamic>;
    final extras = (_data!['extra_products'] as List?) ?? [];
    final source = _data!['data_source'] as String? ?? '';
    final note = _data!['note'] as String? ?? '';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // Editorial referans
        Text(
          'Gram Altın',
          style: TextStyle(
            color: c.textMuted,
            fontSize: 14,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '₺${formatMoney(reference)}',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
        ),
        if (refChange.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            refChange,
            style: TextStyle(
              color: refChange.startsWith('%-') ? c.negative : c.positive,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          source.isNotEmpty ? source : 'Bankalar makas küçükten büyüğe',
          style: TextStyle(
            color: c.textSubtle,
            fontSize: 12,
            letterSpacing: -0.1,
          ),
        ),
        const SizedBox(height: 22),
        // Tablo başlığı
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Banka',
                    style: TextStyle(
                        color: c.textSubtle,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4)),
              ),
              SizedBox(
                  width: 84,
                  child: Center(
                      child: Text('Alış',
                          style: TextStyle(
                              color: c.textSubtle,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)))),
              SizedBox(
                  width: 84,
                  child: Center(
                      child: Text('Satış',
                          style: TextStyle(
                              color: c.textSubtle,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)))),
              SizedBox(
                  width: 62,
                  child: Center(
                      child: Text('Makas',
                          style: TextStyle(
                              color: c.textSubtle,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...banks.asMap().entries.map((entry) {
          final i = entry.key;
          final b = entry.value as Map<String, dynamic>;
          final name = b['name'] as String;
          final buy = (b['buy'] as num).toDouble();
          final sell = (b['sell'] as num).toDouble();
          final spread = (b['spread'] as num).toDouble();
          final spreadPct = (b['spread_pct'] as num?)?.toDouble();
          final isLive = (b['source'] as String?) == 'canlidoviz';
          final isBest = i == 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: isBest ? c.warmAccentSoft : c.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (isBest) ...[
                        Icon(Icons.star_rounded, color: c.warmAccent, size: 15),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isBest ? c.warmAccent : c.textPrimary,
                                fontSize: 13,
                                fontWeight:
                                    isBest ? FontWeight.w600 : FontWeight.w500,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isLive ? 'canlı' : 'tahminî',
                              style: TextStyle(
                                color: isLive ? c.positive : c.textSubtle,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Alış/Satış nötr renkte: yeşil/kırmızı finansta yükseliş-düşüş
                // demektir, sütun etiketi değil. Başlık zaten Alış/Satış yazıyor.
                SizedBox(
                    width: 84,
                    child: Center(
                      child: Text('₺${formatMoney(buy)}',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                    )),
                SizedBox(
                    width: 84,
                    child: Center(
                      child: Text('₺${formatMoney(sell)}',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                    )),
                // Makas hem ₺ hem %: TL tutarı bankalar arası farkı somut
                // gösterir, yüzde ise altın fiyatı değiştikçe kıyaslanabilir
                // kalır. Yüzde ALTTA ve soluk — tek başına "günlük değişim"
                // diye okunmasın diye (sıralama yine TL makasa göre).
                SizedBox(
                    width: 62,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('₺${spread.round()}',
                            style: TextStyle(
                              color: isBest ? c.warmAccent : c.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            )),
                        if (spreadPct != null) ...[
                          const SizedBox(height: 2),
                          Text('%${formatPct(spreadPct, decimals: 2)}',
                              style: TextStyle(
                                color: c.textSubtle,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ],
                    )),
              ],
            ),
          );
        }),
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            // Listede gümüş de var → başlık yalnız "Altın" diyemez.
            'Altın ve Gümüş (Serbest Piyasa)',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          // Kaynak bu turda erişilemedi → önceki liste gösteriliyor. Fiyatın
          // bayat olduğunu söylemek, bölümü hiç göstermemekten iyi.
          if (_data!['products_stale'] == true) ...[
            Text(
              'Kaynağa şu an ulaşılamadı — son alınan fiyatlar gösteriliyor',
              style: TextStyle(color: c.textSubtle, fontSize: 11.5, height: 1.4),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          ...extras.map<Widget>((p) {
            final pr = p as Map<String, dynamic>;
            final name = pr['name'] as String;
            final buy = (pr['buy'] as num).toDouble();
            final sell = (pr['sell'] as num).toDouble();
            final change = pr['change'] as String? ?? '';
            final stale = pr['stale'] == true;
            // '%0,00' yükseliş sayılmamalı: sıfır değişim nötr renkte.
            final isZero = change.replaceAll(RegExp(r'[%,.0\s]'), '').isEmpty;
            final isUp = change.startsWith('%') && !change.startsWith('%-');
            final changeColor = change.isEmpty || isZero
                ? c.textSubtle
                : isUp
                    ? c.positive
                    : c.negative;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1)),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₺${formatMoney(buy)} / ₺${formatMoney(sell)}',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (change.isNotEmpty)
                        Text(change,
                            style: TextStyle(
                              color: changeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ))
                      // Kaynak bu ürünü bugün güncellememiş: sahte '%0,00'
                      // yerine durumu açıkça söyle.
                      else if (stale)
                        Text('bugün güncellenmedi',
                            style: TextStyle(
                              color: c.textSubtle,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            )),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 16),
        if (note.isNotEmpty)
          Text(
            note,
            style: TextStyle(
              color: c.textSubtle,
              fontSize: 11,
              height: 1.5,
              letterSpacing: -0.1,
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
