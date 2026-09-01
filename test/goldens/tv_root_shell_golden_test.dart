/// Fase 7 (hoofdstuk 6.2 and 33's shared shell): production visual acceptance
/// for the TV root — the horizontal top navigation, and the two surfaces fase 7
/// itself owns underneath it.
///
/// Every picture here is produced by the production widgets: [TvRootShell] with
/// [TvTopNavigation] inside it, and under it either the real [TvMyPleyaScreen]
/// or the real [TvMoviesScreen]/[TvSeriesScreen] fed by a fake library client.
/// No stand-in page is composed for the camera — hoofdstuk 27's fase-0 rule
/// that a screen is only golden-ed by the fase that builds it cuts both ways,
/// and a golden that photographs a reconstruction only proves the
/// reconstruction. (`tv_unified_catalog_golden_test.dart` still composes its own
/// `_page()`; that is pre-existing fase-5 debt and is deliberately not turned
/// into a fase-7 refactor project.)
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_root_shell_golden_test.dart`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/screens/discover_screen.dart';
import 'package:pleya/screens/search_screen.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/tv/tv_movies_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';
import 'package:pleya/screens/tv/tv_series_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/side_navigation_rail.dart';
import 'package:pleya/watch_together/watch_together.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';

/// One library that answers immediately, so the catalog pictures have real
/// cards rather than a skeleton.
class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.id, {required this.items});

  final String id;
  final List<MediaItem> items;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final end = (query.offset + query.limit).clamp(0, items.length);
    final slice = query.offset >= items.length ? const <MediaItem>[] : items.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: items.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _movieTitles = [
  'Oppenheimer',
  'Barbie',
  'The Grand Budapest Hotel',
  'Interstellar',
  'Across the Spider-Verse',
  'La La Land',
  'Klaus',
  'The Menu',
  'Past Lives',
  'Wonka',
  'Dune: Part Two',
  'Everything Everywhere All at Once',
];

const _seriesTitles = [
  'Severance',
  'The Bear',
  'Shogun',
  'Slow Horses',
  'Arcane',
  'Silo',
  'Fallout',
  'Ted Lasso',
  'Andor',
  'The Last of Us',
  'Succession',
  'Blue Eye Samurai',
];

MediaItem _item(String id, {required String title, required MediaKind kind, required int year}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: kind,
  title: title,
  serverId: 'nas',
  year: year,
  genres: const ['Drama'],
);

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });

  late TvNavigationCoordinator coordinator;
  late FocusMemoryTracker nodes;
  late FocusScopeNode navScope;
  late FocusScopeNode contentScope;

  Future<void> boot({required bool hasLiveTv, TvDestinationId active = TvDestinationId.home}) async {
    coordinator = TvNavigationCoordinator(initial: active)
      ..updateConditions(TvNavConditions(hasLiveTv: hasLiveTv))
      ..activate(active);
    nodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    navScope = FocusScopeNode(debugLabel: 'nav');
    contentScope = FocusScopeNode(debugLabel: 'content');
    addTearDown(coordinator.dispose);
    addTearDown(nodes.dispose);
    addTearDown(navScope.dispose);
    addTearDown(contentScope.dispose);
  }

  /// The wordmark is an `Image.asset`, and asset decoding is asynchronous:
  /// without this it lands in the slower pictures and misses the faster ones,
  /// which would make the whole set flaky for a reason that has nothing to do
  /// with the design.
  Future<void> precacheWordmark(WidgetTester tester) async {
    final element = tester.element(find.byType(TvTopNavigation));
    await tester.runAsync(() => precacheImage(const AssetImage('assets/branding/pleya_wordmark.png'), element));
    await tester.pumpAndSettle();
  }

  /// The production shell, around whatever the surface under test is.
  Widget shell(Widget content, {Widget Function(Widget child)? withProviders, Locale? locale}) {
    final app = MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: monoTheme(dark: true),
      // A `Scaffold`, because `TvRootShell` does not carry a `Material` of its
      // own — in the app it inherits one from the route above `MainScreen`,
      // exactly as the desktop rail branch does. Without it here every `Text`
      // falls back to Flutter's red-on-yellow monospace error style and the
      // picture says nothing about the design.
      home: Scaffold(
        backgroundColor: monoTheme(dark: true).extension<MonoTokens>()!.bg,
        body: InputModeTracker(
          child: TvRootShell(
            coordinator: coordinator,
            navNodes: nodes,
            navFocusScope: navScope,
            contentFocusScope: contentScope,
            isNavFocused: false,
            profile: null,
            onSelectDestination: (_) {},
            onFocusContent: ({bool restorePreviousFocus = true}) {},
            onFocusNav: () {},
            onOpenProfiles: () {},
            onOverlaySheetOpenChanged: (_) {},
            onKeyEvent: (_) => KeyEventResult.ignored,
            selectLibrary: null,
            openSettings: null,
            child: content,
          ),
        ),
      ),
    );
    return TranslationProvider(child: withProviders == null ? app : withProviders(app));
  }

  // ---------------------------------------------------------------------------
  // The bar (hoofdstuk 33's shared shell)
  // ---------------------------------------------------------------------------

  group('the top navigation', () {
    late MultiServerManager manager;
    late MultiServerProvider servers;

    setUp(() {
      manager = MultiServerManager();
      servers = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(servers.dispose);
    });

    Widget barProviders(Widget child) =>
        ChangeNotifierProvider<MultiServerProvider>.value(value: servers, child: child);

    Widget hub() => TvMyPleyaScreen(onOpenSection: (_) {}, onSwitchProfile: () {}, onSignOut: () {}, onExitUp: () {});

    Future<void> shoot(WidgetTester tester, String name, {Locale? locale}) async {
      setGoldenSurfaceSize(tester);
      await tester.pumpWidget(shell(hub(), withProviders: barProviders, locale: locale));
      await precacheWordmark(tester);
      await tester.pumpAndSettle();
      await expectMatchesGolden(find.byType(TvRootShell), name);
    }

    testWidgets('Mijn Pleya active, with the whole hub underneath it', (tester) async {
      await boot(hasLiveTv: false, active: TvDestinationId.myPleya);
      await shoot(tester, 'tv_shell_my_pleya');
    });

    testWidgets('a focused menu tile lights without moving anything', (tester) async {
      await boot(hasLiveTv: false, active: TvDestinationId.myPleya);
      setGoldenSurfaceSize(tester);
      await tester.pumpWidget(shell(hub(), withProviders: barProviders));
      await precacheWordmark(tester);
      await tester.pumpAndSettle();

      tester.state<TvMyPleyaScreenState>(find.byType(TvMyPleyaScreen)).focusKey(TvMyPleyaSection.settings.tileFocusKey);
      await tester.pumpAndSettle();

      // Hoofdstuk 33.8: the ring and a lighter fill, and the tile does not
      // scale — so nothing in the grid may shift between this and the picture
      // above it.
      await expectMatchesGolden(find.byType(TvRootShell), 'tv_shell_my_pleya_focused');
    });

    testWidgets('Home active', (tester) async {
      await boot(hasLiveTv: false);
      await shoot(tester, 'tv_shell_home_active');
    });

    testWidgets('Films active, with Live TV in the bar', (tester) async {
      await boot(hasLiveTv: true, active: TvDestinationId.movies);
      await shoot(tester, 'tv_shell_live_tv_present');
    });

    testWidgets('the ring can stand somewhere the capsule is not', (tester) async {
      await boot(hasLiveTv: false, active: TvDestinationId.movies);
      setGoldenSurfaceSize(tester);
      await tester.pumpWidget(shell(hub(), withProviders: barProviders));
      await precacheWordmark(tester);
      await tester.pumpAndSettle();

      nodes.get(TvDestinationId.search.focusKey).requestFocus();
      await tester.pumpAndSettle();

      // [DEC-053]: active and focused are two states and they are drawn as two.
      // Films keeps the white capsule while Search wears the ring.
      await expectMatchesGolden(find.byType(TvRootShell), 'tv_shell_focus_not_active');
    });

    testWidgets('a long locale keeps the bar one row high', (tester) async {
      await boot(hasLiveTv: true);
      await shoot(tester, 'tv_shell_long_locale', locale: const Locale('de'));
    });
  });

  // ---------------------------------------------------------------------------
  // The complete catalog under the bar (hoofdstuk 33.5 and 33.6)
  // ---------------------------------------------------------------------------

  group('the complete catalog', () {
    Future<void> shootCatalog(WidgetTester tester, {required MediaKind kind, required String name}) async {
      final titles = kind == MediaKind.movie ? _movieTitles : _seriesTitles;
      final client = _FakeLibraryClient(
        'nas',
        items: [
          for (var i = 0; i < titles.length; i++) _item('i$i', title: titles[i], kind: kind, year: 2014 + i % 10),
        ],
      );
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
      final libraries = LibrariesProvider()
        ..debugSetLibraries([
          MediaLibrary(
            id: '1',
            backend: MediaBackend.plex,
            title: kind == MediaKind.movie ? 'Films' : 'Series',
            kind: kind,
            serverId: 'nas',
            serverName: 'NAS',
          ),
        ]);
      final hidden = HiddenLibrariesProvider();
      final catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hidden);
      addTearDown(() {
        catalogs.dispose();
        hidden.dispose();
        libraries.dispose();
        multiServer.dispose();
      });

      setGoldenSurfaceSize(tester);
      await tester.pumpWidget(
        shell(
          kind == MediaKind.movie ? const TvMoviesScreen() : const TvSeriesScreen(),
          withProviders: (child) => MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
              Provider<UnifiedCatalogs>.value(value: catalogs),
            ],
            child: child,
          ),
        ),
      );
      await precacheWordmark(tester);
      await tester.pumpAndSettle();
      await expectMatchesGolden(find.byType(TvRootShell), name);
    }

    testWidgets('All movies keeps the bar above it, with Films still lit', (tester) async {
      // Hoofdstuk 33.5 draws this page with the shared shell on top of it — a
      // full-screen push over the shell would have lost that, which is why fase
      // 7 makes it a nested route instead.
      await boot(hasLiveTv: false, active: TvDestinationId.movies);
      await shootCatalog(tester, kind: MediaKind.movie, name: 'tv_shell_all_movies');
    });

    testWidgets('All series keeps the bar above it, with Series still lit', (tester) async {
      await boot(hasLiveTv: false, active: TvDestinationId.series);
      await shootCatalog(tester, kind: MediaKind.show, name: 'tv_shell_all_series');
    });
  });

  // ---------------------------------------------------------------------------
  // Home and Search under the bar (hoofdstuk 33's shared shell, fase-7 half)
  // ---------------------------------------------------------------------------
  //
  // These two destinations had no picture of their own when fase 7 was
  // committed, which left the "shared shell is binding on all eight
  // references" claim resting on the four surfaces that did. What is judged
  // here is fase 7's own contract and nothing else: one horizontal bar and no
  // rail, the active destination lit, the content starting under the bar
  // rather than through it, and the page's own top inset not stacking on top
  // of the band. The fase-8 Home composition — the rounded hero billboard, the
  // content feed, the ambient background — is deliberately *not* the subject:
  // what stands under the bar in these pictures is the pre-fase-8 Home, which
  // is exactly what hoofdstuk 27 says fase 7 puts the definitive bar above.

  group('a destination fase 7 did not build itself', () {
    late MultiServerManager manager;
    late MultiServerProvider multiServer;
    late LibrariesProvider libraries;
    late HiddenLibrariesProvider hidden;

    setUp(() {
      manager = MultiServerManager()..debugRegisterClientForTesting(_FakeHomeClient());
      multiServer = MultiServerProvider(manager, DataAggregationService(manager));
      libraries = LibrariesProvider();
      hidden = HiddenLibrariesProvider();
      addTearDown(() {
        hidden.dispose();
        libraries.dispose();
        multiServer.dispose();
      });
    });

    /// The fase-7 concerns, checked numerically so the picture is not the only
    /// evidence: one horizontal authority and no rail, the bar spanning the
    /// frame, and the content strictly below the bar rather than under it.
    void expectShellFrames(WidgetTester tester, Finder content) {
      expect(find.byType(SideNavigationRail), findsNothing);
      final shellRect = tester.getRect(find.byType(TvRootShell));
      final bar = tester.getRect(find.byType(TvTopNavigation));
      expect(bar.top, shellRect.top);
      expect(bar.width, shellRect.width);
      final contentRect = tester.getRect(content);
      expect(contentRect.top, greaterThanOrEqualTo(bar.bottom), reason: 'content must not run under the bar');
      expect(contentRect.left, shellRect.left, reason: 'a top bar takes height, not width');
      expect(contentRect.width, shellRect.width);
      // And the band is chrome, not a page inset stacked on a page inset: the
      // content starts within a row or two of where the bar ends.
      expect(contentRect.top - bar.bottom, lessThan(2));
    }

    testWidgets('Home renders under the bar, with Home lit', (tester) async {
      await boot(hasLiveTv: false);

      final discover = DiscoverProvider(multiServer, hidden, libraries, isProfileBinding: () => false);
      final projection = TvHomeProjectionProvider(
        discover: discover,
        multiServer: multiServer,
        continueWatchingTitle: t.discover.continueWatching,
        latestMoviesTitle: t.discover.recentlyReleased,
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final storage = await StorageService.getInstance();
      final plexHome = PlexHomeService(
        connections: _EmptyConnectionRegistry(db),
        profileConnections: _EmptyProfileConnectionRegistry(db),
        storage: storage,
        plexHomeUserFetcher: (_) async => const [],
      );
      final activeProfile = ActiveProfileProvider(
        registry: _EmptyProfileRegistry(db),
        plexHome: plexHome,
        connections: _EmptyConnectionRegistry(db),
        storage: storage,
      );
      addTearDown(() async {
        projection.dispose();
        discover.dispose();
        activeProfile.dispose();
        await plexHome.dispose();
        await db.close();
      });

      setGoldenSurfaceSize(tester);
      await tester.pumpWidget(
        shell(
          const DiscoverScreen(),
          withProviders: (child) => MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
              ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
              ChangeNotifierProvider<HomeLayoutProvider>(create: (_) => HomeLayoutProvider()),
              ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfile),
              ChangeNotifierProvider<WatchTogetherProvider>(create: (_) => WatchTogetherProvider()),
              ChangeNotifierProvider<CompanionRemoteProvider>(create: (_) => CompanionRemoteProvider()),
              ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
              ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: projection),
            ],
            child: child,
          ),
        ),
      );
      // Pumped rather than settled, and the load is left to the screen's own
      // `initState`: Home's spotlight carousel runs a repeating timer, so
      // `pumpAndSettle` never returns under it, and awaiting `load()` outside a
      // pump would wait on timers the test clock has not been asked to run.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await precacheWordmark(tester);
      expectShellFrames(tester, find.byType(DiscoverScreen));
      // Hoofdstuk 33's shared shell: the destination the viewer is on is the
      // one wearing the capsule.
      expect(coordinator.active, TvDestinationId.home);
      await expectMatchesGolden(find.byType(TvRootShell), 'tv_shell_home');
    });

    testWidgets('Search renders under the bar, with Search lit', (tester) async {
      await boot(hasLiveTv: false, active: TvDestinationId.search);

      setGoldenSurfaceSize(tester);
      await tester.pumpWidget(
        shell(
          const SearchScreen(),
          // SearchScreen resolves hidden-library visibility, which the
          // profile session supplies in production.
          withProviders: (child) => MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
            ],
            child: child,
          ),
        ),
      );
      await precacheWordmark(tester);
      await tester.pumpAndSettle();
      expectShellFrames(tester, find.byType(SearchScreen));
      expect(coordinator.active, TvDestinationId.search);
      await expectMatchesGolden(find.byType(TvRootShell), 'tv_shell_search');
    });
  });
}

/// Enough of a server for Home to load: it answers every discovery fetch with
/// a small, fixed set, so the picture is the same on every run.
class _FakeHomeClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  List<MediaItem> get _movies => [
    for (var i = 0; i < 6; i++) _item('home_$i', title: _movieTitles[i], kind: MediaKind.movie, year: 2018 + i),
  ];

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async => _movies.take(4).toList();

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async => _movies;

  @override
  Future<List<MediaItem>> fetchRecentlyAddedShows({int limit = 50}) async => const [];

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async => const [];

  @override
  Future<List<MediaHub>> fetchGlobalHubs({int limit = 20, bool includePlaybackHubs = true}) async => [
    MediaHub(
      id: 'recently-added-movies',
      identifier: 'recently-added-movies',
      title: 'Recently Added',
      type: 'movie',
      items: _movies,
      size: _movies.length,
      serverId: 'nas',
      serverName: 'NAS',
    ),
  ];

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyProfileRegistry extends ProfileRegistry {
  _EmptyProfileRegistry(super.db);

  @override
  Stream<List<Profile>> watchProfiles() => Stream.value(const []);

  @override
  Future<List<Profile>> list() async => const [];
}

class _EmptyConnectionRegistry extends ConnectionRegistry {
  _EmptyConnectionRegistry(super.db);

  @override
  Stream<List<Connection>> watchConnections() => Stream.value(const []);

  @override
  Future<List<Connection>> list() async => const [];
}

class _EmptyProfileConnectionRegistry extends ProfileConnectionRegistry {
  _EmptyProfileConnectionRegistry(super.db);

  @override
  Stream<List<ProfileConnection>> watchAll() => Stream.value(const []);
}
