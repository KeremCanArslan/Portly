// Platforma göre PDF seçici. Web'de file input (pdf_pick_web.dart), diğer
// platformlarda no-op (pdf_pick_stub.dart). UI tarafı `kIsWeb` ile butonu
// mobilde gizlemeli — image_pick.dart ile aynı kalıp, yeni paket gerekmez.
export 'pdf_pick_stub.dart' if (dart.library.html) 'pdf_pick_web.dart';
