// Web olmayan platformlar için no-op. dart:html dart:ui_web yok, native
// fotoğraf seçici (image_picker paketi) ayrı bir akış. Conditional
// import hedefi — `image_pick.dart`'a bak. Screenshot içe aktarma
// özelliği şu an sadece web'de; mobile UI'da buton gizlenir.
import 'dart:typed_data';

class PickedImage {
  final Uint8List bytes;
  final String filename;
  final String mime;
  const PickedImage(this.bytes, this.filename, this.mime);
}

Future<PickedImage?> pickImageWeb() async => null;
Future<List<PickedImage>> pickImagesWeb() async => const [];
