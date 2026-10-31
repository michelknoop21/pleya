import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/database/app_database.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/offline_watch_provider.dart';
import 'package:pleya/screens/tv/tv_unified_context_actions.dart';
import 'package:pleya/screens/tv/tv_unified_context_menu.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/pleya_server_api_cache.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';
import 'package:pleya/services/unified_catalog/unified_title_scope.dart';
import 'package:pleya/services/watch_actions.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/watch_state_notifier.dart';
import 'package:provider/provider.dart';

import '../pleya_server/pleya_fake_server.dart';
import '../test_helpers/prefs.dart';

/// Watch-state marks must survive their own server being unreachable, and that
/// question is per server.
///
/// [OfflineModeProvider.isOffline] answers a different one: it is false as soon
/// as *any* visible server is up. Routing on it alone meant a mark on a server
/// that was down took the online branch, hit a client that is registered
/// regardless of health, and was lost, while the identical mark with every
/// server down was queued and synced later. Same action, two durability
/// guarantees, decided by a server the item has nothing to do with.
class _UnreachableClient implements MediaServerClient {
  _UnreachableClient(this._id);

  final String _id;

  int markWatchedCalls = 0;

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<void> markWatched(MediaItem item) async {
    markWatchedCalls++;
    // What an unreachable server actually does: the transport gives up.
    throw Exception('connection refused');
  }

