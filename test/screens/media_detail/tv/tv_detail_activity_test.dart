/// The activity line of 03, 01 and 06 through the real screen: a Pleya Server's
/// answer under its capability, the viewer's own line from the watch state, and
/// the Plex path that keeps its own source.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/item_watcher.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/media_detail/watched_by_row.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/profile_navigation.dart';

const Size _panel = Size(1038, 584);

MediaItem _movie({int? viewCount, int? offset, MediaBackend backend = MediaBackend.pleyaServer}) => MediaItem(
  id: 'movie',
  backend: backend,
  kind: MediaKind.movie,
  title: 'Sintel',
  durationMs: 6000000,
  viewCount: viewCount,
  viewOffsetMs: offset,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _show() => MediaItem(
  id: 'show',
  backend: MediaBackend.pleyaServer,
  kind: MediaKind.show,
  title: 'Charge',
  leafCount: 6,
  viewedLeafCount: 0,
  serverId: 'server_1',
  serverName: 'Server',
);

MediaItem _season(int n) => MediaItem(
  id: 'season_$n',
  backend: MediaBackend.pleyaServer,
  kind: MediaKind.season,
  title: 'Season $n',
  index: n,
  parentId: 'show',
  leafCount: 3,
  viewedLeafCount: 0,
  serverId: 'server_1',
  serverName: 'Server',
);

const _you = ItemWatcher(id: 'u1', displayName: 'verify-owner', isSelf: true, initials: 'VO');
const _sam = ItemWatcher(id: 'u2', displayName: 'sam', initials: 'SM');
const _omar = ItemWatcher(id: 'u3', displayName: 'omar');
const _lotte = ItemWatcher(id: 'u4', displayName: 'lotte');

class _Client implements HouseholdActivityClient {
  _Client(this.item, {this.caps = _pleyaWithRoute, this.activity = const {}, this.children = const {}});

  static const _pleyaWithRoute = ServerCapabilities(itemActivity: true, ownActivityLine: true);

  final MediaItem item;
  final ServerCapabilities caps;
  final Map<String, List<ItemWatcher>> activity;
  final Map<String, List<MediaItem>> children;
  final asked = <String>[];

  @override
  Future<List<ItemWatcher>> fetchHouseholdActivity(String itemId) async {
    asked.add(itemId);
    return activity[itemId] ?? const [];
  }

  @override
  Future<bool?> fetchActivitySharing() async => true;
  @override
  Future<bool> saveActivitySharing(bool share) async => share;

  @override
  ServerId get serverId => ServerId('server_1');
  @override
  String? get serverName => 'Server';
  @override
  MediaBackend get backend => item.backend;
  @override
  ServerCapabilities get capabilities => caps;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: item, onDeckEpisode: null);
  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async => children[parentId] ?? const [];
  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final all = children[parentId] ?? const <MediaItem>[];
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
  }) async => const LibraryPage<MediaItem>(items: [], totalCount: 0, offset: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  });

  Future<void> pumpDetail(WidgetTester tester, _Client client, MediaItem item) async {
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
                  child: TvDisplayMetrics(size: _panel, child: withNoticeLayer()(context, child)),
                ),
              ),
            ),
            theme: monoTheme(dark: true),
            home: TvNestedRouteScope(
              dismiss: ([_]) {},
              markResult: (_) {},
              child: MediaDetailScreen(metadata: item),
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

  group('with the capability', () {
    testWidgets('a film says who, the viewer in front whatever the server order', (tester) async {
      final client = _Client(
        _movie(),
        activity: {
          'movie': const [_sam, _you, _omar, _lotte],
        },
      );
      await pumpDetail(tester, client, _movie());

      expect(find.text('Activity by you, sam and 2 others'), findsOneWidget);
      expect(client.asked, ['movie']);
    });

    testWidgets('avatars are the initials the server chose, the first letter otherwise', (tester) async {
      final client = _Client(
        _movie(),
        activity: {
          'movie': const [_you, _sam, _omar],
        },
      );
      await pumpDetail(tester, client, _movie());

      final row = find.byType(WatchedByRow);
      expect(find.descendant(of: row, matching: find.text('VO')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('SM')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('O')), findsOneWidget);
    });

    testWidgets('a season tab asks for that season, once, and the Serie tab keeps its own', (tester) async {
      final client = _Client(
        _show(),
        activity: {
          'show': const [_you, _sam, _omar],
          'season_2': const [_you, _sam],
        },
        children: {
          'show': [_season(1), _season(2)],
        },
      );
      await pumpDetail(tester, client, _show());
      expect(find.text('Activity by you, sam and omar'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.byType(WatchedByRow), findsNothing, reason: 'season 1 has no activity');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Activity by you and sam'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(client.asked, ['show', 'season_1', 'season_2']);
    });

    testWidgets('an empty answer and nothing watched: no line', (tester) async {
      await pumpDetail(tester, _Client(_movie()), _movie());

      expect(find.byType(WatchedByRow), findsNothing);
    });

    testWidgets('an empty answer on a title marked as watched keeps the own line', (tester) async {
      final item = _movie(viewCount: 1);
      await pumpDetail(tester, _Client(item), item);

      expect(find.text('Activity by you'), findsOneWidget);
    });

    testWidgets('someone who opted out is gone, the viewer stays', (tester) async {
      final client = _Client(
        _movie(),
        activity: {
          'movie': const [_you],
        },
      );
      await pumpDetail(tester, client, _movie());

      expect(find.text('Activity by you'), findsOneWidget);
      expect(find.textContaining('sam'), findsNothing);
    });
  });

  group('without the capability', () {
    const older = ServerCapabilities(ownActivityLine: true);

    testWidgets('an older server is not asked and keeps the own line', (tester) async {
      final item = _movie(offset: 1000);
      final client = _Client(
        item,
        caps: older,
        activity: const {
          'movie': [_sam],
        },
      );
      await pumpDetail(tester, client, item);

      expect(client.asked, isEmpty);
      expect(find.text('Activity by you'), findsOneWidget);
    });

    testWidgets('Jellyfin says the viewer watched it, and nothing when they did not', (tester) async {
      final item = _movie(viewCount: 2, backend: MediaBackend.jellyfin);
      await pumpDetail(tester, _Client(item, caps: ServerCapabilities.jellyfin), item);
      expect(find.text('Activity by you'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final unseen = _movie(backend: MediaBackend.jellyfin);
      await pumpDetail(tester, _Client(unseen, caps: ServerCapabilities.jellyfin), unseen);
      expect(find.byType(WatchedByRow), findsNothing);
    });

    testWidgets('Plex keeps its own path: no question to the server and no own line', (tester) async {
      final item = _movie(viewCount: 2, backend: MediaBackend.plex);
      final client = _Client(
        item,
        caps: ServerCapabilities.plex,
        activity: const {
          'movie': [_sam],
        },
      );
      await pumpDetail(tester, client, item);

      expect(client.asked, isEmpty);
      expect(find.byType(WatchedByRow), findsNothing);
    });
  });
}
