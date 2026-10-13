// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web'de Flutter'ın `HapticFeedback`'i NO-OP'tur (platform kanalı yok).
/// Tek gerçek karşılık Vibration API — Android Chrome'da çalışır,
/// iOS Safari'de YOKTUR (Apple desteklemiyor) → orada sessizce geçilir.
void vibrateWeb(int milliseconds) {
  try {
    // `vibrate` dart:html'in Navigator tipinde tanımlı değil (deneysel
    // API) → dinamik çağrı; desteklenmeyen tarayıcıda NoSuchMethod atar.
    (html.window.navigator as dynamic).vibrate(milliseconds);
  } catch (_) {
    // Desteklenmiyor (iOS Safari) ya da kullanıcı etkileşimi yok → önemsiz.
  }
}
