/// Fase 6 (hoofdstuk 9.5, DEC-067) and fase 8: the TV Home hero's *slide
/// list*, now read off the production carousel that replaced the spotlight.
///
/// These drive the real `DiscoverScreen` on a TV surface with real
/// `DiscoverProvider` + `TvHomeProjectionProvider` instances over fake
/// clients, and read the answer off the rendered `TvHeroBillboardCard` —
/// there is deliberately no test-only hero list here. Before DEC-067 the
/// hero rotated over `DiscoverProvider.latestMovies`, so a film present on
/// two servers under two different guids took two rotation slots — the light
/// upstream dedup collapses identical guids only. Three of the tests below
/// are red against that hero.
///
/// Fase 8 changed *where the answer is read*, not what it should be: the
/// slide is `TvHeroBillboardCard.group`, so these assertions now run against
/// the logical group the carousel is showing rather than against a concrete
/// `MediaItem` a full-bleed background happened to hold. Every expectation is
/// the fase-6 one.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/screens/discover_screen.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/watch_together/watch_together.dart';
import 'package:pleya/widgets/side_navigation_rail.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_card.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_carousel.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// The instant `DataAggregationService` measures the hero window against in
/// this file. Pinning it is the whole of HERO5: DEC-097 keeps only films
/// released inside 90 days, the service reads a clock for that, and a file
/// that lets it read the wall clock goes red on a date nobody chose. Every
/// fixture below sits inside the window relative to *this* instant, and the
/// oldest of them (`2026-04-01`) has a month of room under the cutoff.
final DateTime _fixtureNow = DateTime(2026, 6, 1);

/// The release date a fixture gets when it does not name one. DEC-097 puts a
/// film without a date outside the hero by contract, so a fixture that means
/// to reach the hero has to carry one; there is no "no opinion" left to
/// express here.
const String _defaultRelease = '2026-05-01';

