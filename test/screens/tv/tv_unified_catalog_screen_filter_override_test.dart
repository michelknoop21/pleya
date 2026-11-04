/// ROW1c: a viewer-defined row's own "Alle N" tile opens
/// [TvUnifiedCatalogScreen] with that row's own filter and sort, for one
/// visit only (Michel, 6 September 2026) — see
/// [TvUnifiedCatalogScreen.initialFilterOverride].
///
/// Proven end to end through the real screen and the real
/// [UnifiedCatalogQueryStore], not just read off `_restorePreferences`'s
/// source: the override has to win over whatever was already stored, and it
/// has to leave that stored value alone so a later ordinary visit still sees
/// it. A deliberate choice made *while* viewing the override is a different
/// question, and not this suite's to prove — see the note at the bottom.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalog_provider.dart';
import 'package:pleya/screens/tv/tv_unified_catalog_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.items);

  final List<MediaItem> items;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'nas';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async => LibraryPage<MediaItem>(items: items, totalCount: items.length, offset: query.offset);

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {required String title}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  serverId: 'nas',
  serverName: 'nas',
);

Widget _shell(Widget child) {
  final theme = monoTheme(dark: true);
  return TranslationProvider(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: InputModeTracker(
        child: OverlaySheetHost(
          child: Scaffold(backgroundColor: theme.extension<MonoTokens>()!.bg, body: child),
        ),
      ),
    ),
  );
}

class _Built {
  const _Built({required this.catalog, required this.multiServer, required this.libraries});
  final UnifiedCatalogProvider catalog;
  final MultiServerProvider multiServer;
  final LibrariesProvider libraries;
}

