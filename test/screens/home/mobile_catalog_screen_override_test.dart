/// HOME-R1: "Alle N in Films" from the menu of an own Home row opens the
/// catalog on the row's own filter, for this visit only: the stored per-profile
/// filter is neither replaced nor written over (the same as the tvOS "Alle N"
/// tile, ROW1c).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/home/mobile_catalog_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/unified_catalog/unified_artwork_prefetcher.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/focusable_filter_chip.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const own = UnifiedCatalogPreferences(
    filters: UnifiedCatalogFilterSelection(genres: {'Sciencefiction'}),
    sort: UnifiedCatalogSort.newestRelease,
  );

  late LibrariesProvider librariesProvider;

  Future<UnifiedCatalogs> open(
    WidgetTester tester, {
    UnifiedCatalogPreferences? override,
    MediaBackend backend = MediaBackend.plex,
    MobileCatalogKind kind = MobileCatalogKind.movies,
    List<MediaLibrary>? start,
  }) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
    UnifiedCatalogQueryStore.resetForTesting();
    LocaleSettings.setLocaleSync(AppLocale.en);

    final manager = MultiServerManager();
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    final libraries = LibrariesProvider()
      ..debugSetLibraries(
        start ??
            [
              MediaLibrary(
                id: 'A',
                backend: backend,
                title: 'A',
                kind: MediaKind.movie,
                serverId: 's1',
                serverName: 's1',
              ),
            ],
      );
    librariesProvider = libraries;
    final catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hiddenLibraries);
    addTearDown(catalogs.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);

    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          Provider<UnifiedCatalogs>.value(value: catalogs),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: MobileCatalogScreen(
              kind: kind,
              initialFilterOverride: override,
              debugPrefetcher: UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: (_, _) async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return catalogs;
  }

  int filterBadge(WidgetTester tester) => tester
      .widget<FocusableFilterChip>(find.widgetWithText(FocusableFilterChip, t.unifiedCatalog.filters.title))
      .badgeCount;

  testWidgets('the row\'s own filter is what the catalog opens on, and the stored one is left alone', (tester) async {
    await open(tester, override: own);
    expect(filterBadge(tester), 1, reason: 'the genre of the row is applied');
    final stored = await UnifiedCatalogQueryStore.read(MediaKind.movie);
    expect(stored, UnifiedCatalogPreferences.defaults, reason: 'a visit is not a saved filter');
  });

  testWidgets('a stored Newest release on Pleya Server asks for the year and says so', (tester) async {
    final catalogs = await open(
      tester,
      backend: MediaBackend.pleyaServer,
      override: const UnifiedCatalogPreferences(sort: UnifiedCatalogSort.newestRelease),
    );
    final query = catalogs.forKind(MediaKind.movie).query;
    expect(query.sortField, UnifiedCatalogSortField.year);
    expect(query.sortDirection, LibrarySortDirection.descending);
    expect(find.text(t.unifiedCatalog.sort.yearNewest), findsOneWidget);
  });

  group('the set of libraries changes while the page is open', () {
    MediaLibrary series(String id, MediaBackend backend) =>
        MediaLibrary(id: id, backend: backend, title: id, kind: MediaKind.show, serverId: 's1', serverName: 's1');
    final plex = series('p', MediaBackend.plex);
    final jellyfin = series('j', MediaBackend.jellyfin);
    const stored = UnifiedCatalogPreferences(sort: UnifiedCatalogSort.recentlyWatched);

    testWidgets('a Jellyfin library joining takes Bekeken away from the merge too', (tester) async {
      final catalogs = await open(tester, kind: MobileCatalogKind.series, override: stored, start: [plex]);
      final catalog = catalogs.forKind(MediaKind.show);
      expect(catalog.query.sortField, UnifiedCatalogSortField.recentlyWatched);

      librariesProvider.debugSetLibraries([plex, jellyfin]);
      await tester.pump();
      await tester.pump();

      expect(find.text(t.unifiedCatalog.sort.titleAsc), findsOneWidget);
      expect(catalog.query.sortField, UnifiedCatalogSortField.title);
    });

    testWidgets('the library leaving brings it back, for the page and the merge alike', (tester) async {
      final catalogs = await open(tester, kind: MobileCatalogKind.series, override: stored, start: [plex, jellyfin]);
      final catalog = catalogs.forKind(MediaKind.show);
      expect(catalog.query.sortField, UnifiedCatalogSortField.title);

      librariesProvider.debugSetLibraries([plex]);
      await tester.pump();
      await tester.pump();

      expect(find.text(t.unifiedCatalog.sort.recentlyWatched), findsOneWidget);
      expect(catalog.query.sortField, UnifiedCatalogSortField.recentlyWatched);
    });
  });

  testWidgets('two screens on one catalog with different overrides do not write each other back', (tester) async {
    final catalogs = await open(tester, override: const UnifiedCatalogPreferences(sort: UnifiedCatalogSort.titleAsc));
    var notifications = 0;
    catalogs.forKind(MediaKind.movie).addListener(() => notifications++);

    final multiServer = tester.element(find.byType(MobileCatalogScreen)).read<MultiServerProvider>();
    Widget screen(UnifiedCatalogSort sort) => MobileCatalogScreen(
      kind: MobileCatalogKind.movies,
      initialFilterOverride: UnifiedCatalogPreferences(sort: sort),
      debugPrefetcher: UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: (_, _) async {}),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          Provider<UnifiedCatalogs>.value(value: catalogs),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: IndexedStack(
              index: 1,
              children: [screen(UnifiedCatalogSort.titleAsc), screen(UnifiedCatalogSort.titleDesc)],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(notifications, 2);

    // A library joining: each screen answers once, and then it is quiet.
    notifications = 0;
    librariesProvider.debugSetLibraries([
      ...librariesProvider.libraries,
      MediaLibrary(
        id: 'B',
        backend: MediaBackend.plex,
        title: 'B',
        kind: MediaKind.movie,
        serverId: 's1',
        serverName: 's1',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(notifications, 4);
  });

  testWidgets('NEGATIVE CONTROL: without an override the catalog opens on the stored filter', (tester) async {
    await open(tester);
    expect(filterBadge(tester), 0);
  });
}
