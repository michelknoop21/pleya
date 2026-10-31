/// What a replay does with a row when the server can only half take it: the row
/// goes when the position landed, or when there is nothing left to add.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';

import '../test_helpers/mirror_server.dart';
import '../test_helpers/prefs.dart';

/// Plex's aggregate: a season and a series report the last viewing of any of
/// their episodes as their own `lastViewedAt`. The copy of an episode that lands
/// moves it, and in a test that runs in the same second as the mark it has to
/// land visibly later.
class _SeasonServer extends MirrorServer {
  _SeasonServer(this.kind) : super('other');

  final MediaKind kind;
  int? aggregateViewedAt;

  @override
  Future<MediaItem?> readCopyState(String id) async => MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: id == 'parent' ? kind : MediaKind.episode,
    serverId: 'other',
    durationMs: mirrorHour,
    lastViewedAt: id == 'parent' ? aggregateViewedAt : null,
  );

  @override
  Future<bool> writeCopyState(
    MediaItem item, {
    required Duration position,
    Duration? duration,
    required bool watched,
  }) async {
    final landed = await super.writeCopyState(item, position: position, duration: duration, watched: watched);
    if (watched) aggregateViewedAt = DateTime(2100).millisecondsSinceEpoch ~/ 1000;
    return landed;
  }
}

