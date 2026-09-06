/// Which rows Home has, in which order (hoofdstuk 9.1 and 17.5, ROW1 /
/// [DEC-100](../../../docs/DECISIONS.md#dec-100)).
///
/// Two surfaces need this answer and they must not each derive it: the feed
/// draws the rows, and the customise panel lists them so they can be moved.
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

import '../../media/unified/unified_media_hub.dart';
import '../../providers/home_custom_rows_provider.dart';
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
  bool includeHidden = false,
  bool includeEmpty = false,
}) {
  final own = includeEmpty
      ? customRows?.allRows(titleFor: homeCustomRowLabel)
      : customRows?.visibleRows(titleFor: homeCustomRowLabel);
  final orderable = [...?own, ?projection.latestMovies, ...projection.hubs];
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
}) {
  final cw = projection.continueWatching;
  return [
    if (cw != null && cw.groups.isNotEmpty) cw,
    ...tvHomeOrderableRows(projection: projection, layout: layout, customRows: customRows),
  ];
}
