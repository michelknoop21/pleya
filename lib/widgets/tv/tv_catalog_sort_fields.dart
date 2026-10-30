/// The sort page of the full-bleed catalog (A-06c) shows one row per field, not
/// one per [UnifiedCatalogSort]. This file is that view, and only that: the
/// enum, its stored names and the sorting itself are untouched.
///
/// Choosing the field in force turns its direction over. Choosing another
/// field takes that field's own default direction: titles run A to Z, the
/// dates and the scores start with the highest. A field with a single direction
/// (Recent bekeken, Voortgang) has nothing to turn over, so choosing it again
/// keeps it.
library;

import 'package:flutter/widgets.dart' show IconData;
import 'package:material_symbols_icons/symbols.dart';

import '../../media/library_menu_definition.dart';
import '../../media/library_query.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_catalog_query.dart';

/// The rows of the page, from the shared menu definition. Nothing here counts
/// fields, so a new [UnifiedCatalogSortField] is a new row once the definition
/// and its default direction name it.
const List<UnifiedCatalogSortField> tvCatalogSortFields = librarySortMenu;

String tvCatalogSortFieldLabel(UnifiedCatalogSortField field) => librarySortFieldLabel(field);

/// The direction a field starts in when it is chosen from another one.
LibrarySortDirection tvCatalogDefaultDirection(UnifiedCatalogSortField field) => switch (field) {
  UnifiedCatalogSortField.title || UnifiedCatalogSortField.contentRating => LibrarySortDirection.ascending,
  UnifiedCatalogSortField.year ||
  UnifiedCatalogSortField.releaseDate ||
  UnifiedCatalogSortField.criticRating ||
  UnifiedCatalogSortField.audienceRating ||
  UnifiedCatalogSortField.userRating ||
  UnifiedCatalogSortField.duration ||
  UnifiedCatalogSortField.progress ||
  UnifiedCatalogSortField.plays ||
  UnifiedCatalogSortField.addedAt ||
  UnifiedCatalogSortField.recentlyWatched ||
  UnifiedCatalogSortField.resolution => LibrarySortDirection.descending,
};

UnifiedCatalogSort? _of(UnifiedCatalogSortField field, LibrarySortDirection direction) {
  for (final sort in UnifiedCatalogSort.values) {
    if (sort.field == field && sort.direction == direction) return sort;
  }
  return null;
}

/// Whether [sort] has an opposite direction to turn to.
bool tvCatalogCanReverse(UnifiedCatalogSort sort) => _reversed(sort) != null;

UnifiedCatalogSort? _reversed(UnifiedCatalogSort sort) => _of(
  sort.field,
  sort.direction == LibrarySortDirection.ascending ? LibrarySortDirection.descending : LibrarySortDirection.ascending,
);

/// The sort that choosing the row of [field] gives, while [current] is in force.
UnifiedCatalogSort tvCatalogSortAfterChoosing(UnifiedCatalogSort current, UnifiedCatalogSortField field) {
  if (current.field == field) return _reversed(current) ?? current;
  return _of(field, tvCatalogDefaultDirection(field)) ?? current;
}

/// The arrow of the active row: down while the list reads from its first value
/// down (A to Z, oldest first), up for the reverse. Null on a field that cannot
/// turn over, which gets the tick instead: an arrow there would promise a
/// reversal that does not exist.
IconData? tvCatalogDirectionIcon(UnifiedCatalogSort sort) {
  if (!tvCatalogCanReverse(sort)) return null;
  return sort.direction == LibrarySortDirection.ascending
      ? Symbols.arrow_downward_rounded
      : Symbols.arrow_upward_rounded;
}
