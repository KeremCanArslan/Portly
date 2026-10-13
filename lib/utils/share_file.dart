// Platforma göre dosya paylaşımı. dart:io olan platformlarda (mobil/masaüstü)
// bytes'ı geçici dosyaya yazıp native paylaşım sayfasını açar; web'de no-op
// (web indirmeyi Blob ile yapar — bkz. file_download.dart).
//
// Kullanım:
//   import 'package:portly/utils/share_file.dart' as sf;
//   await sf.shareBytes(bytes, 'dosya.csv');
export 'share_file_stub.dart' if (dart.library.io) 'share_file_io.dart';
