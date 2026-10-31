/// Discussies (northstars 04, 05, 07, 08) through the real screen: when Trakt
/// is asked, what a card says, and every way the section stays away.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_review.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/trakt_account_provider.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_discussion_card.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_layout.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_page.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/trakt/trakt_comments_client.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/profile_navigation.dart';

const Size _panel = Size(1038, 584);
const double _pt = 584 / 1080;

final String _longText = List.filled(40, 'A reaction that keeps on going.').join(' ');

MediaItem _film() => MediaItem.plex(
  id: 'film',
  kind: MediaKind.movie,
  title: 'Puss in Boots',
  summary: 'A cat with one life left.',
  roles: const [MediaRole(id: 'p1', tag: 'Antonio Banderas', role: 'Puss')],
  reviews: const [MediaReview(author: 'Amy', text: 'Funny.', source: 'FilmWeek')],
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _show() => MediaItem(
  id: 'show',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.show,
  title: 'MobLand',
  summary: 'Power is up for grabs.',
  roles: const [MediaRole(id: 'p1', tag: 'Tom Hardy', role: 'Harry')],
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _season(int n) => MediaItem(
  id: 'season_$n',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.season,
  title: 'Season $n',
  index: n,
  parentId: 'show',
  serverId: 'server_1',
  serverName: 'Server',
);

class _Client implements MediaServerClient {
  _Client(this.item, {this.ids = const ExternalIds(imdb: 'tt1'), this.seasons = const []});

  final MediaItem item;
  final ExternalIds ids;
  final List<MediaItem> seasons;
  var idCalls = 0;
  final personCalls = <String>[];

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
      (item: item, onDeckEpisode: null);
  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    idCalls++;
    return ids;
  }

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async => parentId == 'show' ? seasons : const [];
  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final all = parentId == 'show' ? seasons : const <MediaItem>[];
    return LibraryPage<MediaItem>(items: all, totalCount: all.length, offset: 0);
  }

  @override
  Future<List<MediaItem>> fetchExtras(String id) async => const [];
  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async => null;
  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => const [];

  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    personCalls.add(personId);
    return LibraryPage<MediaItem>(
      items: [
        MediaItem(id: 'credit_$personId', backend: MediaBackend.jellyfin, kind: MediaKind.movie, serverId: 'server_1'),
      ],
      totalCount: 1,
      offset: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _comment(int id, String text, {int likes = 0, bool spoiler = false}) => {
  'id': id,
  'comment': text,
  'spoiler': spoiler,
  'likes': likes,
  'created_at': '2026-07-19T12:00:00.000Z',
  'user': {'username': 'vineetapathak', 'name': null},
};

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late Map<String, Object> routes;
  Completer<void>? traktGate;

  void useTrakt({String clientId = 'app-key'}) {
    TraktCommentsClient.shared = TraktCommentsClient(
      clientId: clientId,
      httpClient: MockClient((request) async {
        requests.add(request);
        await traktGate?.future;
        final body = routes[request.url.path];
        return body == null
            ? http.Response('{}', 404)
            : http.Response.bytes(utf8.encode(jsonEncode(body)), body is String ? 500 : 200);
      }),
    );
  }

  setUp(() {
    requests = [];
    routes = {};
    traktGate = null;
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    useTrakt();
  });

  tearDown(() {
    resetNotices();
    TvDetectionService.debugSetAppleTVOverride(null);
    TraktCommentsClient.shared = TraktCommentsClient();
  });

  Future<void> pumpDetail(
    WidgetTester tester,
    _Client client, {
    bool kids = false,
    bool kidsCheckThrows = false,
  }) async {
    tester.view.physicalSize = _panel;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await SettingsService.getInstance();
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);
    final account = TraktAccountProvider(
      kidsProfileCheck: () async => kidsCheckThrows ? throw StateError('no profile') : kids,
    );
    addTearDown(account.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
            ChangeNotifierProvider<TraktAccountProvider>.value(value: account),
          ],
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
              child: MediaDetailScreen(metadata: client.item),
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

  List<String> sectionIds(WidgetTester tester) =>
      tester.widget<TvDetailPage>(find.byType(TvDetailPage)).sections.map((section) => section.id).toList();

  Text textIn(WidgetTester tester, Finder card, String text) =>
      tester.widget<Text>(find.descendant(of: card, matching: find.text(text)));

  /// Near the end of the page, from wherever it opened.
  Future<void> walkDown(WidgetTester tester, {int steps = 3}) async {
    for (var i = 0; i < steps; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
  }

  testWidgets('a film: name, date, text, a number of likes, between reviews and the rows under them', (tester) async {
    routes['/movies/tt1/comments/likes'] = [_comment(1, 'Puss in Boots', likes: 6)];
    await pumpDetail(tester, _Client(_film()));
    await walkDown(tester);

    final ids = sectionIds(tester);
    expect(ids.indexOf('discussions'), ids.indexOf('reviews') + 1);
    expect(find.text('Discussions'), findsOneWidget);
    expect(find.text('vineetapathak'), findsOneWidget);
    expect(find.text('Puss in Boots'), findsWidgets);
    expect(find.textContaining('6 likes'), findsOneWidget);

    final card = find.byType(TvDetailDiscussionCard);
    expect(tester.getSize(card).width / _pt, closeTo(TvDetailLayout.wideCardWidth, 1));
    expect(
      find.descendant(of: card, matching: find.byType(IconButton)),
      findsNothing,
      reason: 'no like button',
    );
    expect(
      tester.widget<TvDetailDiscussionCard>(card).titleContext,
      isNull,
      reason: 'on a film the page is the context',
    );
    expect(requests.single.headers.containsKey('Authorization'), isFalse);
    expect(tester.widget<Text>(find.text('vineetapathak')).maxLines, 1);
    expect(textIn(tester, card, 'Puss in Boots').maxLines, 3);
  });

  testWidgets('Select opens the whole text in a panel, and Menu comes back to the card', (tester) async {
    routes['/movies/tt1/comments/likes'] = [_comment(1, _longText)];
    await pumpDetail(tester, _Client(_film()));
    await walkDown(tester);
    final before = FocusManager.instance.primaryFocus;

    await _press(tester, LogicalKeyboardKey.enter);

    final full = tester.widgetList<Text>(find.text(_longText)).where((text) => text.maxLines == null);
    expect(full, hasLength(1));

    await _press(tester, LogicalKeyboardKey.escape);
    expect(FocusManager.instance.primaryFocus, same(before));
  });

  testWidgets('a series reads its seasons too, and a card says which it is on', (tester) async {
    routes['/shows/tt1/comments/likes'] = [_comment(1, 'On the series', likes: 2)];
    routes['/shows/tt1/seasons/2/comments/likes'] = [_comment(2, 'On a season', likes: 9)];
    await pumpDetail(tester, _Client(_show(), seasons: [_season(0), _season(1), _season(2)]));
    await walkDown(tester, steps: 4);

    final cards = tester.widgetList<TvDetailDiscussionCard>(find.byType(TvDetailDiscussionCard)).toList();
    expect(cards.map((card) => card.titleContext), ['S2 • MobLand', 'MobLand']);
    expect(
      textIn(tester, find.byType(TvDetailDiscussionCard).first, 'On a season').maxLines,
      2,
      reason: 'the context line costs a line of text, or the last one is cut off',
    );
    expect(requests.map((request) => request.url.path), isNot(contains('/shows/tt1/seasons/0/comments/likes')));
  });

  testWidgets('without an IMDb id the title goes through the TMDB lookup', (tester) async {
    routes['/search/tmdb/42'] = [
      {
        'type': 'movie',
        'movie': {
          'ids': {'trakt': 77},
        },
      },
    ];
    routes['/movies/77/comments/likes'] = [_comment(1, 'Found')];
    await pumpDetail(tester, _Client(_film(), ids: const ExternalIds(tmdb: 42)));
    await walkDown(tester);

    expect(sectionIds(tester), contains('discussions'));
  });

  group('nothing is asked and nothing is shown', () {
    testWidgets('on a children\'s profile', (tester) async {
      routes['/movies/tt1/comments/likes'] = [_comment(1, 'Not for you')];
      final client = _Client(_film());
      await pumpDetail(tester, client, kids: true);
      await walkDown(tester);

      expect(requests, isEmpty);
      expect(client.idCalls, 0);
      expect(sectionIds(tester), isNot(contains('discussions')));
    });

    testWidgets('when the children\'s check itself fails', (tester) async {
      routes['/movies/tt1/comments/likes'] = [_comment(1, 'Not for you')];
      await pumpDetail(tester, _Client(_film()), kidsCheckThrows: true);
      await walkDown(tester);

      expect(requests, isEmpty);
      expect(sectionIds(tester), isNot(contains('discussions')));
    });

    testWidgets('with the setting off', (tester) async {
      await SettingsService.getInstance();
      await SettingsService.instance.write(SettingsService.showTraktDiscussions, false);
      routes['/movies/tt1/comments/likes'] = [_comment(1, 'Off')];
      await pumpDetail(tester, _Client(_film()));
      await walkDown(tester);

      expect(requests, isEmpty);
      expect(sectionIds(tester), isNot(contains('discussions')));
    });

    testWidgets('in a build without an app key', (tester) async {
      useTrakt(clientId: '');
      routes['/movies/tt1/comments/likes'] = [_comment(1, 'No key')];
      await pumpDetail(tester, _Client(_film()));
      await walkDown(tester);

      expect(requests, isEmpty);
      expect(sectionIds(tester), isNot(contains('discussions')));
    });

    testWidgets('for a title without an IMDb or a TMDB id', (tester) async {
      await pumpDetail(tester, _Client(_film(), ids: const ExternalIds(tvdb: 5)));
      await walkDown(tester);

      expect(requests, isEmpty);
      expect(sectionIds(tester), isNot(contains('discussions')));
    });
  });

  testWidgets('an error at Trakt leaves no section and no hole', (tester) async {
    routes['/movies/tt1/comments/likes'] = 'down';
    await pumpDetail(tester, _Client(_film()));
    await walkDown(tester);

    expect(requests, isNotEmpty);
    expect(sectionIds(tester), isNot(contains('discussions')));
    expect(find.text('Discussions'), findsNothing);
  });

  testWidgets('only spoilers leave no section either', (tester) async {
    routes['/movies/tt1/comments/likes'] = [
      _comment(1, 'Flagged', spoiler: true),
      _comment(2, 'Tagged [spoiler]x[/spoiler]'),
    ];
    await pumpDetail(tester, _Client(_film()));
    await walkDown(tester);

    expect(sectionIds(tester), isNot(contains('discussions')));
  });

  testWidgets('the section waits for the page to get near it', (tester) async {
    routes['/shows/tt1/comments/likes'] = [_comment(1, 'Late')];
    final roles = [for (var i = 0; i < 6; i++) MediaRole(id: 'p$i', tag: 'Person $i', role: 'Role')];
    final show = _show().copyWith(
      roles: roles,
      reviews: const [MediaReview(author: 'Amy', text: 'Funny.', source: 'FilmWeek')],
      summary: List.filled(30, 'A long summary.').join(' '),
    );
    await pumpDetail(tester, _Client(show, seasons: [_season(1), _season(2)]));

    expect(requests, isEmpty, reason: 'opening a page tells Trakt nothing');
    expect(sectionIds(tester), isNot(contains('discussions')));

    await walkDown(tester, steps: 3);

    expect(requests, isNotEmpty);
    expect(sectionIds(tester), contains('discussions'));
  });

  testWidgets('a slow Trakt holds up nothing under it, and lands in its place', (tester) async {
    routes['/shows/tt1/comments/likes'] = [_comment(1, 'Late')];
    traktGate = Completer<void>();
    final show = _show().copyWith(
      roles: [for (var i = 0; i < 6; i++) MediaRole(id: 'p$i', tag: 'Person $i', role: 'Role')],
      reviews: const [
        MediaReview(author: 'Amy', text: 'Funny.', source: 'FilmWeek'),
        MediaReview(author: 'Bob', text: 'Sharp.', source: 'FilmWeek'),
      ],
      summary: List.filled(30, 'A long summary.').join(' '),
    );
    final client = _Client(show, seasons: [_season(1), _season(2)]);
    await pumpDetail(tester, client);

    await walkDown(tester, steps: 3);
    await tester.pumpAndSettle();
    expect(requests, isNotEmpty, reason: 'Trakt was asked and has not answered');
    expect(client.personCalls, ['p0', 'p1']);

    traktGate!.complete();
    await tester.pumpAndSettle();
    final ids = sectionIds(tester);
    expect(ids, contains('discussions'));
    expect(ids.indexOf('discussions'), lessThan(ids.indexWhere((id) => id.startsWith('person:'))));
  });

  testWidgets('a short page with nothing under the hero still asks, so it does not stay empty', (tester) async {
    routes['/movies/tt1/comments/likes'] = [_comment(1, 'Alone')];
    await pumpDetail(tester, _Client(_film().copyWith(roles: const [], reviews: const [])));

    expect(sectionIds(tester), ['discussions']);
  });

  testWidgets('a title opened again reads its cache', (tester) async {
    routes['/movies/tt1/comments/likes'] = [_comment(1, 'Once')];
    await pumpDetail(tester, _Client(_film()));
    await walkDown(tester);
    expect(requests, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await pumpDetail(tester, _Client(_film()));
    await walkDown(tester);

    expect(requests, hasLength(1));
    expect(sectionIds(tester), contains('discussions'));
  });

  test('a date reads in days for a week, after that as a date', () {
    final now = DateTime(2026, 10, 30, 12);
    expect(tvDetailCommentDate(now, now: now), t.discover.watchedAgo.today);
    expect(tvDetailCommentDate(now.subtract(const Duration(days: 1)), now: now), t.discover.watchedAgo.yesterday);
    expect(tvDetailCommentDate(now.subtract(const Duration(days: 6)), now: now), t.discover.watchedAgo.days(count: 6));
    expect(tvDetailCommentDate(DateTime(2026, 10, 16, 12), now: now), contains('2026'));
  });
}
