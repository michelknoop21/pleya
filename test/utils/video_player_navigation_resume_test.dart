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
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/screens/video_player_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/playback_resume_resolver.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/utils/watch_state_notifier.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:provider/provider.dart';

import '../pleya_server/pleya_fake_server.dart';
import '../test_helpers/prefs.dart';

// `shouldRefetchForFreshResume` replaces the old inline condition in
// `navigateToVideoPlayer`, which read:
//
//   resolveWatchState && !isOffline && mediaClient != null &&
//   metadata.viewOffsetMs == null && (movie || episode)
//
// The `viewOffsetMs == null` clause is what these tests remove: an item that
// already carries a view offset is exactly the case where that offset can be
// stale, so it is the case that most needs the refetch.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shouldRefetchForFreshResume', () {
    test('refetches an episode that already carries a view offset', () {
      // Demonstrably red before the change: the old condition required
      // viewOffsetMs == null, so an item with a stale offset was never
      // refetched and resumed from that stale value.
      expect(
        shouldRefetchForFreshResume(
          resolveWatchState: true,
          isOffline: false,
          hasClient: true,
          kind: MediaKind.episode,
        ),
        isTrue,
      );
    });

    test('refetches a movie', () {
      expect(
        shouldRefetchForFreshResume(resolveWatchState: true, isOffline: false, hasClient: true, kind: MediaKind.movie),
        isTrue,
      );
    });

    test('does not refetch for an explicit intent that opted out of watch-state resolution', () {
      expect(
        shouldRefetchForFreshResume(resolveWatchState: false, isOffline: false, hasClient: true, kind: MediaKind.movie),
        isFalse,
      );
    });

    test('does not refetch during offline playback', () {
      expect(
        shouldRefetchForFreshResume(resolveWatchState: true, isOffline: true, hasClient: true, kind: MediaKind.movie),
        isFalse,
      );
    });

    test('does not refetch without a reachable client', () {
      expect(
        shouldRefetchForFreshResume(resolveWatchState: true, isOffline: false, hasClient: false, kind: MediaKind.movie),
        isFalse,
      );
    });

    test('does not refetch kinds that do not resume', () {
      for (final kind in [MediaKind.show, MediaKind.season, MediaKind.collection, MediaKind.playlist]) {
        expect(
          shouldRefetchForFreshResume(resolveWatchState: true, isOffline: false, hasClient: true, kind: kind),
          isFalse,
          reason: 'kind $kind should not trigger a resume refetch',
        );
      }
    });
  });

  group('navigateToVideoPlayer resume handoff', () {
    setUp(() {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      TvDetectionService.debugSetAppleTVOverride(true);
      LocaleSettings.setLocaleSync(AppLocale.en);
      noticeController.debugReset();
    });

    tearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      noticeController.debugReset();
    });

    // A completed fetch belongs to this play request even when the server's
    // timestamp is absent or behind the still-open Apple TV's clock.
    final timestamps = <String, int?>{
      'missing lastViewedAt': null,
      'zero lastViewedAt': 0,
      'lastViewedAt two seconds before the local stop':
          _stoppedAt.subtract(const Duration(seconds: 2)).millisecondsSinceEpoch ~/ 1000,
      'lastViewedAt thirty minutes after the local stop':
          _stoppedAt.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
    };
    for (final timestamp in timestamps.entries) {
      testWidgets('fresh server progress replaces an old session stop with ${timestamp.key}', (tester) async {
        final host = await _pumpResumeHost(tester);
        final pending = navigateToVideoPlayer(host.context, metadata: _movie);
        await tester.pump();

        expect(host.client.fetchCalls, 1);
        expect(host.spy.playerRoutes, isEmpty, reason: 'the actual refetch is blocked');
        host.client.release(_movie.copyWith(viewOffsetMs: _remotePosition, lastViewedAt: timestamp.value));
        await tester.pump();
        await tester.pump();
        await pending;

        _expectHandoff(host, positionMs: _remotePosition, isFresh: true);
        expect(tester.takeException(), isNull);
      });
    }

    for (final position in [const Duration(minutes: 5).inMilliseconds, 0]) {
      testWidgets('a fresh server ${position == 0 ? 'reset' : 'rewind'} replaces the old session stop', (tester) async {
        final host = await _pumpResumeHost(tester);
        final pending = navigateToVideoPlayer(host.context, metadata: _movie);
        await tester.pump();
        expect(host.client.fetchCalls, 1);

        host.client.release(_movie.copyWith(viewOffsetMs: position));
        await tester.pump();
        await tester.pump();
        await pending;

        _expectHandoff(host, positionMs: position, isFresh: true);
        expect(tester.takeException(), isNull);
      });
    }

    for (final fails in [true, false]) {
      testWidgets('a ${fails ? 'failed' : 'null'} fetch preserves the local stop without claiming freshness', (
        tester,
      ) async {
        final host = await _pumpResumeHost(tester);
        final pending = navigateToVideoPlayer(host.context, metadata: _movie);
        await tester.pump();
        expect(host.client.fetchCalls, 1);

        if (fails) {
          host.client.fail();
        } else {
          host.client.release(null);
        }
        await tester.pump();
        await tester.pump();
        await pending;

        _expectHandoff(host, positionMs: _localPosition, isFresh: false);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a client without fresh-read capability preserves the local stop over a cached fallback', (
      tester,
    ) async {
      final host = await _pumpResumeHost(tester, freshCapable: false);
      expect(host.client, isNot(isA<FreshMediaItemClient>()));
      final pending = navigateToVideoPlayer(host.context, metadata: _movie);
      await tester.pump();
      expect(host.client.fetchCalls, 1);

      // Ordinary fetchItem may have answered from its cache after a transport
      // failure. Such an answer cannot retire the real local stop.
      host.client.release(_movie);
      await tester.pump();
      await tester.pump();
      await pending;

      _expectHandoff(host, positionMs: _localPosition, isFresh: false);
      expect(tester.takeException(), isNull);
    });

    testWidgets('play from beginning ignores the local stop and does not fetch', (tester) async {
      final host = await _pumpResumeHost(tester);
      final pending = playFromBeginning(host.context, _movie);
      await tester.pump();
      await tester.pump();
      await pending;

      expect(host.client.fetchCalls, 0);
      _expectHandoff(host, positionMs: 0, isFresh: false);
      expect(tester.takeException(), isNull);
    });

    for (final scenario in [
      (watchState: false, hasState: false, label: 'without watch-state support preserves'),
      (watchState: true, hasState: false, label: 'with supported but absent watch state preserves'),
      (watchState: true, hasState: true, label: 'with a supported zero reset replaces'),
    ]) {
      testWidgets('Pleya Server ${scenario.label} the local stop', (tester) async {
        final server = PleyaFakeServer(watchState: scenario.watchState);
        server.addItem(
          id: _movie.id,
          kind: 'movie',
          title: _movie.title!,
          durationMs: _movie.durationMs,
          userState: scenario.hasState
              ? {'position_ms': 0, 'watched': false, 'play_count': 0, 'updated_at': '2026-10-18T10:00:00Z'}
              : null,
        );
        final client = server.client();
        addTearDown(client.close);
        await client.refreshCapabilities();
        expect(client.wireCapabilities.watchState, scenario.watchState);
        final item = MediaItem(
          id: _movie.id,
          backend: MediaBackend.pleyaServer,
          kind: _movie.kind,
          title: _movie.title,
          durationMs: _movie.durationMs,
          viewOffsetMs: _movie.viewOffsetMs,
          serverId: client.serverId.toString(),
        );
        final host = await _pumpResumeHost(tester, mediaClient: client, metadata: item);
        final pending = navigateToVideoPlayer(host.context, metadata: item);
        await tester.pump();
        await tester.pump();
        await pending;

        _expectHandoff(
          host,
          item: item,
          positionMs: scenario.hasState ? 0 : _localPosition,
          isFresh: scenario.hasState,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a local event arriving during the refetch remains newer than that request', (tester) async {
      final host = await _pumpResumeHost(tester);
      final pending = navigateToVideoPlayer(host.context, metadata: _movie);
      await tester.pump();
      expect(host.client.fetchCalls, 1);
      expect(host.spy.playerRoutes, isEmpty);

      // Separate race requirement: replacing the old stop must not also
      // discard an event that arrived after this play request began.
      host.now = host.now.add(const Duration(seconds: 1));
      const newerPosition = Duration(minutes: 50);
      _notifyStop(newerPosition.inMilliseconds);
      await tester.idle();
      expect(host.store.apply(_movie).viewOffsetMs, newerPosition.inMilliseconds);

      host.client.release(_movie.copyWith(viewOffsetMs: _remotePosition));
      await tester.pump();
      await tester.pump();
      await pending;

      final screen = host.spy.playerScreen(host.context);
      expect(screen.metadata.viewOffsetMs, newerPosition.inMilliseconds);
      expect(screen.resumeProgressIsFresh, isFalse, reason: 'the handed-off position came from the later local event');
      expect(tester.takeException(), isNull);
    });
  });
}