MediaItem _movie(
  String id, {
  required String title,
  String? guid,
  String serverId = 'server_1',
  String originallyAvailableAt = _defaultRelease,
  int? year,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  guid: guid,
  year: year,
  originallyAvailableAt: originallyAvailableAt,
  serverId: serverId,
  serverName: serverId,
);

/// One film on two servers, each carrying its *own* guid — the duplicate the
/// light cross-server dedup in `getLatestMoviesFromAllServers` cannot see (it
/// collapses identical guids only), so it reaches the hero as two concrete
/// films.
///
/// The two guids conflict in the same namespace, which hoofdstuk 11.4 treats
/// as evidence *against* a merge: these stay two groups, and it is
/// `FeaturedSelector`'s shared-bucket rule that stops the second one taking a
/// second slide.
Map<String, List<MediaItem>> _duneWithConflictingGuids() => {
  'server_1': [_movie('dune-1', title: 'Dune', guid: 'plex://movie/dune', serverId: 'server_1', year: 2021)],
  'server_2': [_movie('dune-2', title: 'Dune', guid: 'jellyfin://dune', serverId: 'server_2', year: 2021)],
};

/// The same film on two servers where only one of them names a guid — no
/// conflicting token, so hoofdstuk 11.6's title+year fallback genuinely
/// merges them and the slide becomes one group with two sources.
Map<String, List<MediaItem>> _duneMergeable() => {
  'server_1': [_movie('dune-1', title: 'Dune', guid: 'plex://movie/dune', serverId: 'server_1', year: 2021)],
  'server_2': [_movie('dune-2', title: 'Dune', serverId: 'server_2', year: 2021)],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('two concrete copies of one recent film are one hero slide, not two', (tester) async {
    final harness = await _pumpTvHero(tester, _duneWithConflictingGuids());

    // Precondition, and the whole point: `getLatestMoviesFromAllServers`
    // collapses two copies only when their guid is *identical*, so these two
    // survive into `latestMovies` as two concrete films — which is exactly
    // what the pre-DEC-067 hero rotated over.
    expect(harness.discover.latestMovies, hasLength(2));
    expect(harness.heroTitles, ['Dune'], reason: 'the rotation itself holds one slide, not two Dunes');
    expect(_spotlightId(tester), 'dune-1');

    // And the rotation really is finite at one: Right off the last slide stays
    // put (the existing carousel convention), so the user cannot reach the
    // second copy by navigating either. Asserted on the concrete id, because
    // both copies render the same title.
    await _pressRight(tester);
    expect(_spotlightId(tester), 'dune-1', reason: 'Right must not land on the other server\'s copy');

    // Conflicting guids mean the pipeline could not prove them equal, so the
    // surviving slide honestly claims one source. Widening that is
    // `resolveMoreSources`' job at activation time (hoofdstuk 12.8/14.5),
    // not the hero's.
    expect(harness.projection.heroGroups.single.sources, hasLength(1));
  });

  testWidgets('a mergeable duplicate becomes one slide carrying both sources', (tester) async {
    // Point I: the representative concrete item is presentation. What a slide
    // hands the fase-4 coordinator is the whole group — so a title the
    // pipeline *can* merge reaches activation with both servers, which is
    // what lets the coordinator offer the picker instead of silently playing
    // whichever copy happened to be the representative.
    final harness = await _pumpTvHero(tester, _duneMergeable());

    expect(harness.discover.latestMovies, hasLength(2), reason: 'precondition: two concrete films');
    expect(harness.heroTitles, ['Dune']);
    expect(_spotlightId(tester), 'dune-1');
    await _pressRight(tester);
    expect(_spotlightId(tester), 'dune-1', reason: 'the merged copy is a source, never a second slide');

    final group = harness.projection.heroGroups.single;
    expect(group.sources, hasLength(2));
    expect(group.sources.map((s) => s.item.serverId).toSet(), {'server_1', 'server_2'});
  });

  testWidgets('dedup shrinking the concrete pool shrinks the hero, in release order', (tester) async {
    // Eight concrete films across two servers; three titles are on both, so
    // five logical ones remain.
    final harness = await _pumpTvHero(tester, {
      'server_1': [
        _movie('a1', title: 'Alpha', guid: 'plex://movie/alpha', year: 2026, originallyAvailableAt: '2026-08-01'),
        _movie('b1', title: 'Bravo', guid: 'plex://movie/bravo', year: 2026, originallyAvailableAt: '2026-07-01'),
        _movie('c1', title: 'Charlie', guid: 'plex://movie/charlie', year: 2026, originallyAvailableAt: '2026-06-01'),
        _movie('d1', title: 'Delta', guid: 'plex://movie/delta', year: 2026, originallyAvailableAt: '2026-05-01'),
        _movie('e1', title: 'Echo', guid: 'plex://movie/echo', year: 2026, originallyAvailableAt: '2026-04-01'),
      ],
      // Same three titles, different guids — the case the light guid dedup
      // cannot see and the identity pipeline has to bucket on title+year.
      'server_2': [
        _movie(
          'a2',
          title: 'Alpha',
          guid: 'jellyfin://alpha',
          serverId: 'server_2',
          year: 2026,
          originallyAvailableAt: '2026-08-01',
        ),
        _movie(
          'b2',
          title: 'Bravo',
          guid: 'jellyfin://bravo',
          serverId: 'server_2',
          year: 2026,
          originallyAvailableAt: '2026-07-01',
        ),
        _movie(
          'c2',
          title: 'Charlie',
          guid: 'jellyfin://charlie',
          serverId: 'server_2',
          year: 2026,
          originallyAvailableAt: '2026-06-01',
        ),
      ],
    });

    expect(harness.discover.latestMovies, hasLength(8), reason: 'precondition: eight concrete films');
    expect(harness.heroTitles, ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']);

    // Walk the whole rotation through the production key path — the release
    // order has to survive grouping, not just the group count.
    final walked = <String?>[_spotlightTitle(tester)];
    for (var i = 0; i < 4; i++) {
      await _pressRight(tester);
      walked.add(_spotlightTitle(tester));
    }
    expect(walked, ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']);
  });

  testWidgets('one recent film plus Top Picks gives a hero of exactly that film', (tester) async {
    final harness = await _pumpTvHero(
      tester,
      {
        'server_1': [_movie('only', title: 'The Only Recent One', guid: 'plex://movie/only')],
      },
      hubs: [
        MediaHub(
          id: 'top-picks',
          identifier: 'top-picks',
          title: 'Top Picks',
          type: 'movie',
          size: 2,
          items: [
            _movie('tp1', title: 'Top Pick One', guid: 'plex://movie/tp1'),
            _movie('tp2', title: 'Top Pick Two', guid: 'plex://movie/tp2'),
          ],
        ),
      ],
    );

    expect(harness.heroTitles, ['The Only Recent One'], reason: 'hubs never pad a non-empty hero (DEC-067)');
    expect(_spotlightTitle(tester), 'The Only Recent One');
    await _pressRight(tester);
    expect(_spotlightTitle(tester), 'The Only Recent One', reason: 'no Top Pick sits in the second slot');
  });

  testWidgets('zero recent films keeps the existing hub fallback billboard', (tester) async {
    await _pumpTvHero(
      tester,
      const {},
      hubs: [
        MediaHub(
          id: 'top-picks',
          identifier: 'top-picks',
          title: 'Top Picks',
          type: 'movie',
          size: 1,
          items: [_movie('tp1', title: 'Fallback Billboard', guid: 'plex://movie/tp1')],
        ),
      ],
    );

    // Unchanged behaviour through fase 8 (hoofdstuk 9.5's last sentence): an
    // empty film pool falls through to Continue Watching, then hub content, so
    // the billboard is never blank. What changed is only that the fallback is
    // now a `UnifiedMediaGroup` too, so its Afspelen resolves through the
    // fase-4 coördinator instead of the representative-source shortcut.
    expect(_spotlightTitle(tester), 'Fallback Billboard');
  });

  testWidgets('a single-source hero slide is one group with exactly one source', (tester) async {
    final harness = await _pumpTvHero(tester, {
      'server_1': [_movie('solo', title: 'Solo Title', guid: 'plex://movie/solo')],
    });

    final group = harness.projection.heroGroups.single;
    expect(group.sources, hasLength(1));
    expect(group.representativeSource.item.serverId, 'server_1');
  });

  testWidgets('phone/desktop hero keeps rotating over latestMovies, undeduped', (tester) async {
    // The correction is TV-only. On phone the hero is the `latestMovies`
    // PageView and `TvHomeProjectionProvider` is not even in the tree, so the
    // two concrete Dunes stay two pages exactly as they were.
    TvDetectionService.debugSetAppleTVOverride(false);
    final harness = await _pumpTvHero(
      tester,
      _duneWithConflictingGuids(),
      hubs: [
        MediaHub(
          id: 'top-picks',
          identifier: 'top-picks',
          title: 'Top Picks',
          type: 'movie',
          size: 1,
          items: [_movie('tp1', title: 'Top Pick One', guid: 'plex://movie/tp1')],
        ),
      ],
      tv: false,
    );

    expect(harness.discover.latestMovies, hasLength(2), reason: 'the phone PageView still has two pages');
    expect(find.byType(TvHeroBillboardCarousel), findsNothing, reason: 'no TV billboard off TV');
    // The projection still runs here only because this harness always builds
    // it; the phone screen never reads it. In the app it is not even in the
    // tree off TV — `DiscoverScreen` branches to `_buildTvContent` (and so to
    // `TvContentFeed`) only on TV, so the phone hero stays `latestMovies`.
    expect(find.byType(PageView), findsOneWidget);
  });

  group('P2: one content-focus authority', _p2Tests);
}

/// P2, at the far end: content landing is not a request for the focus.
///
/// This is the third of the three paths the round removes — `DiscoverScreen`'s
/// initial-load post-frame, which called `focusPrimary()` as soon as anything
/// arrived, guarded only by `mounted` and `ModalRoute.isCurrent`. On a cold
/// Home that fired seconds after the viewer had walked somewhere else in the
/// bar, and it is why fixing `_selectTvDestination` alone would not have been
/// enough.
///
/// Both directions are asserted, because only asserting the guard would go
/// green on a screen that had simply stopped focusing anything at all.
void _p2Tests() {
  testWidgets('content arriving on its own does not take the focus', (tester) async {
    final authority = TvContentFocusAuthority();
    await _pumpTvHero(tester, {
      'nas': [_movie('a', title: 'Arrival', guid: 'plex://movie/a')],
    }, contentFocus: authority);

    expect(find.byType(TvHeroBillboardCarousel), findsOneWidget, reason: 'the content did land');
    expect(
      _heroPlayNode(tester).hasFocus,
      isFalse,
      reason: 'nobody asked for the content, so the billboard does not claim the remote',
    );
    expect(authority.hasPendingIntent, isFalse);
  });

  testWidgets('an armed intent is what lets late content claim the focus', (tester) async {
    final authority = TvContentFocusAuthority()..arm(TvContentFocusIntent.primary);
    await _pumpTvHero(tester, {
      'nas': [_movie('a', title: 'Arrival', guid: 'plex://movie/a')],
    }, contentFocus: authority);

    expect(_heroPlayNode(tester).hasFocus, isTrue, reason: 'the DOWN pressed before the load is honoured now');
    expect(authority.hasPendingIntent, isFalse, reason: 'and consumed exactly once');
  });
}

String? _spotlightTitle(WidgetTester tester) => _spotlightItem(tester)?.title;

/// The concrete item id on the billboard. Two copies of one film share a
/// title, so only the id can tell "the rotation moved to the other copy"
/// from "the rotation stayed put" — which is the whole assertion in the
/// duplicate tests.
String? _spotlightId(WidgetTester tester) => _spotlightItem(tester)?.id;

/// The *representative* item of the slide the carousel is showing. Read
/// through the card, so what these tests assert on is the same object the
/// production hero renders — and the group behind it is one hop away, which is
/// what the source-count assertions use.
MediaItem? _spotlightItem(WidgetTester tester) {
  final cards = tester.widgetList<TvHeroBillboardCard>(find.byType(TvHeroBillboardCard));
  if (cards.isEmpty) return null;
  return cards.single.group.representativeSource.item;
}

/// Move the hero one slide right through the production key path: focus the
/// Play pill, then send Arrow Right, which the carousel wires to More info and
/// then to the next slide (hoofdstuk 7.3).
Future<void> _pressRight(WidgetTester tester) async {
  final playNode = _heroPlayNode(tester);
  playNode.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.pump();
  // Right off Play lands on More info; from there Right advances the slide.
  if (_heroPlayNode(tester).hasFocus) return;
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
  await tester.pumpAndSettle();
}

FocusNode _heroPlayNode(WidgetTester tester) => tester
    .widgetList<Focus>(find.byType(Focus))
    .map((f) => f.focusNode)
    .whereType<FocusNode>()
    .firstWhere((node) => node.debugLabel == 'tvHeroPlay');

class _TvHeroHarness {
  _TvHeroHarness({required this.discover, required this.projection});

  final DiscoverProvider discover;
  final TvHomeProjectionProvider projection;

  List<String?> get heroTitles => [for (final g in projection.heroGroups) g.representativeSource.item.title];
}

/// Mounts the real [DiscoverScreen] on a TV surface over [recentlyAdded] —
/// keyed by server id, so a title can genuinely exist on two servers — and
/// settles the whole load + projection.
Future<_TvHeroHarness> _pumpTvHero(
  WidgetTester tester,
  Map<String, List<MediaItem>> recentlyAdded, {
  List<MediaHub> hubs = const [],
  bool tv = true,
  TvContentFocusAuthority? contentFocus,
}) async {
  final settings = await SettingsService.getInstance();
  await settings.write(SettingsService.libraryDensity, LibraryDensity.max);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final manager = MultiServerManager();
  final serverIds = recentlyAdded.isEmpty ? ['server_1'] : recentlyAdded.keys.toList();
  for (final serverId in serverIds) {
    manager.debugRegisterClientForTesting(
      _FakeMediaServerClient(
        serverId: serverId,
        // Hubs come from one server only: two servers returning the same hub
        // would merge, which is a different contract than this file's.
        hubs: serverId == serverIds.first ? hubs : const [],
        recentlyAdded: recentlyAdded[serverId] ?? const [],
      ),
    );
  }

  final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager, now: () => _fixtureNow));
  final hiddenLibrariesProvider = HiddenLibrariesProvider();
  final librariesProvider = LibrariesProvider();
  final watchTogetherProvider = WatchTogetherProvider();
  final companionRemoteProvider = CompanionRemoteProvider();

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final profileRegistry = _FakeProfileRegistry(db);
  final connectionRegistry = _FakeConnectionRegistry(db);
  final profileConnectionRegistry = _FakeProfileConnectionRegistry(db);
  final storage = await StorageService.getInstance();
  final plexHome = PlexHomeService(
    connections: connectionRegistry,
    profileConnections: profileConnectionRegistry,
    storage: storage,
    plexHomeUserFetcher: (_) async => const [],
  );
  final activeProfileProvider = ActiveProfileProvider(
    registry: profileRegistry,
    plexHome: plexHome,
    connections: connectionRegistry,
    storage: storage,
  );
  final discoverProvider = DiscoverProvider(
    multiServerProvider,
    hiddenLibrariesProvider,
    librariesProvider,
    isProfileBinding: () => activeProfileProvider.isBinding,
  );
  final projectionProvider = TvHomeProjectionProvider(
    discover: discoverProvider,
    multiServer: multiServerProvider,
    continueWatchingTitle: t.discover.continueWatching,
    latestMoviesTitle: t.discover.recentlyReleased,
  );
  const foregroundWidth = 1280 - SideNavigationRailState.tvCollapsedWidth;

  addTearDown(() async {
    projectionProvider.dispose();
    discoverProvider.dispose();
    activeProfileProvider.dispose();
    companionRemoteProvider.dispose();
    watchTogetherProvider.dispose();
    librariesProvider.dispose();
    hiddenLibrariesProvider.dispose();
    multiServerProvider.dispose();
    await plexHome.dispose();
    await db.close();
  });

  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
          ChangeNotifierProvider<HomeLayoutProvider>(create: (_) => HomeLayoutProvider()),
          ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
          ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogetherProvider),
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: companionRemoteProvider),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfileProvider),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discoverProvider),
          ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: projectionProvider),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: tv),
          home: MainScreenFocusScope(
            focusSidebar: () {},
            focusContent: () {},
            isSidebarFocused: false,
            sideNavigationWidth: SideNavigationRailState.expandedWidth,
            reservedSideNavigationWidth: SideNavigationRailState.tvCollapsedWidth,
            foregroundLeft: 120.0,
            foregroundWidth: foregroundWidth,
            viewportWidth: 1280,
            tvContentFocus: contentFocus,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: foregroundWidth, height: 720, child: const DiscoverScreen()),
            ),
          ),
        ),
      ),
    ),
  );

  // Settle the load, then the projection it triggers (identity resolution is
  // async), then the rebuild the projection notifies.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }

  return _TvHeroHarness(discover: discoverProvider, projection: projectionProvider);
}

