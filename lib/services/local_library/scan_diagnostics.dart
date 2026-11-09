import 'dart:io' show ProcessInfo;

import '../../utils/app_logger.dart';

/// Counters for one library scan, logged once when the scan ends. They exist to
/// measure what a scan costs on a slow device (requests, whole-file writes,
/// read-index rebuilds), not to steer it.
class ScanStats {
  final _watch = Stopwatch()..start();
  int root = 0;
  int children = 0;
  int detail = 0;
  int extIds = 0;
  int posters = 0;
  int checkpoints = 0;
  int checkpointMs = 0;
  int saveMs = 0;
  int readIndex = 0;
  int readIndexMs = 0;

  String line({required String library, required String backend, required String result, required int items}) =>
      'scanstats lib=$library backend=$backend result=$result ms=${_watch.elapsedMilliseconds} items=$items '
      'req root=$root children=$children detail=$detail extIds=$extIds posters=$posters '
      'checkpoints=$checkpoints checkpointMs=$checkpointMs saveMs=$saveMs '
      'readIndex=$readIndex readIndexMs=$readIndexMs rss=$rssNow';
}

/// `current/peak` process memory in MB, for attributing rss to a log line.
String get rssNow => '${ProcessInfo.currentRss >> 20}/${ProcessInfo.maxRss >> 20}MB';

/// One line after the store read its index files, to tell app start apart from a scan.
void logLoadStats({required int files, required int bytes, required int ms}) =>
    appLogger.i('loadstats files=$files bytes=$bytes ms=$ms rss=$rssNow');

/// Process-wide state the frame log reads, so a scroll during a scan can be
/// told apart from the same scroll without one.
abstract final class ScanDiagnostics {
  static bool scanning = false;

  /// Calls to `LocalLibraryProvider.posterPath`, reset by each frame log line.
  static int posterPathCalls = 0;

  /// Builds of a TV catalog card, reset by each frame log line. Grows with the
  /// number of cards a frame rebuilds, not with the number on screen.
  static int cardBuilds = 0;
}
