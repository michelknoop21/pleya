/// Runs [task] for every index below [count], at most [width] at a time (at
/// least one, so a width of zero cannot skip the work) and started in index
/// order. After a failure no new index starts; the running
/// tasks finish and the first error is rethrown, so nothing keeps running
/// once this returns.
Future<void> bounded(int width, int count, Future<void> Function(int index) task) async {
  var next = 0;
  var failed = false;
  Future<void> worker() async {
    while (!failed && next < count) {
      try {
        await task(next++);
      } catch (_) {
        failed = true;
        rethrow;
      }
    }
  }

  await Future.wait([for (var w = 0; w < count && (w < width || w == 0); w++) worker()]);
}
