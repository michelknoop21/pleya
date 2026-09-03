import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_filter_options.dart';
import 'package:pleya/widgets/mobile/mobile_filter_categories.dart';

/// The filter panel's data layer — mockup `04-filters-sheet.png`, iOS Unified
/// 2026 fase 3. Pure, so these run without a widget tree.
void main() {
  CatalogLibrary library(String serverId, String libraryId, {MediaBackend backend = MediaBackend.plex}) => (
    serverId: ServerId(serverId),
    serverName: serverId.toUpperCase(),
    libraryId: libraryId,
    libraryTitle: 'Library $libraryId',
    backend: backend,
  );

  const allCapable = UnifiedFilterCapabilities(supportsMetadataFilters: true, supportsWatchFilter: true);
  const noneCapable = UnifiedFilterCapabilities(supportsMetadataFilters: false, supportsWatchFilter: false);

  List<MobileFilterSection> sections({
    UnifiedCatalogFilterSelection selection = UnifiedCatalogFilterSelection.empty,
    UnifiedFilterCapabilities capabilities = allCapable,
    UnifiedFilterOptions options = const UnifiedFilterOptions(genres: ['Drama', 'Sci-Fi'], years: [2024, 2023]),
    List<CatalogLibrary>? libraries,
  }) => buildMobileFilterSections(
    selection: selection,
    capabilities: capabilities,
    options: options,
    eligibleLibraries: libraries ?? [library('nas', 'films'), library('nas', 'kids'), library('attic', 'films')],
  );

  MobileFilterSection sectionFor(List<MobileFilterSection> all, MobileFilterCategory category) =>
      all.firstWhere((s) => s.category == category);

  test('the panel has mockup 04\'s five categories, in its order', () {
    expect(sections().map((s) => s.category).toList(), [
      MobileFilterCategory.status,
      MobileFilterCategory.genre,
      MobileFilterCategory.year,
      MobileFilterCategory.servers,
      MobileFilterCategory.libraries,
    ]);
  });

  test('Status ticks a row but is not counted while it sits on All', () {
    final status = sectionFor(sections(), MobileFilterCategory.status);
    // The tick and the count answer different questions: "All" is a row that
    // has to look chosen, and it is not a narrowing.
    expect(status.selected, {UnifiedWatchFilter.all.name});
    expect(status.activeCount, 0);
  });

  test('Status counts once it is on Unwatched', () {
    final status = sectionFor(
      sections(selection: const UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched)),
      MobileFilterCategory.status,
    );
    expect(status.selected, {UnifiedWatchFilter.unwatched.name});
    expect(status.activeCount, 1);
  });

  test('a category counts its values, not one per field', () {
    final genre = sectionFor(
      sections(selection: const UnifiedCatalogFilterSelection(genres: {'Drama', 'Sci-Fi'})),
      MobileFilterCategory.genre,
    );
    // Mockup 04 draws "Genre 1" beside one picked genre; two picks read 2 here
    // while the header's "N active" still reads 1 for the one field.
    expect(genre.activeCount, 2);
  });

  test('an unsupported category is listed and disabled, never dropped', () {
    final all = sections(
      capabilities: noneCapable,
      selection: const UnifiedCatalogFilterSelection(genres: {'Drama'}),
    );

    expect(all.length, 5, reason: 'a missing row would look like a missing feature');
    expect(sectionFor(all, MobileFilterCategory.genre).supported, isFalse);
    // Still ticked, so the choice is visible and can be untangled by narrowing
    // sources; not counted, because right now it narrows nothing.
    expect(sectionFor(all, MobileFilterCategory.genre).selected, {'Drama'});
    expect(sectionFor(all, MobileFilterCategory.genre).activeCount, 0);
  });

  test('servers and libraries stay available whatever the backends are', () {
    final all = sections(capabilities: noneCapable);
    expect(sectionFor(all, MobileFilterCategory.servers).supported, isTrue);
    expect(sectionFor(all, MobileFilterCategory.libraries).supported, isTrue);
  });

  test('servers are listed once each, libraries once per library', () {
    final all = sections();
    expect(sectionFor(all, MobileFilterCategory.servers).options.map((o) => o.id).toList(), ['nas', 'attic']);
    expect(sectionFor(all, MobileFilterCategory.libraries).options.length, 3);
  });

  test('a supported category with nothing to offer says so rather than drawing nothing', () {
    final genre = sectionFor(sections(options: UnifiedFilterOptions.empty), MobileFilterCategory.genre);
    expect(genre.supported, isTrue);
    expect(genre.hasOptions, isFalse);
  });

  group('toggling', () {
    test('genre adds and removes, and the last removal is an empty set', () {
      var selection = UnifiedCatalogFilterSelection.empty;
      selection = toggleMobileFilter(selection: selection, category: MobileFilterCategory.genre, optionId: 'Drama');
      expect(selection.genres, {'Drama'});

      selection = toggleMobileFilter(selection: selection, category: MobileFilterCategory.genre, optionId: 'Sci-Fi');
      expect(selection.genres, {'Drama', 'Sci-Fi'});

      selection = toggleMobileFilter(selection: selection, category: MobileFilterCategory.genre, optionId: 'Drama');
      selection = toggleMobileFilter(selection: selection, category: MobileFilterCategory.genre, optionId: 'Sci-Fi');
      // Not "every genre" — the empty set is what "no genre filter" is.
      expect(selection.genres, isEmpty);
    });

    test('status replaces instead of accumulating', () {
      var selection = toggleMobileFilter(
        selection: UnifiedCatalogFilterSelection.empty,
        category: MobileFilterCategory.status,
        optionId: UnifiedWatchFilter.unwatched.name,
      );
      expect(selection.watchState, UnifiedWatchFilter.unwatched);

      selection = toggleMobileFilter(
        selection: selection,
        category: MobileFilterCategory.status,
        optionId: UnifiedWatchFilter.all.name,
      );
      expect(selection.watchState, UnifiedWatchFilter.all);
    });

    test('a year that is not a number changes nothing rather than throwing', () {
      const before = UnifiedCatalogFilterSelection(years: {2024});
      final after = toggleMobileFilter(
        selection: before,
        category: MobileFilterCategory.year,
        optionId: 'nineteen-eighty',
      );
      expect(after, before);
    });

    test('servers and libraries are independent sets', () {
      var selection = toggleMobileFilter(
        selection: UnifiedCatalogFilterSelection.empty,
        category: MobileFilterCategory.servers,
        optionId: 'nas',
      );
      selection = toggleMobileFilter(
        selection: selection,
        category: MobileFilterCategory.libraries,
        optionId: 'nas:films',
      );
      expect(selection.serverIds, {'nas'});
      expect(selection.libraryKeys, {'nas:films'});
    });
  });

  group('the status line summary', () {
    test('is null when nothing narrows the items', () {
      expect(
        mobileActiveFilterSummary(selection: UnifiedCatalogFilterSelection.empty, capabilities: allCapable),
        isNull,
      );
    });

    test('reads values, not field names — mockup 03\'s "Sciencefiction · 2020–2025"', () {
      expect(
        mobileActiveFilterSummary(
          selection: const UnifiedCatalogFilterSelection(genres: {'Sciencefiction'}, years: {2020, 2025, 2023}),
          capabilities: allCapable,
        ),
        'Sciencefiction · 2020–2025',
      );
    });

    test('a single year is itself, not a range of one', () {
      expect(
        mobileActiveFilterSummary(
          selection: const UnifiedCatalogFilterSelection(years: {2024}),
          capabilities: allCapable,
        ),
        '2024',
      );
    });

    test('a source restriction alone summarises to nothing, it has its own control', () {
      expect(
        mobileActiveFilterSummary(
          selection: const UnifiedCatalogFilterSelection(serverIds: {'nas'}),
          capabilities: allCapable,
        ),
        isNull,
      );
    });

    test('a filter the backends cannot execute is left out of the summary', () {
      expect(
        mobileActiveFilterSummary(
          selection: const UnifiedCatalogFilterSelection(genres: {'Drama'}),
          capabilities: noneCapable,
        ),
        isNull,
      );
    });
  });
}
