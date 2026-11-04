/// Which rows Home has, in which order (hoofdstuk 9.1 and 17.5, ROW1 /
/// [DEC-100](../../../docs/DECISIONS.md#dec-100)).
///
/// Every surface that needs this answer reads it here and none derives it: the
/// TV feed and the iPhone Home draw the rows, and the customise panel lists
/// them so they can be moved.
/// A panel that ordered rows by its own rule would move a row to a place the
/// feed then puts it somewhere else, which is the kind of disagreement nobody
/// reports as a bug because it merely feels arbitrary.
///
/// ## Continue Watching is the only row outside the layout
///
/// It used to be two. DEC-100 (4) locks Uitgelicht and Verder kijken and
/// nothing else, and mockup 32 B draws Recent uitgebracht with the same move
/// and hide controls as a backend row. It already carried a contributing row id
/// from `projectHubs`, so nothing had to be invented for it — it reaches the
/// layout now, where it always could have.
///
/// ## Where a new own row lands
///
/// At the front, which is where a Home with no stored order draws it: directly
/// under Verder kijken, as DEC-100 (5) asks. Once anything has been moved the
/// stored order decides instead and this position stops mattering.
library;

import '../../media/media_item.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../providers/home_custom_rows_provider.dart';
import '../../providers/home_extra_rows_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../utils/home_custom_row_labels.dart';

/// Every row the layout may reorder, in display order.
///
/// [includeHidden] and [includeEmpty] are what separate the two audiences. Home
/// wants neither: a hidden row is hidden, and DEC-100 (6) takes an own row that
/// has gone empty off the page. The customise panel wants both, because a row
/// you cannot see is a row you cannot bring back.
List<UnifiedMediaHub> tvHomeOrderableRows({
  required TvHomeProjectionProvider projection,
  HomeLayoutProvider? layout,
  HomeCustomRowsProvider? customRows,
  HomeExtraRowsProvider? extraRows,
  bool includeHidden = false,
  bool includeEmpty = false,
}) {
  final own = includeEmpty
      ? customRows?.allRows(titleFor: homeCustomRowLabel)
      : customRows?.visibleRows(titleFor: homeCustomRowLabel);
  // Kijklijst and Nu op tv sit under Recent uitgebracht until the viewer moves
  // them (DEC-145).
  final extra = includeEmpty ? extraRows?.allRows() : extraRows?.visibleRows();
  final orderable = [...?own, ?projection.latestMovies, ...?extra, ...projection.hubs];
  if (layout == null) return orderable;
  return applyHomeLayoutToUnifiedRows(
    orderable,
    hiddenRowIds: includeHidden ? const {} : layout.hiddenRowIds,
    order: layout.order,
  );
}

/// What the feed draws: [tvHomeOrderableRows] with Verder kijken pinned in
/// front of it.
List<UnifiedMediaHub> tvHomeFeedRows({
  required TvHomeProjectionProvider projection,
  HomeLayoutProvider? layout,
  HomeCustomRowsProvider? customRows,
  HomeExtraRowsProvider? extraRows,
}) {
  final cw = projection.continueWatching;
  return [
    if (cw != null && cw.groups.isNotEmpty) cw,
    ...tvHomeOrderableRows(projection: projection, layout: layout, customRows: customRows, extraRows: extraRows),
  ];
}

/// Which slides the Home billboard shows, and whether that is the final answer.
///
/// Hoofdstuk 9.7: an empty `heroGroups` for the films Home is *currently*
/// showing is an answer; an empty one because the projection has not yet
/// consumed the films that just landed is not. [settled] tells them apart. The
/// two get different treatment, the fallback billboard for the first and
/// reserved space for the second, because flashing a Continue Watching title as
/// the billboard and then replacing it a beat later with a film is the exact
/// "hero mag niet boven een al gefocuste rij ingevoegd worden" jump 9.7 forbids.
///
/// Hoofdstuk 9.5's last sentence, and fase-8 brief §22's "0 hero groups": when
/// the deduplicated recent-film pool is genuinely empty, a show-only library or
/// every recent film ineligible, the billboard falls through to the first
/// Continue Watching title, then to the first hub's.
///
/// One slide, never a rotation over the whole library: this is a stand-in for
/// a featured title, and rotating it would claim these are new releases. And
/// it is still a group, so its Afspelen resolves through the fase-4
/// coordinator like every other card on the page.
///
/// [idleIsSettled] closes the two ways "not caught up" can last: a projection
/// that threw, and a reload whose new empty list the projection skips because
/// it equals the old one. Nothing is on its way then. tvOS keeps its reserved
/// space; the iPad would hold an empty band of nearly a whole page above the
/// rows and any error message.
({List<UnifiedMediaGroup> groups, bool settled}) homeBillboardGroups({
  required TvHomeProjectionProvider projection,
  required List<MediaItem> latestMovies,
  required List<UnifiedMediaHub> rows,
  bool idleIsSettled = false,
}) {
  final caughtUp = projection.hasProjectedHero && identical(projection.projectedLatestMovies, latestMovies);
  final settled = caughtUp || (idleIsSettled && !projection.isProjecting);
  if (projection.heroGroups.isNotEmpty) return (groups: projection.heroGroups, settled: settled);
  if (!settled) return (groups: const [], settled: false);
  for (final row in rows) {
    if (row.groups.isNotEmpty) return (groups: [row.groups.first], settled: true);
  }
  return (groups: const [], settled: true);
}
