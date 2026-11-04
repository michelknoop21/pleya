/// A-17: the iPad Home hero. Billboard held sideways, card held upright, one
/// list of slides, and the slide survives the turn. Real providers, with only
/// the aggregation faked, because the reported fault was in which slides exist.
library;

import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/screens/home/ipad_home_hero.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/featured_selector.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/widgets/mobile/mobile_hero_card.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_card.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_carousel.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _portrait = Size(834, 1194);
const _landscape = Size(1194, 834);

MediaItem _film(String id) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: id,
  year: 2026,
  serverId: 'server_1',
  serverName: 'server_1',
);

/// A film that lands in the projection and blows it up.
class _ThrowingSelector extends FeaturedSelector {
  const _ThrowingSelector();

  @override
  List<UnifiedMediaGroup> select(List<UnifiedMediaHub> candidateHubs, {DateTime? now}) => throw StateError('boom');
}

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
  }) async => (items: [...latestMovies], succeededServerIds: serverIds ?? const {'server_1'});

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
  String thumbnailUrl(String? path, {int? width, int? height}) => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAggregationService aggregation;
  late MultiServerProvider multiServer;
  late DiscoverProvider discover;
  late HomeLayoutProvider homeLayout;
  late TvHomeProjectionProvider projection;
  late MultiServerManager manager;
  late HiddenLibrariesProvider hiddenLibraries;

  final belowHero = GlobalKey();
  final seen = <String>[];

  setUp(() async {
    seen.clear();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    aggregation = _FakeAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    discover = DiscoverProvider(multiServer, hiddenLibraries, LibrariesProvider(), isProfileBinding: () => false);
    homeLayout = HomeLayoutProvider();
    projection = TvHomeProjectionProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: 'Continue Watching',
      latestMoviesTitle: 'Recently Released',
    );
  });

  Future<void> settleProviders(WidgetTester tester) async {
    await tester.runAsync(() async {
      await discover.load();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    await tester.pump();
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
            ChangeNotifierProvider<HomeLayoutProvider>.value(value: homeLayout),
            ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: projection),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.iOS),
            home: InputModeTracker(
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    IpadHomeHero(
                      firstRailHeight: (_) => 200,
                      onNavigateDown: () => seen.add('down'),
                      onNavigateUp: () => seen.add('up'),
                    ),
                    SliverToBoxAdapter(child: SizedBox(key: belowHero, height: 900)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleProviders(tester);
  }

  /// The tree holds timers while the hero is mounted; this drops them.
  Future<void> finish(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  String billboardTitle(WidgetTester tester) =>
      heroTitleFor(tester.widget<TvHeroBillboardCard>(find.byType(TvHeroBillboardCard)).group);

  test('the billboard needs a landscape window with room for its text', () {
    expect(ipadHeroIsBillboard(_landscape), isTrue);
    expect(ipadHeroIsBillboard(_portrait), isFalse);
    expect(ipadHeroIsBillboard(const Size(900, 479)), isFalse);
    expect(ipadHeroIsBillboard(const Size(900, 900)), isFalse);
  });

  testWidgets('landscape carries the tvOS billboard, full bleed, and no card', (tester) async {
    aggregation.latestMovies = [_film('A'), _film('B')];
    await pump(tester, _landscape);

    expect(find.byType(TvHeroBillboardCarousel), findsOneWidget);
    expect(find.byType(MobileHeroCard), findsNothing);
    expect(tester.widget<TvHeroBillboardCarousel>(find.byType(TvHeroBillboardCarousel)).touchInput, isTrue);
    final rect = tester.getRect(find.byType(TvHeroBillboardCarousel));
    expect(rect.left, 0);
    expect(rect.top, 0);
    expect(rect.width, _landscape.width);
    await finish(tester);
  });

  testWidgets('the billboard stays in its box, so its wash does not bleed over the rail', (tester) async {
    aggregation.latestMovies = [_film('A')];
    await pump(tester, _landscape);

    expect(find.ancestor(of: find.byType(TvHeroBillboardCarousel), matching: find.byType(ClipRect)), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a vertical drag on the billboard scrolls the page, a horizontal one stays a swipe', (tester) async {
    aggregation.latestMovies = [_film('A'), _film('B')];
    await pump(tester, _landscape);

    final top = tester.getTopLeft(find.byType(TvHeroBillboardCard)).dy;
    await tester.drag(find.byType(TvHeroBillboardCard), const Offset(0, -200));
    await tester.pump();
    expect(tester.getTopLeft(find.byType(TvHeroBillboardCard)).dy, lessThan(top));
    expect(billboardTitle(tester), 'A');
    await finish(tester);
  });

  testWidgets('portrait carries the iPhone card, inset, clear of the app bar', (tester) async {
    aggregation.latestMovies = [_film('A'), _film('B')];
    await pump(tester, _portrait);

    expect(find.byType(MobileHeroCard), findsOneWidget);
    expect(find.byType(TvHeroBillboardCarousel), findsNothing);
    final rect = tester.getRect(find.byType(MobileHeroCard));
    expect(rect.left, 16);
    expect(rect.right, _portrait.width - 16);
    expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
    await finish(tester);
  });

  // The report. The pool is empty on a source without a release date and on a
  // library without a recent film (DEC-097); tvOS shows a stand-in, and the old
  // iPad tree showed nothing.
  for (final (name, size) in [('portrait', _portrait), ('landscape', _landscape)]) {
    testWidgets('an empty recent-film pool still shows one stand-in slide in $name', (tester) async {
      aggregation.onDeck = [_film('Halfway Through'), _film('Next Up')];
      await pump(tester, size);

      expect(projection.heroGroups, isEmpty, reason: 'the pool really is empty');
      expect(ipadHomeHeroSlides(tester.element(find.byType(Scaffold)), listen: false).groups, hasLength(1));
      expect(find.text('Halfway Through'), findsOneWidget);
      await finish(tester);
    });
  }

  // Review: the first rail has to peek, not merely follow. This is the height
  // the Verify assertion `peeksAbove: nav.bar` checks on a real viewport.
  testWidgets('the first rail starts on screen under the billboard', (tester) async {
    aggregation.latestMovies = [_film('A')];
    await pump(tester, _landscape);

    expect(tester.getTopLeft(find.byKey(belowHero)).dy, lessThanOrEqualTo(_landscape.height - 60));
    await finish(tester);
  });

  // The old hero hid an unwatched episode's synopsis. The iPhone card never
  // needed to, and on the iPad its stand-in can be exactly that episode.
  for (final (name, size) in [('portrait', _portrait), ('landscape', _landscape)]) {
    testWidgets('an unwatched stand-in episode keeps its synopsis hidden in $name', (tester) async {
      await SettingsService.instance.write(SettingsService.hideSpoilers, true);
      aggregation.onDeck = [
        MediaItem(
          id: 'ep',
          backend: MediaBackend.plex,
          kind: MediaKind.episode,
          title: 'The Reveal',
          grandparentTitle: 'Some Show',
          summary: 'The butler did it.',
          serverId: 'server_1',
          serverName: 'server_1',
        ),
      ];
      await pump(tester, size);

      expect(find.text('Some Show'), findsOneWidget);
      expect(find.text('The butler did it.'), findsNothing);
      await finish(tester);
    });
  }

  // Everything the slides can hold is already on this profile's Home: a row the
  // viewer hid is not a source for the stand-in.
  testWidgets('a row hidden from Home does not come back as the stand-in', (tester) async {
    final hub = MediaHub(
      id: 'hidden-row',
      identifier: 'hidden-row',
      title: 'Hidden Row',
      type: 'movie',
      items: [_film('Hidden Title')],
      size: 1,
      serverId: 'server_1',
      serverName: 'Server',
    );
    aggregation.hubs = [hub];
    await pump(tester, _portrait);
    expect(find.text('Hidden Title'), findsOneWidget, reason: 'the row is the stand-in while it is visible');

    final row = projection.hubs.single.contributingRowIds.first;
    await homeLayout.setRowHidden(row, true);
    await tester.pump();
    await tester.pump();

    expect(find.byType(MobileHeroCard), findsNothing);
    await finish(tester);
  });

  group('the page never waits on a projection that is not coming', () {
    double bandHeight(WidgetTester tester) => tester.getTopLeft(find.byKey(belowHero)).dy;
    const pageTop = kToolbarHeight + 16;

    testWidgets('no server at all, the offline start', (tester) async {
      manager = MultiServerManager();
      multiServer = MultiServerProvider(manager, _FakeAggregationService(manager));
      discover = DiscoverProvider(multiServer, hiddenLibraries, LibrariesProvider(), isProfileBinding: () => false);
      projection = TvHomeProjectionProvider(
        discover: discover,
        multiServer: multiServer,
        continueWatchingTitle: 'Continue Watching',
        latestMoviesTitle: 'Recently Released',
      );
      await pump(tester, _landscape);

      expect(discover.errorMessage, isNotNull);
      expect(bandHeight(tester), pageTop);
      await finish(tester);
    });

    testWidgets('a projection that throws on the films that just landed', (tester) async {
      aggregation.latestMovies = [_film('A')];
      projection = TvHomeProjectionProvider(
        discover: discover,
        multiServer: multiServer,
        continueWatchingTitle: 'Continue Watching',
        latestMoviesTitle: 'Recently Released',
        featuredSelector: const _ThrowingSelector(),
      );
      await pump(tester, _landscape);

      expect(projection.hasProjectedHero, isFalse);
      expect(billboardTitle(tester), 'A', reason: 'the row got projected; the page shows it rather than a blank band');
      await finish(tester);
    });

    testWidgets('a reload that swaps one empty pool for another', (tester) async {
      await pump(tester, _landscape);
      await settleProviders(tester);

      expect(identical(projection.projectedLatestMovies, discover.latestMovies), isFalse, reason: 'the trap itself');
      expect(bandHeight(tester), pageTop);
      await finish(tester);
    });
  });

  test('a projection that fails tells its listeners, or a waiting page never hears it', () async {
    final failing = TvHomeProjectionProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: 'Continue Watching',
      latestMoviesTitle: 'Recently Released',
      featuredSelector: const _ThrowingSelector(),
    );
    var heard = 0;
    failing.addListener(() => heard++);

    await pumpEventQueue();

    expect(failing.isProjecting, isFalse);
    expect(failing.hasProjectedHero, isFalse);
    expect(heard, greaterThan(0));
  });

  group('hardware keyboard', () {
    Future<void> keyboardMode(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump();
    }

    IpadHomeHeroState hero(WidgetTester tester) => tester.state(find.byType(IpadHomeHero));

    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;

    for (final (name, size) in [('portrait', _portrait), ('landscape', _landscape)]) {
      testWidgets('the first arrow on an untouched page lands on the hero in $name', (tester) async {
        // iOS's own shortcuts carry this arrow: nothing holds the focus yet, and
        // the action bar is out of traversal, so the hero is the first stop.
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        aggregation.latestMovies = [_film('A')];
        await pump(tester, size);

        await press(tester, LogicalKeyboardKey.arrowDown);
        await tester.pump();

        final landed = focused();
        await finish(tester);
        debugDefaultTargetPlatformOverride = null;
        expect(landed, anyOf('mobileHeroPlay0', 'tvHeroPlay'));
      });
    }

    testWidgets('the card takes the arrows: across, to the next slide, and out', (tester) async {
      aggregation.latestMovies = [_film('A'), _film('B')];
      await pump(tester, _portrait);
      await keyboardMode(tester);

      expect(hero(tester).focusPlay(), isTrue);
      await tester.pump();
      expect(focused(), 'mobileHeroPlay0');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'mobileHeroSecondary0');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focused(), 'mobileHeroSecondary1');
      expect(find.text('B'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(seen, ['down', 'up']);
      await finish(tester);
    });

    testWidgets('the slide does not roll away from under the focus', (tester) async {
      aggregation.latestMovies = [_film('A'), _film('B')];
      await pump(tester, _portrait);
      await keyboardMode(tester);
      hero(tester).focusPlay();
      await tester.pump();

      await tester.pump(mobileHeroAutoAdvanceInterval + const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(focused(), 'mobileHeroPlay0');
      await finish(tester);
    });

    testWidgets('a turn keeps the focus on the hero, both ways', (tester) async {
      aggregation.latestMovies = [_film('A')];
      await pump(tester, _portrait);
      await keyboardMode(tester);
      hero(tester).focusPlay();
      await tester.pump();

      tester.view.physicalSize = _landscape;
      await tester.pump();
      await tester.pump();
      expect(tester.state<TvHeroBillboardCarouselState>(find.byType(TvHeroBillboardCarousel)).hasFocus, isTrue);

      tester.view.physicalSize = _portrait;
      await tester.pump();
      await tester.pump();
      expect(tester.state<MobileHeroCardState>(find.byType(MobileHeroCard)).hasFocus, isTrue);
      await finish(tester);
    });
  });

  testWidgets('nothing at all to show leaves only the page top, not an empty hero', (tester) async {
    await pump(tester, _portrait);

    expect(find.byType(MobileHeroCard), findsNothing);
    expect(find.byType(TvHeroBillboardCarousel), findsNothing);
    await finish(tester);
  });

  testWidgets('turning the iPad keeps the slide, both ways', (tester) async {
    aggregation.latestMovies = [_film('A'), _film('B'), _film('C')];
    await pump(tester, _portrait);

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 2000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('B'), findsOneWidget);

    tester.view.physicalSize = _landscape;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(billboardTitle(tester), 'B');

    await tester.fling(find.byType(TvHeroBillboardCard), const Offset(-400, 0), 1500);
    await tester.pump();
    expect(billboardTitle(tester), 'C');

    tester.view.physicalSize = _portrait;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('C'), findsOneWidget);
    expect(tester.widget<PageView>(find.byType(PageView)).controller?.page, 2);
    await finish(tester);
  });
}
