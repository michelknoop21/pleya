/// How a catalog reads an age rating: one label for what several rating systems
/// spell differently. Split out of `unified_catalog_filters.dart` so the sort
/// comparator can use it without importing the filter model.
library;

/// One Leeftijd choice can stand for several raw ratings: Plex `gb/12` and
/// Jellyfin `12` are both "12", and each only matches on its own server. The
/// choice stores them joined by this, and [buildUnifiedCatalogQuery] sends
/// all of them to every library.
const String contentRatingValueSeparator = '|';

/// What a stored Leeftijd value reads as: the rating without its country
/// prefix, so `gb/12` and `12` are the same "12" in the panel, the rail tags
/// and a Home row's name.
String contentRatingLabel(String value) {
  final first = value.split(contentRatingValueSeparator).first;
  return first.substring(first.lastIndexOf('/') + 1);
}

/// Numeric ages in age order ("6" before "12"), named ratings after them.
int compareContentRatingLabels(String a, String b) {
  final ageA = int.tryParse(a);
  final ageB = int.tryParse(b);
  if (ageA != null && ageB != null) return ageA.compareTo(ageB);
  if (ageA != null || ageB != null) return ageA != null ? -1 : 1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// Whether the Leeftijd choice [label] is on. Compared by label, not by the
/// stored value: which raw ratings a choice joins depends on which servers were
/// online when it was ticked, so a stored `12|gb/12` is still the "12" a panel
/// offers as plain `12` while the Plex server is offline.
bool isContentRatingSelected(Set<String> stored, String label) =>
    stored.any((value) => contentRatingLabel(value) == label);

/// [stored] with the Leeftijd choice [label] switched: off removes every stored
/// value that reads as [label], on adds [value] (the raw ratings the reachable
/// servers name for it right now).
Set<String> toggleContentRating(Set<String> stored, {required String label, required String value}) =>
    isContentRatingSelected(stored, label)
    ? {
        for (final v in stored)
          if (contentRatingLabel(v) != label) v,
      }
    : {...stored, value};

/// The labels of [ratings], each once, in display order.
List<String> contentRatingLabels(Iterable<String> ratings) =>
    {for (final rating in ratings) contentRatingLabel(rating)}.toList()..sort(compareContentRatingLabels);
