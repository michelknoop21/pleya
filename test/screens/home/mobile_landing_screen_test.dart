import 'dart:async';

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
import 'package:pleya/screens/home/mobile_landing_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/widgets/mobile/mobile_chip_bar.dart';
import 'package:pleya/widgets/mobile/mobile_hero_card.dart';
import 'package:pleya/widgets/mobile/mobile_media_rail.dart';
import 'package:pleya/widgets/mobile/mobile_page_header.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// The Series and Films landings against the frozen `01-series-landing.png` and
/// `02-films-landing.png` (iOS Unified 2026 fase 2, [DEC-094]).
///
/// Mounted end to end over the real provider stack, like
/// `mobile_home_screen_test.dart`: the rows on screen come out of the same
/// projection the app runs, so a landing cannot quietly grow a second one.
///
/// The viewport is the iPhone 15 Pro's 393x852 **points**, which is why the
/// device pixel ratio is 1.0 and not 3: `physicalSize` is divided by it, so
/// dpr 3 would give a 131x284 logical viewport.
MediaItem _movie(String id, {String? title}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title ?? id,
  serverId: 'server_1',
  serverName: 'server_1',
);

MediaItem _show(String id, {String? title}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.show,
  title: title ?? id,
  serverId: 'server_1',
  serverName: 'server_1',
);

MediaHub _hub(String id, {required List<MediaItem> items, required String type}) => MediaHub(
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

  List<MediaHub> hubs = const [];
  bool hang = false;

  @override
  Future<OnDeckAggregationResult> getLatestMoviesFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: const <MediaItem>[], succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: const <MediaItem>[], succeededServerIds: serverIds ?? const {'server_1'});

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
  }) async {
    if (hang) await Future<void>.delayed(const Duration(seconds: 30));
    return (hubs: hubs, succeededServerIds: serverIds ?? const {'server_1'});
  }
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
  });

  tearDown(() {
    homeLayout.dispose();
    discover.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  Future<void> pumpLanding(WidgetTester tester, MobileLandingKind kind, {VoidCallback? onSearchTap}) async {
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
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: MobileLandingScreen(kind: kind, onSearchTap: onSearchTap),
        ),
      ),
    );
    await tester.pump();
  }

  /// Load and let the projection, which resolves identities over an await,
  /// actually land before reading rows off the tree.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(discover.load);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  testWidgets('the Series landing draws the title line from the northstar', (tester) async {
    aggregation.hubs = [
      _hub('Aanbevolen voor jou', items: [_show('s1')], type: 'show'),
    ];

    await pumpLanding(tester, MobileLandingKind.series);
    await settle(tester);

    expect(find.text('Series'), findsOneWidget);
    expect(find.text('All series'), findsOneWidget);
    expect(find.text('Aanbevolen voor jou'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Films landing is the same screen with the other kind', (tester) async {
    aggregation.hubs = [
      _hub('Recent toegevoegd', items: [_movie('m1')], type: 'movie'),
    ];

    await pumpLanding(tester, MobileLandingKind.movies);
    await settle(tester);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('All movies'), findsOneWidget);
    expect(find.text('Recent toegevoegd'), findsOneWidget);
  });

  testWidgets('a landing shows only its own kind, never the other one', (tester) async {
    aggregation.hubs = [
      _hub('Films row', items: [_movie('m1')], type: 'movie'),
      _hub('Series row', items: [_show('s1')], type: 'show'),
    ];

    await pumpLanding(tester, MobileLandingKind.series);
    await settle(tester);

    expect(find.text('Series row'), findsOneWidget);
    expect(find.text('Films row'), findsNothing);
  });

  testWidgets('there is no hero and no chip bar', (tester) async {
    aggregation.hubs = [
      _hub('Series row', items: [_show('s1')], type: 'show'),
    ];

    await pumpLanding(tester, MobileLandingKind.series);
    await settle(tester);

    expect(find.byType(MobileHeroCard), findsNothing, reason: 'the hero belongs to Home');
    expect(find.byType(MobileChipBar), findsNothing, reason: 'a landing is already filtered');
    expect(find.byType(MobilePageHeader), findsOneWidget, reason: 'the header is shared with Home unchanged');
  });

  testWidgets('the Alle-action is drawn and inert until fase 3', (tester) async {
    aggregation.hubs = [
      _hub('Series row', items: [_show('s1')], type: 'show'),
    ];

    await pumpLanding(tester, MobileLandingKind.series);
    await settle(tester);

    // Visible, and not hidden behind an enabled-looking control that does
    // nothing: there is no button widget under it at all yet. Fase 3 puts one
    // handler there and nothing else changes.
    expect(find.text('All series'), findsOneWidget);
    await tester.tap(find.text('All series'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Series'), findsOneWidget, reason: 'tapping it navigates nowhere');
  });

  testWidgets('while loading it shows a skeleton rather than an empty page', (tester) async {
    aggregation.hang = true;

    await pumpLanding(tester, MobileLandingKind.series);
    unawaited(discover.load());
    await tester.pump();

    expect(find.byType(MobileMediaRail), findsNothing);
    expect(find.text('Nothing to discover yet'), findsNothing, reason: 'loading is not the same as empty');
  });

  testWidgets('an empty projection gets an empty state, because there is no hero to fill the page', (tester) async {
    aggregation.hubs = [
      _hub('Films row', items: [_movie('m1')], type: 'movie'),
    ];

    await pumpLanding(tester, MobileLandingKind.series);
    await settle(tester);

    expect(find.byType(MobileMediaRail), findsNothing);
    expect(find.text('Nothing to discover yet'), findsOneWidget);
  });

  testWidgets('the header search action reaches the shell', (tester) async {
    var opened = 0;
    aggregation.hubs = [
      _hub('Series row', items: [_show('s1')], type: 'show'),
    ];

    await pumpLanding(tester, MobileLandingKind.series, onSearchTap: () => opened++);
    await settle(tester);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    expect(opened, 1);
  });
}
