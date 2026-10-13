import 'package:flutter/foundation.dart';

/// Alt navigasyon sekme geçiş kanalı.
///
/// Herhangi bir ekran `kRequestedTab.value = <index>` ile alt
/// navigasyondaki sekmeyi değiştirebilir (ör. boş portföy rehberindeki
/// "İlk hisseni al" → İşlem sekmesi). `MainScreen` bunu dinler, uygular ve
/// -1'e sıfırlar (aynı sekme tekrar istenebilsin).
///
/// İndeksler: 0:Piyasalar · 1:Haberler · 2:İşlem · 3:Portföy
final ValueNotifier<int> kRequestedTab = ValueNotifier<int>(-1);