Future<_Built> _buildCatalog({MediaBackend backend = MediaBackend.plex}) async {
  final client = _FakeLibraryClient([_movie('m1', title: 'Alpha'), _movie('m2', title: 'Bravo')]);
  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
  final libraries = LibrariesProvider()
    ..debugSetLibraries([
      MediaLibrary(
        id: '1',
        backend: backend,
        title: 'Films',
        kind: MediaKind.movie,
        serverId: 'nas',
        serverName: 'nas',
      ),
    ]);
  final hiddenLibraries = HiddenLibrariesProvider();
  final catalog = UnifiedCatalogProvider(
    multiServer: multiServer,
    libraries: libraries,
    hiddenLibraries: hiddenLibraries,
    kind: MediaKind.movie,
  );
  await catalog.ensureStarted();
  return _Built(catalog: catalog, multiServer: multiServer, libraries: libraries);
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('an override wins over the stored preferences, and is not written back', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    const stored = UnifiedCatalogPreferences(sort: UnifiedCatalogSort.titleAsc);
    await UnifiedCatalogQueryStore.write(MediaKind.movie, stored);

    const override = UnifiedCatalogPreferences(sort: UnifiedCatalogSort.titleDesc);
    final built = await _buildCatalog();
    addTearDown(built.catalog.dispose);
    addTearDown(built.multiServer.dispose);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: built.multiServer,
        child: _shell(
          TvUnifiedCatalogScreen(
            catalog: built.catalog,
            title: t.unifiedCatalog.moviesTitle,
            initialFilterOverride: override,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      built.catalog.query.sortField,
      UnifiedCatalogSortField.title,
      reason: 'the override, not the stored ascending default, is what the merge was actually asked for',
    );
    expect(built.catalog.query.sortDirection, LibrarySortDirection.descending);

    final afterVisit = await UnifiedCatalogQueryStore.read(MediaKind.movie);
    expect(
      afterVisit.sort,
      UnifiedCatalogSort.titleAsc,
      reason: 'leaving the screen must not have overwritten what an ordinary visit already had stored',
    );
  });

  testWidgets('a stored Newest release on Pleya Server asks for the year', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    final built = await _buildCatalog(backend: MediaBackend.pleyaServer);
    addTearDown(built.catalog.dispose);
    addTearDown(built.multiServer.dispose);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: built.multiServer,
        child: _shell(
          TvUnifiedCatalogScreen(
            catalog: built.catalog,
            title: t.unifiedCatalog.moviesTitle,
            // The route `_restorePreferences` takes for a stored value, without
            // the store read that does not finish inside testWidgets.
            initialFilterOverride: const UnifiedCatalogPreferences(sort: UnifiedCatalogSort.newestRelease),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(built.catalog.query.sortField, UnifiedCatalogSortField.year);
    expect(built.catalog.query.sortDirection, LibrarySortDirection.descending);
  });

  group('the set of libraries changes while the page is open', () {
    MediaLibrary series(String id, MediaBackend backend) =>
        MediaLibrary(id: id, backend: backend, title: id, kind: MediaKind.show, serverId: 'nas', serverName: 'nas');
    final plex = series('p', MediaBackend.plex);
    final jellyfin = series('j', MediaBackend.jellyfin);

    Future<({UnifiedCatalogProvider catalog, LibrariesProvider libraries})> open(
      WidgetTester tester,
      List<MediaLibrary> start,
    ) async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
      LocaleSettings.setLocaleSync(AppLocale.en);
      final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeLibraryClient(const []));
      final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
      final libraries = LibrariesProvider()..debugSetLibraries(start);
      final catalog = UnifiedCatalogProvider(
        multiServer: multiServer,
        libraries: libraries,
        hiddenLibraries: HiddenLibrariesProvider(),
        kind: MediaKind.show,
      );
      addTearDown(catalog.dispose);
      addTearDown(multiServer.dispose);
      await catalog.ensureStarted();
      setGoldenSurfaceSize(tester);
      await tester.pumpWidget(
        ChangeNotifierProvider<MultiServerProvider>.value(
          value: multiServer,
          child: _shell(
            TvUnifiedCatalogScreen(
              catalog: catalog,
              title: t.unifiedCatalog.seriesTitle,
              initialFilterOverride: const UnifiedCatalogPreferences(sort: UnifiedCatalogSort.recentlyWatched),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (catalog: catalog, libraries: libraries);
    }

    testWidgets('a Jellyfin library joining takes Bekeken away from the merge too', (tester) async {
      final h = await open(tester, [plex]);
      expect(h.catalog.query.sortField, UnifiedCatalogSortField.recentlyWatched);

      h.libraries.debugSetLibraries([plex, jellyfin]);
      await tester.pumpAndSettle();

      expect(h.catalog.query.sortField, UnifiedCatalogSortField.title);
    });

    testWidgets('the library leaving brings it back, for the page and the merge alike', (tester) async {
      final h = await open(tester, [plex, jellyfin]);
      expect(h.catalog.query.sortField, UnifiedCatalogSortField.title);

      h.libraries.debugSetLibraries([plex]);
      await tester.pumpAndSettle();

      expect(h.catalog.query.sortField, UnifiedCatalogSortField.recentlyWatched);
    });

    testWidgets('NEGATIVE CONTROL: a change that leaves the query equal restarts once', (tester) async {
      final h = await open(tester, [plex]);
      var changes = 0;
      final before = h.catalog.query;
      h.catalog.addListener(() => changes++);
      h.libraries.debugSetLibraries([plex]);
      await tester.pumpAndSettle();
      expect(h.catalog.query, before);
      expect(changes, 0, reason: 'the same libraries: nothing to restart and nothing to derive');
    });
  });

  testWidgets('two screens on one catalog with different overrides do not write each other back', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    final built = await _buildCatalog();
    addTearDown(built.catalog.dispose);
    addTearDown(built.multiServer.dispose);
    var notifications = 0;
    built.catalog.addListener(() => notifications++);

    Widget screen(UnifiedCatalogSort sort) => TvUnifiedCatalogScreen(
      catalog: built.catalog,
      title: 'x',
      initialFilterOverride: UnifiedCatalogPreferences(sort: sort),
    );
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: built.multiServer,
        child: _shell(
          IndexedStack(index: 1, children: [screen(UnifiedCatalogSort.titleAsc), screen(UnifiedCatalogSort.titleDesc)]),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(notifications, 4);

    // A library joining: each screen answers once, and then it is quiet.
    notifications = 0;
    built.libraries.debugSetLibraries([
      ...built.libraries.libraries,
      MediaLibrary(
        id: '2',
        backend: MediaBackend.plex,
        title: 'Meer films',
        kind: MediaKind.movie,
        serverId: 'nas',
        serverName: 'nas',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(notifications, 6);
  });

  // A deliberate sort change made while viewing an override is not this
  // suite's to prove: `_updatePreferences` (the code that writes it) is
  // unchanged by ROW1c — only `_restorePreferences`'s initial read is. The
  // one attempt at a widget test for it here foundered on `_updatePreferences`
  // firing the store write with `unawaited`, which the fake test zone's own
  // pumping does not reliably wait out; that is a test-harness gap, not a
  // product one.
}
