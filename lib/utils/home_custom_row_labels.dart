/// The words a saved Home row is shown under (ROW1,
/// [DEC-100](../../docs/DECISIONS.md#dec-100)).
///
/// Separate from `home_custom_row.dart` because deriving a label needs a
/// locale and the model layer has none, and separate from the widgets because
/// Home, the customise panel and the settings screen have to agree on it: a row
/// called one thing on Home and another in the panel is a row the viewer cannot
/// find again.
library;

import '../i18n/strings.g.dart';
import '../media/media_kind.dart';
import '../services/unified_catalog/home_custom_row.dart';
import '../services/unified_catalog/unified_catalog_filters.dart';

/// What the row is called on Home.
///
/// An unnamed row is named after its filter and keeps following it (C1), which
/// is what lets a row be made without ever opening the keyboard. Only the
/// *item* filters take part: the source restriction says which servers were
/// asked, not what the row is about, and putting it in the label would call a
/// row "Science fiction, NAS".
String homeCustomRowLabel(HomeCustomRow row) {
  if (row.name.isNotEmpty) return row.name;
  final parts = homeCustomRowFilterParts(row);
  if (parts.isNotEmpty) return parts.join(', ');
  return row.kind == MediaKind.movie ? t.unifiedCatalog.discovery.allMovies : t.unifiedCatalog.discovery.allSeries;
}

/// The row's item filters, one phrase per narrowing, in the order the filter
/// panel lists them.
///
/// Sorted within a field so two rows built from the same choices read the same
/// way; the sets themselves carry no order.
List<String> homeCustomRowFilterParts(HomeCustomRow row) {
  final filters = row.filters;
  return [
    if (filters.genres.isNotEmpty) (filters.genres.toList()..sort()).join(', '),
    if (filters.years.isNotEmpty) (filters.years.toList()..sort()).join(', '),
    if (filters.watchState == UnifiedWatchFilter.unwatched) t.unifiedCatalog.filters.unwatched,
  ];
}
