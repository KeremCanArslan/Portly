import 'package:flutter/material.dart';
import 'package:portly/theme/app_theme.dart';
import 'package:portly/utils/haptics.dart';

/// AI analiz alt-sayfaları (Temel / Teknik analiz, haber piyasa etkisi) için
/// ortak sarmalayıcı: yükleniyor → veri → hata + **Tekrar Dene**. Hata çoğu
/// zaman geçici (Render free instance cold-start, yfinance/AI anlık yoğunluk)
/// olduğundan retry, veriyi `force: true` ile (cache'i atlayarak) yeniden çeker.
///
/// Bazı uçlar başarısızlığı HTTP 200 + `{"error": ...}` gövdesiyle bildirir;
/// o durumda hangi gövdenin hata sayılacağı [isFailure] ile verilir (varsayılan:
/// yalnız `null` yanıt hatadır).
class AiSheet extends StatefulWidget {
  final Future<Map<String, dynamic>?> Function({bool force}) fetch;
  final Widget Function(BuildContext, Map<String, dynamic>) onData;
  final String errorMessage;
  final bool Function(Map<String, dynamic> data)? isFailure;
  const AiSheet({
    super.key,
    required this.fetch,
    required this.onData,
    required this.errorMessage,
    this.isFailure,
  });

  @override
  State<AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<AiSheet> {
  late Future<Map<String, dynamic>?> _future = widget.fetch();

  @override
  void initState() {
    super.initState();
    // AI sheet'i açmak sonucu olan bir eylem (kota harcar, saniyeler sürer) —
    // hafif tık "başladı" der.
    Haptics.selection();
  }

  void _retry() {
    // Blok gövde ŞART: `setState(() => _future = ...)` ok gövdesi atamanın
    // değerini (Future) döndürür ve framework "setState callback'i Future
    // döndürdü" assert'iyle patlar → debug/profile derlemede retry hiç
    // çalışmaz. Taşınmadan önceki kopyada bu kusur vardı.
    setState(() {
      _future = widget.fetch(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorsExt.of(context);
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(child: CircularProgressIndicator(color: c.textPrimary));
        }
        final data = snap.data;
        if (data == null || (widget.isFailure?.call(data) ?? false)) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 36, color: c.textSubtle),
                  const SizedBox(height: 12),
                  Text(
                    widget.errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: c.textMuted, fontSize: 13, height: 1.45),
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: _retry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 11),
                      decoration: BoxDecoration(
                        color: c.textPrimary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, color: c.bg, size: 17),
                          const SizedBox(width: 7),
                          Text(
                            'Tekrar Dene',
                            style: TextStyle(
                              color: c.bg,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
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
          );
        }
        return widget.onData(ctx, data);
      },
    );
  }
}
