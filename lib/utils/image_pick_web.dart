// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

/// Web'de görsel seçtirir (gizli `<input type=file>`), seçilen dosyanın
/// bytes/ad/mime'ını döndürür. İptal edilirse null. CSV indirmedeki
/// (file_download_web) aynı dart:html yaklaşımı — yeni paket gerekmez.
class PickedImage {
  final Uint8List bytes;
  final String filename;
  final String mime;
  const PickedImage(this.bytes, this.filename, this.mime);
}

Future<PickedImage?> pickImageWeb() async {
  final picked = await pickImagesWeb();
  return picked.isEmpty ? null : picked.first;
}

/// Web'de BİRDEN FAZLA görsel seçtirir (`multiple`). Kullanıcı tek seçim de
/// yapabilir. İptal/boş seçimde boş liste döner. Çoklu portföy screenshot'ını
/// tek seferde alıp satır satır içe aktarmak için.
Future<List<PickedImage>> pickImagesWeb() async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/png,image/jpeg,image/webp'
    ..multiple = true;
  input.click();

  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return const [];

  final picked = <PickedImage>[];
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

    final mime = file.type.isNotEmpty ? file.type : 'image/png';
    picked.add(await _downscale(PickedImage(bytes, file.name, mime)));
  }
  return picked;
}

/// Telefon screenshot'ları büyük (PNG, 2–5 MB) → 8 MB backend limitine yaklaşır
/// ve vision token'ı pahalanır. En uzun kenarı [maxSide]'a indirip JPEG'e
/// çevirir; metin OCR için okunur kalır, boyut tipik 5–10× düşer. Herhangi bir
/// hatada VEYA küçültme kazanç sağlamazsa orijinal bytes döner (bozmaktansa).
Future<PickedImage> _downscale(
  PickedImage img, {
  int maxSide = 2000,
  num quality = 0.85,
}) async {
  String? url;
  try {
    url = html.Url.createObjectUrlFromBlob(html.Blob([img.bytes], img.mime));
    final el = html.ImageElement()..src = url;
    await el.onLoad.first;
    final w = el.naturalWidth, h = el.naturalHeight;
    if (w == 0 || h == 0) return img;

    final longest = w > h ? w : h;
    final scale = longest > maxSide ? maxSide / longest : 1.0;
    final tw = (w * scale).round(), th = (h * scale).round();

    final canvas = html.CanvasElement(width: tw, height: th);
    canvas.context2D.drawImageScaled(el, 0, 0, tw, th);
    final dataUrl = canvas.toDataUrl('image/jpeg', quality);
    final encoded = base64Decode(dataUrl.split(',').last);

    if (encoded.lengthInBytes >= img.bytes.lengthInBytes) return img;
    final name = '${img.filename.replaceAll(RegExp(r"\.\w+$"), "")}.jpg';
    return PickedImage(encoded, name, 'image/jpeg');
  } catch (_) {
    return img;
  } finally {
    if (url != null) html.Url.revokeObjectUrl(url);
  }
}
