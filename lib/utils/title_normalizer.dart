/// Lower-cased, punctuation- and whitespace-stripped title for comparison.
///
/// A trailing `(2024)` is dropped so "Movie (2024)" matches "Movie", which is
/// the difference between two libraries that disagree about whether the year
/// belongs in the name.
///
/// Extracted from `LocalServerSyncBridge` so the watchlist matcher can share
/// exactly the same rule without dragging a service, its preferences and its
/// server manager into a pure model. `LocalServerSyncBridge.normalizeTitle`
/// still exists and calls through here, so both paths cannot drift apart.
String normalizeTitleForMatching(String? title) {
  if (title == null) return '';
  var t = title.toLowerCase();
  t = t.replaceAll(RegExp(r'\(\d{4}\)'), ' ');
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return t;
}

/// A folder-style year suffix is metadata, not part of the visible title.
/// Raw backend fields and standalone numeric titles remain untouched.
String titleWithoutYearSuffix(String title) => title.trim().replaceFirst(RegExp(r'\s*\(\d{4}\)$'), '').trim();
