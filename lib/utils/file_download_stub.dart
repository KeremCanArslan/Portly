/// Web-olmayan platformlar için no-op (mobilde indirme launchUrl ile ayrı
/// ele alınır). Conditional import hedefi — `file_download.dart`'a bak.
void downloadBytes(List<int> bytes, String filename,
    {String mime = 'text/csv'}) {
  // Web değil: bir şey yapma.
}
