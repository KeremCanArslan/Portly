// Web olmayan platformlar için no-op. Conditional import hedefi —
// `pdf_pick.dart`'a bak. Ekstre içe aktarma şu an yalnız web'de;
// mobil UI'da buton gizlenir.
import 'dart:typed_data';

class PickedPdf {
  final Uint8List bytes;
  final String filename;
  const PickedPdf(this.bytes, this.filename);
}

Future<List<PickedPdf>> pickPdfsWeb() async => const [];
