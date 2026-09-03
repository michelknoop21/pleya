import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_filter_options.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_filter_categories.dart';
import 'package:pleya/widgets/mobile/mobile_filter_sheet.dart';

import '../../test_helpers/prefs.dart';

/// The two-column filter panel from mockup `04-filters-sheet.png`. iOS Unified
/// 2026 fase 3.
///
/// Mounted directly rather than through `OverlaySheetHost`: the host's own
/// behaviour (drag handle, barrier, back) is covered by
/// `overlay_sheet_test.dart`, and what is worth pinning here is the panel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  CatalogLibrary library(String serverId, String libraryId, {MediaBackend backend = MediaBackend.plex}) => (
    serverId: ServerId(serverId),
    serverName: serverId.toUpperCase(),
    libraryId: libraryId,
    libraryTitle: 'Library $libraryId',
    backend: backend,
  );

  const allCapable = UnifiedFilterCapabilities(supportsMetadataFilters: true, supportsWatchFilter: true);

  Future<UnifiedCatalogFilterSelection?> pumpSheet(
    WidgetTester tester, {
    UnifiedCatalogFilterSelection selection = UnifiedCatalogFilterSelection.empty,
    UnifiedFilterCapabilities capabilities = allCapable,
    UnifiedFilterOptions options = const UnifiedFilterOptions(genres: ['Drama', 'Sci-Fi'], years: [2024, 2023]),
    MobileFilterCategory initialCategory = MobileFilterCategory.status,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    UnifiedCatalogFilterSelection? applied;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: MobileFilterSheet(
            selection: selection,
            capabilities: capabilities,
            options: options,
            eligibleLibraries: [library('nas', 'films'), library('attic', 'films')],
            initialCategory: initialCategory,
            onApply: (value) => applied = value,
          ),
        ),
      ),
    );
    await tester.pump();
    return applied;
  }

  testWidgets('draws the five categories and opens on the first one', (tester) async {
    await pumpSheet(tester);

    for (final label in ['Status', 'Genre', 'Year', 'Servers', 'Libraries']) {
      expect(find.text(label), findsOneWidget, reason: '$label is one of mockup 04\'s five');
    }
    // Status is open, so its two values are the right-hand column.
    expect(find.text('Unwatched'), findsOneWidget);
    expect(find.text('Drama'), findsNothing);
  });

  testWidgets('opens on the category the caller asked for — the sources control', (tester) async {
    await pumpSheet(tester, initialCategory: MobileFilterCategory.servers);

    expect(find.text('NAS'), findsOneWidget);
    expect(find.text('ATTIC'), findsOneWidget);
  });

  testWidgets('tapping a category swaps the right-hand column', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.text('Genre'));
    await tester.pump();

    expect(find.text('Drama'), findsOneWidget);
    expect(find.text('Sci-Fi'), findsOneWidget);
    expect(find.text('Unwatched'), findsNothing);
  });

  testWidgets('the foot carries Clear and Apply, and nothing else', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Clear all'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    // Hoofdstuk 33.7 and mockup 04: no third way out sitting next to Apply.
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('edits stay local until Apply commits them', (tester) async {
    UnifiedCatalogFilterSelection? applied;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: MobileFilterSheet(
            selection: UnifiedCatalogFilterSelection.empty,
            capabilities: allCapable,
            options: const UnifiedFilterOptions(genres: ['Drama', 'Sci-Fi']),
            eligibleLibraries: [library('nas', 'films')],
            initialCategory: MobileFilterCategory.genre,
            onApply: (value) => applied = value,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Drama'));
    await tester.pump();
    // Nothing has left the sheet: the catalogue restarts its merge on a query
    // change, so committing per tap would reload the grid mid-decision.
    expect(applied, isNull);

    await tester.tap(find.text('Sci-Fi'));
    await tester.pump();
    expect(applied, isNull);

    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(applied?.genres, {'Drama', 'Sci-Fi'});
  });

  testWidgets('the header counts fields, and the category counts values', (tester) async {
    await pumpSheet(
      tester,
      selection: const UnifiedCatalogFilterSelection(genres: {'Drama', 'Sci-Fi'}, years: {2024}),
    );

    // Two fields narrowing: genre and year — mockup 04's "2 active".
    expect(find.text('2 active'), findsOneWidget);
    // Beside Genre, the number of values.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('Clear empties the draft without committing it', (tester) async {
    UnifiedCatalogFilterSelection? applied;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: MobileFilterSheet(
            selection: const UnifiedCatalogFilterSelection(genres: {'Drama'}),
            capabilities: allCapable,
            options: const UnifiedFilterOptions(genres: ['Drama']),
            eligibleLibraries: [library('nas', 'films')],
            onApply: (value) => applied = value,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1 active'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(find.text('1 active'), findsNothing);
    expect(applied, isNull);

    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(applied, UnifiedCatalogFilterSelection.empty);
  });

  testWidgets('Clear is muted, never the accent', (tester) async {
    await pumpSheet(tester);

    // `monoTheme` paints a bare TextButton in kAccent, and hoofdstuk 34
    // reserves red for progress, live and the active navigation mark. A red
    // "Clear all" would read as a warning about the user's own filters, which
    // mockup 04 draws in plain grey.
    final button = tester.widget<TextButton>(
      find.ancestor(of: find.text('Clear all'), matching: find.byType(TextButton)),
    );
    final resolved = button.style?.foregroundColor?.resolve({});
    expect(resolved, isNotNull);
    expect(resolved, isNot(kAccent));
  });

  testWidgets('the panel leaves the catalogue visible behind it', (tester) async {
    await pumpSheet(tester);

    // A panel over the grid, not a page replacing it. Without an explicit
    // height the two columns took every pixel the sheet offered, and a
    // catalogue whose only filter is a watch state drew a full-height panel
    // holding one line.
    final size = tester.getSize(find.byType(MobileFilterSheet));
    expect(size.height, lessThan(852 * 0.75));
  });

  testWidgets('an unsupported category is still listed and says why', (tester) async {
    await pumpSheet(
      tester,
      capabilities: const UnifiedFilterCapabilities(supportsMetadataFilters: false, supportsWatchFilter: true),
      initialCategory: MobileFilterCategory.genre,
    );

    expect(find.text('Genre'), findsOneWidget, reason: 'a dropped row would look like a missing feature');
    expect(find.text('Not available for the current sources'), findsOneWidget);
    expect(find.text('Drama'), findsNothing);
  });

  testWidgets('a supported category with no values says so instead of drawing an empty column', (tester) async {
    await pumpSheet(tester, options: UnifiedFilterOptions.empty, initialCategory: MobileFilterCategory.genre);

    expect(find.text('Nothing to choose from'), findsOneWidget);
  });
}
