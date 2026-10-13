import 'package:flutter/material.dart';
import 'package:portly/utils/money.dart';
import 'package:portly/widgets/load_error_card.dart';
import 'package:flutter/services.dart';
import 'package:portly/services/api_service.dart';
import 'package:portly/utils/symbol_display.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/theme/ios_widgets.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _alerts = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _api.fetchPriceAlerts();
    if (!mounted) return;
    setState(() {
      // null = istek başarısız (boş liste DEĞİL). Ayırmazsak ağ hatasında
      // "henüz alarm yok" diyip kullanıcının alarmlarını yok sayıyorduk.
      _loadFailed = list == null;
      _alerts = list ?? [];
      _loading = false;
    });
    // Ekranı açan kullanıcı tetiklenmiş alarmları görmüş sayılır → rozeti temizle.
    _api.markAlertsSeen();
  }

  Future<void> _delete(int id) async {
    final ok = await _api.deletePriceAlert(id);
    if (!mounted) return;
    if (ok) await _load();
  }

  void _showCreateSheet() {
    final symbolCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String direction = 'ABOVE';
    bool email = true;

    showIOSBottomSheet(
      context: context,
      title: 'Yeni Fiyat Alarmı',
      child: StatefulBuilder(
        builder: (sheetCtx, setSt) {
          final c = AppColorsExt.of(sheetCtx);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IOSGroupedCard(
                  children: [
                    IOSField(
                      controller: symbolCtrl,
                      label: 'Sembol — AAPL, THYAO.IS, BTC-USD',
                      icon: Icons.tag_rounded,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    IOSField(
                      controller: priceCtrl,
                      label: 'Eşik fiyat',
                      icon: Icons.attach_money_rounded,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                    ),
                    IOSField(
                      controller: noteCtrl,
                      label: 'Not (opsiyonel)',
                      icon: Icons.notes_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _dirToggle(
                          sheetCtx,
                          'ABOVE',
                          'Üstüne çıkınca',
                          direction,
                          c.positive,
                          (v) => setSt(() => direction = v)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dirToggle(
                          sheetCtx,
                          'BELOW',
                          'Altına düşünce',
                          direction,
                          c.negative,
                          (v) => setSt(() => direction = v)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                IOSGroupedCard(
                  children: [
                    IOSListRow(
                      icon: Icons.mail_outline_rounded,
                      title: 'E-posta gönder',
                      subtitle: 'Alarm tetiklendiğinde mail al',
                      trailing: Switch(
                        value: email,
                        onChanged: (v) => setSt(() => email = v),
                        activeColor: c.textPrimary,
                        activeTrackColor: c.textPrimary.withValues(alpha: 0.3),
                        inactiveTrackColor: c.surfaceAlt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                IOSPillButton(
                  label: 'Alarmı Kur',
                  width: double.infinity,
                  onPressed: () async {
                    final symbol = symbolCtrl.text.trim().toUpperCase();
                    final price = double.tryParse(priceCtrl.text);
                    if (symbol.isEmpty || price == null || price <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Sembol ve fiyat zorunlu')),
                      );
                      return;
                    }
                    Navigator.pop(sheetCtx);
                    final r = await _api.createPriceAlert(
                      symbol: symbol,
                      thresholdPrice: price,
                      direction: direction,
                      notifyEmail: email,
                      note: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(r != null
                            ? 'Alarm kuruldu'
                            : 'Alarm oluşturulamadı'),
                        backgroundColor:
                            r != null ? null : const Color(0xFFFB7185),
                      ),
                    );
                    if (r != null) await _load();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _dirToggle(BuildContext ctx, String value, String label,
      String current, Color dataColor, ValueChanged<String> onChange) {
    final c = AppColorsExt.of(ctx);
    final selected = current == value;
    return GestureDetector(
      onTap: () => onChange(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? dataColor : c.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : c.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
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
        title: Text('Fiyat Alarmları',
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: c.textPrimary, size: 24),
            tooltip: 'Yeni alarm',
            onPressed: _showCreateSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading
                ? Center(child: CircularProgressIndicator(color: c.textPrimary))
                : _alerts.isEmpty
                    ? (_loadFailed
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: LoadErrorCard(
                              title: 'Alarmlar yüklenemedi',
                              onRetry: _load,
                            ),
                          )
                        : _empty())
                    : RefreshIndicator(
                        color: c.textPrimary,
                        backgroundColor: c.surface,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          itemCount: _alerts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) => _buildAlertCard(
                              _alerts[i] as Map<String, dynamic>),
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final c = AppColorsExt.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 38, color: c.textSubtle),
            const SizedBox(height: 14),
            Text('Henüz alarm kurmadın',
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2)),
            const SizedBox(height: 4),
            Text(
              'Fiyat belirlediğin seviyeye ulaşınca e-posta al.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textMuted, fontSize: 13, letterSpacing: -0.1),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 200,
              child: IOSPillButton(
                label: 'İlk Alarmı Kur',
                onPressed: _showCreateSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> a) {
    final c = AppColorsExt.of(context);
    final id = a['id'] as int;
    final symbol = a['symbol'] as String;
    final threshold = (a['threshold_price'] as num).toDouble();
    final direction = a['direction'] as String;
    final active = a['active'] as bool;
    final email = a['notify_email'] as bool;
    final triggeredAt = a['triggered_at'] as String?;
    final triggeredPrice = (a['triggered_price'] as num?)?.toDouble();
    final note = a['note'] as String?;

    // Yön = fiyat yönü = veri → renk izinli; pasifse gri
    final dataColor = active
        ? (direction == 'ABOVE' ? c.positive : c.negative)
        : c.textSubtle;
    final currency = SymbolDisplay.currencyOf(symbol);
    final arrow = direction == 'ABOVE' ? '↑' : '↓';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: dataColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              arrow,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
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
                const SizedBox(height: 2),
                Text(
                  '$currency${formatMoney(threshold)}'
                  '${active ? '' : '  ·  tetiklendi'}',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 12,
                    letterSpacing: -0.1,
                  ),
                ),
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSubtle, fontSize: 11)),
                ],
                if (!active && triggeredPrice != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Cari: $currency${formatMoney(triggeredPrice)} · ${_fmtDate(triggeredAt)}',
                    style: TextStyle(
                      color: c.textSubtle,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (email)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.mail_outline_rounded,
                  color: c.textSubtle, size: 15),
            ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: c.textMuted, size: 20),
            onPressed: () => _delete(id),
          ),
        ],
      ),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}.${dt.month}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
