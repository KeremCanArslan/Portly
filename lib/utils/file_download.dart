// Platforma göre dosya indirme. Web'de Blob+anchor (file_download_web.dart),
// diğer platformlarda no-op (file_download_stub.dart).
//
// Kullanım:
//   import 'package:portly/utils/file_download.dart' as fd;
//   fd.downloadBytes(bytes, 'dosya.csv');
export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';
