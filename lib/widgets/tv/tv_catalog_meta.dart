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
import '../../media/media_item.dart';
import '../../media/media_kind.dart';

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
