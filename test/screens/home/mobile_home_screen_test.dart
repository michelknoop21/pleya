import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_discovery_landing_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/screens/home/mobile_home_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/widgets/mobile/mobile_hero_card.dart';
import 'package:pleya/widgets/mobile/mobile_media_rail.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// The screen `discover_screen.dart` picks on `PlatformDetector.isPhone` —
/// mounting it end to end catches a missing provider in the real app tree
/// that a unit test of any single piece cannot (`docs/ios-unified-2026-fase1-plan.md`
/// stap 8).
///
/// `ActiveProfileProvider` is deliberately absent: the screen reads it as
/// `ActiveProfileProvider?`, so leaving it out also pins that the Home tree
/// survives a session without an active profile. The avatar path with a real
/// profile is covered by `mobile_page_header_test.dart`.
///
/// The provider stack is the one `tv_home_projection_provider_test.dart`
/// uses: a fake aggregation service behind the real `DiscoverProvider`, so
/// the rows on screen come out of the same projection the app runs.

MediaItem _movie(String id, {String? title, int? year}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title ?? id,
  year: year,
  serverId: 'server_1',
  serverName: 'server_1',
);

MediaHub _hub(String id, {required List<MediaItem> items}) => MediaHub(
  id: id,
  identifier: id,
  title: id,
  type: 'movie',
  items: items,
  size: items.length,
  serverId: 'server_1',
  serverName: 'Server',
);

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaItem> latestMovies = const [];
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
  }) async => (items: const <MediaItem>[], succeededServerIds: serverIds ?? const {'server_1'});

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
  late HomeLayoutProvider homeLayout;
  late TvHomeProjectionProvider homeProjection;

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
    homeLayout = HomeLayoutProvider();
    homeProjection = TvHomeProjectionProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: 'Continue Watching',
      latestMoviesTitle: 'Recently Released',
    );
  });

  tearDown(() {
    homeProjection.dispose();
    homeLayout.dispose();
    discover.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ChangeNotifierProvider<HomeLayoutProvider>.value(value: homeLayout),
          ChangeNotifierProvider<TvDiscoveryLandingProvider>(
            create: (context) => TvDiscoveryLandingProvider(discover: discover, multiServer: multiServer),
          ),
          ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: homeProjection),
        ],
        child: MaterialApp(theme: monoTheme(dark: true), home: const MobileHomeScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('mounts against a real provider tree and renders header, chips and hero region', (tester) async {
    await pumpHome(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
  });

  testWidgets('renders Verder kijken first and then the hubs in projection order', (tester) async {
    aggregation.latestMovies = [_movie('m1', title: 'Recent One', year: 2026)];
    aggregation.onDeck = [_movie('d1', title: 'Half Watched')];
    aggregation.hubs = [
      _hub('Trending', items: [_movie('t1')]),
      _hub('Because you watched', items: [_movie('b1')]),
    ];

    await pumpHome(tester);
    await tester.runAsync(discover.load);
    await tester.pump();
    await tester.pump();

    // The hero rotates over latestMovies, so it is present on the Home chip.
    expect(find.byType(MobileHeroCard), findsOneWidget);

    // Slivers below the fold are not built yet, so read the order off
    // `railIndex` while scrolling rather than off one flat widget list.
    final seen = <int, String>{};
    void collect() {
      for (final rail in tester.widgetList<MobileMediaRail>(find.byType(MobileMediaRail))) {
        seen[rail.railIndex] = rail.hub.title;
      }
    }

    collect();
    expect(seen[0], 'Continue Watching', reason: 'Verder kijken sits directly under the hero');
    for (var i = 0; i < 4 && seen.length < 3; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
      collect();
    }
    // The row order itself is the projection's, not the screen's: assert the
    // screen reproduces `TvHomeProjectionProvider.hubs` rather than the raw
    // fixture order, so this test cannot silently re-decide row ranking.
    final projected = homeProjection.hubs.map((h) => h.title).toList();
    expect(projected, hasLength(2));
    expect(seen[1], projected[0]);
    expect(seen[2], projected[1]);
  });

  testWidgets('the Series chip drops the hero and swaps in the series rails', (tester) async {
    aggregation.latestMovies = [_movie('m1', title: 'Recent One', year: 2026)];
    aggregation.onDeck = [_movie('d1', title: 'Half Watched')];
    aggregation.hubs = [
      _hub('Trending', items: [_movie('t1')]),
    ];

    await pumpHome(tester);
    await tester.runAsync(discover.load);
    await tester.pump();
    await tester.pump();
    expect(find.byType(MobileHeroCard), findsOneWidget);

    await tester.tap(find.text('Series'));
    await tester.pump();

    // Hero and Continue Watching belong to the Home chip only; the Series
    // chip shows `TvDiscoveryLandingProvider.seriesRails`, which is empty for
    // this movie-only fixture.
    expect(find.byType(MobileHeroCard), findsNothing);
    expect(find.text('Continue Watching'), findsNothing);
    expect(find.text('Trending'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