void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late OfflineWatchSyncService queue;

  setUp(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    manager = MultiServerManager();
    for (final server in const ['playing', 'other', 'third']) {
      manager.debugMarkAdministeredForTesting(ServerId(server));
    }
    queue = OfflineWatchSyncService(database: db, serverManager: manager);
  });

  tearDown(() async {
    queue.dispose();
    manager.dispose();
    await db.close();
  });

  Future<void> ownRow() => db.upsertProgressAction(
    serverId: ServerId('other'),
    ratingKey: 'film',
    viewOffset: 60000,
    duration: mirrorHour,
    shouldMarkWatched: false,
  );

  Future<void> mirroredRow({bool watched = false}) => queue.queueMirroredProgress(
    serverId: ServerId('other'),
    itemId: 'film',
    viewOffset: 60000,
    duration: mirrorHour,
    watched: watched,
    profileId: queue.activeProfileId,
  );

  group('a start that fails', () {
    test('keeps the row on a server that needs the session: the stop would land nowhere', () async {
      final other = MirrorServer('other', backend: MediaBackend.jellyfin, startFails: true);
      manager.debugRegisterClientForTesting(other);
      await ownRow();

      await queue.syncPendingItems();

      expect(other.positions, isEmpty);
      expect((await db.getLatestWatchAction('other:film'))?.syncAttempts, 1);
    });

    test('goes on to the stop on Plex, where the stop is what persists', () async {
      final other = MirrorServer('other', startFails: true);
      manager.debugRegisterClientForTesting(other);
      await ownRow();

      await queue.syncPendingItems();

      expect(other.positions, [60000]);
      expect(await queue.getPendingSyncCount(), 0);
    });
  });

  group('a copy on a watched title', () {
    MirrorServer seen({bool movesCopyWithoutViewing = true}) => MirrorServer(
      'other',
      item: mirrorFilm('other').copyWith(viewCount: 1, lastViewedAt: 1000),
      backend: MediaBackend.jellyfin,
      movesCopyWithoutViewing: movesCopyWithoutViewing,
    );

    test('takes the position of a rewatch and stays watched: nothing counts as a viewing', () async {
      final other = seen();
      manager.debugRegisterClientForTesting(other);
      await mirroredRow();

      await queue.syncPendingItems();

      expect(other.played, isTrue);
      expect(other.playCount, 1);
      expect(other.started, 0);
      expect(other.positions, [60000]);
    });

    test('is left alone where a position cannot land without a viewing', () async {
      final other = seen(movesCopyWithoutViewing: false);
      manager.debugRegisterClientForTesting(other);
      await mirroredRow();

      await queue.syncPendingItems();

      expect(other.tokens, isEmpty, reason: 'nothing was sent');
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('a rewatch that finishes takes its position off the copy again', () async {
      final other = MirrorServer('other', item: mirrorFilm('other').copyWith(viewCount: 1, viewOffsetMs: 3000000));
      manager.debugRegisterClientForTesting(other);
      await mirroredRow(watched: true);

      await queue.syncPendingItems();

      expect(other.position, 0);
    });

    test('counts a finished viewing once: a stop that failed brings it back later', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);

      await mirroredRow(watched: true);
      await queue.syncPendingItems();
      await mirroredRow(watched: true);
      await queue.syncPendingItems();

      expect(other.watched, hasLength(1));
      expect(other.playCount, 1);
      expect(await queue.getPendingSyncCount(), 0);
    });
  });

  group('what the copy says', () {
    test('an empty fresh read is no reason to drop the row', () async {
      final other = MirrorServer('other', freshIsEmpty: true);
      manager.debugRegisterClientForTesting(other);
      await mirroredRow();

      await queue.syncPendingItems();

      expect(other.positions, [60000]);
    });

    test('gone ends the row', () async {
      final other = MirrorServer('other', gone: true);
      manager.debugRegisterClientForTesting(other);
      await mirroredRow();

      await queue.syncPendingItems();

      expect(other.tokens, isEmpty);
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('a read without an answer keeps the row', () async {
      final other = MirrorServer('other', onRead: () => throw StateError('offline'));
      manager.debugRegisterClientForTesting(other);
      await mirroredRow(watched: true);

      await queue.syncPendingItems();

      expect((await db.getLatestWatchAction('other:film'))?.syncAttempts, 1);
    });

    test('a title set back to unwatched counts as unwatched, whatever its play count on Pleya Server', () async {
      final other = MirrorServer(
        'other',
        item: mirrorFilm('other').copyWith(viewCount: 2),
        backend: MediaBackend.pleyaServer,
        movesCopyWithoutViewing: false,
      )..played = false;
      manager.debugRegisterClientForTesting(other);
      await mirroredRow();

      await queue.syncPendingItems();

      expect(other.positions, [60000]);
    });
  });

  test('a copy viewed after the row was written stays as it is', () async {
    final later = mirrorFilm('other').copyWith(lastViewedAt: DateTime(2100).millisecondsSinceEpoch ~/ 1000);
    final other = MirrorServer('other', item: later);
    manager.debugRegisterClientForTesting(other);
    await mirroredRow();

    await queue.syncPendingItems();

    expect(other.positions, isEmpty);
    expect(await queue.getPendingSyncCount(), 0);
  });

  test('the row of the source itself keeps the old rule', () async {
    final seen = mirrorFilm('other').copyWith(viewCount: 1, lastViewedAt: 1000);
    final other = MirrorServer('other', item: seen);
    manager.debugRegisterClientForTesting(other);
    await ownRow();

    await queue.syncPendingItems();

    expect(other.positions, isEmpty);
  });

  test('a copy never hears a start or a stop: nobody is watching there', () async {
    final other = MirrorServer('other');
    manager.debugRegisterClientForTesting(other);
    await mirroredRow();

    await queue.syncPendingItems();

    expect((other.started, other.stopped), (0, 0));
    expect(other.positions, [60000]);
    expect(await queue.getPendingSyncCount(), 0);
  });

  test('a 404 under the next token ends nothing: that account may just not see the title', () async {
    queue.setActiveProfileId('adult');
    final other = MirrorServer('other', gone: true, onRead: () => queue.setActiveProfileId('kid'));
    manager.debugRegisterClientForTesting(other);
    await queue.queueMirroredProgress(
      serverId: ServerId('other'),
      itemId: 'film',
      viewOffset: 60000,
      duration: mirrorHour,
      watched: false,
      profileId: 'adult',
    );

    await queue.syncPendingItems();

    expect((await db.getLatestWatchAction('other:film'))?.profileId, 'adult');
  });

  test('a read that outlasts a profile switch sends nothing under the next token', () async {
    queue.setActiveProfileId('adult');
    late MirrorServer other;
    other = MirrorServer(
      'other',
      onRead: () {
        other.token = 'kid';
        queue.setActiveProfileId('kid');
      },
    );
    manager.debugRegisterClientForTesting(other);
    await queue.queueMirroredProgress(
      serverId: ServerId('other'),
      itemId: 'film',
      viewOffset: 60000,
      duration: mirrorHour,
      watched: false,
      profileId: 'adult',
    );

    await queue.syncPendingItems();

    expect(other.tokens, isEmpty);
    final row = await db.getLatestWatchAction('other:film');
    expect(row?.profileId, 'adult');
    expect(row?.syncAttempts, 0, reason: 'nothing went wrong with the row');
  });

  test('a switch during the start of an own row sends no stop under the next token', () async {
    queue.setActiveProfileId('adult');
    late MirrorServer other;
    other = MirrorServer(
      'other',
      onStart: () {
        other.token = 'kid';
        queue.setActiveProfileId('kid');
      },
    );
    manager.debugRegisterClientForTesting(other);
    await db.upsertProgressAction(
      profileId: 'adult',
      serverId: ServerId('other'),
      ratingKey: 'film',
      viewOffset: 60000,
      duration: mirrorHour,
      shouldMarkWatched: false,
    );

    await queue.syncPendingItems();

    expect(other.tokens, isNot(contains('kid')));
    expect(await db.getLatestWatchAction('other:film'), isNotNull);
  });

  group('a mark held for a copy', () {
    final afterTheMark = DateTime(2100).millisecondsSinceEpoch ~/ 1000;

    Future<void> heldMark({required bool watched, String? profileId}) => queue.queueCopyMark(
      serverId: ServerId('other'),
      itemId: 'film',
      watched: watched,
      profileId: profileId ?? queue.activeProfileId,
    );

    for (final watched in const [true, false]) {
      test('stays away from a copy viewed after the mark (watched: $watched)', () async {
        final other = MirrorServer(
          'other',
          item: mirrorFilm('other').copyWith(lastViewedAt: afterTheMark, viewOffsetMs: 3000000),
          backend: MediaBackend.jellyfin,
        );
        manager.debugRegisterClientForTesting(other);
        await heldMark(watched: watched);

        await queue.syncPendingItems();

        expect(other.tokens, isEmpty, reason: 'nothing was sent');
        expect(other.position, 3000000);
        expect(await queue.getPendingSyncCount(), 0);
      });

      test('lands on a copy last viewed before the mark (watched: $watched)', () async {
        final other = MirrorServer(
          'other',
          item: mirrorFilm('other').copyWith(lastViewedAt: 1000),
          backend: MediaBackend.jellyfin,
        );
        manager.debugRegisterClientForTesting(other);
        await heldMark(watched: watched);

        await queue.syncPendingItems();

        expect(watched ? other.watched : other.unwatched, ['film']);
        expect(await queue.getPendingSyncCount(), 0);
      });

      test('stays in the queue when the read has no answer (watched: $watched)', () async {
        final other = MirrorServer('other', onRead: () => throw StateError('offline'));
        manager.debugRegisterClientForTesting(other);
        await heldMark(watched: watched);

        await queue.syncPendingItems();

        expect(other.tokens, isEmpty);
        expect((await db.getLatestWatchAction('other:film'))?.syncAttempts, 1);
      });

      test('ends when the server says the copy is gone (watched: $watched)', () async {
        final other = MirrorServer('other', gone: true);
        manager.debugRegisterClientForTesting(other);
        await heldMark(watched: watched);

        await queue.syncPendingItems();

        expect(other.tokens, isEmpty);
        expect(await queue.getPendingSyncCount(), 0);
      });
    }

    for (final kind in const [MediaKind.season, MediaKind.show]) {
      for (final watched in const [true, false]) {
        test('on a ${kind.id} lands after an episode came back and moved its aggregate (watched: $watched)', () async {
          final server = _SeasonServer(kind);
          manager.debugRegisterClientForTesting(server);
          await queue.queueMirroredProgress(
            serverId: ServerId('other'),
            itemId: 'e3',
            viewOffset: mirrorHour,
            duration: mirrorHour,
            watched: true,
            profileId: queue.activeProfileId,
          );
          await queue.queueCopyMark(
            serverId: ServerId('other'),
            itemId: 'parent',
            watched: watched,
            profileId: queue.activeProfileId,
          );

          await queue.syncPendingItems();

          expect(server.watched, contains('e3'), reason: 'the episode came first and moved the aggregate');
          expect(watched ? server.watched : server.unwatched, contains('parent'));
          expect(await queue.getPendingSyncCount(), 0);
        });
      }
    }

    test('on an episode keeps the check: that lastViewedAt is its own', () async {
      final other = MirrorServer(
        'other',
        item: mirrorFilm('other').copyWith(kind: MediaKind.episode, lastViewedAt: afterTheMark),
      );
      manager.debugRegisterClientForTesting(other);
      await heldMark(watched: false);

      await queue.syncPendingItems();

      expect(other.tokens, isEmpty);
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('a read that outlasts a profile switch sends nothing under the next token', () async {
      queue.setActiveProfileId('adult');
      late MirrorServer other;
      other = MirrorServer(
        'other',
        gone: true,
        onRead: () {
          other.token = 'kid';
          queue.setActiveProfileId('kid');
        },
      );
      manager.debugRegisterClientForTesting(other);
      await heldMark(watched: true, profileId: 'adult');

      await queue.syncPendingItems();

      expect(other.tokens, isEmpty);
      final row = await db.getLatestWatchAction('other:film');
      expect(row?.profileId, 'adult', reason: 'a 404 for the next account says nothing about this one');
      expect(row?.syncAttempts, 0);
    });
  });

  group('a viewing holds the title', () {
    test('a position is gone: what that viewing reports is newer', () async {
      final other = MirrorServer('other', holdsTitle: true);
      manager.debugRegisterClientForTesting(other);
      await mirroredRow();

      await queue.syncPendingItems();

      expect(other.tokens, ['adult'], reason: 'it was asked, and it said no');
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('a finished viewing waits for its turn', () async {
      manager.debugRegisterClientForTesting(MirrorServer('other', holdsTitle: true));
      await mirroredRow(watched: true);

      await queue.syncPendingItems();

      expect((await db.getLatestWatchAction('other:film'))?.syncAttempts, 1);
    });
  });

  group('a bind that is running', () {
    Future<void> rowFor(String server) => queue.queueMirroredProgress(
      serverId: ServerId(server),
      itemId: 'film',
      viewOffset: 60000,
      duration: mirrorHour,
      watched: false,
      profileId: queue.activeProfileId,
    );

    Future<void> untilQuiet() async {
      await pumpEventQueue();
      while (queue.isSyncing) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    test('sends nothing: the clients and their rights are still those of the last profile', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      await rowFor('other');
      queue.isProfileBinding = () => true;

      await queue.syncPendingItems();

      expect(other.tokens, isEmpty);
      expect((await db.getLatestWatchAction('other:film'))?.syncAttempts, 0, reason: 'nothing went wrong with the row');
    });

    test('holds a row of the source itself too', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      await ownRow();
      queue.isProfileBinding = () => true;

      await queue.syncPendingItems();

      expect(other.tokens, isEmpty);
      expect((await db.getLatestWatchAction('other:film'))?.syncAttempts, 0);
    });

    test('stops a pass that was running: the row on the line and the one after it stay', () async {
      var binding = false;
      final other = MirrorServer('other', onRead: () => binding = true);
      final third = MirrorServer('third');
      manager
        ..debugRegisterClientForTesting(other)
        ..debugRegisterClientForTesting(third);
      await rowFor('other');
      await rowFor('third');
      queue.isProfileBinding = () => binding;

      await queue.syncPendingItems();

      expect(other.tokens, isEmpty);
      expect(third.tokens, isEmpty);
      expect(await queue.getPendingSyncCount(), 2);
    });

    test('is followed by a pass of its own: the startup sync runs only once', () async {
      var binding = true;
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      await rowFor('other');
      queue.isProfileBinding = () => binding;
      await queue.syncPendingItems();

      binding = false;
      queue.setActiveProfileId(queue.activeProfileId);
      await untilQuiet();

      expect(other.positions, [60000]);
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('that caught the last row on the line brings that row back too', () async {
      var binding = false;
      var reads = 0;
      final other = MirrorServer('other', onRead: () => binding = reads++ == 0);
      manager.debugRegisterClientForTesting(other);
      await rowFor('other');
      queue.isProfileBinding = () => binding;
      await queue.syncPendingItems();
      expect(other.tokens, isEmpty);

      binding = false;
      queue.setActiveProfileId(queue.activeProfileId);
      await untilQuiet();

      expect(other.positions, [60000]);
      expect(await queue.getPendingSyncCount(), 0);
    });

    test('that is still running keeps the follow-up pass away', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      await rowFor('other');
      queue.isProfileBinding = () => true;
      await queue.syncPendingItems();

      queue.setActiveProfileId(queue.activeProfileId);
      await untilQuiet();

      expect(other.tokens, isEmpty);
    });

    test('a new profile on the service starts no pass when no bind stopped one', () async {
      final other = MirrorServer('other');
      manager.debugRegisterClientForTesting(other);
      await rowFor('other');
      queue.isProfileBinding = () => false;

      queue.setActiveProfileId(queue.activeProfileId);
      await untilQuiet();

      expect(other.tokens, isEmpty);
    });
  });

  group('a server that is not connected', () {
    test('keeps its row until a client can say whose server it is', () async {
      await mirroredRow();

      await queue.syncPendingItems();

      expect(await queue.getPendingSyncCount(), 1);
    });

    test('during a bind a row is passed over: the rights of the last profile still stand', () async {
      await queue.queueMirroredProgress(
        serverId: ServerId('friend'),
        itemId: 'film',
        viewOffset: 60000,
        duration: mirrorHour,
        watched: false,
        profileId: queue.activeProfileId,
      );
      manager.debugRegisterClientForTesting(MirrorServer('friend'));
      queue.isProfileBinding = () => true;

      await queue.syncPendingItems();

      expect(await db.getLatestWatchAction('friend:film'), isNotNull);
    });

    test('a row for a server that turns out to be someone else\'s is dropped', () async {
      await queue.queueMirroredProgress(
        serverId: ServerId('friend'),
        itemId: 'film',
        viewOffset: 60000,
        duration: mirrorHour,
        watched: false,
        profileId: queue.activeProfileId,
      );
      final friend = MirrorServer('friend');
      manager.debugRegisterClientForTesting(friend);

      await queue.syncPendingItems();

      expect(friend.tokens, isEmpty);
      expect(await db.getLatestWatchAction('friend:film'), isNull);
    });
  });
}
