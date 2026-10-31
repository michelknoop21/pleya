/// `navigateToVideoPlayer` is where every play ends: the page's button, an
/// episode row, a context menu. It starts the copy on the chosen source, and
/// hands the title on to the player (DEC-XXX "Eén titel over servers heen").
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/screens/video_player_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';
import 'package:pleya/services/unified_catalog/unified_title_scope.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

class _Client implements MediaServerClient {
  _Client(this._id, this.episodes);

  final String _id;
  final List<MediaItem> episodes;

  @override
  ServerId get serverId => ServerId(_id);

  @override
  String? get serverName => _id;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async => episodes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FreshClient extends _Client implements FreshMediaItemClient {
  _FreshClient(super.id, super.episodes, {required this.fresh});

  final MediaItem fresh;

  @override
  Future<MediaItem?> fetchFreshItem(String id) async => fresh;
}

/// Answers the widget the route would build, then drops the route: a real
/// player would spin up mpv.
class _RouteSpy extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    if (previousRoute == null) return;
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }
}

MediaItem _show(String server) =>
    MediaItem(id: 'show-$server', backend: MediaBackend.plex, kind: MediaKind.show, title: 'S', serverId: server);

MediaItem _episode(String server, {int? viewOffsetMs, int? lastViewedAt}) => MediaItem(
  id: 'ep-$server',
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'E1',
  grandparentId: 'show-$server',
  parentIndex: 1,
  index: 1,
  durationMs: 3600000,
  viewOffsetMs: viewOffsetMs,
  lastViewedAt: lastViewedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(false);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  UnifiedTitlePlayback titleOver(MultiServerManager manager) {
    final sources = [UnifiedMediaSource.fromItem(_show('chosen')), UnifiedMediaSource.fromItem(_show('page'))];
    return UnifiedTitlePlayback(
      routeContext: UnifiedMediaRouteContext(
        groupId: 'g',
        identity: CanonicalMediaIdentity.show(title: 'S'),
        sourceKey: 'chosen:show-chosen',
        pageSourceKey: 'page:show-page',
        titleSources: sources,
        availableSourceKeys: [for (final s in sources) s.sourceKey],
        coverage: SourceCoverageState.none,
        intent: UnifiedActivationIntent.play,
      ),
      sources: sources,
      gate: UnifiedSourceGate(
        clientFor: manager.getClient,
        isOnline: manager.isServerOnline,
        isAuthRejected: (_) => false,
        isVisible: (_) => true,
        isOwn: (_) => true,
        hiddenLibraryKeys: () => const {},
        isRestrictedProfile: () async => false,
      ),
    );
  }

  Future<(BuildContext, _RouteSpy, UnifiedTitlePlayback)> pumpHost(
    WidgetTester tester, {
    bool scoped = false,
    MediaItem? freshOnChosen,
  }) async {
    await SettingsService.getInstance();
    final chosen = freshOnChosen == null
        ? _Client('chosen', [_episode('chosen')])
        : _FreshClient('chosen', [_episode('chosen')], fresh: freshOnChosen);
    final manager = MultiServerManager()
      ..debugRegisterClientForTesting(_Client('page', [_episode('page', viewOffsetMs: 600000, lastViewedAt: 2000)]))
      ..debugRegisterClientForTesting(chosen);
    final title = titleOver(manager);
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    final downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloadProvider.ensureInitialized();
    final offlineWatchSync = OfflineWatchSyncService(database: db, serverManager: manager);
    final watchStateStore = WatchStateStore();
    addTearDown(() async {
      watchStateStore.dispose();
      offlineWatchSync.dispose();
      downloadProvider.dispose();
      multiServerProvider.dispose();
      await db.close();
    });

    final spy = _RouteSpy();
    late BuildContext hostContext;
    final host = Builder(
      builder: (context) {
        hostContext = context;
        return const SizedBox.shrink();
      },
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
          ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatchSync),
          ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
        ],
        child: MaterialApp(
          navigatorObservers: [spy],
          home: scoped ? UnifiedTitleScope(title: title, child: host) : host,
        ),
      ),
    );
    spy.pushed.clear();
    return (hostContext, spy, title);
  }

  /// The player the last route would build, without building it.
  VideoPlayerScreen playerOf(BuildContext context, _RouteSpy spy) {
    final route = spy.pushed.last as PageRoute<dynamic>;
    return route.buildPage(context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation) as VideoPlayerScreen;
  }

  final requested = _episode('page', viewOffsetMs: 600000, lastViewedAt: 2000).copyWith(serverId: 'page');

  testWidgets('the copy on the chosen source starts, at the position of the page', (tester) async {
    final (context, spy, title) = await pumpHost(tester);

    await tester.runAsync(() => navigateToVideoPlayer(context, metadata: requested, unifiedTitle: title));
    await tester.pump();

    final player = playerOf(context, spy);
    expect(player.metadata.globalKey, 'chosen:ep-chosen');
    expect(player.startPosition, const Duration(milliseconds: 600000));
    expect(player.unifiedTitle, same(title));
  });

  testWidgets('a position the chosen server turns out to have beats the carried one', (tester) async {
    final fresh = _episode('chosen', viewOffsetMs: 900000).copyWith(serverId: 'chosen');
    final (context, spy, title) = await pumpHost(tester, freshOnChosen: fresh);

    await tester.runAsync(() => navigateToVideoPlayer(context, metadata: requested, unifiedTitle: title));
    await tester.pump();

    final player = playerOf(context, spy);
    expect(player.startPosition, isNull, reason: 'the fresh position plays, as it does for any other start');
    expect(player.metadata.viewOffsetMs, 900000);
  });

  testWidgets('a play from below a page finds the title without being told', (tester) async {
    final (context, spy, title) = await pumpHost(tester, scoped: true);

    await tester.runAsync(() => navigateToVideoPlayer(context, metadata: requested));
    await tester.pump();

    final player = playerOf(context, spy);
    expect(player.metadata.serverId, 'chosen');
    expect(player.unifiedTitle, same(title));
  });

  testWidgets('play from the beginning starts on the chosen source, at zero', (tester) async {
    final (context, spy, title) = await pumpHost(tester);

    await tester.runAsync(() => playFromBeginning(context, requested, unifiedTitle: title));
    await tester.pump();

    final player = playerOf(context, spy);
    expect(player.metadata.serverId, 'chosen');
    expect(player.metadata.viewOffsetMs, 0);
    expect(player.startPosition, isNull);
  });

  testWidgets('a version picked from a menu stays on the item it was picked from', (tester) async {
    final (context, spy, title) = await pumpHost(tester);

    await tester.runAsync(
      () => navigateToVideoPlayer(context, metadata: requested, unifiedTitle: title, selectedMediaIndex: 1),
    );
    await tester.pump();

    expect(playerOf(context, spy).metadata.serverId, 'page');
  });

  testWidgets('something else on the page, a trailer, plays as itself and tells the player nothing', (tester) async {
    final (context, spy, _) = await pumpHost(tester, scoped: true);
    final trailer = MediaItem(id: 'clip', backend: MediaBackend.plex, kind: MediaKind.clip, serverId: 'page');

    await tester.runAsync(() => navigateToVideoPlayer(context, metadata: trailer));
    await tester.pump();

    final player = playerOf(context, spy);
    expect(player.metadata.id, 'clip');
    expect(player.unifiedTitle, isNull);
  });
}
