import 'library_query.dart';
import 'media_kind.dart';

/// A backend that can count how many titles of a library listing sort before
/// a given name, without fetching the titles.
///
/// Jellyfin answers this with `NameLessThan` plus `Limit=0`. The phone alphabet
/// scrubber turns the counts into per-letter offsets.
abstract interface class TitleLetterCountClient {
  /// Count the titles in the listing [query] describes (offset, limit and sort
  /// ignored) that sort before each entry of [bounds], plus the listing total.
  ///
  /// Throws when the server does not report an exact total.
  Future<({int total, Map<String, int> before})> fetchTitleCountsBefore(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    required List<String> bounds,
  });
}
