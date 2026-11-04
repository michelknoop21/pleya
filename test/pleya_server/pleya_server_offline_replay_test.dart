/// A viewing that ran offline on Pleya Server itself, through the real client and
/// the real queue. A backlog is history once a title has a state (rule 6), and the
/// server says so with a 200. So the answer decides what happened, and nobody hears
/// of a viewing that did not land.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/database/app_database.dart';
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
  late List<bool> heard;
  late List<WatchStateEvent> told;
  const length = 6720000;

  Future<void> connect({
    Map<String, dynamic>? userState,
    http.Client Function(PleyaFakeServer server)? transport,
  }) async {
    server = PleyaFakeServer(watchState: true, watchStateOwnership: true);
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

  Future<void> playedOffline({required bool finished}) => db.upsertProgressAction(
    serverId: ServerId(client.serverId),
    clientScopeId: client.scopedServerId,
    ratingKey: 'movie-1',
    viewOffset: finished ? length : 1800000,
    duration: length,
    shouldMarkWatched: finished,
  );

  Future<void> sync() async {
    await queue.syncPendingItems();
    await pumpEventQueue();
  }

  Future<OfflineWatchProgressItem?> row() => db.getLatestWatchAction('${client.serverId}:movie-1');

  Map<String, dynamic> state({required DateTime at}) => {
    'position_ms': 600000,
    'watched': false,
    'play_count': 0,
    'updated_at': at.toUtc().toIso8601String(),
    'revision': 3,
  };

  final longAgo = DateTime.utc(2026, 1, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    PleyaServerApiCache.initialize(db);
    manager = MultiServerManager();
    heard = [];
    told = [];
    final subscription = WatchStateNotifier().stream.listen(told.add);
    addTearDown(subscription.cancel);
    queue = OfflineWatchSyncService(database: db, serverManager: manager)
      ..onOwnPlayReplayed = (item, position, duration, {required watched}) => heard.add(watched);
  });

  tearDown(() async {
    queue.dispose();
    manager.dispose();
    await db.close();
  });

  group('a finished viewing on a title that has a state', () {
    test('the server turns the backlog down, so a mark puts it there', () async {
      await connect(userState: state(at: longAgo));
      await playedOffline(finished: true);

      await sync();

      expect(server.watchEvents.first['backlog'], isTrue);
      expect(server.watchEvents.last['explicit_action'], 'mark_watched');
      expect(server.watchEvents, hasLength(2));
      expect(server.watchStates['movie-1']?['watched'], isTrue);
      expect(await row(), isNull);
      expect(heard, [true]);
    });

    test('a session on it stands: no mark, the row stays, and nobody hears of it', () async {
      await connect(userState: state(at: DateTime.now().subtract(const Duration(seconds: 5))));
      server.watchLeases['movie-1'] = 'tv-watching';
      await playedOffline(finished: true);

      await sync();

      expect(server.watchEvents.single['backlog'], isTrue);
      expect(server.watchLeases['movie-1'], 'tv-watching');
      expect((await row())?.syncAttempts, 1);
      expect(heard, isEmpty);
    });

    test('ends when that session ticked on: the newest wins, and nobody hears of it', () async {
      await connect(userState: state(at: DateTime.now().subtract(const Duration(seconds: 5))));
      server.watchLeases['movie-1'] = 'tv-watching';
      await playedOffline(finished: true);
      await sync();

      server.acceptTick('movie-1', positionMs: 2700000, at: DateTime.now().add(const Duration(minutes: 1)));
      await sync();

      expect(server.watchEvents.where((event) => event['explicit_action'] == 'mark_watched'), isEmpty);
      expect(await row(), isNull);
      expect(heard, isEmpty);
    });

    test('lands once nothing moved for two leases', () async {
      await connect(userState: state(at: DateTime.now().subtract(const Duration(seconds: 5))));
      await playedOffline(finished: true);
      await sync();

      server.acceptTick('movie-1', positionMs: 600000, at: DateTime.now().subtract(const Duration(minutes: 4)));
      await sync();

      expect(server.watchEvents.last['explicit_action'], 'mark_watched');
      expect(await row(), isNull);
      expect(heard, [true]);
    });

    test('a mark that fails keeps the row, and nobody hears of it', () async {
      await connect(
        userState: state(at: longAgo),
        transport: _FailingMark.new,
      );
      await playedOffline(finished: true);

      await sync();

      expect((await row())?.syncAttempts, 1);
      expect(heard, isEmpty);
    });

    test('an answer that does not say watched keeps the row, and nobody hears of it', () async {
      await connect(userState: state(at: longAgo));
      server.watchStateRawAnswer = jsonEncode(state(at: longAgo));
      await playedOffline(finished: true);

      await sync();

      expect((await row())?.syncAttempts, 1);
      expect(heard, isEmpty);
    });

    test('a server error on the backlog keeps the row', () async {
      await connect(userState: state(at: longAgo));
      server.watchStateFailureStatus = 500;
      await playedOffline(finished: true);

      await sync();

      expect((await row())?.syncAttempts, 1);
      expect(heard, isEmpty);
    });
  });

  test('a finished viewing on a title a copy set to watched is one announcement, without a mark', () async {
    Map<String, dynamic> copied({required DateTime at}) => {
      'position_ms': 0,
      'watched': true,
      'play_count': 1,
      'updated_at': at.toUtc().toIso8601String(),
      'revision': 3,
    };
    await connect(
      userState: copied(at: longAgo),
      // The server takes it as the first viewing, and that moves updated_at.
      transport: (server) => _AfterWrite(server, '"backlog":true', () {
        server.items['movie-1']?['user_state'] = copied(at: DateTime.now().add(const Duration(minutes: 1)));
      }),
    );
    await playedOffline(finished: true);

    await sync();

    expect(server.watchEvents.single['backlog'], isTrue);
    expect(await row(), isNull);
    expect(heard, [true]);
    expect(told, hasLength(1));
  });

  group('a read that fails before the backlog says nothing, so the read after it decides', () {
    for (final (name, standing) in [
      (
        'a viewing that went further on',
        {
          'position_ms': 2700000,
          'watched': false,
          'play_count': 0,
          'updated_at': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
          'revision': 4,
        },
      ),
      (
        'a mark as unwatched',
        {
          'position_ms': 0,
          'watched': false,
          'play_count': 1,
          'updated_at': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
          'revision': 4,
        },
      ),
      (
        'a mark as watched',
        {
          'position_ms': 0,
          'watched': true,
          'play_count': 1,
          'updated_at': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
          'revision': 4,
        },
      ),
    ]) {
      test('$name stands: no mark, the row ends, and nobody hears of it', () async {
        await connect(userState: standing, transport: _FlakyReads.new);
        await playedOffline(finished: true);

        await sync();

        expect(server.watchEvents.single['backlog'], isTrue);
        expect(server.watchStates, isEmpty);
        expect(await row(), isNull);
        expect(heard, isEmpty);
        expect(told, isEmpty);
      });
    }

    test('an older state still gets the mark', () async {
      await connect(
        userState: state(at: longAgo),
        transport: _FlakyReads.new,
      );
      await playedOffline(finished: true);

      await sync();

      expect(server.watchEvents.last['explicit_action'], 'mark_watched');
      expect(await row(), isNull);
      expect(heard, [true]);
    });

    test('what was watched comes from that read, so a tracker can place it', () async {
      await connect(
        userState: state(at: longAgo),
        transport: _FlakyReads.new,
      );
      await playedOffline(finished: true);

      await sync();

      expect(told.single.mediaType, 'movie');
    });
  });

  group('a profile that changes once the write is out', () {
    for (final (name, userState, write) in [
      ('after the mark', _anOldState, '"mark_watched"'),
      ('after a backlog that landed', null, '"backlog":true'),
    ]) {
      test('$name: the row stays, and nobody hears of it', () async {
        var binding = false;
        queue.isProfileBinding = () => binding;
        await connect(userState: userState, transport: (server) => _AfterWrite(server, write, () => binding = true));
        await playedOffline(finished: true);

        await sync();

        expect(await row(), isNotNull);
        expect(heard, isEmpty);
        expect(told, isEmpty);
      });
    }
  });

  group('the copies hear only the profile that watched', () {
    var binding = false;

    Future<void> adultPlayed({required bool finished}) async {
      queue.setActiveProfileId('adult');
      await db.upsertProgressAction(
        profileId: 'adult',
        serverId: ServerId(client.serverId),
        clientScopeId: client.scopedServerId,
        ratingKey: 'movie-1',
        viewOffset: finished ? length : 1800000,
        duration: length,
        shouldMarkWatched: finished,
      );
    }

    setUp(() {
      binding = false;
      queue.isProfileBinding = () => binding;
    });

    for (final (name, change) in <(String, void Function())>[
      ('a switch', () => queue.setActiveProfileId('kid')),
      ('a bind', () => binding = true),
    ]) {
      test('$name during the write of a position: nobody hears of it', () async {
        await connect(transport: (server) => _AfterWrite(server, '"backlog":true', change));
        await adultPlayed(finished: false);

        await sync();

        expect(heard, isEmpty);
      });

      test('$name while the trackers run: the copies hear nothing', () async {
        await connect();
        await adultPlayed(finished: true);
        final subscription = WatchStateNotifier().stream.listen((_) => change());
        addTearDown(subscription.cancel);

        await sync();

        expect(told, isNotEmpty);
        expect(heard, isEmpty);
      });

      test('$name while the item for the copies comes in: nobody hears of it', () async {
        await connect(transport: (server) => _AfterWrite(server, '', change, onlyAfterAWrite: true));
        await adultPlayed(finished: false);

        await sync();

        expect(heard, isEmpty);
      });
    }

    test('nothing changes, and they hear of it', () async {
      await connect();
      await adultPlayed(finished: false);

      await sync();

      expect(heard, [false]);
    });
  });

  group('the session of a row', () {
    Iterable<Object?> backlogSessions() =>
        server.watchEvents.where((event) => event['backlog'] == true).map((event) => event['session_id']);

    test('stays the same for every attempt, also after a restart: the history keeps one viewing', () async {
      await connect(userState: state(at: DateTime.now().subtract(const Duration(seconds: 5))));
      await playedOffline(finished: true);
      await sync();
      await sync();

      final restarted = server.client();
      addTearDown(restarted.close);
      await restarted.refreshCapabilities();
      manager.debugRegisterClientForTesting(restarted);
      await sync();

      expect(backlogSessions(), hasLength(3));
      expect(backlogSessions().toSet(), hasLength(1));
    });

    test('differs per row: a later viewing is a viewing of its own', () async {
      await connect(userState: state(at: longAgo));
      await playedOffline(finished: false);
      await sync();
      await playedOffline(finished: false);
      await sync();

      expect(backlogSessions(), hasLength(2));
      expect(backlogSessions().toSet(), hasLength(2));
    });
  });

  test('a finished viewing on a title without a state lands as a backlog, without a mark', () async {
    await connect();
    await playedOffline(finished: true);

    await sync();

    expect(server.watchEvents.single['backlog'], isTrue);
    expect(server.watchStates['movie-1']?['watched'], isTrue);
    expect(await row(), isNull);
    expect(heard, [true]);
  });

  group('a position', () {
    test('on a title that has a state falls away, and nobody hears of it', () async {
      await connect(userState: state(at: longAgo));
      await playedOffline(finished: false);

      await sync();

      expect(server.watchEvents.single['backlog'], isTrue);
      expect(server.watchStates, isEmpty);
      expect(await row(), isNull);
      expect(heard, isEmpty);
    });

    test('on a title without a state lands, and the copies hear of it', () async {
      await connect();
      await playedOffline(finished: false);

      await sync();

      expect(server.watchStates['movie-1']?['position_ms'], 1800000);
      expect(await row(), isNull);
      expect(heard, [false]);
    });
  });
}