  @override
  Future<void> markUnwatched(MediaItem item) async {
    throw Exception('connection refused');
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HealthyClient implements MediaServerClient {
  _HealthyClient(
    this._id, {
    this.ids = const ExternalIds(),
    this.matches = const [],
    this.seasons = const [],
    this.episodes = const [],
    this.lookupGate,
  });

  final String _id;
  final ExternalIds ids;
  final List<MediaItem> matches;
  final List<MediaItem> seasons;
  final List<MediaItem> episodes;
  final Future<void>? Function()? lookupGate;

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async => episodes;

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async => seasons;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => ids;

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async {
    await lookupGate?.call();
    return matches;
  }

  final List<({String itemId, bool watched})> writes = [];

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<void> markWatched(MediaItem item) async => writes.add((itemId: item.id, watched: true));

  @override
  Future<void> markUnwatched(MediaItem item) async => writes.add((itemId: item.id, watched: false));

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers, and refuses every write.
class _RefusingClient extends _HealthyClient {
  _RefusingClient(super.id, {Object? failure}) : _failure = failure ?? Exception('server hiccup');

  final Object _failure;

  @override
  Future<void> markWatched(MediaItem item) async => throw _failure;
}

class _Profiles extends ChangeNotifier implements ActiveProfileProvider {
  _Profiles(this.id);

  String id;

  @override
  String? get activeId => id;

  @override
  Profile? get active => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SwitchesThenFails extends _HealthyClient {
  _SwitchesThenFails(super.id, this.onWrite);

  final VoidCallback onWrite;

  @override
  Future<void> markWatched(MediaItem item) async {
    onWrite();
    throw const SocketException('server went away');
  }
}

/// Takes a write and does not answer until told to.
class _HungClient extends _HealthyClient {
  _HungClient(super.id);

  /// Made inside `runAsync`: a future from the fake zone never hears its
  /// completion out there.
  late Completer<void> answer;

  @override
  Future<void> markWatched(MediaItem item) => answer.future;
}

/// Hands out the real answers, after something changed meanwhile.
class _SlowTitle implements UnifiedTitlePlayback {
  _SlowTitle(this._title, {this.onCopies, this.holdUntil});

  final UnifiedTitlePlayback _title;
  final VoidCallback? onCopies;
  final Future<void>? Function()? holdUntil;

  @override
  bool holds(MediaItem item) => _title.holds(item);

  @override
  Future<List<MediaItem>> copiesOf(MediaItem item) async {
    final copies = await _title.copiesOf(item);
    onCopies?.call();
    await holdUntil?.call();
    return copies;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fails every token round: `queueFailure` lasts one request, and a write can
/// make several.
class _FailingRefresh extends http.BaseClient {
  _FailingRefresh(this.server, this.status, this.code) : inner = server.asHttpClient();

  final PleyaFakeServer server;
  final http.Client inner;
  final int status;
  final String code;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.contains('/auth/refresh')) {
      server.queueFailure(pathPrefix: '/auth/refresh', status: status, errorCode: code);
    }
    return inner.send(request);
  }
}

MediaItem _itemOn(String serverId, String id) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune', serverId: serverId);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MultiServerManager serverManager;
  late OfflineWatchSyncService syncService;
  late DownloadManagerService downloadManager;
  late DownloadProvider downloadProvider;
  late OfflineWatchProvider offlineWatch;
  late MultiServerProvider multiServer;
  late OfflineModeProvider offlineMode;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    PleyaServerApiCache.initialize(db);
    serverManager = MultiServerManager();
    for (final server in const ['a', 'b', 'c']) {
      serverManager.debugMarkAdministeredForTesting(ServerId(server));
    }
    syncService = OfflineWatchSyncService(database: db, serverManager: serverManager);

    downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloadProvider.ensureInitialized();
    offlineWatch = OfflineWatchProvider(syncService: syncService, downloadProvider: downloadProvider);
  });

  tearDown(() async {
    offlineMode.dispose();
    multiServer.dispose();
    offlineWatch.dispose();
    downloadProvider.dispose();
    downloadManager.dispose();
    syncService.dispose();
    serverManager.dispose();
    await db.close();
  });

  /// Pumps the provider tree `WatchActions` reads from and hands back a context
  /// inside it.
  Future<BuildContext> pumpTree(WidgetTester tester) async {
    multiServer = MultiServerProvider(serverManager, DataAggregationService(serverManager));
    offlineMode = OfflineModeProvider(serverManager, multiServerProvider: multiServer);

    late BuildContext ctx;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
          ChangeNotifierProvider<OfflineWatchProvider>.value(value: offlineWatch),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  /// A mark and everything it sets going for its copies.
  Future<WatchMarkOutcome?> markAll(WidgetTester tester, BuildContext ctx, MediaItem item, {bool watched = true}) =>
      tester.runAsync(() async {
        final outcome = await WatchActions.setWatched(ctx, item, watched: watched);
        await WatchActions.copiesReached();
        return outcome;
      });

  group('a mark on a title with more sources', () {
    UnifiedTitlePlayback titleOf(List<MediaItem> copies, {ExternalIds ids = const ExternalIds(tmdb: 1)}) {
      final sources = [for (final copy in copies) UnifiedMediaSource.fromItem(copy, externalIds: ids)];
      return UnifiedTitlePlayback(
        routeContext: UnifiedMediaRouteContext(
          groupId: 'g',
          identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
          sourceKey: sources.first.sourceKey,
          titleSources: sources,
          availableSourceKeys: [for (final s in sources) s.sourceKey],
          coverage: SourceCoverageState.none,
          intent: UnifiedActivationIntent.details,
        ),
        sources: sources,
        gate: UnifiedSourceGate(
          clientFor: serverManager.getClient,
          isOnline: serverManager.isServerOnline,
          isAuthRejected: serverManager.authErrorServerIds.map(ServerId.new).contains,
          isVisible: (_) => true,
          isOwn: (_) => true,
          hiddenLibraryKeys: () => const {},
          isRestrictedProfile: () async => false,
        ),
      );
    }

    Future<BuildContext> scoped(WidgetTester tester, BuildContext tree, UnifiedTitlePlayback title) async {
      late BuildContext inside;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
            ChangeNotifierProvider<OfflineWatchProvider>.value(value: offlineWatch),
          ],
          child: MaterialApp(
            home: UnifiedTitleScope(
              title: title,
              child: Builder(
                builder: (context) {
                  inside = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      return inside;
    }

    testWidgets('reaches every other source of the title', (tester) async {
      final other = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(other);
      final ctx = await scoped(tester, await pumpTree(tester), titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]));

      await markAll(tester, ctx, _itemOn('a', 'dune'));

      expect(other.writes, [(itemId: 'dune', watched: true)]);
    });

    testWidgets('a source that refuses is the caller\'s problem no more than a log line', (tester) async {
      final first = _HealthyClient('a');
      final last = _HealthyClient('c');
      serverManager
        ..debugRegisterClientForTesting(first)
        ..debugRegisterClientForTesting(_RefusingClient('b'))
        ..debugRegisterClientForTesting(last);
      final ctx = await scoped(
        tester,
        await pumpTree(tester),
        titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune'), _itemOn('c', 'dune')]),
      );

      final outcome = await markAll(tester, ctx, _itemOn('a', 'dune'));

      expect(outcome, WatchMarkOutcome.marked);
      expect(first.writes, hasLength(1));
      expect(last.writes, hasLength(1), reason: 'one refusal does not stop the source after it');
      final held = await tester.runAsync(() => db.getLatestWatchAction('b:dune'));
      expect(held?.actionType, 'mirroredWatched', reason: 'a refusal is retried like any queued write');
    });

    // What the server itself refused. A Pleya Server client that could not get a
    // token never asked: see 'a Pleya Server copy'.
    for (final (name, failure) in <(String, Object)>[
      ('a token Plex or Jellyfin rejected', const MediaServerAuthException('rejected', statusCode: 401)),
      ('a 403', MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 403)),
      ('a 404', MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 404)),
      ('a missing endpoint', UnsupportedError('no such endpoint')),
    ]) {
      testWidgets('$name gets no row: waiting does not fix it', (tester) async {
        serverManager
          ..debugRegisterClientForTesting(_HealthyClient('a'))
          ..debugRegisterClientForTesting(_RefusingClient('b', failure: failure));
        final ctx = await scoped(tester, await pumpTree(tester), titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]));

        await markAll(tester, ctx, _itemOn('a', 'dune'));

        final held = await tester.runAsync(() => db.getLatestWatchAction('b:dune'));
        expect(held, isNull);
      });
    }

    testWidgets('a server error is worth a retry and gets its row', (tester) async {
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(
          _RefusingClient(
            'b',
            failure: MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 503),
          ),
        );
      final ctx = await scoped(tester, await pumpTree(tester), titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]));

