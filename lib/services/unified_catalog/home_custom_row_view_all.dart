/// Where a viewer-defined row's own "Alle N" tile sends the viewer (ROW1c,
/// [DEC-100](../../../docs/DECISIONS.md#dec-100) (2)): this row's exact
/// filter and sort, opened on its own kind's complete catalog.
///
/// Kept out of [UnifiedMediaHub] rather than added to its `viewAll` field:
/// hoofdstuk 10.2a's architecture boundary keeps `lib/media/unified/` pure of
/// the catalog's own filter model ([UnifiedCatalogFilterSelection],
/// [UnifiedCatalogSort]), which lives here in `lib/services/unified_catalog/`.
/// `HomeCustomRowsProvider` builds one of these next to the projected hub, and
/// the feed matches the two back up by `hubId`.
library;

import '../../media/media_kind.dart';
import 'unified_catalog_filters.dart';

class HomeCustomRowViewAllTarget {
  final MediaKind kind;
  final UnifiedCatalogFilterSelection filters;
  final UnifiedCatalogSort sort;

  /// The row's own count (hoofdstuk 10.7): what has loaded so far, not
  /// necessarily the catalog's true total. The tile shows it as-is — see
  /// mockup 32 A2, which draws a bare "Alle N" with no "geladen" qualifier.
  final int count;

  const HomeCustomRowViewAllTarget({
    required this.kind,
    required this.filters,
    required this.sort,
    required this.count,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeCustomRowViewAllTarget &&
          other.kind == kind &&
          other.filters == filters &&
          other.sort == sort &&
          other.count == count;

  @override
  int get hashCode => Object.hash(kind, filters, sort, count);
}