final _stoppedAt = DateTime.utc(2026, 10, 18, 10);
const _localPosition = 10 * 60 * 1000;
const _remotePosition = 45 * 60 * 1000;
final _movie = MediaItem(
  id: 'movie_1',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Movie 1',
  serverId: 'server_1',
  durationMs: const Duration(hours: 2).inMilliseconds,
  viewOffsetMs: const Duration(minutes: 3).inMilliseconds,
);

void _notifyStop(int positionMs, {MediaItem? item}) {
  final metadata = item ?? _movie;
  WatchStateNotifier().notifyProgress(
    item: metadata,
    viewOffset: positionMs,
    duration: metadata.durationMs!,
    isFinal: true,
  );
}

class _ResumeHost {
  _ResumeHost({bool freshCapable = true}) : client = freshCapable ? _BlockingClient() : _LegacyBlockingClient();

  DateTime now = _stoppedAt;
  late final WatchStateStore store = WatchStateStore(now: () => now);
  final _LegacyBlockingClient client;
  final spy = _PlayerRouteSpy();
  late BuildContext context;
}

Future<_ResumeHost> _pumpResumeHost(
  WidgetTester tester, {
  bool freshCapable = true,
  MediaServerClient? mediaClient,
  MediaItem? metadata,
}) async {
  await SettingsService.getInstance();
  final host = _ResumeHost(freshCapable: freshCapable);
  final manager = MultiServerManager()..debugRegisterClientForTesting(mediaClient ?? host.client);
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
  addTearDown(() async {
    host.store.dispose();
    offlineWatchSync.dispose();
    downloadProvider.dispose();
    multiServerProvider.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
        ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
        ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatchSync),
        ChangeNotifierProvider<WatchStateStore>.value(value: host.store),
      ],
      child: MaterialApp(
        navigatorObservers: [host.spy],
        home: Builder(
          builder: (context) {
            host.context = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );

  // Record the real terminal event at t0, then leave that store alive for an
  // hour while another device watches. Only the injected clock advances.
  final item = metadata ?? _movie;
  _notifyStop(_localPosition, item: item);
  await tester.idle();
  expect(host.store.apply(item).viewOffsetMs, _localPosition);
  host.now = _stoppedAt.add(const Duration(hours: 1));
  return host;
}

void _expectHandoff(_ResumeHost host, {required int positionMs, required bool isFresh, MediaItem? item}) {
  expect(host.spy.playerRoutes, hasLength(1));
  final screen = host.spy.playerScreen(host.context);
  expect(screen.metadata.globalKey, (item ?? _movie).globalKey);
  expect(screen.metadata.viewOffsetMs, positionMs);
  expect(screen.resumeProgressIsFresh, isFresh);

  // Confirm the resolver boundary using exactly the metadata handed to the
  // real player route. This does not mount mpv or prove actual playback.
  final resolution = PlaybackResumeResolver.resolve(
    backend: BackendResumeProgress(
      position: Duration(milliseconds: screen.metadata.viewOffsetMs!),
      isFresh: screen.resumeProgressIsFresh,
    ),
  );
  expect(resolution.position, Duration(milliseconds: positionMs));
  expect(resolution.source, isFresh ? PlaybackResumeSource.freshBackend : PlaybackResumeSource.cachedMetadata);
}

/// Capture the real route, removing it before its player state mounts mpv.
class _PlayerRouteSpy extends NavigatorObserver {
  final playerRoutes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name != kVideoPlayerRouteName) return;
    playerRoutes.add(route);
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }

  VideoPlayerScreen playerScreen(BuildContext context) {
    final route = playerRoutes.single as PageRouteBuilder<bool>;
    return route.pageBuilder(context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation) as VideoPlayerScreen;
  }
}

class _BlockingClient extends _LegacyBlockingClient implements FreshMediaItemClient {
  @override
  Future<MediaItem?> fetchFreshItem(String id) => fetchItem(id);
}

class _LegacyBlockingClient implements MediaServerClient {
  int fetchCalls = 0;
  final _pending = <Completer<MediaItem?>>[];

  void release(MediaItem? item) => _pending.removeAt(0).complete(item);
  void fail() => _pending.removeAt(0).completeError(StateError('server unreachable'));

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<MediaItem?> fetchItem(String id) {
    fetchCalls++;
    final pending = Completer<MediaItem?>();
    _pending.add(pending);
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
