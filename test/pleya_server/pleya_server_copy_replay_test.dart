/// The real client through the real queue: a row for a Pleya Server copy lands,
/// on a title nobody touched as well, and only a proven 404 ends it. Everything
/// a fake client answers here would be the code talking to itself.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/database/app_database.dart';
import 'package:pleya/database/download_operations.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/pleya_server_api_cache.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

import 'pleya_fake_server.dart';

void main() {
  late AppDatabase db;
  late PleyaFakeServer server;
  late PleyaServerClient client;
  late MultiServerManager manager;
  late OfflineWatchSyncService queue;
  const length = 6720000;

  Future<void> connect({
    Map<String, dynamic>? userState,
    bool copy = false,
    http.Client Function(PleyaFakeServer server)? transport,
  }) async {
    server = PleyaFakeServer(watchState: true, watchStateOwnership: true)..watchStateCopyCapability = copy;
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    server.addItem(
      id: 'movie-1',
      kind: 'movie',
      title: 'Grease',
      libraryId: 'lib-films',
      durationMs: length,
      userState: userState,
    );
    client = transport == null
        ? server.client()
        : PleyaServerClient.create(server.connection(), httpClientFactory: () => transport(server));
    await client.refreshCapabilities();
    addTearDown(client.close);
    manager
      ..debugMarkAdministeredForTesting(client.serverId)
      ..debugRegisterClientForTesting(client);
  }

  Future<void> mirrored({int offset = 1800000, bool watched = false, String item = 'movie-1'}) =>
      queue.queueMirroredProgress(
        serverId: ServerId(client.serverId),
        itemId: item,
        viewOffset: offset,
        duration: length,
        watched: watched,
        profileId: queue.activeProfileId,
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    PleyaServerApiCache.initialize(db);
    manager = MultiServerManager();
    queue = OfflineWatchSyncService(database: db, serverManager: manager);
  });

  tearDown(() async {
    queue.dispose();
    manager.dispose();
    await db.close();
  });

  group('a position has no way onto this server without a viewing', () {
    test('the row ends, nothing goes out, and a next round has nothing to repeat', () async {
      await connect();
      await mirrored();

      await queue.syncPendingItems();
      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('nothing is told to the surfaces either: the copy did not change', () async {
      await connect();
      await mirrored();
      final events = <WatchStateEvent>[];
      final subscription = WatchStateNotifier().stream.listen(events.add);
      addTearDown(subscription.cancel);

      await queue.syncPendingItems();
      await pumpEventQueue();

      expect(events, isEmpty);
    });
  });

  group('a finished viewing on a copy is a mark, on a title nobody touched as well', () {
    test('it goes out once as mark_watched and ends the row', () async {
      await connect();
      await mirrored(watched: true);

      await queue.syncPendingItems();

      expect(server.watchEvents.single['explicit_action'], 'mark_watched');
      expect(server.watchEvents.single.containsKey('cause'), isFalse);
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('the surfaces hear it as a copy, so a tracker does not count it twice', () async {
      await connect();
      await mirrored(watched: true);
      final events = <WatchStateEvent>[];
      final subscription = WatchStateNotifier().stream.listen(events.add);
      addTearDown(subscription.cancel);

      await queue.syncPendingItems();
      await pumpEventQueue();

      expect(events.single.isCopy, isTrue);
    });

    for (final (name, body) in const [
      ('a body that is no object', '"ok"'),
      ('a list', '[]'),
      ('an object that is no state', '{"status":"ok"}'),
    ]) {
      test('a 200 with $name says nothing, so the row stays and nobody hears of it', () async {
        await connect();
        await mirrored(watched: true);
        server.watchStateRawAnswer = body;
        final events = <WatchStateEvent>[];
        final subscription = WatchStateNotifier().stream.listen(events.add);
        addTearDown(subscription.cancel);

        await queue.syncPendingItems();
        await pumpEventQueue();

        expect(server.watchEvents.single['explicit_action'], 'mark_watched');
        expect((await db.getLatestWatchAction('${client.serverId}:movie-1'))?.syncAttempts, 1);
        expect(events, isEmpty);
      });
    }

    test('a server error keeps the row for the next round', () async {
      await connect();
      await mirrored(watched: true);
      server.watchStateFailureStatus = 503;

      await queue.syncPendingItems();

      expect((await db.getLatestWatchAction('${client.serverId}:movie-1'))?.syncAttempts, 1);
    });

    test('a refusal ends the row: nothing here waits for its turn', () async {
      await connect();
      await mirrored(watched: true);
      server.watchStateFailureStatus = 403;

      await queue.syncPendingItems();

      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });
  });

  group('a finished viewing on a title that was written a moment ago', () {
    Map<String, dynamic> writtenAt(DateTime at) => {
      'position_ms': 2400000,
      'watched': false,
      'play_count': 0,
      'updated_at': at.toUtc().toIso8601String(),
      'revision': 7,
    };

    test('leaves a session on it alone: no mark goes out, the row stays, the lease stands', () async {
      await connect(userState: writtenAt(DateTime.now().subtract(const Duration(seconds: 5))));
      server.watchLeases['movie-1'] = 'tv-watching';
      await mirrored(watched: true);

      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect(server.watchLeases['movie-1'], 'tv-watching');
      expect((await db.getLatestWatchAction('${client.serverId}:movie-1'))?.syncAttempts, 1);
    });

    test('ends when that session ticked on: the newest wins', () async {
      await connect(userState: writtenAt(DateTime.now().subtract(const Duration(seconds: 5))));
      server.watchLeases['movie-1'] = 'tv-watching';
      await mirrored(watched: true);
      await queue.syncPendingItems();

      server.acceptTick('movie-1', positionMs: 2700000, at: DateTime.now().add(const Duration(minutes: 1)));
      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('lands once nothing moved for two leases', () async {
      await connect(userState: writtenAt(DateTime.now().subtract(const Duration(seconds: 5))));
      await mirrored(watched: true);
      await queue.syncPendingItems();

      server.acceptTick('movie-1', positionMs: 2400000, at: DateTime.now().subtract(const Duration(minutes: 4)));
      await queue.syncPendingItems();

      expect(server.watchEvents.single['explicit_action'], 'mark_watched');
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('an old write holds nothing back', () async {
      await connect(userState: writtenAt(DateTime.now().subtract(const Duration(minutes: 4))));
      await mirrored(watched: true);

      await queue.syncPendingItems();

      expect(server.watchEvents.single['explicit_action'], 'mark_watched');
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });
  });

  group('with watch_state_copy a row goes out as a copy', () {
    test('a position lands in one event, and the row ends', () async {
      await connect(copy: true);
      await mirrored();

      await queue.syncPendingItems();

      final event = server.watchEvents.single;
      expect(event['copy'], isTrue);
      expect(event['position_ms'], 1800000);
      expect(event['explicit_action'], 'none');
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('a finished viewing lands and is heard as a copy', () async {
      await connect(copy: true);
      await mirrored(watched: true);
      final events = <WatchStateEvent>[];
      final subscription = WatchStateNotifier().stream.listen(events.add);
      addTearDown(subscription.cancel);

      await queue.syncPendingItems();
      await pumpEventQueue();

      expect(server.watchEvents.single['completed'], isTrue);
      expect(server.watchEvents.single['copy'], isTrue);
      expect(events.single.isCopy, isTrue);
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('the same position again has nothing to add: the copy shows it now', () async {
      await connect(copy: true);
      await mirrored();
      await queue.syncPendingItems();
      await mirrored();

      await queue.syncPendingItems();

      expect(server.watchEvents, hasLength(1));
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('a position on a title someone is watching ends the row: that viewing is newer', () async {
      await connect(copy: true);
      server.watchLeases['movie-1'] = 'someone-watching';
      await mirrored();

      await queue.syncPendingItems();

      expect(server.watchStates, isEmpty);
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('a finished viewing stays behind a viewing, and lands when that viewing added nothing', () async {
      await connect(copy: true);
      server.watchLeases['movie-1'] = 'someone-watching';
      await mirrored(watched: true);

      await queue.syncPendingItems();
      expect((await db.getLatestWatchAction('${client.serverId}:movie-1'))?.syncAttempts, 1);

      server.watchLeases.clear();
      await queue.syncPendingItems();

      expect(server.watchStates['movie-1']?['watched'], isTrue);
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('a finished viewing ends when the viewing ticked on: the newest wins, the copy stays unseen', () async {
      await connect(copy: true);
      server.watchLeases['movie-1'] = 'someone-watching';
      await mirrored(watched: true);
      await queue.syncPendingItems();

      server.acceptTick('movie-1', positionMs: 2700000, at: DateTime.now().add(const Duration(minutes: 1)));
      server.watchLeases.clear();
      await queue.syncPendingItems();

      expect(server.watchEvents, hasLength(1));
      expect(server.watchStates, isEmpty);
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });

    test('a title that was set back to unwatched takes a position again: play_count stays behind', () async {
      await connect(userState: _unwatchedTwice, copy: true);
      await mirrored();

      await queue.syncPendingItems();

      expect(server.watchEvents.single['position_ms'], 1800000);
      expect(server.watchStates['movie-1']?['play_count'], 2);
    });

    test('a watched title gets no request for a position', () async {
      await connect(userState: _watchedOnce, copy: true);
      await mirrored();

      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });
  });

  group('every kind of row reaches a server that is online', () {
    test('a held mark', () async {
      await connect();
      await queue.queueCopyMark(
        serverId: ServerId(client.serverId),
        itemId: 'movie-1',
        watched: true,
        profileId: queue.activeProfileId,
      );

      await queue.syncPendingItems();

      expect(server.watchEvents.single['explicit_action'], 'mark_watched');
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('a viewing that ran offline on this server itself', () async {
      await connect();
      await db.upsertProgressAction(
        serverId: ServerId(client.serverId),
        clientScopeId: client.scopedServerId,
        ratingKey: 'movie-1',
        viewOffset: 1800000,
        duration: length,
        shouldMarkWatched: false,
      );

      await queue.syncPendingItems();

      expect(server.watchEvents, isNotEmpty);
      expect(await queue.getPendingSyncCount(), 0);
    });
  });

  test('a row of another account on that server waits for that account', () async {
    await connect();
    await db.upsertProgressAction(
      serverId: ServerId(client.serverId),
      clientScopeId: 'pleyaServer.srv-1.someone-else',
      ratingKey: 'movie-1',
      viewOffset: 1800000,
      duration: length,
      shouldMarkWatched: false,
      actionType: OfflineActionType.mirroredProgress,
    );

    await queue.syncPendingItems();

    expect(server.watchEvents, isEmpty);
    expect(await queue.getPendingSyncCount(), 1);
  });

  group('a read that says nothing about the copy', () {
    test('a server error keeps the row', () async {
      await connect();
      await mirrored(watched: true);
      server.queueFailure(pathPrefix: '/items/movie-1', status: 503);

      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      final row = await db.getLatestWatchAction('${client.serverId}:movie-1');
      expect(row?.syncAttempts, 1);
    });

    test('a proven 404 ends the row', () async {
      await connect();
      await mirrored(item: 'gone');

      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect(await queue.getPendingSyncCount(), 0);
    });
  });

  group('a copy that finished counts no viewing', () {
    for (final kind in const ['movie', 'episode']) {
      test('$kind: a client that reads play_count sees it as watched', () async {
        await connect(copy: true);
        server.addItem(id: 'copy-1', kind: kind, title: 'Grease', libraryId: 'lib-films', durationMs: length);
        await mirrored(watched: true, item: 'copy-1');

        await queue.syncPendingItems();

        final item = await client.fetchItem('copy-1');
        expect(item?.viewCount, 1);
        expect(item?.isWatched, isTrue);
      });

      test('$kind: the plays it had stay what they were', () async {
        await connect(copy: true);
        server.addItem(
          id: 'copy-1',
          kind: kind,
          title: 'Grease',
          libraryId: 'lib-films',
          durationMs: length,
          userState: _unwatchedTwice,
        );
        await mirrored(watched: true, item: 'copy-1');

        await queue.syncPendingItems();

        expect(server.watchStates['copy-1']?['watched'], isTrue);
        expect(server.watchStates['copy-1']?['play_count'], 2);
      });
    }
  });

  test('a title that was set back to unwatched takes a finished viewing again: play_count stays behind', () async {
    await connect(userState: _unwatchedTwice);
    await mirrored(watched: true);

    await queue.syncPendingItems();

    expect(server.watchEvents.single['explicit_action'], 'mark_watched');
  });

  test('a position that ran offline on a title set back to unwatched ends its row', () async {
    await connect(userState: _unwatchedTwice);
    await db.upsertProgressAction(
      serverId: ServerId(client.serverId),
      clientScopeId: client.scopedServerId,
      ratingKey: 'movie-1',
      viewOffset: 1800000,
      duration: length,
      shouldMarkWatched: false,
    );

    await queue.syncPendingItems();

    expect(server.watchEvents.single['backlog'], isTrue);
    expect(await queue.getPendingSyncCount(), 0);
  });

  group('a token round that fails says nothing about the copy', () {
    for (final (name, status, code) in const [
      ('a rate limit', 429, 'auth.rate_limited'),
      ('a bare 401', 401, 'proxy'),
      ('a 409', 409, 'conflict'),
    ]) {
      test('$name keeps the row', () async {
        // On every refresh: the session waits out a single 429 itself.
        await connect(transport: (server) => _FailingRefresh(server, status, code));
        await mirrored(watched: true);

        await queue.syncPendingItems();

        expect((await db.getLatestWatchAction('${client.serverId}:movie-1'))?.syncAttempts, 1);
      });
    }
  });

  group('a mark held for a copy when the token round fails', () {
    Future<void> connectFailing(int status, String code) async {
      server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
      server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
      server.addItem(id: 'movie-1', kind: 'movie', title: 'Grease', libraryId: 'lib-films', durationMs: length);
      client = PleyaServerClient.create(
        server.connection(),
        httpClientFactory: () => _FailingRefresh(server, status, code),
      );
      await client.refreshCapabilities();
      addTearDown(client.close);
      manager
        ..debugMarkAdministeredForTesting(client.serverId)
        ..debugRegisterClientForTesting(client);
    }

    Future<void> heldMark({required bool watched}) => queue.queueCopyMark(
      serverId: ServerId(client.serverId),
      itemId: 'movie-1',
      watched: watched,
      profileId: queue.activeProfileId,
    );

    for (final (name, status, code) in const [
      ('a rate limit', 429, 'auth.rate_limited'),
      ('a bare 401', 401, 'proxy'),
      ('a 409', 409, 'conflict'),
    ]) {
      for (final watched in const [true, false]) {
        test('$name keeps the mark (watched: $watched): nothing was sent', () async {
          await connectFailing(status, code);
          await heldMark(watched: watched);

          await queue.syncPendingItems();

          expect(server.watchEvents, isEmpty);
          expect((await db.getLatestWatchAction('${client.serverId}:movie-1'))?.syncAttempts, 1);
        });
      }
    }

    test('a revoked chain keeps it too: the write never went out, and a sign-in brings it home', () async {
      await connectFailing(401, 'auth.refresh_token_reused');
      await heldMark(watched: true);

      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect((await db.getLatestWatchAction('${client.serverId}:movie-1'))?.syncAttempts, 1);
    });

    test('a write the server itself refuses still ends the row', () async {
      await connect();
      await heldMark(watched: true);
      server.watchStateFailureStatus = 403;

      await queue.syncPendingItems();

      expect(await db.getLatestWatchAction('${client.serverId}:movie-1'), isNull);
    });
  });

  group('a mark held for a copy that moved on after it', () {
    Map<String, dynamic> viewedLater({required bool watched}) => {
      'position_ms': watched ? 0 : 3000000,
      'watched': watched,
      'play_count': 1,
      'updated_at': DateTime.now().toUtc().add(const Duration(days: 2)).toIso8601String(),
      'revision': 3,
    };

    Future<void> heldMark({required bool watched}) => queue.queueCopyMark(
      serverId: ServerId(client.serverId),
      itemId: 'movie-1',
      watched: watched,
      profileId: queue.activeProfileId,
    );

    test('as unwatched leaves a copy watched since', () async {
      await connect(userState: viewedLater(watched: true));
      await heldMark(watched: false);

      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('as watched does not set a newer position to zero', () async {
      await connect(userState: viewedLater(watched: false));
      await heldMark(watched: true);

      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('a read that gets a server error keeps the mark', () async {
      await connect();
      await heldMark(watched: true);
      server.queueFailure(pathPrefix: '/items/movie-1', status: 503);

      await queue.syncPendingItems();

      expect(server.watchEvents, isEmpty);
      expect((await db.getLatestWatchAction('${client.serverId}:movie-1'))?.syncAttempts, 1);
    });
  });

  group('the pull on a downloaded film', () {
    for (final (name, state) in const [
      ('watched', <String, dynamic>{..._watchedOnce}),
      ('set back to unwatched', <String, dynamic>{..._unwatchedTwice}),
    ]) {
      test('$name: three rounds report nothing, without an earlier state to compare with', () async {
        await connect(userState: state);
        await db.insertDownload(
          serverId: ServerId(client.serverId),
          clientScopeId: client.scopedServerId,
          ratingKey: 'movie-1',
          globalKey: '${client.serverId}:movie-1',
          type: 'movie',
          status: 3,
        );
        await db.addDownloadOwner(profileId: 'p', globalKey: '${client.serverId}:movie-1');
        queue.setActiveProfileId('p');
        final events = <WatchStateEvent>[];
        final subscription = WatchStateNotifier().stream.listen(events.add);
        addTearDown(subscription.cancel);

        for (var round = 0; round < 3; round++) {
          await queue.syncWatchStatesFromServer();
          await pumpEventQueue();
        }

        expect(events.where((e) => e.changeType == WatchStateChangeType.watched), isEmpty);
      });
    }
  });
}

/// `queueFailure` lasts one request, and the sync makes several.
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

const _watchedOnce = {
  'position_ms': 0,
  'watched': true,
  'play_count': 1,
  'updated_at': '2026-01-01T00:00:00Z',
  'revision': 3,
};

const _unwatchedTwice = {
  'position_ms': 0,
  'watched': false,
  'play_count': 2,
  'updated_at': '2026-01-01T00:00:00Z',
  'revision': 3,
};
