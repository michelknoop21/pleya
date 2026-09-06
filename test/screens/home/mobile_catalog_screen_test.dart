/// Covers `MobileCatalogScreen` against the frozen `03-alle-films.png` and
/// `04-filters-sheet.png` (iOS Unified 2026 fase 3,
/// `docs/ios-unified-2026-fase3-plan.md`). Mounted over the real
/// `UnifiedCatalogProvider`/`UnifiedCatalogs` stack, the same way
/// `unified_catalog_provider_test.dart` exercises the provider and
/// `mobile_landing_screen_test.dart` exercises a sibling mobile screen: a
/// fake `MediaServerClient` stands in for the network, everything else is
/// the real merge/query/filter pipeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
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
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_sort_sheet.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.id, {this.itemsByLibrary = const {}});

  final String id;
  final Map<String, List<MediaItem>> itemsByLibrary;
  bool shouldThrow = false;
  int fetchCalls = 0;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => id;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  void close() {}

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    fetchCalls++;
    if (shouldThrow) throw StateError('offline');
    final all = itemsByLibrary[libraryId] ?? const <MediaItem>[];
    final end = (query.offset + query.limit).clamp(0, all.length);
    final slice = query.offset >= all.length ? const <MediaItem>[] : all.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: all.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {required String title, required String serverId}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: serverId, year: 2024);

