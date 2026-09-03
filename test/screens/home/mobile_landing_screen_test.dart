import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/mobile_shell_scope.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_discovery_landing_provider.dart';
import 'package:pleya/screens/home/mobile_landing_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/widgets/mobile/mobile_hero_card.dart';
import 'package:pleya/widgets/mobile/mobile_media_rail.dart';
import 'package:pleya/widgets/mobile/mobile_page_title_row.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// The Series and Films landings from mockups 01 and 02. iOS Unified 2026
/// fase 2.
///
/// Same provider stack as `mobile_home_screen_test.dart`, so what the rails
/// show comes out of the real projection rather than a hand-built hub list.

MediaItem _movie(String id, {String? title, int? year}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title ?? id,
  year: year,
  serverId: 'server_1',
  serverName: 'server_1',
);

MediaItem _show(String id, {String? title, int? year}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.show,
  title: title ?? id,
  year: year,
  serverId: 'server_1',
  serverName: 'server_1',
);

MediaHub _hub(String id, {required List<MediaItem> items, String type = 'movie'}) => MediaHub(
  id: id,
  identifier: id,
  title: id,
  type: type,
  items: items,
  size: items.length,
  serverId: 'server_1',
  serverName: 'Server',
);

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaItem> latestMovies = const [];
  List<MediaItem> latestShows = const [];
  List<MediaItem> onDeck = const [];
  List<MediaHub> hubs = const [];

  @override
  Future<OnDeckAggregationResult> getLatestMoviesFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: latestMovies, succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: onDeck, succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<OnDeckAggregationResult> getLatestShowsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: latestShows, succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubs, succeededServerIds: serverIds ?? const {'server_1'});
}

class _FakeClient implements MediaServerClient {
  @override
  final ServerId serverId = ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAggregationService aggregation;
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late DiscoverProvider discover;
  late TvDiscoveryLandingProvider landing;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    aggregation = _FakeAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    libraries = LibrariesProvider();
    discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
    landing = TvDiscoveryLandingProvider(discover: discover, multiServer: multiServer);
  });

  tearDown(() {
    landing.dispose();
    discover.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  Future<void> pumpLanding(
    WidgetTester tester,
    MobileLandingKind kind, {
    void Function(NavigationTabId tab)? onOpenTab,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final screen = MobileLandingScreen(kind: kind);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ChangeNotifierProvider<TvDiscoveryLandingProvider>.value(value: landing),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: onOpenTab == null ? screen : MobileShellScope(openTab: onOpenTab, child: screen),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> loadFixture(WidgetTester tester) async {
    await tester.runAsync(discover.load);
    await tester.pump();
    await tester.pump();
  }

  List<String> railTitles(WidgetTester tester) =>
      tester.widgetList<MobileMediaRail>(find.byType(MobileMediaRail)).map((rail) => rail.hub.title).toList();

  testWidgets('the Films landing carries its own title and no hero', (tester) async {
    aggregation.latestMovies = [_movie('m1', title: 'Recent One', year: 2026)];

    await pumpLanding(tester, MobileLandingKind.movies);
    await loadFixture(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.byType(MobileHeroCard), findsNothing, reason: 'a landing has no hero (rapport §5)');
  });

  testWidgets('the Series landing shows the series rails and never a movie rail', (tester) async {
    aggregation.latestShows = [_show('s1', title: 'A Show', year: 2024)];
    aggregation.latestMovies = [_movie('m1', title: 'A Movie', year: 2026)];
    aggregation.hubs = [
      _hub('Trending movies', items: [_movie('t1')]),
    ];

    await pumpLanding(tester, MobileLandingKind.series);
    await loadFixture(tester);

    expect(find.text('Series'), findsOneWidget);
    // The screen reproduces the projection rather than re-deciding it, so the
    // assertion is against the provider and not against the fixture order.
    expect(railTitles(tester), landing.seriesRails.map((hub) => hub.title).toList());
    expect(railTitles(tester), isNot(contains('Trending movies')));
  });

  testWidgets('neither landing shows Verder kijken, Home owns it (DEC-086)', (tester) async {
    aggregation.onDeck = [_movie('d1', title: 'Half Watched')];
    aggregation.latestMovies = [_movie('m1', title: 'Recent One', year: 2026)];

    await pumpLanding(tester, MobileLandingKind.movies);
    await loadFixture(tester);

    expect(find.text('Half Watched'), findsNothing);
    expect(find.text('Continue Watching'), findsNothing);
  });

  testWidgets('the complete-catalog entry is drawn now that fase 3 has built it', (tester) async {
    aggregation.latestMovies = [_movie('m1', title: 'Recent One', year: 2026)];

    await pumpLanding(tester, MobileLandingKind.movies);
    await loadFixture(tester);

    // Fase 2 pinned the opposite on purpose (DEC-093): the entry could not
    // appear until it had somewhere to go, and `UnifiedCatalogProvider` had no
    // UI consumer. Fase 3 built that surface, so the expectation is turned
    // around here deliberately rather than deleted.
    expect(find.byType(MobilePageTitleRow), findsOneWidget);
    expect(tester.widget<MobilePageTitleRow>(find.byType(MobilePageTitleRow)).onViewAll, isNotNull);
    expect(find.text('All movies'), findsOneWidget);
  });

  testWidgets('the Series landing points at the series catalogue', (tester) async {
    aggregation.latestShows = [_show('s1', title: 'A Show', year: 2024)];

    await pumpLanding(tester, MobileLandingKind.series);
    await loadFixture(tester);

    expect(find.text('All series'), findsOneWidget);
    expect(find.text('All movies'), findsNothing);
  });

  testWidgets('the header search asks the shell for the Search destination', (tester) async {
    final opened = <NavigationTabId>[];
    aggregation.latestMovies = [_movie('m1', title: 'Recent One', year: 2026)];

    await pumpLanding(tester, MobileLandingKind.series, onOpenTab: opened.add);
    await loadFixture(tester);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();

    expect(opened, [NavigationTabId.search]);
  });

  testWidgets('without a shell the search action is inert rather than throwing', (tester) async {
    aggregation.latestMovies = [_movie('m1', title: 'Recent One', year: 2026)];

    await pumpLanding(tester, MobileLandingKind.movies);
    await loadFixture(tester);

    await tester.tap(find.byType(IconButton).first);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
