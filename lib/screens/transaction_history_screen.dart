import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';
import 'package:provider/provider.dart';
import 'package:portly/providers/portfolio_provider.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/utils/file_download.dart' as fd;
import 'package:portly/utils/share_file.dart' as sf;
import 'package:flutter/foundation.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/utils/snackbar.dart';
import 'package:portly/theme/app_theme.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _transactions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<PortfolioProvider>();
    final userId = provider.userId;
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _error = 'Giriş yapılmamış';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final list = await _api.fetchTransactions(userId);
    if (!mounted) return;
    setState(() {
      _transactions = list;
      _isLoading = false;
    });
  }

  Future<void> _exportCsv() async {
    final userId = context.read<PortfolioProvider>().userId;
    if (userId == null) return;

    // CSV endpoint Bearer token ister; ham URL'yi açmak (eski mobil yolu)
    // token taşımadığı için "Not authenticated" dönüyordu. Her platformda
    // önce token'lı çek (fetchCsvBytes), sonra platforma göre teslim et:
    // web → Blob indirme, mobil/masaüstü → geçici dosya + native paylaşım.
    final url = '${ApiService.baseUrl}/trading/transactions/$userId/csv';
    try {
      final bytes = await _api.fetchCsvBytes(url);
      if (bytes == null || !mounted) return;
      if (kIsWeb) {
        _downloadBytes(bytes, 'portly_islemler.csv');
      } else {
        await sf.shareBytes(bytes, 'portly_islemler.csv');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'CSV dışa aktarılamadı: $e', isError: true);
      }
    }
  }

  void _downloadBytes(List<int> bytes, String filename) {
    // Web'de gerçek indirme: Blob + `download` anchor (conditional import).
    // Eski `launchUrl(data:URI)` modern tarayıcılarda bloklanıyordu → inmiyordu.
    if (!kIsWeb) return;
    fd.downloadBytes(bytes, filename, mime: 'text/csv');
  }

  String _formatDate(String iso) {
    try {
      final date = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inSeconds < 60) return 'az önce';
      if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
      if (diff.inHours < 24) return '${diff.inHours} saat önce';
      if (diff.inDays < 7) return '${diff.inDays} gün önce';
      const months = [
        'Oca',
        'Şub',
        'Mar',
        'Nis',
        'May',
        'Haz',
        'Tem',
        'Ağu',
        'Eyl',
        'Eki',
        'Kas',
        'Ara'
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return iso;
    }
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
        title: Text('İşlem Geçmişi',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.file_download_outlined,
                color: c.textMuted, size: 21),
            tooltip: 'CSV indir',
            onPressed: _isLoading || _transactions.isEmpty ? null : _exportCsv,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: c.textMuted, size: 21),
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: c.textPrimary))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: TextStyle(color: c.textMuted, fontSize: 14)))
                    : _transactions.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: c.textPrimary,
                            backgroundColor: c.surface,
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 16),
                              itemCount: _transactions.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final tx =
                                    _transactions[i] as Map<String, dynamic>;
                                return _buildTransactionCard(tx);
                              },
                            ),
                          ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final c = AppColorsExt.of(context);
    final symbol = tx['symbol'] as String? ?? '';
    final type = tx['transaction_type'] as String? ?? '';
    final quantity = (tx['quantity'] as num?)?.toDouble() ?? 0;
    final price = (tx['price'] as num?)?.toDouble() ?? 0;
    final timestamp = tx['timestamp'] as String? ?? '';

    final isBuy = type == 'BUY';
    final isDividend = type == 'DIVIDEND';
    final isAdjust = type == 'ADJUST'; // hisse bölünmesi düzeltmesi
    // Rozet etiketi + rengi. AL/SAT yön = veri (yeşil/kırmızı izinli).
    // Temettü = warmAccent (gelir; temettü ekranıyla tutarlı). Bölünme =
    // nötr gri (nakit etkisi yok). Eskiden BUY dışı her şey "SAT" sanılıp
    // temettüler kırmızı "SAT", bölünmeler anlamsız "$0" görünüyordu.
    final String badge;
    final Color badgeColor;
    if (isBuy) {
      badge = 'AL';
      badgeColor = c.positive;
    } else if (isDividend) {
      badge = 'TEMETTÜ';
      badgeColor = c.warmAccent;
    } else if (isAdjust) {
      badge = 'BÖLÜNME';
      badgeColor = c.textSubtle;
    } else {
      badge = 'SAT';
      badgeColor = c.negative;
    }
    // Temettü tahsil anında ₺/adet KİLİTLİ kaydedilir → satır ₺ (sembol USD
    // olsa bile). Diğerleri sembolün kendi parasında.
    final currency = isDividend
        ? '₺'
        : (symbol.endsWith('.IS') ||
                symbol.endsWith('.FON') ||
                symbol.contains('TRY')
            ? '₺'
            : '\$');
    final total = quantity * price;
    // Nakit yönü: AL çıkış (−), SAT/Temettü giriş (+); Bölünme nakit etkisiz.
    final amountSign = isBuy ? '−' : (isAdjust ? '' : '+');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isAdjust
                      ? 'Hisse bölünmesi · ${formatQty(quantity)} lot · ${_formatDate(timestamp)}'
                      : '${formatQty(quantity)} lot · $currency${formatMoney(price)} · ${_formatDate(timestamp)}',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 11,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isAdjust ? '—' : '$amountSign$currency${formatMoney(total)}',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final c = AppColorsExt.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 38, color: c.textSubtle),
            const SizedBox(height: 14),
            Text(
              'Henüz işlemin yok',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'İşlem sekmesinden bir hisse al veya sat.',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 13,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
