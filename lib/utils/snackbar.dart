import 'package:flutter/material.dart';
import 'package:portly/theme/app_theme.dart';

/// Uygulama geneli tutarlı snackbar — floating, yuvarlak köşe, tema renkleri.
/// Default beyaz/siyah tam-genişlik Material snackbar yerine data-ink uyumlu,
/// her iki temada da düzgün görünen kompakt bildirim.
/// [actionLabel] verilirse sağda bir buton çıkar (ör. "Geri Al"): geri
/// alınabilir silmelerde onay diyaloğunun yerini tutar — akışı kesmez ama
/// yanlışlıkla silmeyi kurtarır.
void showAppSnackBar(BuildContext context, String message,
    {bool isError = false, String? actionLabel, VoidCallback? onAction}) {
  final c = AppColorsExt.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          color: isError ? Colors.white : c.textPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 13.5,
          letterSpacing: -0.1,
        ),
      ),
      backgroundColor: isError ? c.negative : c.surface,
      // Floating snackbar, AI Koç FAB'ı yüzünden yukarı kalkıp "ortada"
      // görünüyordu (kullanıcı: aşağıya çek). Fixed → en altta sabit, FAB'dan
      // etkilenmez. (40. turdaki floating/yuvarlak tercihi bu nedenle değişti.)
      behavior: SnackBarBehavior.fixed,
      elevation: 4,
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(
              label: actionLabel,
              textColor: isError ? Colors.white : c.accent,
              onPressed: onAction,
            )
          : null,
      // Geri alınabilir bir işlemde 2,2 sn karar için kısa.
      duration: Duration(
          milliseconds:
              (actionLabel != null && onAction != null) ? 5000 : 2200),
    ),
  );
}
