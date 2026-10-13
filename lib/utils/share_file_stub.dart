/// Web (veya dart:io olmayan) için no-op — web'de indirme Blob ile yapılır
/// (file_download_web.dart). Conditional import hedefi — `share_file.dart`'a bak.
Future<void> shareBytes(List<int> bytes, String filename,
    {String mime = 'text/csv'}) async {
  // Web değil: bir şey yapma.
}
