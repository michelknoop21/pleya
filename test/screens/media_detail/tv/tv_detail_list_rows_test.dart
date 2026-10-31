/// The list rows of Meer acties (northstar 12): Add to List and Add to Playlist /
/// Collection stand there on a backend that can do it, and only there.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/providers/watchlist_store.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_action_panel.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import '../../../test_helpers/profile_navigation.dart';

const Size _panel = Size(1038, 584);

MediaItem _movie(MediaBackend backend) => MediaItem(
  id: 'movie',
  backend: backend,
  kind: MediaKind.movie,
  title: 'Puss in Boots',
  guid: 'plex://movie/5d776be17a53e9001e732ab9',
  durationMs: 6000000,
  serverId: 'server_1',
  serverName: 'Server',
);

/// Takes what a Plex account or a Jellyfin server would take.
class _Source implements WatchlistSource {
  _Source(this.takes);

  final MediaBackend takes;

  @override
  WatchlistScopeId get scope => WatchlistScopeId(profileId: 'p', backend: takes, accountId: 'a', userId: 'u');
  @override
  bool accepts(MediaItem item) => item.backend == takes;
  @override
  Future<List<WatchlistEntry>> fetch() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager extends MultiServerManager {
  _Manager({required this.owner});

  final bool owner;

  @override
  bool canManageServerMetadata(ServerId serverId) => owner;
}

class _Client implements MediaServerClient {
  _Client(this.movie, this.caps);

  final MediaItem movie;
  final ServerCapabilities caps;

  @override
  ServerId get serverId => ServerId('server_1');
  @override
  String? get serverName => 'Server';
  @override
  MediaBackend get backend => movie.backend;
  @override
  ServerCapabilities get capabilities => caps;
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: movie, onDeckEpisode: null);
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

  late AppDatabase db;
  setUpAll(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });
  tearDownAll(() => db.close());

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

  /// Opens Meer acties through the real screen and hands back its rows.
  Future<Map<String, TvDetailActionRow>> rows(
    WidgetTester tester,
    MediaBackend backend,
    ServerCapabilities caps, {
    bool owner = false,
    bool watchlist = true,
  }) async {
    tester.view.physicalSize = _panel;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await SettingsService.getInstance();
    final movie = _movie(backend);
    final manager = _Manager(owner: owner)..debugRegisterClientForTesting(_Client(movie, caps));
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);
    final lists = WatchlistProvider(
      snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
      repository: WatchlistRepository(sources: [if (watchlist) _Source(backend)]),
    );
    addTearDown(lists.dispose);
    final store = WatchlistStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
            ChangeNotifierProvider<WatchlistProvider>.value(value: lists),
            ChangeNotifierProvider<WatchlistStore>.value(value: store),
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
              child: MediaDetailScreen(metadata: movie),
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

    for (var i = 0; i < 12 && FocusManager.instance.primaryFocus?.debugLabel != 'detail_more'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'detail_more');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    return {
      for (final row in tester.widget<TvDetailActionPanel>(find.byType(TvDetailActionPanel).last).rows) row.id: row,
    };
  }

  testWidgets('Plex has both, the list before the playlist, as 12 draws them', (tester) async {
    final panel = await rows(tester, MediaBackend.plex, ServerCapabilities.plex, owner: true);

    expect(panel['watchlist_toggle']!.label, t.watchlist.add);
    expect(panel['add_to']!.label, t.mediaMenu.addToPlaylistOrCollection);
    final ids = panel.keys.toList();
    expect(ids.indexOf('watchlist_toggle'), lessThan(ids.indexOf('add_to')));
  });

  testWidgets('someone who cannot manage the server is only offered a playlist', (tester) async {
    final panel = await rows(tester, MediaBackend.plex, ServerCapabilities.plex);

    expect(panel['add_to']!.label, t.mediaMenu.addToPlaylist);
  });

  testWidgets('Jellyfin has its favorites and its playlists', (tester) async {
    final panel = await rows(tester, MediaBackend.jellyfin, ServerCapabilities.jellyfin, owner: true);

    expect(panel, contains('watchlist_toggle'));
    expect(panel, contains('add_to'));
  });

  testWidgets('a Pleya Server has neither: no route behind them, so no rows', (tester) async {
    final panel = await rows(
      tester,
      MediaBackend.pleyaServer,
      const ServerCapabilities(ownActivityLine: true),
      watchlist: false,
    );

    expect(panel, isNot(contains('watchlist_toggle')));
    expect(panel, isNot(contains('add_to')));
  });

  testWidgets('a backend with playlists but no source for the title drops the list row only', (tester) async {
    final panel = await rows(tester, MediaBackend.jellyfin, ServerCapabilities.jellyfin, watchlist: false);

    expect(panel, isNot(contains('watchlist_toggle')));
    expect(panel, contains('add_to'));
  });
}
