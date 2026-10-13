import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'haptics_stub.dart' if (dart.library.html) 'haptics_web.dart';

/// Dokunsal geri bildirim — tek giriş noktası.
///
/// ⚠️ Platform gerçeği: Flutter Web'de `HapticFeedback` platform kanalı
/// olmadığı için NO-OP'tur. Dağıtım PWA olduğundan burada Vibration API'ye
/// düşülür — Android Chrome'da çalışır, **iOS Safari'de titreşim API'si
/// yoktur** (orada hiçbir dokunsal geri bildirim mümkün değil). Native
/// Android/iOS derlemesinde gerçek haptic motor kullanılır.
///
/// Kural: dokunsal geri bildirim kritik yol değildir → hata yutulur, çağrı
/// hiçbir zaman await edilmez (UI'ı bekletmesin).
abstract final class Haptics {
  /// Hafif — bir eşiğin geçildiğini bildirir (kaydırma silme eşiği vb.).
  static void light() => _fire(HapticFeedback.lightImpact, 10);

  /// Orta — sonucu olan bir eylem gerçekleşti (kayıt başarılı).
  static void medium() => _fire(HapticFeedback.mediumImpact, 18);

  /// Seçim tıkı — sheet/menü açılışı gibi hafif geçişler.
  static void selection() => _fire(HapticFeedback.selectionClick, 6);

  static void _fire(Future<void> Function() native, int webMilliseconds) {
    if (kIsWeb) {
      vibrateWeb(webMilliseconds);
      return;
    }
    native().ignore();
  }
}
