/// The catalog's selection, as the tags CAT5 puts beside the heading and inside
/// the rail (DEC-093).
///
/// Pure list arithmetic, tested away from a widget tree: the ordering, the cap
/// and the sort tag's separate status are the part that has to be identical in
/// both places the tags are drawn, and a golden can only ever show one of them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/widgets/tv/tv_catalog_selection_tags.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

void main() {
  List<String> labels(List<TvCatalogSelectionTag> tags) => [for (final tag in tags) tag.label];

  test('an untouched catalog states only its sort, and states it as not a filter', () {
    final tags = tvCatalogSelectionTags(
      filters: UnifiedCatalogFilterSelection.empty,
      sort: UnifiedCatalogSort.titleAsc,
    );

    expect(labels(tags), [sortLabel(UnifiedCatalogSort.titleAsc)]);
    expect(tags.single.muted, isTrue, reason: 'the sort is always set, so a solid tag would claim a narrowing');
  });

  test('filters come first, in a stable order, with the sort last', () {
    final tags = tvCatalogSelectionTags(
      filters: const UnifiedCatalogFilterSelection(
        genres: {'Thriller', 'Animatie'},
        years: {2024, 1999},
        watchState: UnifiedWatchFilter.unwatched,
      ),
      sort: UnifiedCatalogSort.recentlyAdded,
      overflowAfter: null,
      sourcesLabel: '2 sources',
    );

    expect(labels(tags), [
      t.unifiedCatalog.filters.unwatched,
      // Sorted rather than in set order: the sets behind these are unordered,
      // and a row that reshuffles between builds makes a golden and a
      // screenshot disagree for no reason.
      'Animatie',
      'Thriller',
      '1999',
      '2024',
      '2 sources',
      sortLabel(UnifiedCatalogSort.recentlyAdded),
    ]);
    expect(tags.where((tag) => tag.muted).map((tag) => tag.label), [sortLabel(UnifiedCatalogSort.recentlyAdded)]);
  });

  test('the heading caps the filters and counts the rest, and never drops the sort', () {
    final tags = tvCatalogSelectionTags(
      filters: const UnifiedCatalogFilterSelection(
        genres: {'Animatie', 'Comedy', 'Drama'},
        years: {2024},
        watchState: UnifiedWatchFilter.unwatched,
      ),
      sort: UnifiedCatalogSort.titleAsc,
    );

    expect(TvCatalogLayout.tagOverflowThreshold, 3, reason: 'the expectation below is written against this number');
    // Five filters: three shown, two counted, and the sort still last.
    expect(labels(tags), [
      t.unifiedCatalog.filters.unwatched,
      'Animatie',
      'Comedy',
      '+2',
      sortLabel(UnifiedCatalogSort.titleAsc),
    ]);
  });

  test('exactly the threshold shows every filter and no counter', () {
    final tags = tvCatalogSelectionTags(
      filters: const UnifiedCatalogFilterSelection(
        genres: {'Comedy', 'Drama'},
        watchState: UnifiedWatchFilter.unwatched,
      ),
      sort: UnifiedCatalogSort.titleAsc,
    );

    expect(labels(tags), [
      t.unifiedCatalog.filters.unwatched,
      'Comedy',
      'Drama',
      sortLabel(UnifiedCatalogSort.titleAsc),
    ]);
  });

  test('a source restriction is a tag only when the page says one applies', () {
    const restricted = UnifiedCatalogFilterSelection(serverIds: {'nas'});

    expect(
      labels(tvCatalogSelectionTags(filters: restricted, sort: UnifiedCatalogSort.titleAsc, sourcesLabel: '1 source')),
      contains('1 source'),
    );
    // The screen owns that string, because only it knows how many libraries
    // actually took part; a null means every source is in.
    expect(labels(tvCatalogSelectionTags(filters: restricted, sort: UnifiedCatalogSort.titleAsc)), [
      sortLabel(UnifiedCatalogSort.titleAsc),
    ]);
  });
}
