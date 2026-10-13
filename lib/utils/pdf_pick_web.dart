// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Web'de BİRDEN ÇOK PDF seçtirir (gizli `<input type=file multiple>`).
/// Midas ekstreyi yalnız AYLIK verdiği için bir yıllık geçmiş 12 dosya
/// demek — kullanıcı hepsini tek seferde seçebilmeli.
/// İptal/boş seçimde boş liste döner.
class PickedPdf {
  final Uint8List bytes;
  final String filename;
  const PickedPdf(this.bytes, this.filename);
}

Future<List<PickedPdf>> pickPdfsWeb() async {
  final input = html.FileUploadInputElement()
    ..accept = 'application/pdf,.pdf'
    ..multiple = true
    ..style.display = 'none';
  // Girdi DOM'a EKLENİR: kopuk (detached) input üzerinde click() Chrome'da
  // çalışsa da Safari'de güvenilir değil ve bazı otomasyon/erişilebilirlik
  // katmanları onu hiç görmez. İş bitince kaldırılır.
  html.document.body?.append(input);
  try {
    input.click();
    await input.onChange.first;
    final files = input.files;
    if (files == null || files.isEmpty) return const [];
    return await _readAll(files);
  } finally {
    input.remove();
  }
}

/// Seçilen dosyaları sırayla belleğe okur.
Future<List<PickedPdf>> _readAll(List<html.File> files) async {
  final picked = <PickedPdf>[];
  for (final file in files) {
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoadEnd.first;

    final result = reader.result;
    final Uint8List bytes;
    if (result is ByteBuffer) {
      bytes = result.asUint8List();
    } else if (result is List<int>) {
      bytes = Uint8List.fromList(result);
    } else {
      continue;
    }
    // Görsel import'un aksine küçültme YOK: PDF'in metin katmanı
    // bozulmamalı, parse tam ona dayanıyor.
    picked.add(PickedPdf(bytes, file.name));
  }
  return picked;
}
