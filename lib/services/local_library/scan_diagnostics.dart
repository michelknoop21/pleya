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
      'readIndex=$readIndex readIndexMs=$readIndexMs';
}

/// Process-wide state the frame log reads, so a scroll during a scan can be
/// told apart from the same scroll without one.
abstract final class ScanDiagnostics {
  static bool scanning = false;

  /// Calls to `LocalLibraryProvider.posterPath`, reset by each frame log line.
  static int posterPathCalls = 0;
}