MediaLibrary _library(String id, {required String serverId}) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: id,
  kind: MediaKind.movie,
  serverId: serverId,
  serverName: serverId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLibraryClient client;
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late UnifiedCatalogs catalogs;

  // A second, empty-backed fixture, built once per test alongside the
  // populated one above rather than by disposing and rebuilding the first
  // mid-test. The empty-state tests select this one instead; nothing here
  // is ever torn down and reconstructed inside a single `testWidgets` body.
  late MultiServerManager emptyManager;
  late MultiServerProvider emptyMultiServer;
  late UnifiedCatalogs emptyCatalogs;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    // `UnifiedCatalogQueryStore.write` also reads `StorageService` (for the
    // profile scope in its key); primed here for the same reason as
    // `SettingsService` above, so its first-ever async platform round trip
    // runs inside this controlled `setUp` rather than mid-test.
    await StorageService.getInstance();
    // `UnifiedCatalogQueryStore.write`'s static write-lock future: see this
    // method's own doc comment for why leaving it alone here can hang every
    // later test in this file, not just flake one.
    UnifiedCatalogQueryStore.resetForTesting();

    client = _FakeLibraryClient(
      's1',
      itemsByLibrary: {
        'A': [
          _movie('a1', title: 'Alien', serverId: 's1'),
          _movie('a2', title: 'Dune', serverId: 's1'),
          _movie('a3', title: 'Civil War', serverId: 's1'),
        ],
      },
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    libraries = LibrariesProvider()..debugSetLibraries([_library('A', serverId: 's1')]);
    catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hiddenLibraries);

    emptyManager = MultiServerManager()..debugRegisterClientForTesting(_FakeLibraryClient('s1'));
    emptyMultiServer = MultiServerProvider(emptyManager, DataAggregationService(emptyManager));
    emptyCatalogs = UnifiedCatalogs(
      multiServer: emptyMultiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
    );
  });

  tearDown(() {
    catalogs.dispose();
    emptyCatalogs.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
    emptyMultiServer.dispose();
  });

  Future<void> pumpCatalog(
    WidgetTester tester, {
    MobileCatalogKind kind = MobileCatalogKind.movies,
    bool useEmpty = false,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: useEmpty ? emptyMultiServer : multiServer),
          Provider<UnifiedCatalogs>.value(value: useEmpty ? emptyCatalogs : catalogs),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: MobileCatalogScreen(
              kind: kind,
              // A real prefetcher would dispatch a real `precacheImage`
              // network fetch the moment the grid renders, which nothing
              // here mocks; it hangs the test instead of failing it.
              debugPrefetcher: UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: (_, _) async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Mounts the screen the way `_TitleRow` does: pushed with
  /// `Navigator.of(context).push` onto a navigator that sits *above* the
  /// screen holding the `OverlaySheetHost`. `MaterialApp.home` stands in for
  /// `MainScreen` here — same shape, one screen under a host, pushing onto the
  /// navigator over it.
  Future<void> pumpPushedCatalog(WidgetTester tester, {MobileCatalogKind kind = MobileCatalogKind.movies}) async {
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
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MobileCatalogScreen(
                          kind: kind,
                          debugPrefetcher: UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: (_, _) async {}),
                        ),
                      ),
                    ),
                    child: const Text('All movies'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('All movies'));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    // `pumpAndSettle` first: it drives the sheet-close animation and the
    // *awaited* half of `_updatePreferences` (`_applyQuery`, which restarts
    // the merge) to completion. The `runAsync` delay after it is the other
    // half: `_updatePreferences` also writes the query store
    // fire-and-forget, and that write needs real wall-clock time through a
    // real (mocked) platform channel round trip, which frame-pumping alone
    // does not provide.
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  /// Taps [finder], scrolling the chip row into view first: three chips at
  /// full label width do not all fit inside a 393pt viewport, so the row
  /// scrolls horizontally the same way the mockup's own chip row would on a
  /// real phone.
  Future<void> tapChip(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  // The screen is not mounted the way the app mounts it. `MobileLandingScreen`
  // is a tab inside `MainScreen`, and `MainScreen.build` is what installs the
  // `OverlaySheetHost`; `_TitleRow` then pushes this screen with
  // `Navigator.of(context).push`, which resolves to the profile navigator
  // *above* `MainScreen`. The pushed route is therefore a sibling of the
  // screen that owns the host, not a descendant of it, and
  // `OverlaySheetController.of` finds nothing. In debug that trips an assert;
  // in a release build the assert is gone and `scope!` throws, the framework
  // swallows it, and every chip is simply dead. Michel on iOS, build 266:
  // "Filters werken helemaal niet bij alle films, kan er niet op drukken."
  //
  // `pumpCatalog` wraps the screen in a host directly, so it cannot see this;
  // this test pushes the screen the way the app does.
  testWidgets('every chip still opens its sheet when the screen is pushed as a route (CAT9)', (tester) async {
    await pumpPushedCatalog(tester);
    await settle(tester);

    await tapChip(tester, find.text(t.unifiedCatalog.filters.title));
    await tester.pumpAndSettle();
    expect(find.text(t.unifiedCatalog.filters.genre), findsOneWidget, reason: 'the Filters chip must open its sheet');
    await tester.tap(find.text(t.unifiedCatalog.filters.apply));
    await settle(tester);

    await tapChip(tester, find.text(mobileCatalogSortLabel(UnifiedCatalogSort.titleAsc)));
    await tester.pumpAndSettle();
    expect(
      find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)),
      findsOneWidget,
      reason: 'and so must the Sort chip',
    );
  });

  testWidgets('shows a skeleton before the stored preferences and the first page have loaded', (tester) async {
    await pumpCatalog(tester);
    // One frame in: `_restorePreferences` has not resolved its first await yet.
    expect(find.byType(GridView), findsNothing);
    expect(find.text(t.unifiedCatalog.states.emptyTitle), findsNothing);
    await settle(tester);
  });

  testWidgets('shows the populated grid, the count line and the chip labels once loaded', (tester) async {
    await pumpCatalog(tester);
    await settle(tester);

    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Civil War'), findsOneWidget);
    expect(find.text(t.unifiedCatalog.titlesLoaded(count: 3)), findsOneWidget);
    expect(find.text(t.unifiedCatalog.allSources), findsOneWidget);
    expect(find.text(t.unifiedCatalog.filters.title), findsOneWidget);
    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.titleAsc)), findsOneWidget);
  });

  testWidgets('shows the error state with a retry action when every library fails', (tester) async {
    client.shouldThrow = true;
    await pumpCatalog(tester);
    await settle(tester);

    expect(find.text(t.unifiedCatalog.states.errorTitle), findsOneWidget);
    expect(find.text(t.common.retry), findsOneWidget);
  });

  testWidgets('the sort chip opens the sort sheet and applying a choice re-labels the chip', (tester) async {
    await pumpCatalog(tester);
    await settle(tester);

    await tapChip(tester, find.text(mobileCatalogSortLabel(UnifiedCatalogSort.titleAsc)));
    await tester.pumpAndSettle();
    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)), findsOneWidget);

    await tester.tap(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)));
    // `settle`, not `pumpAndSettle`: the choice writes the query store
    // fire-and-forget, and that write needs real wall-clock time via
    // `runAsync` to actually land before this test ends; `pumpAndSettle`
    // alone does not guarantee that.
    await settle(tester);

    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)), findsOneWidget);
    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.titleAsc)), findsNothing);
  });

  testWidgets('the filters chip opens the filter sheet and Toepassen updates the badge count', (tester) async {
    await pumpCatalog(tester);
    await settle(tester);
    final callsBeforeFilter = client.fetchCalls;

    // The Filters chip opens the sheet on Status, unlike the sources chip
    // (which opens on Servers). Status is the one category whose options
    // do not depend on what the fake client happens to have loaded.
    await tapChip(tester, find.text(t.unifiedCatalog.filters.title));
    await tester.pumpAndSettle();
    expect(find.text(t.unifiedCatalog.filters.genre), findsOneWidget);

    await tester.tap(find.text(t.unifiedCatalog.filters.unwatched));
    await tester.tap(find.text(t.unifiedCatalog.filters.apply));
    // `settle`, not `pumpAndSettle`: see the sort-chip test above.
    await settle(tester);

    expect(client.fetchCalls, greaterThan(callsBeforeFilter));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a previously stored selection is restored on the next open', (tester) async {
    // `runAsync`, niet een kale await: de statische prefs-cache is in `setUp`
    // aangemaakt, dus in de echte zone. Een `testWidgets`-body draait in de
    // FakeAsync-zone, en een future die in een andere zone voltooide levert
    // daar zijn continuation nooit af. Zie de noot boven de laatste twee tests.
    await tester.runAsync(
      () => UnifiedCatalogQueryStore.write(
        MediaKind.movie,
        UnifiedCatalogPreferences.defaults.copyWith(sort: UnifiedCatalogSort.recentlyAdded),
      ),
    );

    await pumpCatalog(tester);
    await settle(tester);

    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)), findsOneWidget);
  });

  testWidgets('a stored library restriction naming a library that no longer exists is dropped on open', (tester) async {
    await tester.runAsync(
      () => UnifiedCatalogQueryStore.write(
        MediaKind.movie,
        UnifiedCatalogPreferences.defaults.copyWith(
          filters: const UnifiedCatalogFilterSelection(libraryKeys: {'s1:ghost-library'}),
        ),
      ),
    );

    await pumpCatalog(tester);
    await settle(tester);

    final restored = (await tester.runAsync(() => UnifiedCatalogQueryStore.read(MediaKind.movie)))!;
    expect(restored.filters.libraryKeys, isEmpty, reason: 'a vanished library has no row left to untick it with');
    // The prune is also written back, so the badge does not keep counting a
    // restriction the panel can no longer show.
    expect(find.text(t.unifiedCatalog.filters.title), findsOneWidget);
  });

  // Deze twee stonden hier als laatste omdat de vastloop hierna toesloeg, en
  // dat is opgelost, niet omzeild. De oorzaak was geen omgeving en geen
  // flakiness: `setUp` maakt de statische prefs-cache aan
  // (`SettingsService.getInstance`, `StorageService.getInstance`) en dus in de
  // echte zone, terwijl een `testWidgets`-body in de FakeAsync-zone draait. Een
  // future die in de ene zone voltooide levert zijn continuation in de andere
  // nooit af, dus elke kale `await UnifiedCatalogQueryStore.write/read` in een
  // body hing stil en permanent, tot de timeout van tien minuten. Op CI net zo
  // goed als lokaal. De drie tests die zo'n directe aanroep doen gebruiken nu
  // `tester.runAsync`, dat in de echte zone draait; daarmee loopt dit bestand
  // in seconden in plaats van drie keer tien minuten. De volgorde hieronder is
  // sindsdien willekeurig en mag veranderen.
  testWidgets('shows the generic empty state when the catalog has nothing and no filter is active', (tester) async {
    await pumpCatalog(tester, useEmpty: true);
    await settle(tester);

    expect(find.text(t.unifiedCatalog.states.emptyTitle), findsOneWidget);
  });

  testWidgets('shows the filtered-empty state when a stored selection matches nothing', (tester) async {
    await tester.runAsync(
      () => UnifiedCatalogQueryStore.write(
        MediaKind.movie,
        UnifiedCatalogPreferences.defaults.copyWith(filters: const UnifiedCatalogFilterSelection(genres: {'Horror'})),
      ),
    );

    await pumpCatalog(tester, useEmpty: true);
    await settle(tester);

    expect(find.text(t.unifiedCatalog.states.filterEmptyTitle), findsOneWidget);
    expect(find.text(t.unifiedCatalog.states.clearFilters), findsOneWidget);
  });
}
