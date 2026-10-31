/// The one line under a catalog card's title, for every surface that draws one.
///
/// Split out of `tv_unified_media_card.dart` when
/// [DEC-108](../../../docs/DECISIONS.md#dec-108) put the kijklijst and Zoeken
/// on the same card: "2024 · Sciencefiction" under a film and "2022 · 2
/// seizoenen" under a series has to mean the same thing on all of them, and two
/// copies of that rule would be two vocabularies for one card.
///
/// [TvCatalogCard] itself deliberately takes the finished string and knows
/// nothing about media — this is the adapters' shared half, not the card's.
library;

import '../../i18n/strings.g.dart';
import '../../media/catalog_score.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/unified/unified_media_group.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_catalog_query.dart';
import '../../utils/formatters.dart';

/// Year and first genre, as the mockups show and hoofdstuk 10.2 allows
/// ("Jaar optioneel onder titel").
///
/// One genre, not the list: at card width a second one is always truncated,
/// and a truncated genre reads as a broken string rather than as more
/// information. Empty when neither is known, which keeps the line's height
/// reserved — dropping the row instead would make cards in the same row
/// different heights and break the grid's baseline.
String tvCatalogMetaLine(MediaItem item) {
  final parts = <String>[if (item.year != null) '${item.year}', ?_seasonsOrGenre(item)];
  return parts.join('  ·  ');
}

/// The source whose value put [group] where it stands.
///
/// A group sits at its first candidate (hoofdstuk 11.9), which is the source
/// that sorts first. A card showing another source's score would read out of
/// order between its neighbours.
MediaItem tvCatalogSortValueItem(UnifiedMediaGroup group, UnifiedCatalogSort sort) {
  final compare = unifiedCatalogSortComparator(sort.field, sort.direction);
  var best = group.representativeSource.item;
  for (final source in group.sources) {
    if (compare(source.item, best) < 0) best = source.item;
  }
  return best;
}

/// The score the compact card draws as a badge, when the sort is on one.
CatalogScore? tvCatalogSortScore(MediaItem item, UnifiedCatalogSort sort) => switch (sort.field) {
  UnifiedCatalogSortField.criticRating => catalogCriticScore(item),
  UnifiedCatalogSortField.audienceRating => catalogAudienceScore(item),
  UnifiedCatalogSortField.userRating => catalogUserScore(item),
  _ => null,
};

/// The compact card's line (A-06c): the fact the page is sorted on, so a viewer
/// can read the order off the wall. A title without that fact gets an empty line
/// of the same height: a year in its place would read as the value.
///
/// Scores come back empty here and go through [tvCatalogSortScore]. Progress is
/// the position rather than a percentage, because the position is what the
/// servers order by.
///
/// [lastViewedAt] comes from the group, which folds its sources; the item only
/// knows its own server.
String tvCatalogSortedMetaLine(MediaItem item, {required UnifiedCatalogSort sort, int? lastViewedAt}) {
  String? positive(int? ms) => ms != null && ms > 0 ? formatDurationTextual(ms) : null;
  final line = switch (sort.field) {
    UnifiedCatalogSortField.title || UnifiedCatalogSortField.year => item.year?.toString(),
    UnifiedCatalogSortField.releaseDate => switch (item.originallyAvailableAt) {
      null || '' => null,
      final date => formatAbbreviatedDate(date),
    },
    UnifiedCatalogSortField.addedAt => _formatEpoch(item.addedAt),
    UnifiedCatalogSortField.recentlyWatched => _formatEpoch(lastViewedAt ?? item.lastViewedAt),
    UnifiedCatalogSortField.duration => positive(item.durationMs),
    UnifiedCatalogSortField.progress => positive(item.viewOffsetMs),
    UnifiedCatalogSortField.plays => _playCount(item.viewCount),
    UnifiedCatalogSortField.contentRating => switch (item.contentRating) {
      null || '' => null,
      final rating => contentRatingLabel(rating),
    },
    UnifiedCatalogSortField.resolution => item.mediaVersions?.firstOrNull?.videoResolutionLabel,
    UnifiedCatalogSortField.criticRating ||
    UnifiedCatalogSortField.audienceRating ||
    UnifiedCatalogSortField.userRating => null,
  };
  return line ?? '';
}

String? _playCount(int? count) {
  if (count == null || count <= 0) return null;
  return count == 1 ? t.unifiedCatalog.onePlay : t.unifiedCatalog.plays(count: count);
}

/// Servers report epoch seconds; the same guard against milliseconds as
/// `newBadgeLabel`.
String? _formatEpoch(int? epoch) {
  if (epoch == null || epoch <= 0) return null;
  final ms = epoch > 1000000000000 ? epoch : epoch * 1000;
  return formatAbbreviatedDate(DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String());
}

/// The half of the line where a show is allowed to look unlike a film.
///
/// A series is a different object: you resume into an episode, not into a
/// runtime, and "2015 · Family" under *Bluey* tells a viewer nothing they can
/// act on. So a show spends its second slot on how much there is of it rather
/// than on a genre — hoofdstuk 33.3's "S/A-aanduiding onder de titel". Films
/// keep the genre, which is the fact that separates two films of the same year.
///
/// Falls back to the genre when the backend did not report a season count, so a
/// show whose `childCount` is missing gets a film's line rather than a line with
/// a hole in it.
String? _seasonsOrGenre(MediaItem item) {
  if (item.kind == MediaKind.show) {
    final seasons = item.childCount ?? 0;
    if (seasons > 0) {
      return seasons == 1 ? t.unifiedCatalog.oneSeason : t.unifiedCatalog.seasons(count: seasons);
    }
  }
  final genre = (item.genres ?? const <String>[]).firstOrNull;
  return genre != null && genre.isNotEmpty ? genre : null;
}