      await markAll(tester, ctx, _itemOn('a', 'dune'));

      final held = await tester.runAsync(() => db.getLatestWatchAction('b:dune'));
      expect(held?.actionType, 'mirroredWatched');
    });

    testWidgets('a profile that took over does not write the mark of the one before it', (tester) async {
      final other = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(other);
      final profiles = _Profiles('adult');
      await pumpTree(tester);
      late BuildContext ctx;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
            ChangeNotifierProvider<OfflineWatchProvider>.value(value: offlineWatch),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: profiles),
          ],
          child: MaterialApp(
            home: UnifiedTitleScope(
              title: _SlowTitle(
                titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]),
                onCopies: () => profiles.id = 'kid',
              ),
              child: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      await markAll(tester, ctx, _itemOn('a', 'dune'));

      expect(other.writes, isEmpty);
    });

    testWidgets('a write that fails after a profile switch leaves no row for the new profile', (tester) async {
      final profiles = _Profiles('adult');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(_SwitchesThenFails('b', () => profiles.id = 'kid'));
      await pumpTree(tester);
      late BuildContext ctx;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
            ChangeNotifierProvider<OfflineWatchProvider>.value(value: offlineWatch),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: profiles),
          ],
          child: MaterialApp(
            home: UnifiedTitleScope(
              title: titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]),
              child: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      await markAll(tester, ctx, _itemOn('a', 'dune'));

      expect(await tester.runAsync(() => db.getLatestWatchAction('b:dune')), isNull);
    });

    testWidgets('one mark is one viewing: only the first source reports it', (tester) async {
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(_HealthyClient('b'));
      final ctx = await scoped(tester, await pumpTree(tester), titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]));
      final events = <WatchStateEvent>[];
      final subscription = WatchStateNotifier().stream.listen(events.add);
      addTearDown(subscription.cancel);

      await markAll(tester, ctx, _itemOn('a', 'dune'));

      expect({for (final e in events) e.globalKey: e.isCopy}, {'a:dune': false, 'b:dune': true});
    });

    testWidgets('a source that is down keeps the mark in the queue', (tester) async {
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(_HealthyClient('b'), online: false);
      final ctx = await scoped(tester, await pumpTree(tester), titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]));

      await markAll(tester, ctx, _itemOn('a', 'dune'));

      final action = await tester.runAsync(() => db.getLatestWatchAction('b:dune'));
      expect(action?.actionType, 'mirroredWatched');
    });

    testWidgets('a title on the page that is not this one still looks up its own copies', (tester) async {
      final other = _HealthyClient('b', ids: const ExternalIds(tmdb: 1), matches: [_itemOn('b', 'blade-runner')]);
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a', ids: const ExternalIds(tmdb: 1)))
        ..debugRegisterClientForTesting(other);
      final ctx = await scoped(tester, await pumpTree(tester), titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]));

      await markAll(tester, ctx, _itemOn('a', 'blade-runner'));

      expect(other.writes, [(itemId: 'blade-runner', watched: true)]);
    });

    testWidgets('the mark does not wait for a copy that hangs', (tester) async {
      final hung = _HungClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(hung);
      final ctx = await scoped(tester, await pumpTree(tester), titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]));

      final outcome = await tester.runAsync(() async {
        hung.answer = Completer<void>();
        final marked = await WatchActions.setWatched(ctx, _itemOn('a', 'dune'), watched: true);
        hung.answer.complete();
        await WatchActions.copiesReached();
        return marked;
      });

      expect(outcome, WatchMarkOutcome.marked);
    });

    testWidgets('a correction beats the mark whose lookup answers after it', (tester) async {
      final other = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(other);
      final copies = [_itemOn('a', 'dune'), _itemOn('b', 'dune')];
      late Completer<void> lookup;
      final tree = await pumpTree(tester);
      final slow = await scoped(tester, tree, _SlowTitle(titleOf(copies), holdUntil: () => lookup.future));

      await tester.runAsync(() async {
        lookup = Completer<void>();
        await WatchActions.setWatched(slow, _itemOn('a', 'dune'), watched: true);
        await WatchActions.setWatched(slow, _itemOn('a', 'dune'), watched: false);
        lookup.complete();
        await WatchActions.copiesReached();
      });

      expect(other.writes, [(itemId: 'dune', watched: false)], reason: 'the older mark stays away from the copy');
    });

    testWidgets('a mark made on the copy itself wins from the one still on its way to it', (tester) async {
      final other = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(other);
      final copies = [_itemOn('a', 'dune'), _itemOn('b', 'dune')];
      late Completer<void> lookup;
      final ctx = await scoped(
        tester,
        await pumpTree(tester),
        _SlowTitle(titleOf(copies), holdUntil: () => lookup.future),
      );

      await tester.runAsync(() async {
        lookup = Completer<void>();
        await WatchActions.setWatched(ctx, _itemOn('a', 'dune'), watched: true);
        await WatchActions.setWatched(ctx, _itemOn('b', 'dune'), watched: false);
        lookup.complete();
        await WatchActions.copiesReached();
      });

      expect(other.writes, [(itemId: 'dune', watched: false)]);
    });

    testWidgets('another cut keeps its own state, as it does for a play', (tester) async {
      final other = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(other);
      final theatrical = _itemOn('a', 'dune').copyWith(durationMs: 2 * 3600000);
      final extended = _itemOn('b', 'dune').copyWith(durationMs: 3 * 3600000);
      final ctx = await scoped(tester, await pumpTree(tester), titleOf([theatrical, extended]));

      await markAll(tester, ctx, theatrical);

      expect(other.writes, isEmpty);
      expect(await tester.runAsync(() => db.getLatestWatchAction('b:dune')), isNull);
    });

    testWidgets('a second film under the same title and year hears nothing of the mark', (tester) async {
      final other = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(other);
      final ctx = await scoped(
        tester,
        await pumpTree(tester),
        titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')], ids: const ExternalIds()),
      );

      await markAll(tester, ctx, _itemOn('a', 'dune'));

      expect(other.writes, isEmpty);
    });

    testWidgets('a correction beats the mark whose lookup on the other servers answers last', (tester) async {
      late Completer<void> answer;
      final other = _HealthyClient(
        'b',
        ids: const ExternalIds(tmdb: 1),
        matches: [_itemOn('b', 'dune')],
        lookupGate: () => answer.future,
      );
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a', ids: const ExternalIds(tmdb: 1)))
        ..debugRegisterClientForTesting(other);
      final ctx = await pumpTree(tester);

      await tester.runAsync(() async {
        answer = Completer<void>();
        await WatchActions.setWatched(ctx, _itemOn('a', 'dune'), watched: true);
        await pumpEventQueue();
        await WatchActions.setWatched(ctx, _itemOn('a', 'dune'), watched: false);
        answer.complete();
        await WatchActions.copiesReached();
      });

      expect(other.writes, [(itemId: 'dune', watched: false)]);
    });

    testWidgets('a server someone else runs hears nothing of the mark', (tester) async {
      await pumpTree(tester);
      final friend = _HealthyClient('friend');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(friend, online: false);
      final copies = WatchCopyWriter(serverManager, offlineWatch, null);

      final outcome = await copies.write(_itemOn('friend', 'dune'), watched: true);

      expect(outcome, WatchCopyOutcome.leftAlone);
      expect(friend.writes, isEmpty);
      expect(await db.getLatestWatchAction('friend:dune'), isNull);
    });

    testWidgets('a mark that lands directly clears what still waits for that copy', (tester) async {
      await pumpTree(tester);
      final other = _HealthyClient('b');
      serverManager.debugRegisterClientForTesting(other);
      await tester.runAsync(() async {
        await syncService.queueMirroredProgress(
          serverId: ServerId('b'),
          itemId: 'dune',
          viewOffset: 7000000,
          duration: 7200000,
          watched: true,
          profileId: syncService.activeProfileId,
        );
        await WatchCopyWriter(serverManager, offlineWatch, null).write(_itemOn('b', 'dune'), watched: false);
      });

      expect(await tester.runAsync(() => db.getLatestWatchAction('b:dune')), isNull);
    });

    testWidgets('a mark on the item itself clears it too', (tester) async {
      final ctx = await pumpTree(tester);
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(_HealthyClient('b'));
      await tester.runAsync(() async {
        await syncService.queueMirroredProgress(
          serverId: ServerId('b'),
          itemId: 'dune',
          viewOffset: 7000000,
          duration: 7200000,
          watched: true,
          profileId: syncService.activeProfileId,
        );
        await WatchActions.setWatched(ctx, _itemOn('b', 'dune'), watched: false);
      });

      expect(await tester.runAsync(() => db.getLatestWatchAction('b:dune')), isNull);
    });

    testWidgets('a mark on a season clears what waits for its episodes', (tester) async {
      await pumpTree(tester);
      final season = MediaItem(id: 'season', backend: MediaBackend.plex, kind: MediaKind.season, serverId: 'b');
      final other = _HealthyClient('b', episodes: [_itemOn('b', 'ep-3')]);
      serverManager.debugRegisterClientForTesting(other);
      await tester.runAsync(() async {
        await syncService.queueMirroredProgress(
          serverId: ServerId('b'),
          itemId: 'ep-3',
          viewOffset: 3000000,
          duration: 3600000,
          watched: true,
          profileId: syncService.activeProfileId,
        );
        await syncService.queueMirroredProgress(
          serverId: ServerId('b'),
          itemId: 'elsewhere',
          viewOffset: 3000000,
          duration: 3600000,
          watched: true,
          profileId: syncService.activeProfileId,
        );
        await WatchCopyWriter(serverManager, offlineWatch, null).write(season, watched: false);
      });

      expect(await tester.runAsync(() => db.getLatestWatchAction('b:ep-3')), isNull);
      expect(await tester.runAsync(() => db.getLatestWatchAction('b:elsewhere')), isNotNull);
    });

    testWidgets('a rejected token gets no row either: it would replay under the next login', (tester) async {
      await pumpTree(tester);
      final other = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(other, online: false)
        ..debugMarkAuthErrorForTesting(ServerId('b'));
      final copies = WatchCopyWriter(serverManager, offlineWatch, null);

      final outcome = await copies.write(_itemOn('b', 'dune'), watched: true);

      expect(outcome, WatchCopyOutcome.skipped);
      expect(await db.getLatestWatchAction('b:dune'), isNull);
    });

    testWidgets('a held mark stays with the profile that made it', (tester) async {
      await pumpTree(tester);
      serverManager.debugRegisterClientForTesting(_HealthyClient('b'), online: false);
      syncService.setActiveProfileId('adult');
      final copies = WatchCopyWriter(serverManager, offlineWatch, null);
      syncService.setActiveProfileId('kid');

      final outcome = await copies.write(_itemOn('b', 'dune'), watched: true);

      expect(outcome, WatchCopyOutcome.skipped);
      expect(await db.getLatestWatchAction('b:dune'), isNull);
    });

    testWidgets('another title on the same page stays alone', (tester) async {
      final other = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(other);
      final ctx = await scoped(tester, await pumpTree(tester), titleOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]));

      await markAll(tester, ctx, _itemOn('a', 'blade-runner'));

      expect(other.writes, isEmpty);
    });
  });

  group('a Pleya Server copy', () {
    late PleyaFakeServer server;
    late PleyaServerClient pleya;

    const failedRounds = [
      ('a rate limit', 429, 'auth.rate_limited'),
      ('a bare 401', 401, 'proxy'),
      ('a 409', 409, 'conflict'),
    ];

    Future<void> connect({(int, String)? failingRefresh}) async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
      server.addItem(id: 'movie-1', kind: 'movie', title: 'Dune', libraryId: 'lib-films', durationMs: 6720000);
      pleya = failingRefresh == null
          ? server.client()
          : PleyaServerClient.create(
              server.connection(),
              httpClientFactory: () => _FailingRefresh(server, failingRefresh.$1, failingRefresh.$2),
            );
      await pleya.refreshCapabilities();
      addTearDown(pleya.close);
      serverManager
        ..debugMarkAdministeredForTesting(pleya.serverId)
        ..debugRegisterClientForTesting(pleya);
    }

    MediaItem copy() => MediaItem(
      id: 'movie-1',
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      title: 'Dune',
      serverId: pleya.serverId.value,
    );

    Future<OfflineWatchProgressItem?> row() => db.getLatestWatchAction('${pleya.serverId}:movie-1');

    UnifiedMediaGroup groupOf(List<MediaItem> copies) {
      final sources = [
        for (final item in copies) UnifiedMediaSource.fromItem(item, externalIds: const ExternalIds(tmdb: 1)),
      ];
      return UnifiedMediaGroup(
        groupId: 'g',
        identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
        sources: sources,
        representativeSourceKey: sources.first.sourceKey,
        watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
      );
    }

    Future<void> markGroup(BuildContext ctx, List<MediaItem> copies) async {
      await runUnifiedGroupAction(
        ctx,
        action: UnifiedGroupAction.markWatched,
        group: groupOf(copies),
        availabilityFor: (_) => SourceAvailability.online,
      );
      await WatchActions.copiesReached();
    }

    for (final (name, status, code) in failedRounds) {
      testWidgets('$name on the token round keeps a direct mark: the write never went out', (tester) async {
        await pumpTree(tester);
        await tester.runAsync(() async {
          await connect(failingRefresh: (status, code));

          final outcome = await WatchCopyWriter(serverManager, offlineWatch, null).write(copy(), watched: true);

          expect(outcome, WatchCopyOutcome.held);
          expect((await row())?.actionType, 'mirroredWatched');
          expect(server.watchEvents, isEmpty);
        });
      });

      testWidgets('$name on the first source of a card keeps the mark as a copy', (tester) async {
        final other = _HealthyClient('b');
        serverManager.debugRegisterClientForTesting(other);
        final ctx = await pumpTree(tester);
        await tester.runAsync(() async {
          await connect(failingRefresh: (status, code));

          await markGroup(ctx, [copy(), _itemOn('b', 'movie-1')]);

          expect((await row())?.actionType, 'mirroredWatched');
          expect(other.writes, [(itemId: 'movie-1', watched: true)]);
        });
      });

      testWidgets('$name on the only source of a card keeps the report', (tester) async {
        final ctx = await pumpTree(tester);
        await tester.runAsync(() async {
          await connect(failingRefresh: (status, code));

          await markGroup(ctx, [copy()]);

          expect((await row())?.actionType, 'watched');
        });
      });
    }

    testWidgets('a write the server itself refuses gets no row', (tester) async {
      await pumpTree(tester);
      await tester.runAsync(() async {
        await connect();
        server.watchStateFailureStatus = 403;

        final outcome = await WatchCopyWriter(serverManager, offlineWatch, null).write(copy(), watched: true);

        expect(outcome, WatchCopyOutcome.skipped);
        expect(await row(), isNull);
      });
    });
  });

  group('the TV menu counts one viewing too', () {
    UnifiedMediaGroup groupOf(List<MediaItem> copies, {ExternalIds ids = const ExternalIds(tmdb: 1)}) {
      final sources = [for (final copy in copies) UnifiedMediaSource.fromItem(copy, externalIds: ids)];
      return UnifiedMediaGroup(
        groupId: 'g',
        identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
        sources: sources,
        representativeSourceKey: sources.first.sourceKey,
        watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
      );
    }

    testWidgets('the first membership reports it, the others only get the write', (tester) async {
      final second = _HealthyClient('b', ids: const ExternalIds(tmdb: 1), matches: [_itemOn('b', 'dune')]);
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a', ids: const ExternalIds(tmdb: 1)))
        ..debugRegisterClientForTesting(second);
      final ctx = await pumpTree(tester);
      final events = <WatchStateEvent>[];
      final subscription = WatchStateNotifier().stream.listen(events.add);
      addTearDown(subscription.cancel);

      await tester.runAsync(() async {
        await runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]),
          availabilityFor: (_) => SourceAvailability.online,
        );
        await WatchActions.copiesReached();
      });

      expect(second.writes, hasLength(1), reason: 'once: the lookup finds it too, and leaves it to the fan-out');
      expect({for (final e in events) e.globalKey: e.isCopy}, {'a:dune': false, 'b:dune': true});
    });

    testWidgets('a series only reaches the seasons both servers hold', (tester) async {
      MediaItem show(String server) =>
          MediaItem(id: 'show', backend: MediaBackend.plex, kind: MediaKind.show, title: 'Dune', serverId: server);
      MediaItem season(int number) =>
          MediaItem(id: 'season-$number', backend: MediaBackend.plex, kind: MediaKind.season, index: number);
      final first = _HealthyClient('a', seasons: [season(1), season(2)]);
      final second = _HealthyClient('b', seasons: [season(0), season(1), season(2), season(3)]);
      serverManager
        ..debugRegisterClientForTesting(first)
        ..debugRegisterClientForTesting(second);
      final ctx = await pumpTree(tester);

      await tester.runAsync(() async {
        await runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([show('a'), show('b')]),
          availabilityFor: (_) => SourceAvailability.online,
        );
        await WatchActions.copiesReached();
      });

      expect(first.writes, [(itemId: 'show', watched: true)]);
      expect(second.writes.map((w) => w.itemId), ['season-1', 'season-2']);
    });

    testWidgets('a card folded on title and year only marks the one the viewer picked', (tester) async {
      final second = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(second);
      final ctx = await pumpTree(tester);

      await tester.runAsync(() async {
        await runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')], ids: const ExternalIds()),
          availabilityFor: (_) => SourceAvailability.online,
        );
        await WatchActions.copiesReached();
      });

      expect(second.writes, isEmpty);
    });

    testWidgets('a mark an own server refuses for now joins the queue', (tester) async {
      serverManager
        ..debugRegisterClientForTesting(_RefusingClient('a', failure: Exception('503')))
        ..debugRegisterClientForTesting(_HealthyClient('b'));
      final ctx = await pumpTree(tester);

      await tester.runAsync(() async {
        await runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]),
          availabilityFor: (_) => SourceAvailability.online,
        );
        await WatchActions.copiesReached();
      });

      expect((await tester.runAsync(() => db.getLatestWatchAction('a:dune')))?.actionType, 'mirroredWatched');
    });

    testWidgets('a Special on a card keeps its number to itself', (tester) async {
      MediaItem special(String server) => MediaItem(
        id: 'sp',
        backend: MediaBackend.plex,
        kind: MediaKind.episode,
        title: 'Special',
        grandparentId: 'show',
        parentIndex: 0,
        index: 5,
        serverId: server,
      );
      final second = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(second);
      final ctx = await pumpTree(tester);

      await tester.runAsync(() async {
        await runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([special('a'), special('b')]),
          availabilityFor: (_) => SourceAvailability.online,
        );
        await WatchActions.copiesReached();
      });

      expect(second.writes, isEmpty);
    });

    testWidgets('the mark lands on the viewer\'s own server, whatever ranks first', (tester) async {
      // `rankSources` ends on the server name: this friend comes first.
      final friend = _HealthyClient('a-friend');
      final mine = _HealthyClient('zz');
      serverManager
        ..debugMarkAdministeredForTesting(ServerId('zz'))
        ..debugRegisterClientForTesting(friend)
        ..debugRegisterClientForTesting(mine);
      final ctx = await pumpTree(tester);
      final events = <WatchStateEvent>[];
      final subscription = WatchStateNotifier().stream.listen(events.add);
      addTearDown(subscription.cancel);

      await tester.runAsync(() async {
        await runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([_itemOn('a-friend', 'dune'), _itemOn('zz', 'dune')]),
          availabilityFor: (_) => SourceAvailability.online,
        );
        await WatchActions.copiesReached();
      });

      expect(friend.writes, isEmpty);
      expect(mine.writes, hasLength(1));
      expect(events.singleWhere((e) => e.globalKey == 'zz:dune').isCopy, isFalse, reason: 'it reports the viewing');
    });

    testWidgets('held for later it goes to the viewer\'s own server as well', (tester) async {
      serverManager
        ..debugMarkAdministeredForTesting(ServerId('zz'))
        ..debugRegisterClientForTesting(_HealthyClient('a-friend'), online: false)
        ..debugRegisterClientForTesting(_HealthyClient('zz'), online: false);
      final ctx = await pumpTree(tester);

      await tester.runAsync(
        () => runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([_itemOn('a-friend', 'dune'), _itemOn('zz', 'dune')]),
          availabilityFor: (_) => SourceAvailability.offline,
        ),
      );

      expect(await tester.runAsync(() => db.getLatestWatchAction('a-friend:dune')), isNull);
      expect((await tester.runAsync(() => db.getLatestWatchAction('zz:dune')))?.actionType, 'watched');
    });

    testWidgets('a card with only someone else\'s servers gets it on the one the viewer sees', (tester) async {
      final first = _HealthyClient('friend');
      final second = _HealthyClient('neighbour');
      serverManager
        ..debugRegisterClientForTesting(first)
        ..debugRegisterClientForTesting(second);
      final ctx = await pumpTree(tester);

      await tester.runAsync(() async {
        await runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([_itemOn('friend', 'dune'), _itemOn('neighbour', 'dune')]),
          availabilityFor: (_) => SourceAvailability.online,
        );
        await WatchActions.copiesReached();
      });

      expect(first.writes.length + second.writes.length, 1);
    });

    testWidgets('another cut in the group keeps its own state', (tester) async {
      final second = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(second);
      final ctx = await pumpTree(tester);

      await tester.runAsync(() async {
        await runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([
            _itemOn('a', 'dune').copyWith(durationMs: 2 * 3600000),
            _itemOn('b', 'dune').copyWith(durationMs: 3 * 3600000),
          ]),
          availabilityFor: (_) => SourceAvailability.online,
        );
        await WatchActions.copiesReached();
      });

      expect(second.writes, isEmpty);
    });

    testWidgets('a membership held for later is a copy once another one reported', (tester) async {
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(_HealthyClient('b'), online: false);
      final ctx = await pumpTree(tester);

      await tester.runAsync(
        () => runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]),
          availabilityFor: (source) =>
              source.serverId.value == 'a' ? SourceAvailability.online : SourceAvailability.offline,
        ),
      );

      final held = await tester.runAsync(() => db.getLatestWatchAction('b:dune'));
      expect(held?.actionType, 'mirroredWatched');
    });

    testWidgets('with nothing reachable the first held row carries the report', (tester) async {
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'), online: false)
        ..debugRegisterClientForTesting(_HealthyClient('b'), online: false);
      final ctx = await pumpTree(tester);

      await tester.runAsync(
        () => runUnifiedGroupAction(
          ctx,
          action: UnifiedGroupAction.markWatched,
          group: groupOf([_itemOn('a', 'dune'), _itemOn('b', 'dune')]),
          availabilityFor: (_) => SourceAvailability.offline,
        ),
      );

      final first = await tester.runAsync(() => db.getLatestWatchAction('a:dune'));
      final second = await tester.runAsync(() => db.getLatestWatchAction('b:dune'));
      expect(first?.actionType, 'watched');
      expect(second?.actionType, 'mirroredWatched');
    });
  });

  group('a mark on an unreachable server stays durable', () {
    testWidgets('one server down while another is up still queues the mark', (tester) async {
      final down = _UnreachableClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(down, online: false);

      final ctx = await pumpTree(tester);
      expect(offlineMode.isOffline, isFalse, reason: 'server a is up, so the app is not in offline mode');

      final outcome = await WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: true);

      expect(outcome, WatchMarkOutcome.queuedOffline);
      expect(
        await syncService.getPendingSyncCount(),
        1,
        reason: 'the mark belongs to server b, which is down, so it has to wait for server b',
      );
      expect(down.markWatchedCalls, 0, reason: 'no point spending a doomed request on a server known to be down');
    });

    testWidgets('unmarking on an unreachable server queues too', (tester) async {
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(_UnreachableClient('b'), online: false);

      final ctx = await pumpTree(tester);

      final outcome = await WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: false);

      expect(outcome, WatchMarkOutcome.queuedOffline);
      expect(await syncService.getPendingSyncCount(), 1);
    });

    testWidgets('a server with no client at all queues rather than doing nothing', (tester) async {
      // `skipped` used to be the answer here: the button reacted, nothing
      // happened, and nothing said so.
      serverManager.debugRegisterClientForTesting(_HealthyClient('a'));

      final ctx = await pumpTree(tester);

      final outcome = await WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: true);

      expect(outcome, WatchMarkOutcome.queuedOffline);
      expect(await syncService.getPendingSyncCount(), 1);
    });
  });

  group('the reachable paths are untouched', () {
    testWidgets('a mark on a healthy server still goes straight to it', (tester) async {
      final healthy = _HealthyClient('a');
      serverManager.debugRegisterClientForTesting(healthy);

      final ctx = await pumpTree(tester);

      final outcome = await WatchActions.setWatched(ctx, _itemOn('a', 'i1'), watched: true);

      expect(outcome, WatchMarkOutcome.marked);
      expect(healthy.writes, [(itemId: 'i1', watched: true)]);
      expect(await syncService.getPendingSyncCount(), 0, reason: 'a write that landed has nothing to queue');
    });

    testWidgets('a server outside the profile filter is still written to directly', (tester) async {
      // Profile visibility scopes what a surface *shows*, not what a server can
      // accept. Reading the filtered answer here deferred a write to a server
      // that was up, while `tv_unified_context_actions` read the unfiltered one
      // and had already counted the same membership as written.
      final hidden = _HealthyClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(hidden);

      final ctx = await pumpTree(tester);
      multiServer.setVisibleServerIds({'a'});
      expect(multiServer.isServerOnline(ServerId('b')), isFalse, reason: 'invisible to the active profile');
      expect(serverManager.isServerOnline(ServerId('b')), isTrue, reason: 'but the server itself is up');

      final outcome = await WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: true);

      expect(outcome, WatchMarkOutcome.marked);
      expect(hidden.writes, [(itemId: 'i1', watched: true)]);
      expect(await syncService.getPendingSyncCount(), 0);
    });

    testWidgets('a rejected token reaches the caller instead of the queue', (tester) async {
      // An auth rejection reads as not-online, but no reconnect fixes it, so
      // queueing would swap the re-auth prompt for a silent "marked offline"
      // while the app is plainly online. `tv_unified_context_actions` refuses
      // to queue an auth error for the same reason.
      final rejected = _UnreachableClient('b');
      serverManager
        ..debugRegisterClientForTesting(_HealthyClient('a'))
        ..debugRegisterClientForTesting(rejected)
        ..debugMarkAuthErrorForTesting(ServerId('b'));

      final ctx = await pumpTree(tester);

      await expectLater(WatchActions.setWatched(ctx, _itemOn('b', 'i1'), watched: true), throwsA(isA<Exception>()));
      expect(rejected.markWatchedCalls, 1, reason: 'the write is attempted so the 401 can surface');
      expect(await syncService.getPendingSyncCount(), 0, reason: 'nothing waits for a reconnect that cannot help');
    });

    testWidgets('an item with no server id is still skipped', (tester) async {
      serverManager.debugRegisterClientForTesting(_HealthyClient('a'));

      final ctx = await pumpTree(tester);
      final item = MediaItem(id: 'i1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune');

      expect(await WatchActions.setWatched(ctx, item, watched: true), WatchMarkOutcome.skipped);
      expect(await syncService.getPendingSyncCount(), 0, reason: 'the queue is keyed by server, so there is no row');
    });

    testWidgets('an explicit offline caller keeps queueing', (tester) async {
      serverManager.debugRegisterClientForTesting(_HealthyClient('a'));

      final ctx = await pumpTree(tester);

      final outcome = await WatchActions.setWatched(ctx, _itemOn('a', 'i1'), watched: true, offline: true);

      expect(outcome, WatchMarkOutcome.queuedOffline);
      expect(await syncService.getPendingSyncCount(), 1);
    });
  });
}
