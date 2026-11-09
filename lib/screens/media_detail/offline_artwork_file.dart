import 'dart:io';

/// The local file for a piece of offline detail artwork: the offline index
/// copy when its file still exists, otherwise the downloaded copy. Each one is
/// checked on its own, because the index hands out its stored path without a
/// file check and a purged poster must not hide a downloaded one.
String? offlineArtworkFile(String? indexPath, String? Function() downloadPath) {
  if (indexPath != null && File(indexPath).existsSync()) return indexPath;
  final download = downloadPath();
  return download != null && File(download).existsSync() ? download : null;
}
