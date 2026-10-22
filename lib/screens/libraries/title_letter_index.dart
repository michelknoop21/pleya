import '../../data/ducet_order.dart';
import '../../media/library_first_character.dart';

/// Letter index for backends without Plex's `/firstCharacter` endpoint.
///
/// Both builders return `null` when the index cannot be trusted. The caller
/// treats `null` as "no scrubber": a rail that lands on the wrong title is
/// worse than no rail.
///
/// [AlphaJumpHelper] re-sorts the buckets with [ducetCompare] and reverses them
/// for a descending sort, so a bucket list is only correct when the backend's
/// own order agrees with that. Both builders check it.

/// Bounds sent as `NameLessThan` to count the titles before each letter.
/// Jellyfin compares them case-insensitively against `SortName`, the same key
/// `SortBy=SortName` orders by, so the counts line up with the grid offsets.
const List<String> titleIndexBounds = [
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', //
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
];

/// The bound just past `z` (`{` follows `z` in code point order), so
/// `total - before[titleIndexEndBound]` counts the titles that sort after `z`.
const String titleIndexEndBound = '{';

/// The bucket a title falls in: its first character upper-cased, or `#` for a
/// digit, punctuation, an empty title or a script without letter case.
String titleLetterBucket(String title) {
  final trimmed = title.trimLeft();
  if (trimmed.isEmpty) return '#';
  final first = String.fromCharCode(trimmed.runes.first);
  final upper = first.toUpperCase();
  if (upper == first.toLowerCase()) return '#';
  return upper;
}

/// Buckets from the complete listing in the order the grid shows it.
///
/// Returns `null` when a letter appears in more than one run, or when the runs
/// are not in the order [AlphaJumpHelper] will put them in. Either means the
/// backend sorts by something other than these first letters (an article
/// rule, a case-sensitive compare, another collation), and every offset after
/// the first disagreement would be wrong.
List<LibraryFirstCharacter>? letterIndexFromOrderedTitles(Iterable<String> titles, {required bool descending}) {
  final runs = <({String letter, int size})>[];
  for (final title in titles) {
    final letter = titleLetterBucket(title);
    if (runs.isNotEmpty && runs.last.letter == letter) {
      runs.last = (letter: letter, size: runs.last.size + 1);
    } else {
      runs.add((letter: letter, size: 1));
    }
  }
  for (var i = 1; i < runs.length; i++) {
    final order = ducetCompare(runs[i - 1].letter, runs[i].letter);
    if (descending ? order <= 0 : order >= 0) return null;
  }
  return [for (final run in runs) LibraryFirstCharacter(key: run.letter, title: run.letter, size: run.size)];
}

/// Buckets from "how many titles sort before this letter" counts.
///
/// [before] holds a count per entry of [titleIndexBounds] plus
/// [titleIndexEndBound]; [total] is the size of the whole listing. Titles
/// before `a` form `#`. Returns `null` when a count is missing, when the
/// counts are not non-decreasing (the listing changed between requests), or
/// when titles sort after `z` (another script, an accented first letter):
/// those would only fit under a `Z` label that does not describe them.
List<LibraryFirstCharacter>? letterIndexFromCountsBefore({required int total, required Map<String, int> before}) {
  final counts = <int>[];
  for (final bound in [...titleIndexBounds, titleIndexEndBound]) {
    final count = before[bound];
    if (count == null) return null;
    counts.add(count);
  }
  var previous = 0;
  for (final count in [...counts, total]) {
    if (count < previous) return null;
    previous = count;
  }
  if (counts.last != total) return null;
  final result = <LibraryFirstCharacter>[LibraryFirstCharacter(key: '#', title: '#', size: counts.first)];
  for (var i = 0; i < titleIndexBounds.length; i++) {
    final end = counts[i + 1];
    final letter = titleIndexBounds[i].toUpperCase();
    result.add(LibraryFirstCharacter(key: letter, title: letter, size: end - counts[i]));
  }
  return result;
}
