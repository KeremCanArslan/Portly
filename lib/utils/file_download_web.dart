// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web'de gerçek dosya indirmesi: Blob + `download` attribute'lu görünmez
/// anchor + programatik tık. Eskiden `launchUrl(data:URI)` kullanılıyordu
/// ama modern tarayıcılar `data:` URI'ye top-level navigasyonu güvenlik
/// nedeniyle bloklar → CSV inmiyordu. Blob/anchor yöntemi standart ve
/// güvenilir. Bytes backend'den geldiği gibi yazılır (UTF-8-sig BOM korunur).
void downloadBytes(List<int> bytes, String filename,
    {String mime = 'text/csv'}) {
  final blob = html.Blob(<dynamic>[bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
