// Platforma göre görsel seçici. Web'de file input (image_pick_web.dart),
// diğer platformlarda no-op (image_pick_stub.dart). UI tarafı `kIsWeb` ile
// butonu mobile'de gizlemeli.
export 'image_pick_stub.dart'
    if (dart.library.html) 'image_pick_web.dart';
