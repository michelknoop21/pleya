/// The discovery source is shared by the phone, tablet/desktop and TV views.
enum SeerrDiscoverySource { popular, trending, upcoming }

/// Kept under its existing name for callers of the phone presentation.
enum MobileSeerrCatalogSort { popularity, newest, oldest, rating, title }

/// Inclusive dates for Seerr's movie-release / TV-first-air-date parameters.
/// Upcoming means future releases, not a verified regional cinema schedule.
({String? from, String? through}) seerrReleaseWindow({int? year, required bool upcoming, required DateTime today}) {
  String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final start = year == null ? null : DateTime(year);
  final from = upcoming && (start == null || start.isBefore(tomorrow)) ? tomorrow : start;
  return (from: from == null ? null : date(from), through: year == null ? null : date(DateTime(year, 12, 31)));
}
