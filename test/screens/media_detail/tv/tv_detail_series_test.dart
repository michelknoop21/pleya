/// The series on [TvDetailPage], through the real screen: the tabs of 03 and 01,
/// the row of seasons of 04, and every way in and out of a season.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_episode_card.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_hero_widgets.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_layout.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_page.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_tab_pill.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_navigation_helper.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/profile_navigation.dart';

const Size _panel = Size(1038, 584);

MediaItem _show() => MediaItem(
  id: 'show',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.show,
  title: 'MobLand',
  summary: 'Power is up for grabs.',
  year: 2025,
  genres: const ['Crime'],
  roles: const [MediaRole(id: 'p1', tag: 'Tom Hardy', role: 'Harry')],
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _season(int n, {int leafs = 3, int watched = 0}) => MediaItem(
  id: 'season_$n',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.season,
  title: 'Season $n',
  summary: 'What season $n is about.',
  index: n,
  parentId: 'show',
  leafCount: leafs,
  viewedLeafCount: watched,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _episode(int season, int n, {int? offset}) => MediaItem(
  id: 'e$season-$n',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.episode,
  title: 'Episode $n',
  summary: 'What episode $n of season $season is about.',
  index: n,
  parentIndex: season,
  parentId: 'season_$season',
  grandparentId: 'show',
  durationMs: 3000000,
  viewOffsetMs: offset,
  serverId: 'server_1',
  serverName: 'Server',
);

class _Client implements MediaServerClient {
  _Client({
    List<MediaItem>? seasons,
    Map<String, List<MediaItem>>? episodes,
    this.seasonsFail = false,
    this.hubs = const [],
    this.show,
  }) : seasons = seasons ?? [_season(1, watched: 3), _season(2)],
       episodes =
           episodes ??
           {
             'season_1': [for (var i = 1; i <= 3; i++) _episode(1, i)],
             'season_2': [for (var i = 1; i <= 3; i++) _episode(2, i)],
           };

  final List<MediaItem> seasons;
  final Map<String, List<MediaItem>> episodes;
  final bool seasonsFail;
  final List<MediaHub> hubs;
  final MediaItem? show;
  final pageCalls = <String>[];

  @override
  ServerId get serverId => ServerId('server_1');
  @override
  String? get serverName => 'Server';
  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async => (
    item: episodes.values.expand((list) => list).where((episode) => episode.id == id).firstOrNull ?? show ?? _show(),
    onDeckEpisode: null,
  );
  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    if (seasonsFail) throw StateError('seasons did not load');
    return parentId == 'show' ? seasons : episodes[parentId] ?? const [];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    pageCalls.add(parentId);
    final all = parentId == 'show' ? seasons : episodes[parentId] ?? const <MediaItem>[];
    final offset = start ?? 0;
    final end = (offset + (size ?? all.length)).clamp(0, all.length);
    return LibraryPage<MediaItem>(
      items: offset >= all.length ? const [] : all.sublist(offset, end),
      totalCount: all.length,
      offset: offset,
    );
  }

  @override
  Future<List<MediaItem>> fetchExtras(String id) async => const [];
  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async => null;
  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => hubs;
  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => const LibraryPage<MediaItem>(items: [], totalCount: 0, offset: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? get _focus => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int bar;
  late int dismissed;

  setUp(() {
    bar = 0;
    dismissed = 0;
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() {
    resetNotices();
    TvDetectionService.debugSetAppleTVOverride(null);
    MediaDetailScreen.debugOnPlayEpisode = null;
  });

  Future<void> pumpDetail(
    WidgetTester tester,
    _Client client, {
    String? episode,
    int? season,
    String? seasonId,
    Size window = _panel,
    MediaItem? show,
    UnifiedMediaRouteContext? unified,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await SettingsService.getInstance();
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            // Above the Navigator: an episode opened from this page is a route
            // of its own and needs the same scopes.
            builder: (context, child) => withProfileNavigationScope(
              child: InputModeTracker(
                child: MainScreenFocusScope(
                  focusSidebar: () => bar++,
                  focusContent: () {},
                  isSidebarFocused: false,
                  sideNavigationWidth: 0,
                  child: TvDisplayMetrics(size: _panel, child: withNoticeLayer()(context, child)),
                ),
              ),
            ),
            theme: monoTheme(dark: true),
            home: TvNestedRouteScope(
              dismiss: ([_]) => dismissed++,
              markResult: (_) {},
              child: MediaDetailScreen(
                metadata: show ?? _show(),
                initialEpisodeId: episode,
                initialSeasonIndex: season,
                initialSeasonId: seasonId,
                unifiedRouteContext: unified,
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  Iterable<TvDetailTabPill> pills(WidgetTester tester) =>
      tester.widgetList<TvDetailTabPill>(find.byType(TvDetailTabPill));

  BoxDecoration pillDecoration(WidgetTester tester, String label) =>
      tester
              .widget<AnimatedContainer>(
                find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer)).first,
              )
              .decoration!
          as BoxDecoration;

  testWidgets('a series opens on the page, Serie open and the white pill on it', (tester) async {
    await pumpDetail(tester, _Client());

    expect(find.byType(TvDetailPage), findsOneWidget);
    expect(find.byType(TvBrowseRail), findsNothing);
    expect(pills(tester).map((pill) => pill.label), ['Series', 'Season 1', 'Season 2']);
    expect(pills(tester).map((pill) => pill.active), [true, false, false]);
    expect(_focus, 'detail_tab_series');
    expect(pillDecoration(tester, 'Series').color, Colors.white);
  });

  testWidgets('RIGHT opens the next season in this same screen', (tester) async {
    await pumpDetail(tester, _Client());
    final state = tester.state(find.byType(MediaDetailScreen));

    await _press(tester, LogicalKeyboardKey.arrowRight);

    expect(tester.state(find.byType(MediaDetailScreen)), same(state));
    expect(find.byType(MediaDetailScreen), findsOneWidget);
    expect(pills(tester).map((pill) => pill.active), [false, true, false]);
    expect(find.text('What season 1 is about.'), findsOneWidget);
    expect(find.text('Tom Hardy'), findsNothing, reason: 'cast belongs to the Serie tab');

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(pills(tester).map((pill) => pill.active), [false, false, true]);
    expect(find.text('What season 2 is about.'), findsOneWidget);
    expect(_focus, 'season_tab_1');

    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focus, 'season_tab_1', reason: 'the last tab keeps the press');
  });

  testWidgets('the open tab is outlined once the focus left it, and filled again when it returns', (tester) async {
    await pumpDetail(tester, _Client());
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowDown);

    final outlined = pillDecoration(tester, 'Season 1');
    expect(outlined.color, Colors.transparent);
    expect((outlined.border! as Border).top.color, isNot(Colors.transparent));

    final idle = pillDecoration(tester, 'Season 2');
    expect(idle.color, Colors.transparent);
    expect((idle.border! as Border).top.color, Colors.transparent);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focus, 'season_tab_0');
    expect(pillDecoration(tester, 'Season 1').color, Colors.white);
  });

  testWidgets('UP from the tabs reaches the top bar', (tester) async {
    await pumpDetail(tester, _Client());

    await _press(tester, LogicalKeyboardKey.arrowUp);

    expect(bar, 1);
  });

  testWidgets('the Serie tab walks tabs, actions, seasons, cast, and back up the same way', (tester) async {
    await pumpDetail(tester, _Client());

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus, 'play_button');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus, contains('TvDetailCard_seasons'));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus, contains('TvDetailCard_cast'));

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focus, contains('TvDetailCard_seasons'));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focus, 'play_button');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focus, 'detail_tab_series');
    expect(bar, 0);
  });

  testWidgets('a section back up sends the page to offset 0 on the actions and on the tabs', (tester) async {
    await pumpDetail(tester, _Client());

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, greaterThan(0));

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(scrollable.position.pixels, 0);
  });

  testWidgets('season posters carry their name, their count and a tick when watched', (tester) async {
    await pumpDetail(tester, _Client());
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);

    expect(find.text('2 seasons'), findsOneWidget);
    expect(find.text('3 episodes'), findsNWidgets(2));
    final sections = tester.widget<TvDetailPage>(find.byType(TvDetailPage)).sections;
    expect(sections.map((section) => section.title).first, '2 seasons');
  });

  testWidgets('Select on a poster opens that season, and Menu comes back to the poster', (tester) async {
    await pumpDetail(tester, _Client());
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);

    await _press(tester, LogicalKeyboardKey.enter);
    expect(pills(tester).map((pill) => pill.active), [false, false, true]);
    expect(_focus, contains('TvDetailCard_episodes'));

    await _press(tester, LogicalKeyboardKey.escape);
    expect(dismissed, 0);
    expect(pills(tester).map((pill) => pill.active), [true, false, false]);
    expect(_focus, 'TvDetailCard_seasons(season_2)');

    await _press(tester, LogicalKeyboardKey.escape);
    expect(dismissed, 1);
  });

  testWidgets('Menu on the Serie tab closes the page, from anywhere on it', (tester) async {
    await pumpDetail(tester, _Client());
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);

    await _press(tester, LogicalKeyboardKey.escape);

    expect(dismissed, 1);
  });

  testWidgets('a deep link opens the season tab on that episode, and Menu leaves the page', (tester) async {
    await pumpDetail(tester, _Client(), episode: 'e2-3', season: 2, seasonId: 'season_2');

    expect(pills(tester).map((pill) => pill.active), [false, false, true]);
    expect(_focus, 'TvDetailCard_episodes(e2-3)');

    await _press(tester, LogicalKeyboardKey.escape);
    expect(dismissed, 1);
  });

  testWidgets('a deep link past the first page keeps paging until it lands', (tester) async {
    final client = _Client(
      episodes: {
        'season_1': [for (var i = 1; i <= 3; i++) _episode(1, i)],
        'season_2': [for (var i = 1; i <= 230; i++) _episode(2, i)],
      },
    );
    await pumpDetail(tester, client, episode: 'e2-225', season: 2, seasonId: 'season_2');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(_focus, 'TvDetailCard_episodes(e2-225)');
  });

  testWidgets('a link to an episode that is gone falls back to the season', (tester) async {
    await pumpDetail(tester, _Client(), episode: 'gone', season: 2, seasonId: 'season_2');

    expect(pills(tester).map((pill) => pill.active), [false, false, true]);
    expect(_focus, contains('TvDetailCard_episodes'));
  });

  group('Select on an episode follows Episode Action', () {
    late List<String> played;

    Iterable<MediaDetailScreen> pages(WidgetTester tester) =>
        tester.widgetList<MediaDetailScreen>(find.byType(MediaDetailScreen, skipOffstage: false));

    Future<void> setAction(EpisodeAction action) async {
      played = [];
      MediaDetailScreen.debugOnPlayEpisode = (episode) => played.add(episode.id);
      await SettingsService.getInstance();
      await SettingsService.instance.write(SettingsService.episodeAction, action);
    }

    testWidgets('play starts the episode and opens nothing', (tester) async {
      await setAction(EpisodeAction.play);
      await pumpDetail(tester, _Client(), episode: 'e2-2', season: 2, seasonId: 'season_2');

      await _press(tester, LogicalKeyboardKey.enter);

      expect(played, ['e2-2']);
      expect(pages(tester), hasLength(1));
    });

    testWidgets('details opens the episode itself, not this series a second time', (tester) async {
      await setAction(EpisodeAction.details);
      await pumpDetail(tester, _Client(), episode: 'e2-2', season: 2, seasonId: 'season_2');

      await _press(tester, LogicalKeyboardKey.enter);

      expect(played, isEmpty);
      expect(pages(tester).map((page) => page.metadata.id), ['show', 'e2-2']);
      expect(pages(tester).last.initialEpisodeId, isNull);
      expect(
        find.descendant(
          of: find.byType(MediaDetailScreen).last,
          matching: find.text('What episode 2 of season 2 is about.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('details on a title across servers keeps the choice, read-only', (tester) async {
      await setAction(EpisodeAction.details);
      final page = _show();
      final other = page.copyWith(id: 'other_show', serverId: 'server_2', serverName: 'Attic');
      UnifiedMediaSource source(MediaItem item) => UnifiedMediaSource(
        sourceKey: item.globalKey,
        item: item,
        serverId: ServerId(item.serverId!),
        serverName: item.serverName!,
        backend: item.backend,
      );
      final route = UnifiedMediaRouteContext(
        groupId: 'g',
        identity: CanonicalMediaIdentity.movie(title: 'MobLand', year: 2025),
        sourceKey: page.globalKey,
        availableSourceKeys: [page.globalKey, other.globalKey],
        titleSources: [source(page), source(other)],
        coverage: SourceCoverageState.complete({page.globalKey, other.globalKey}),
        intent: UnifiedActivationIntent.details,
      );
      await pumpDetail(tester, _Client(), episode: 'e2-2', season: 2, seasonId: 'season_2', unified: route);

      await _press(tester, LogicalKeyboardKey.enter);

      expect(pages(tester).map((page) => page.metadata.id), ['show', 'e2-2']);
      expect(pages(tester).last.unifiedRouteContext?.groupId, 'g');
      expect(pages(tester).last.onChangeSource, isNull);
    });

    testWidgets('an episode of this series on a row of the page follows the same setting', (tester) async {
      await setAction(EpisodeAction.play);
      final hubs = [
        MediaHub(id: 'ondeck', title: 'On deck', type: 'episode', items: [_episode(1, 2)]),
      ];
      await pumpDetail(tester, _Client(hubs: hubs));
      for (var i = 0; i < 4; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(_focus, contains('hub:ondeck'));

      await _press(tester, LogicalKeyboardKey.enter);
      expect(played, ['e1-2']);
      expect(pages(tester), hasLength(1));

      await SettingsService.instance.write(SettingsService.episodeAction, EpisodeAction.details);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(played, ['e1-2']);
      expect(pages(tester).map((page) => page.metadata.id), ['show', 'e1-2']);
    });

    test('the target of an episode opened on its own series is the episode, and only then', () {
      final episode = _episode(1, 2);

      final own = mediaDetailNavigationTargetFor(episode, openEpisodeItself: true);
      expect(own.metadata.id, 'e1-2');
      expect(own.initialEpisodeId, isNull);
      expect(tvDetailRouteId(own), isNot(contains('_e')));

      final series = mediaDetailNavigationTargetFor(episode);
      expect(series.metadata.id, 'show');
      expect(series.initialEpisodeId, 'e1-2');
    });
  });

  testWidgets('focus on an episode puts its summary in the hero, the actions give it back', (tester) async {
    await pumpDetail(tester, _Client(), episode: 'e2-2', season: 2, seasonId: 'season_2');

    expect(find.text('What episode 2 of season 2 is about.'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('What episode 3 of season 2 is about.'), findsOneWidget);
    expect(find.text('What episode 2 of season 2 is about.'), findsNothing);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus, 'play_button');
    expect(find.text('What season 2 is about.'), findsOneWidget);
  });

  testWidgets('the tab above the row is still the episode: only the actions give the summary back', (tester) async {
    await pumpDetail(tester, _Client(), episode: 'e2-2', season: 2, seasonId: 'season_2');

    await _press(tester, LogicalKeyboardKey.arrowUp);

    expect(_focus, 'season_tab_1');
    expect(find.text('What episode 2 of season 2 is about.'), findsOneWidget);
    expect(find.text('What season 2 is about.'), findsNothing);
  });

  testWidgets('a season gets back the card it was left on, per season', (tester) async {
    await pumpDetail(tester, _Client());
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focus, 'TvDetailCard_episodes(e1-3)');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focus, 'season_tab_1', reason: 'the row that emptied under the tab must not take the focus');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus, 'TvDetailCard_episodes(e2-1)', reason: 'season 2 was never walked: under the tab, not on e2-3');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus, 'TvDetailCard_episodes(e1-3)');
  });

  group('a season tab, as 01 draws it', () {
    const pt = 584 / 1080;

    testWidgets('the tabs, then the row, then the actions, and back up the same way', (tester) async {
      await pumpDetail(tester, _Client());
      await _press(tester, LogicalKeyboardKey.arrowRight);

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focus, 'TvDetailCard_episodes(season_1)');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focus, 'play_button');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focus, 'play_button', reason: 'nothing is left under the actions');

      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focus, 'TvDetailCard_episodes(season_1)');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focus, 'season_tab_0');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(bar, 1);
    });

    testWidgets('the page stays on offset 0 and everything sits on the height of 01', (tester) async {
      await pumpDetail(tester, _Client());
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);

      expect(scrollable.position.pixels, 0);
      expect(tester.getTopLeft(find.byType(TvDetailEpisodeCard).first).dy / pt, closeTo(592 * 0.96, 6));
      expect(tester.getSize(find.byType(TvDetailEpisodeCard).first).width / pt, closeTo(533 * 0.96, 1));
      expect(find.text('What season 1 is about.'), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(scrollable.position.pixels, 0);
      final actions = tester.getCenter(find.byType(TvDetailRoundButton).first);
      expect(actions.dy / pt, closeTo(968 * 0.96, 8));
      expect(actions.dx, lessThan(_panel.width / 3));
    });

    testWidgets('a page too tall for its box stays on 0 under the row, and the actions bring in the rest', (
      tester,
    ) async {
      await pumpDetail(tester, _Client(), window: const Size(1038, 480));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scrollable.position.maxScrollExtent, greaterThan(0), reason: 'this test needs a page that can scroll');

      expect(_focus, 'TvDetailCard_episodes(season_1)');
      expect(scrollable.position.pixels, 0);

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);

      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focus, 'TvDetailCard_episodes(season_1)');
      expect(scrollable.position.pixels, 0);
    });

    testWidgets('the row keeps its height when the summary changes length', (tester) async {
      await pumpDetail(tester, _Client());
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final before = tester.getTopLeft(find.byType(TvDetailEpisodeCard).first).dy;

      await _press(tester, LogicalKeyboardKey.arrowRight);

      expect(tester.getTopLeft(find.byType(TvDetailEpisodeCard).first).dy, before);
    });

    testWidgets('the cards carry A1, a tick, and the name of the season in front', (tester) async {
      await pumpDetail(
        tester,
        _Client(
          episodes: {
            'season_1': [_episode(1, 1).copyWith(viewCount: 1), _episode(1, 2)],
            'season_2': const [],
          },
        ),
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);

      final cards = tester.widgetList<TvDetailEpisodeCard>(find.byType(TvDetailEpisodeCard)).toList();
      expect(cards.map((card) => card.badge), ['Season 1', 'E1', 'E2']);
      expect(cards.map((card) => card.watched), [false, true, false]);
    });

    testWidgets('the name line says which episode the ring is on', (tester) async {
      await pumpDetail(tester, _Client(), episode: 'e2-2', season: 2, seasonId: 'season_2');

      expect(find.text('Season 2 • E2 • Episode 2'), findsOneWidget);
    });

    testWidgets('Select on the season card plays its next episode', (tester) async {
      final played = <String>[];
      MediaDetailScreen.debugOnPlayEpisode = (episode) => played.add(episode.id);
      await pumpDetail(
        tester,
        _Client(
          episodes: {
            'season_1': [_episode(1, 1).copyWith(viewCount: 1), _episode(1, 2)],
            'season_2': const [],
          },
        ),
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowDown);

      await _press(tester, LogicalKeyboardKey.enter);

      expect(played, ['e1-2']);
    });

    testWidgets('the ring on the play button reads the episode it resumes', (tester) async {
      await pumpDetail(
        tester,
        _Client(
          episodes: {
            'season_1': [_episode(1, 1, offset: 1500000)],
            'season_2': const [],
          },
        ),
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);

      final ring = tester.widget<TvDetailProgressRing>(find.byType(TvDetailProgressRing));
      expect(ring.value, closeTo(0.5, 0.001));
    });

    testWidgets('Menu on the actions of a walked-in season goes back to the Serie tab', (tester) async {
      await pumpDetail(tester, _Client());
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);

      await _press(tester, LogicalKeyboardKey.escape);

      expect(dismissed, 0);
      expect(pills(tester).map((pill) => pill.active), [true, false, false]);
      expect(_focus, 'TvDetailCard_seasons(season_1)');
    });

    testWidgets('a popped route gets its episode back through the restore host', (tester) async {
      await pumpDetail(tester, _Client(), episode: 'e2-1', season: 2, seasonId: 'season_2');

      final host = tester.state(find.byType(MediaDetailScreen)) as TvFocusRestoreHost;
      expect(host.restoreTvFocus(const TvFocusRestoreTarget(itemId: 'e2-3', containerId: 'episodes')), isTrue);
      await tester.pumpAndSettle();

      expect(_focus, 'TvDetailCard_episodes(e2-3)');
    });
  });

  testWidgets('a tab stepped back to reads its pager: no second first page', (tester) async {
    final client = _Client();
    await pumpDetail(tester, client);

    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(tester.widget<TvDetailPage>(find.byType(TvDetailPage)).sections.single.itemIds, [
      'season_1',
      'e1-1',
      'e1-2',
      'e1-3',
    ]);
    await _press(tester, LogicalKeyboardKey.arrowRight);

    expect(client.pageCalls.where((id) => id == 'season_1'), hasLength(1));
    expect(client.pageCalls.where((id) => id == 'season_2'), hasLength(1));
    final page = tester.widget<TvDetailPage>(find.byType(TvDetailPage));
    expect(page.sections.single.itemIds, ['season_2', 'e2-1', 'e2-2', 'e2-3']);
  });

  testWidgets('a series without seasons of its own gets one Episodes tab', (tester) async {
    await pumpDetail(
      tester,
      _Client(
        seasons: [_season(1)],
        episodes: {
          'season_1': [for (var i = 1; i <= 2; i++) _episode(1, i)],
        },
      ),
    );

    expect(pills(tester).map((pill) => pill.label), ['Series', 'Episodes']);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focus, 'detail_tab_episodes');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focus, 'TvDetailCard_episodes(e1-1)');
  });

  testWidgets('seasons that did not load leave a way to try again', (tester) async {
    await pumpDetail(tester, _Client(seasonsFail: true));

    expect(find.text('Retry'), findsWidgets);
    expect(pills(tester).map((pill) => pill.label), ['Series']);
  });

  testWidgets('the Serie tab keeps its focus on the tabs when a tab is stepped back to', (tester) async {
    await pumpDetail(tester, _Client());
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowLeft);

    expect(_focus, 'detail_tab_series');
    expect(tester.takeException(), isNull);
    expect(find.text('Power is up for grabs.'), findsOneWidget);
  });

  group('the tabs and the actions keep their place (DET2, DET4)', () {
    final longSummary = List.filled(40, 'A sentence that keeps the synopsis running.').join(' ');
    MediaItem longShow() => _show().copyWith(
      title: 'A Very Long Series Title For Overflow Testing',
      summary: longSummary,
      genres: const ['Drama', 'Mystery', 'Crime', 'Thriller'],
      roles: [for (var i = 0; i < 8; i++) MediaRole(id: 'p$i', tag: 'Person $i', role: 'Role $i')],
    );

    for (final (name, window) in [('full window', _panel), ('box under a bar', const Size(1038, 480))]) {
      testWidgets('$name: title, synopsis and the actions stay on the first screen', (tester) async {
        final show = longShow();
        await pumpDetail(
          tester,
          _Client(show: show),
          window: window,
          show: show,
        );

        expect(tester.takeException(), isNull);
        expect(find.text(show.title!), findsWidgets);
        final synopsis = tester.widget<Text>(find.text(longSummary));
        expect(synopsis.maxLines, greaterThanOrEqualTo(1));
        expect(tester.getBottomLeft(find.text(longSummary)).dy, lessThan(window.height));
        final actions = tester.getRect(find.byType(TvDetailRoundButton).first);
        expect(actions.bottom, lessThanOrEqualTo(window.height));
      });
    }

    testWidgets('a tab wants no more height than the row reserves for it', (tester) async {
      await pumpDetail(tester, _Client());

      final band = find.byWidgetPredicate((w) => w is AutomationNode && w.id == AutomationIds.mediaDetailTabs);
      final pill = find.byType(TvDetailTabPill).first;
      final wanted = tester.renderObject<RenderBox>(pill).getMaxIntrinsicHeight(double.infinity);

      expect(wanted, lessThanOrEqualTo(tester.getSize(band).height));
      expect(
        wanted,
        closeTo(tester.getSize(band).height, 0.5),
        reason: 'the pill is the row: nothing is clipped off it',
      );
    });
  });

  test('the tab row reads the height of 03', () {
    expect(TvDetailLayout.tabsTop + TvDetailLayout.tabHeight / 2, closeTo(67 * 0.96, 1));
  });
}
