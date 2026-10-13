import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Mobil/masaüstü: bytes'ı geçici dosyaya yazıp native paylaşım sayfasını açar
/// (kaydet/WhatsApp/Drive vb.). Eskiden mobilde `launchUrl(backendUrl)` ile
/// açılıyordu ama Bearer token taşımıyordu → backend "Not authenticated"
/// dönüyordu. Bytes auth'lu çekilip (api_service.fetchCsvBytes) buraya verilir.
Future<void> shareBytes(List<int> bytes, String filename,
    {String mime = 'text/csv'}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: mime)],
    subject: filename,
  );
}