const _anOldState = {
  'position_ms': 600000,
  'watched': false,
  'play_count': 0,
  'updated_at': '2026-01-01T00:00:00Z',
  'revision': 3,
};

/// Item reads fail until the first write, the way a server that throttles for a
/// moment does.
class _FlakyReads extends http.BaseClient {
  _FlakyReads(PleyaFakeServer server) : inner = server.asHttpClient();

  final http.Client inner;
  bool _wrote = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/watch-state')) _wrote = true;
    if (!_wrote && request.method == 'GET' && request.url.path.contains('/items/')) {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
    }
    return inner.send(request);
  }
}

/// Runs [then] once a write carrying [marker] was answered, or with
/// [onlyAfterAWrite] once a read after a write was.
class _AfterWrite extends http.BaseClient {
  _AfterWrite(PleyaFakeServer server, this.marker, this.then, {this.onlyAfterAWrite = false})
    : inner = server.asHttpClient();

  final http.Client inner;
  final String marker;
  final void Function() then;
  final bool onlyAfterAWrite;
  bool _wrote = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final response = await inner.send(request);
    if (onlyAfterAWrite) {
      if (_wrote && request.method == 'GET') then();
      if (request.url.path.endsWith('/watch-state')) _wrote = true;
    } else if (body.contains(marker)) {
      then();
    }
    return response;
  }
}

/// The server takes everything but the mark.
class _FailingMark extends http.BaseClient {
  _FailingMark(this.server) : inner = server.asHttpClient();

  final PleyaFakeServer server;
  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    if (!body.contains('"mark_watched"')) return inner.send(request);
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 500);
  }
}
