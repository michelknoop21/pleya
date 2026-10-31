/// What a detail page does while its data is on its way or did not come: the
/// list under a tab, the way back from a failure, and a cast that names one
/// person twice. Through the real screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_action_panel.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_cards.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_hero_widgets.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_page.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_tab_pill.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/pressable.dart';
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
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _movie(List<MediaRole> roles) => MediaItem(
  id: 'movie',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: 'Toy Story',
  durationMs: 6000000,
  roles: roles,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _season(int n, {int leafs = 3}) => MediaItem(
  id: 'season_$n',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.season,
  title: 'Season $n',
  index: n,
  parentId: 'show',
  leafCount: leafs,
  viewedLeafCount: 0,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _episode(int season, int n, {int? viewCount}) => MediaItem(
  id: 'e$season-$n',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.episode,
  title: 'Episode $n',
  index: n,
  parentIndex: season,
  parentId: 'season_$season',
  grandparentId: 'show',
  durationMs: 3000000,
  viewCount: viewCount,
  serverId: 'server_1',
  serverName: 'Server',
);

class _Client implements MediaServerClient {
  _Client({
    MediaItem? item,
    List<MediaItem>? seasons,
    Map<String, List<MediaItem>>? episodes,
    this.onDeck,
    this.fileInfo,
  }) : item = item ?? _show(),
       seasons = seasons ?? [_season(1), _season(2)],
       episodes =
           episodes ??
           {
             'season_1': [for (var i = 1; i <= 3; i++) _episode(1, i)],
             'season_2': [for (var i = 1; i <= 3; i++) _episode(2, i)],
           };

  final MediaItem item;
  final List<MediaItem> seasons;
  final Map<String, List<MediaItem>> episodes;
  final MediaItem? onDeck;
  final MediaFileInfo? fileInfo;

  /// A page of this parent waits here.
  final gates = <String, Completer<void>>{};

  /// The next read of these parents throws.
  final failOnce = <String>{};

  /// The next page after the first of any parent throws.
  var failNextLaterPage = false;
  var seasonsFail = false;

  /// What the server says it holds per parent, when it is more than it sends.
  final totals = <String, int>{};

  final pages = <String>[];
  final fileInfoFor = <String>[];

  @override
  ServerId get serverId => ServerId('server_1');
  @override
  String? get serverName => 'Server';
  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: item, onDeckEpisode: onDeck);
  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    if (seasonsFail && parentId == 'show') throw StateError('seasons did not load');
    return parentId == 'show' ? seasons : episodes[parentId] ?? const [];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final offset = start ?? 0;
    pages.add('$parentId@$offset');
    await gates[parentId]?.future;
    if (failOnce.remove(parentId)) throw StateError('page did not load');
    if (offset > 0 && failNextLaterPage) {
      failNextLaterPage = false;
      throw StateError('page did not load');
    }
    final all = parentId == 'show' ? seasons : episodes[parentId] ?? const <MediaItem>[];
    if (offset >= all.length) return LibraryPage<MediaItem>(items: const [], totalCount: all.length, offset: offset);
    final end = (offset + (totals.containsKey(parentId) ? 2 : (size ?? all.length))).clamp(0, all.length);
    return LibraryPage<MediaItem>(
      items: all.sublist(offset, end),
      totalCount: totals[parentId] ?? all.length,
      offset: offset,
    );
  }

  @override
  Future<List<MediaItem>> fetchExtras(String id) async => const [];
  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async {
    fileInfoFor.add(item.id);
    return fileInfo;
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => const [];
  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => LibraryPage<MediaItem>(
    items: [
      MediaItem(
        id: 'credit_$personId',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Credit of $personId',
        serverId: 'server_1',
      ),
    ],
    totalCount: 1,
    offset: 0,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String? get _focus => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pumpAndSettle();
}

/// One step, without waiting for a page that is held back.
Future<void> _step(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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

  Future<void> pumpDetail(WidgetTester tester, _Client client, {String? episode}) async {
    tester.view.physicalSize = _panel;
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
            builder: (context, child) => withProfileNavigationScope(
              child: InputModeTracker(
                child: MainScreenFocusScope(
                  focusSidebar: () {},
                  focusContent: () {},
                  isSidebarFocused: false,
                  sideNavigationWidth: 0,
                  child: TvDisplayMetrics(
                    size: _panel,
                    child: OverlaySheetHost(child: withNoticeLayer()(context, child)),
                  ),
                ),
              ),
            ),
            theme: monoTheme(dark: true),
            home: TvNestedRouteScope(
              dismiss: ([_]) {},
              markResult: (_) {},
              child: MediaDetailScreen(metadata: client.item, initialEpisodeId: episode),
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

  TvDetailPage page(WidgetTester tester) => tester.widget<TvDetailPage>(find.byType(TvDetailPage));

  Iterable<String> episodeRow(WidgetTester tester) => page(tester).sections.single.itemIds;

  Pressable playButton(WidgetTester tester) => tester.widget<Pressable>(
    find.ancestor(of: find.byType(TvDetailRoundButton).first, matching: find.byType(Pressable)).first,
  );

  group('a cast that names one person twice', () {
    const hanks = MediaRole(id: 'p1', tag: 'Tom Hanks', role: 'Woody');
    const hanksAgain = MediaRole(id: 'p1', tag: 'Tom Hanks', role: 'Narrator');
    const allen = MediaRole(id: 'p2', tag: 'Tim Allen', role: 'Buzz');

    testWidgets('gets one row of their own, and the next person the second', (tester) async {
      await pumpDetail(tester, _Client(item: _movie(const [hanks, hanksAgain, allen])));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _press(tester, LogicalKeyboardKey.arrowDown);

      expect(tester.takeException(), isNull);
      final ids = page(tester).sections.map((section) => section.id);
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, containsAll(['person:p1', 'person:p2']));
    });

    testWidgets('stands once in the cast, so RIGHT walks on instead of landing on itself', (tester) async {
      await pumpDetail(tester, _Client(item: _movie(const [hanks, allen, hanksAgain])));
      final cast = page(tester).sections.firstWhere((section) => section.id == 'cast');
      expect(cast.itemIds, ['p1', 'p2']);

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focus, 'TvDetailCard_cast(p1)');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focus, 'TvDetailCard_cast(p2)');
    });

    testWidgets('two people without an id both stay', (tester) async {
      await pumpDetail(
        tester,
        _Client(
          item: _movie(const [MediaRole(tag: 'One', role: 'A'), MediaRole(tag: 'Two', role: 'B')]),
        ),
      );

      expect(page(tester).sections.firstWhere((section) => section.id == 'cast').itemIds, ['role-0', 'role-1']);
    });
  });

  group('a season tab whose first page is on its way', () {
    testWidgets('shows only its own card, and Play waits for the page', (tester) async {
      final client = _Client()..gates['season_2'] = Completer<void>();
      await pumpDetail(tester, client);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(episodeRow(tester), ['season_1', 'e1-1', 'e1-2', 'e1-3']);

      await _step(tester, LogicalKeyboardKey.arrowRight);

      expect(episodeRow(tester), ['season_2']);
      expect(playButton(tester).onTap, isNull);

      client.gates['season_2']!.complete();
      await tester.pumpAndSettle();
      expect(episodeRow(tester), ['season_2', 'e2-1', 'e2-2', 'e2-3']);
      expect(playButton(tester).onTap, isNotNull);
    });

    testWidgets('a tab stepped back to has its cards at once', (tester) async {
      final client = _Client();
      await pumpDetail(tester, client);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowRight);

      await _step(tester, LogicalKeyboardKey.arrowLeft);

      expect(episodeRow(tester), ['season_1', 'e1-1', 'e1-2', 'e1-3']);
      await tester.pumpAndSettle();
    });
  });

  group('the retry card', () {
    List<MediaItem> oneSeason = const [];
    setUp(() => oneSeason = [_season(1)]);

    testWidgets('a series without seasons of its own: a first load that failed has a way back', (tester) async {
      final client = _Client(seasons: oneSeason)..failOnce.add('season_1');
      await pumpDetail(tester, client);

      expect(find.text('Episodes'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(episodeRow(tester), ['retry']);

      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.enter);

      expect(episodeRow(tester), ['e1-1', 'e1-2', 'e1-3']);
    });

    testWidgets('a series without seasons of its own: a later page is read again', (tester) async {
      final client = _Client(seasons: oneSeason)
        ..totals['season_1'] = 3
        ..failNextLaterPage = true;
      await pumpDetail(tester, client);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      page(tester).sections.single.onLoadMore!();
      await tester.pumpAndSettle();
      expect(episodeRow(tester).last, 'retry');

      client.pages.clear();
      tester.widget<TvDetailViewAllCard>(find.byType(TvDetailViewAllCard)).onSelect();
      await tester.pumpAndSettle();

      expect(client.pages, ['season_1@2']);
      expect(episodeRow(tester), ['e1-1', 'e1-2', 'e1-3']);
    });

    testWidgets('a season: a later page is read again', (tester) async {
      final client = _Client()
        ..totals['season_1'] = 3
        ..totals['season_2'] = 3
        ..failNextLaterPage = true;
      await pumpDetail(tester, client);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      page(tester).sections.single.onLoadMore!();
      await tester.pumpAndSettle();
      expect(episodeRow(tester).last, 'retry');

      client.pages.clear();
      tester.widget<TvDetailViewAllCard>(find.byType(TvDetailViewAllCard)).onSelect();
      await tester.pumpAndSettle();

      expect(client.pages, hasLength(1));
      expect(episodeRow(tester).last, isNot('retry'));
      expect(episodeRow(tester), hasLength(4));
    });

    testWidgets('a deep link while the seasons fail leaves a way to try again', (tester) async {
      final client = _Client()..seasonsFail = true;
      await pumpDetail(tester, client, episode: 'e1-1');

      expect(find.text(t.common.retry), findsOneWidget);
      client.seasonsFail = false;
      tester.widget<TvDetailViewAllCard>(find.byType(TvDetailViewAllCard)).onSelect();
      await tester.pumpAndSettle();

      expect(page(tester).sections.single.itemIds, contains('e1-1'));
    });
  });

  testWidgets('a season tab reads the tracks of the episode Play starts there', (tester) async {
    final client = _Client(
      onDeck: _episode(1, 2),
      episodes: {
        'season_1': [_episode(1, 1, viewCount: 1), _episode(1, 2), _episode(1, 3)],
        'season_2': [_episode(2, 1, viewCount: 1), _episode(2, 2), _episode(2, 3)],
      },
    );
    await pumpDetail(tester, client);
    expect(client.fileInfoFor.last, 'e1-2');

    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(tester.widget<TvDetailTabPill>(find.widgetWithText(TvDetailTabPill, 'Season 2')).active, isTrue);
    expect(client.fileInfoFor.last, 'e2-2');
  });

  testWidgets('Meer acties offers no tracks of another season while this one loads', (tester) async {
    final client = _Client(
      fileInfo: MediaFileInfo(
        audioTracks: [MediaAudioTrack(id: 1, languageCode: 'eng', codec: 'eac3', channels: 6, selected: true)],
      ),
    )..gates['season_2'] = Completer<void>();
    await pumpDetail(tester, client);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 8 && _focus != 'detail_more'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(_focus, 'detail_more');
    await _press(tester, LogicalKeyboardKey.enter);

    final rows = tester.widget<TvDetailActionPanel>(find.byType(TvDetailActionPanel).last).rows.map((row) => row.id);
    expect(rows, isNot(contains('audio')));
    client.gates['season_2']!.complete();
    await tester.pumpAndSettle();
  });
}