class _FakeMediaServerClient implements MediaServerClient {
  _FakeMediaServerClient({required String serverId, required this.hubs, required this.recentlyAdded})
    : serverId = ServerId(serverId),
      serverName = serverId;

  final List<MediaHub> hubs;
  final List<MediaItem> recentlyAdded;

  @override
  final ServerId serverId;

  @override
  final String serverName;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async => const [];

  @override
  Future<List<MediaHub>> fetchGlobalHubs({int limit = defaultHubPreviewLimit, bool includePlaybackHubs = true}) async =>
      hubs;

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async => recentlyAdded;

  @override
  Future<List<MediaItem>> fetchRecentlyAddedShows({int limit = 50}) async => const [];

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRegistry extends ProfileRegistry {
  _FakeProfileRegistry(super.db);

  @override
  Stream<List<Profile>> watchProfiles() => Stream.value(const []);

  @override
  Future<List<Profile>> list() async => const [];
}

class _FakeConnectionRegistry extends ConnectionRegistry {
  _FakeConnectionRegistry(super.db);

  @override
  Stream<List<Connection>> watchConnections() => Stream.value(const []);

  @override
  Future<List<Connection>> list() async => const [];
}

class _FakeProfileConnectionRegistry extends ProfileConnectionRegistry {
  _FakeProfileConnectionRegistry(super.db);

  @override
  Stream<List<ProfileConnection>> watchAll() => Stream.value(const []);
}
